import Foundation
import PerchCore

/// One agent's hook configuration file. Implementations only ever add or remove Perch's own hooks.
public protocol HookFile {
    var agent: String { get }
    var eventNames: [String] { get }
    /// Where the agent keeps the file (see `ConfigLocation.candidates`).
    var location: ConfigLocation { get }
    /// Printed after a successful install.
    var installNote: String? { get }
    /// The agent runs new or changed hooks only after the user trusts them (Codex's /hooks).
    var needsTrust: Bool { get }
    /// The file holds nothing but Perch's hooks (Grok's ~/.grok/hooks/perch.json): no backup, deleted once empty.
    var ownsFile: Bool { get }
    /// The file with Perch's hooks (replacing any old ones). `text` is nil when the file does not exist.
    func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String
    /// The file without Perch's hooks, and how many there were.
    func removing(_ text: String, path: String) throws -> (text: String, removed: Int)
    /// Perch's hooks alone, in a canonical form: equal for the same hooks whatever else is in the file and in
    /// whatever order. Empty when the file has none of Perch's hooks.
    func perchHooks(in text: String?, path: String) throws -> String
    /// The `--wait` Perch's PermissionRequest hook was installed with, if any.
    func wait(in text: String?) -> Int?
    /// Files the hooks need next to the perch binary they run, by path (dsh's plugin). `perch` may be shell-quoted.
    /// Written with the hooks and whenever the binaries are synced.
    func supportFiles(perch: String) -> [String: String]
    /// Whether `text` holds nothing worth keeping once Perch's part is gone: the file is deleted instead.
    func isBlank(_ text: String) -> Bool
}

extension HookFile {
    public var ownsFile: Bool { false }
    public func supportFiles(perch: String) -> [String: String] { [:] }
    public func isBlank(_ text: String) -> Bool { false }
}

public enum HookFiles {
    public static var all: [any HookFile] { [HookSettings.claudeCode, HookSettings.codex, HookSettings.grok, HookSettings.cursor, AntigravityHooks(), DshPatch(), HermesHooks()] }

    public static func `for`(_ agent: String) throws -> any HookFile {
        guard let file = all.first(where: { $0.agent == agent }) else {
            let names = all.map(\.agent)
            throw SetupError("unknown agent '\(agent)'; use \(names.dropLast().joined(separator: ", ")) or \(names.last!)", code: 64)
        }
        return file
    }

    public static func currentBinary() throws -> String {
        let url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        if FileManager.default.isExecutableFile(atPath: url.path) { return url.path }
        guard let path = Bundle.main.executablePath else { throw SetupError("cannot tell where perch is; pass --binary") }
        return path
    }

    public static func read(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else {
            throw SetupError("\(path) is not UTF-8 text; nothing was changed")
        }
        return text
    }

    /// Writes `file`'s hook file after a change: `write`, except that a file Perch owns gets no backup (it would sit
    /// next to the agent's hook files) and is deleted once it holds nothing.
    /// A file left blank (see `HookFile.isBlank`) is deleted too.
    public static func save(_ text: String, to path: String, for file: any HookFile) throws {
        if file.isBlank(text) {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            return
        }
        guard file.ownsFile else { return try write(text, to: path) }
        let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        if root?.isEmpty == true {
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
            return
        }
        try write(text, to: path, backup: false)
    }

    /// Backs up the old file to `<path>.perch-backup`, then replaces it atomically.
    public static func write(_ text: String, to path: String, backup: Bool = true) throws {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if backup, fm.fileExists(atPath: path) {
            let backup = URL(fileURLWithPath: path + ".perch-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Writes `file`'s support files for `perch` (see `HookFile.supportFiles`), each replaced atomically, and only when
    /// its contents differ. Returns the paths written.
    @discardableResult
    public static func writeSupportFiles(for file: any HookFile, perch: String) throws -> [String] {
        var written: [String] = []
        for (path, contents) in file.supportFiles(perch: perch).sorted(by: { $0.key < $1.key }) {
            if (try? String(contentsOfFile: path, encoding: .utf8)) == contents { continue }
            do {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                throw SetupError("cannot write \(path): \(error.localizedDescription)")
            }
            written.append(path)
        }
        return written
    }

    /// The path `shellQuote` quoted, back as it was.
    public static func shellUnquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("'"), s.hasSuffix("'") else { return s }
        return String(s.dropFirst().dropLast()).replacingOccurrences(of: #"'\''"#, with: "'")
    }

    /// Single-quotes a path for the hook's shell command when it needs it.
    public static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+@%:,"))
        if !s.isEmpty && s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// An agent's hook file, edited as plain JSON. Claude Code's settings.json and Codex's hooks.json share the
/// `hooks → event → [{matcher, hooks: [handler]}]` shape; Cursor's hooks.json is flat, `hooks → event → [handler]`
/// plus a top-level `version` (`flat`). Only handlers whose command runs `perch … hook <agent>` are Perch's;
/// everything else is left as it was (key order may change: the file is rewritten sorted).
public struct HookSettings: HookFile {
    struct HookEvent {
        enum Mode {
            /// The agent never waits for it. Codex caps Interrupt at 3 s even in the background.
            case async(timeout: Int = 10)
            /// PermissionRequest: may return a decision, so the agent waits up to `--wait`.
            case blocking
            /// Runs inline with a short cap (Codex's SessionEnd is always synchronous, at most 3 s).
            case sync(timeout: Int)
        }
        let name: String
        var matcher: String?
        var mode: Mode = .async()
    }

    public let agent: String
    let events: [HookEvent]
    public let location: ConfigLocation
    public var installNote: String?
    public var needsTrust = false
    public var ownsFile = false
    /// Cursor's layout: an event lists its handlers directly, and the file says `"version": 1`.
    var flat = false

    public var eventNames: [String] { events.map(\.name) }

    public static var claudeCode: HookSettings {
        HookSettings(agent: "claude-code", events: [
            HookEvent(name: "UserPromptSubmit"),
            HookEvent(name: "Notification", matcher: HookAdapter.waitingNotifications.sorted { order($0) < order($1) }.joined(separator: "|")),
            HookEvent(name: "PermissionRequest", mode: .blocking),
            HookEvent(name: "PostToolUse"),
            HookEvent(name: "PostToolUseFailure"),
            HookEvent(name: "Stop"),
            HookEvent(name: "StopFailure"),
            HookEvent(name: "SessionEnd"),
        ], location: ConfigLocation(dirVariable: "CLAUDE_CONFIG_DIR", defaultDir: ".claude", file: "settings.json"))
    }

    /// Codex has no Notification / StopFailure / PostToolUseFailure; Interrupt covers Esc (no Stop follows).
    /// SubagentStart / SubagentStop keep a session running while its subagents work (#94).
    public static var codex: HookSettings {
        HookSettings(agent: "codex", events: [
            HookEvent(name: "UserPromptSubmit"),
            HookEvent(name: "PermissionRequest", mode: .blocking),
            HookEvent(name: "PostToolUse"),
            HookEvent(name: "Stop"),
            HookEvent(name: "SubagentStart"),
            HookEvent(name: "SubagentStop"),
            HookEvent(name: "Interrupt", mode: .async(timeout: 3)),
            HookEvent(name: "SessionEnd", mode: .sync(timeout: 3)),
        ], location: ConfigLocation(dirVariable: "CODEX_HOME", defaultDir: ".codex", file: "hooks.json"),
        installNote: "Codex skips new or changed hooks until you trust them: start codex and review them with /hooks.",
        needsTrust: true)
    }

    /// Grok Build reads every `~/.grok/hooks/*.json`, so Perch keeps its own file there; global hooks need no trust.
    /// Grok has no async hooks (it runs them all in the foreground and logs a load error for `async`), so each one
    /// gets a short explicit timeout; Stop / PostToolUse would otherwise default to 600 s. No PermissionRequest:
    /// Grok has none, and the notch can never answer it.
    public static var grok: HookSettings {
        HookSettings(agent: "grok", events: [
            HookEvent(name: "UserPromptSubmit", mode: .sync(timeout: 5)),
            HookEvent(name: "Notification", matcher: (HookAdapter.waitingNotifications.sorted { order($0) < order($1) } + ["idle_prompt"])
                .joined(separator: "|"), mode: .sync(timeout: 5)),
            HookEvent(name: "PostToolUse", mode: .sync(timeout: 5)),
            HookEvent(name: "PostToolUseFailure", mode: .sync(timeout: 5)),
            HookEvent(name: "Stop", mode: .sync(timeout: 5)),
            HookEvent(name: "StopFailure", mode: .sync(timeout: 5)),
            HookEvent(name: "StopCancelled", mode: .sync(timeout: 5)),
            HookEvent(name: "SessionEnd", mode: .sync(timeout: 3)),
        ], location: ConfigLocation(dirVariable: "GROK_HOME", defaultDir: ".grok", file: "hooks/perch.json"),
        installNote: "Grok loads hooks when a session starts: restart running grok sessions (or reload them in /hooks with r).",
        ownsFile: true)
    }

    /// Cursor (#98): the IDE's Agent panel and the `cursor-agent` CLI read ~/.cursor/hooks.json, a file other tools
    /// write to as well. Hooks run in the foreground (a missing `timeout` is Cursor's platform default), so each one
    /// gets a short cap. Perch never answers a Cursor hook (it prints nothing), so it installs no permission hook:
    /// `beforeShellExecution` fires for every command, and Cursor has no event saying it waits for you.
    /// Cursor reloads the file on save; no trust step.
    public static var cursor: HookSettings {
        HookSettings(agent: "cursor", events: [
            HookEvent(name: "beforeSubmitPrompt", mode: .sync(timeout: 5)),
            HookEvent(name: "afterAgentResponse", mode: .sync(timeout: 5)),
            HookEvent(name: "stop", mode: .sync(timeout: 5)),
            HookEvent(name: "sessionEnd", mode: .sync(timeout: 5)),
        ], location: ConfigLocation(dirVariable: nil, defaultDir: ".cursor", file: "hooks.json"),
        flat: true)
    }

    private static func order(_ type: String) -> Int {
        ["permission_prompt", "elicitation_dialog", "agent_needs_input"].firstIndex(of: type) ?? 99
    }

    public func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String {
        var root = try parse(text, path: path)
        remove(from: &root)
        add(to: &root, perch: perch, wait: wait)
        return try Self.render(root)
    }

    public func removing(_ text: String, path: String) throws -> (text: String, removed: Int) {
        var root = try parse(text, path: path)
        let removed = remove(from: &root)
        return (try Self.render(root), removed)
    }

    public func perchHooks(in text: String?, path: String) throws -> String {
        let root = try parse(text, path: path)
        var ours: [String: Any] = [:]
        for (event, value) in root["hooks"] as? [String: Any] ?? [:] {
            if flat {
                let list = (value as? [[String: Any]] ?? []).filter(isPerch)
                if !list.isEmpty { ours[event] = list }
                continue
            }
            let groups = (value as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                let list = (group["hooks"] as? [[String: Any]] ?? []).filter(isPerch)
                guard !list.isEmpty else { return nil }
                var group = group
                group["hooks"] = list
                return group
            }
            if !groups.isEmpty { ours[event] = groups }
        }
        return ours.isEmpty ? "" : try Self.render(ours)
    }

    public func wait(in text: String?) -> Int? {
        guard let text, let root = try? parse(text, path: ""),
              let hooks = root["hooks"] as? [String: Any] else { return nil }
        let commands = hooks.values.flatMap { value -> [[String: Any]] in
            let list = value as? [[String: Any]] ?? []
            return flat ? list : list.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
        }.filter(isPerch).compactMap { $0["command"] as? String }
        for command in commands {
            let words = command.split(separator: " ")
            if let i = words.firstIndex(of: "--wait"), i + 1 < words.count, let wait = Int(words[i + 1]) { return wait }
        }
        return nil
    }

    public func isPerch(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.contains(" hook \(agent)") && command.contains("perch")
    }

    private func parse(_ text: String?, path: String) throws -> [String: Any] {
        guard let text, !text.allSatisfy(\.isWhitespace) else { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw SetupError("\(path) is not valid JSON (or not an object); fix it first, nothing was changed")
        }
        return root
    }

    /// Removes Perch's hooks, then any groups / events / `hooks` left empty by that. Returns how many were removed.
    @discardableResult
    func remove(from root: inout [String: Any]) -> Int {
        guard var hooks = root["hooks"] as? [String: Any] else { return 0 }
        var removed = 0
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            if flat {
                let remaining = groups.filter { !isPerch($0) }
                removed += groups.count - remaining.count
                hooks[event] = remaining.isEmpty ? nil : remaining
                continue
            }
            var kept: [[String: Any]] = []
            for var group in groups {
                guard let list = group["hooks"] as? [[String: Any]] else { kept.append(group); continue }
                let remaining = list.filter { !isPerch($0) }
                removed += list.count - remaining.count
                if remaining.isEmpty && !list.isEmpty { continue }
                group["hooks"] = remaining
                kept.append(group)
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return removed
    }

    func add(to root: inout [String: Any], perch: String, wait: Int) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\(perch) hook \(agent)"
        for event in events {
            let hook: [String: Any]
            switch event.mode {
            case .async(let timeout):
                hook = ["type": "command", "command": command, "async": true, "timeout": timeout]
            case .blocking:
                hook = ["type": "command", "command": "\(command) --wait \(wait)", "timeout": wait + 10,
                        "statusMessage": "Waiting for Perch (⌥⇧A allow · ⌥⇧D deny)…"]
            case .sync(let timeout):
                hook = flat ? ["command": command, "timeout": timeout] : ["type": "command", "command": command, "timeout": timeout]
            }
            if flat {
                hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [hook]
                continue
            }
            var group: [String: Any] = ["hooks": [hook]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [group]
        }
        root["hooks"] = hooks
        if flat, root["version"] == nil { root["version"] = 1 }
    }

    static func render(_ root: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// Google Antigravity's global hooks live in ~/.gemini/config/hooks.json (shared by Antigravity 2.0, Antigravity IDE,
/// and the `agy` CLI). Unlike Claude Code / Codex / Cursor, each top-level key is a named hook (`"perch": { … }`);
/// simple events (`SessionStart`, `PreInvocation`, `PostInvocation`, `Stop`) take a flat array of handler objects,
/// while tool events (`PreToolUse`, `PostToolUse`) wrap handlers in `{matcher, hooks}`.
///
/// Hooks run synchronously and expect a JSON object on stdout, so each gets a short timeout. Antigravity has no
/// Notification / PermissionRequest / SessionEnd event, and `PreToolUse` runs on every tool call regardless of whether
/// Antigravity will prompt, so Perch installs only `PreInvocation` and `Stop`. Detected by `~/.gemini` (exists for
/// App, IDE, and `agy` CLI even before `~/.gemini/config` does).
public struct AntigravityHooks: HookFile {
    public let agent = "antigravity"
    public let eventNames = ["PreInvocation", "Stop"]
    public let location = ConfigLocation(dirVariable: nil, defaultDir: ".gemini", file: "config/hooks.json")
    public let installNote: String? = nil
    public let needsTrust = false
    static let hookName = "perch"
    static let timeout = 5
    static let groupedEvents: Set<String> = ["PreToolUse", "PostToolUse"]

    public init() {}

    public func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String {
        var root = try parse(text, path: path)
        remove(from: &root)
        add(to: &root, perch: perch)
        return try HookSettings.render(root)
    }

    public func removing(_ text: String, path: String) throws -> (text: String, removed: Int) {
        var root = try parse(text, path: path)
        let removed = remove(from: &root)
        return (try HookSettings.render(root), removed)
    }

    public func perchHooks(in text: String?, path: String) throws -> String {
        let root = try parse(text, path: path)
        var ours: [String: Any] = [:]
        for (name, value) in root {
            guard let spec = value as? [String: Any] else { continue }
            var found: [String: Any] = [:]
            for (event, eventValue) in spec {
                guard let list = eventValue as? [[String: Any]] else { continue }
                if isGrouped(event, list) {
                    let groups = list.compactMap { group -> [String: Any]? in
                        let hooks = (group["hooks"] as? [[String: Any]] ?? []).filter(isPerch)
                        guard !hooks.isEmpty else { return nil }
                        var group = group
                        group["hooks"] = hooks
                        return group
                    }
                    if !groups.isEmpty { found[event] = groups }
                } else {
                    let hooks = list.filter(isPerch)
                    if !hooks.isEmpty { found[event] = hooks }
                }
            }
            if !found.isEmpty { ours[name] = found }
        }
        return ours.isEmpty ? "" : try HookSettings.render(ours)
    }

    /// Antigravity hooks never block on Perch.
    public func wait(in text: String?) -> Int? { nil }

    public func isPerch(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.contains(" hook \(agent)") && command.contains("perch")
    }

    private func isGrouped(_ event: String, _ list: [[String: Any]]) -> Bool {
        Self.groupedEvents.contains(event) || list.contains { $0["hooks"] is [[String: Any]] }
    }

    private func parse(_ text: String?, path: String) throws -> [String: Any] {
        guard let text, !text.allSatisfy(\.isWhitespace) else { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw SetupError("\(path) is not valid JSON (or not an object); fix it first, nothing was changed")
        }
        return root
    }

    /// Removes Perch's handlers from every named hook, dropping events and named hooks left empty by that.
    @discardableResult
    func remove(from root: inout [String: Any]) -> Int {
        var removed = 0
        for (name, value) in root {
            guard var spec = value as? [String: Any] else { continue }
            var specRemoved = 0
            for (event, eventValue) in spec {
                guard let list = eventValue as? [[String: Any]] else { continue }
                if isGrouped(event, list) {
                    var kept: [[String: Any]] = []
                    for var group in list {
                        guard let hooks = group["hooks"] as? [[String: Any]] else { kept.append(group); continue }
                        let remaining = hooks.filter { !isPerch($0) }
                        specRemoved += hooks.count - remaining.count
                        if remaining.isEmpty && !hooks.isEmpty { continue }
                        group["hooks"] = remaining
                        kept.append(group)
                    }
                    if specRemoved > 0 { spec[event] = kept.isEmpty ? nil : kept }
                } else {
                    let remaining = list.filter { !isPerch($0) }
                    let count = list.count - remaining.count
                    if count > 0 {
                        specRemoved += count
                        spec[event] = remaining.isEmpty ? nil : remaining
                    }
                }
            }
            guard specRemoved > 0 else { continue }
            removed += specRemoved
            let hasEvents = spec.keys.contains { $0 != "enabled" }
            root[name] = hasEvents ? spec : nil
        }
        return removed
    }

    func add(to root: inout [String: Any], perch: String) {
        var spec = root[Self.hookName] as? [String: Any] ?? [:]
        let command = "\(perch) hook \(agent)"
        let handler: [String: Any] = ["type": "command", "command": command, "timeout": Self.timeout]
        for event in eventNames {
            spec[event] = (spec[event] as? [[String: Any]] ?? []) + [handler]
        }
        root[Self.hookName] = spec
    }
}

/// Hermes Agent's shell hooks live in the top-level `hooks:` map of ~/.hermes/config.yaml. Without a YAML
/// library Perch writes one marked block at the end of the file and never edits anything else. Hermes may later
/// rewrite the file with yaml.dump, which drops the markers, so a `hooks:` section is also recognised by its
/// commands: one holding only Perch's hooks is Perch's; one with anyone else's is left alone and install refuses
/// (two `hooks:` keys would clash).
///
/// Hermes runs shell hooks synchronously, so every hook gets a short timeout; the adapter itself is fast.
public struct HermesHooks: HookFile {
    public let agent = "hermes"
    public let eventNames = ["pre_llm_call", "post_llm_call", "on_session_end", "pre_approval_request", "post_approval_response"]
    public let location = ConfigLocation(dirVariable: "HERMES_HOME", defaultDir: ".hermes", file: "config.yaml")
    public let needsTrust = false
    public let installNote: String? = """
        Hermes asks once before running a new hook: start `hermes` in a terminal and accept Perch's hooks \
        (or run it once with --accept-hooks), then `hermes gateway restart` so the gateway picks them up.
        """
    static let timeout = 10
    static let begin = "# >>> perch hooks: added by `perch hooks install hermes`, removed by `perch hooks uninstall hermes` >>>"
    static let end = "# <<< perch hooks <<<"

    /// The top-level `hooks:` section (outside Perch's marked block).
    enum Section: Equatable {
        case none
        /// `hooks: {}`, `hooks: null`, or `hooks:` with nothing under it.
        case empty(Range<Int>)
        /// Every command in it runs `perch … hook hermes`.
        case perch(Range<Int>, hooks: Int)
        /// Someone else's hooks, maybe next to Perch's.
        case others(withPerch: Bool)
    }

    public func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String {
        var lines = Self.withoutBlock(text ?? "").text.components(separatedBy: "\n")
        switch Self.section(in: lines) {
        case .none: break
        case .empty(let range), .perch(let range, _): lines.removeSubrange(range)
        case .others:
            throw SetupError("\(path) already has a hooks: section; add Perch's to it by hand (`perch hooks install hermes --settings /dev/null --dry-run` prints them)")
        }
        var kept = lines.joined(separator: "\n")
        if !kept.isEmpty && !kept.hasSuffix("\n") { kept += "\n" }
        return kept + block(perch: perch)
    }

    public func perchHooks(in text: String?, path: String) throws -> String {
        guard let text else { return "" }
        let block = Self.blockRange(in: text).map { String(text[$0]) } ?? ""
        let lines = Self.withoutBlock(text).text.components(separatedBy: "\n")
        guard case .perch(let range, _) = Self.section(in: lines) else { return block }
        return block + lines[range].joined(separator: "\n")
    }

    /// Hermes hooks never block on Perch.
    public func wait(in text: String?) -> Int? { nil }

    public func removing(_ text: String, path: String) throws -> (text: String, removed: Int) {
        let (rest, inBlock) = Self.withoutBlock(text)
        var lines = rest.components(separatedBy: "\n")
        switch Self.section(in: lines) {
        case .perch(let range, let hooks):
            lines.removeSubrange(range)
            return (lines.joined(separator: "\n"), inBlock + hooks)
        case .others(withPerch: true):
            throw SetupError("\(path) mixes Perch's hooks with others under hooks:; remove Perch's entries by hand")
        case .none, .empty, .others(withPerch: false):
            return (rest, inBlock)
        }
    }

    func block(perch: String) -> String {
        let command = "\(perch) hook \(agent)"
        let quoted = "\"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        var lines = [Self.begin, "hooks:"]
        for event in eventNames {
            lines += ["  \(event):", "    - command: \(quoted)", "      timeout: \(Self.timeout)"]
        }
        return (lines + [Self.end]).joined(separator: "\n") + "\n"
    }

    /// The text with Perch's marked block cut out, and how many hooks it held.
    static func withoutBlock(_ text: String) -> (text: String, removed: Int) {
        guard let range = blockRange(in: text) else { return (text, 0) }
        let removed = text[range].components(separatedBy: "- command:").count - 1
        var kept = text
        kept.removeSubrange(range)
        return (kept, removed)
    }

    /// Perch's marked block, including the newline after its end marker.
    static func blockRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: begin + "\n"),
              let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return nil }
        var upper = stop.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        return start.lowerBound..<upper
    }

    static func section(in lines: [String]) -> Section {
        guard let index = lines.firstIndex(where: isHooksKey) else { return .none }
        // The section runs until the next top-level key.
        var stop = index + 1
        while stop < lines.count, !startsTopLevelKey(lines[stop]) { stop += 1 }
        let range = index..<stop
        let afterColon = lines[index].split(separator: ":", maxSplits: 1).dropFirst().first ?? ""
        let value = afterColon.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if ["{}", "[]", "null", "~"].contains(value) { return .empty(range) }
        guard value.isEmpty else { return .others(withPerch: false) }
        let body = lines[(index + 1)..<stop].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        if body.isEmpty { return .empty(range) }
        let commands = body.compactMap { line -> String? in
            let entry = line.hasPrefix("- ") ? String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) : line
            return entry.hasPrefix("command:") ? entry : nil
        }
        let ours = commands.filter { $0.contains("perch") && $0.contains(" hook hermes") }
        if !commands.isEmpty && ours.count == commands.count { return .perch(range, hooks: ours.count) }
        return .others(withPerch: !ours.isEmpty)
    }

    private static func isHooksKey(_ line: String) -> Bool {
        guard line.hasPrefix("hooks") else { return false }
        return line.dropFirst("hooks".count).drop { $0 == " " || $0 == "\t" }.first == ":"
    }

    private static func startsTopLevelKey(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return !" \t-#".contains(first)
    }
}
