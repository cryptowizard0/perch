import ArgumentParser
import Foundation
import PerchCore

struct Hooks: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove agent hook adapters.",
        subcommands: [HooksInstall.self, HooksUninstall.self]
    )
}

struct HooksInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Add Perch's hooks to an agent's settings (other hooks are kept).",
        discussion: """
        claude-code: ~/.claude/settings.json ($CLAUDE_CONFIG_DIR/settings.json if set).
        codex: ~/.codex/hooks.json ($CODEX_HOME/hooks.json if set); Codex runs them only after you trust them in /hooks.
        hermes: ~/.hermes/config.yaml ($HERMES_HOME/config.yaml if set); Hermes asks once before running them.
        A backup is written next to the file.
        """
    )
    @Argument(help: "claude-code | codex | hermes") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Option(help: "perch binary the hooks run (default: this one).") var binary: String?
    @Option(help: "Seconds a permission request waits for the notch before the terminal asks.")
    var wait: Int = Int(HookAdapter.permissionWait)
    @Flag(help: "Print the resulting settings instead of writing them.") var dryRun = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookFiles.for(agent)
        let path = settings ?? target.defaultPath
        let perch = try binary ?? HookFiles.currentBinary()
        guard (5...300).contains(wait) else { throw CLIError("--wait must be between 5 and 300 seconds", code: 64) }
        let text = try target.installing(HookFiles.read(path), path: path, perch: HookFiles.shellQuote(perch), wait: wait)
        if dryRun { return print(text, terminator: "") }
        if perch.contains("/.build/") {
            FileHandle.standardError.write(Data("perch: warning: hooks run \(perch); `swift package clean` would break them. Copy perch somewhere stable and install with --binary.\n".utf8))
        }
        try HookFiles.write(text, to: path)
        if json { return printJSON(Response(ok: true)) }
        print("installed Perch hooks for \(agent) in \(path): \(target.eventNames.joined(separator: ", "))")
        if let note = target.installNote { print(note) }
    }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove Perch's hooks (only Perch's).")
    @Argument(help: "claude-code | codex | hermes") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookFiles.for(agent)
        let path = settings ?? target.defaultPath
        guard let text = try HookFiles.read(path) else {
            return json ? printJSON(Response(ok: true)) : print("no \(path); nothing to remove")
        }
        let (kept, removed) = try target.removing(text, path: path)
        if removed > 0 { try HookFiles.write(kept, to: path) }
        if json { return printJSON(Response(ok: true)) }
        print(removed > 0 ? "removed \(removed) Perch hook\(removed == 1 ? "" : "s") from \(path)" : "no Perch hooks in \(path)")
    }
}

/// One agent's hook configuration file. Implementations only ever add or remove Perch's own hooks.
protocol HookFile {
    var agent: String { get }
    var eventNames: [String] { get }
    var defaultPath: String { get }
    /// Printed after a successful install.
    var installNote: String? { get }
    /// The file with Perch's hooks (replacing any old ones). `text` is nil when the file does not exist.
    func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String
    /// The file without Perch's hooks, and how many there were.
    func removing(_ text: String, path: String) throws -> (text: String, removed: Int)
}

enum HookFiles {
    static var all: [any HookFile] { [HookSettings.claudeCode, HookSettings.codex, HermesHooks()] }

    static func `for`(_ agent: String) throws -> any HookFile {
        guard let file = all.first(where: { $0.agent == agent }) else {
            let names = all.map(\.agent)
            throw CLIError("unknown agent '\(agent)'; use \(names.dropLast().joined(separator: ", ")) or \(names.last!)", code: 64)
        }
        return file
    }

    static func currentBinary() throws -> String {
        let url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        if FileManager.default.isExecutableFile(atPath: url.path) { return url.path }
        guard let path = Bundle.main.executablePath else { throw CLIError("cannot tell where perch is; pass --binary") }
        return path
    }

    /// `$<dirVariable>/<file>`, else `~/<defaultDir>/<file>`.
    static func configFile(dirVariable: String, defaultDir: String, file: String) -> String {
        let dir = ProcessInfo.processInfo.environment[dirVariable].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultDir).path
        return URL(fileURLWithPath: dir).appendingPathComponent(file).path
    }

    static func read(_ path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError("\(path) is not UTF-8 text; nothing was changed")
        }
        return text
    }

    /// Backs up the old file to `<path>.perch-backup`, then replaces it atomically.
    static func write(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: path) {
            let backup = URL(fileURLWithPath: path + ".perch-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Single-quotes a path for the hook's shell command when it needs it.
    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+@%:,"))
        if !s.isEmpty && s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// An agent's hook file, edited as plain JSON. Claude Code's settings.json and Codex's hooks.json share the
/// `hooks → event → [{matcher, hooks: [handler]}]` shape. Only handlers whose command runs `perch … hook <agent>`
/// are Perch's; everything else is left as it was (key order may change: the file is rewritten sorted).
struct HookSettings: HookFile {
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

    let agent: String
    let events: [HookEvent]
    let defaultPath: String
    var installNote: String?

    var eventNames: [String] { events.map(\.name) }

    static var claudeCode: HookSettings {
        HookSettings(agent: "claude-code", events: [
            HookEvent(name: "UserPromptSubmit"),
            HookEvent(name: "Notification", matcher: HookAdapter.waitingNotifications.sorted { order($0) < order($1) }.joined(separator: "|")),
            HookEvent(name: "PermissionRequest", mode: .blocking),
            HookEvent(name: "PostToolUse"),
            HookEvent(name: "PostToolUseFailure"),
            HookEvent(name: "Stop"),
            HookEvent(name: "StopFailure"),
            HookEvent(name: "SessionEnd"),
        ], defaultPath: HookFiles.configFile(dirVariable: "CLAUDE_CONFIG_DIR", defaultDir: ".claude", file: "settings.json"))
    }

    /// Codex has no Notification / StopFailure / PostToolUseFailure; Interrupt covers Esc (no Stop follows).
    static var codex: HookSettings {
        HookSettings(agent: "codex", events: [
            HookEvent(name: "UserPromptSubmit"),
            HookEvent(name: "PermissionRequest", mode: .blocking),
            HookEvent(name: "PostToolUse"),
            HookEvent(name: "Stop"),
            HookEvent(name: "Interrupt", mode: .async(timeout: 3)),
            HookEvent(name: "SessionEnd", mode: .sync(timeout: 3)),
        ], defaultPath: HookFiles.configFile(dirVariable: "CODEX_HOME", defaultDir: ".codex", file: "hooks.json"),
        installNote: "Codex skips new or changed hooks until you trust them: start codex and review them with /hooks.")
    }

    private static func order(_ type: String) -> Int {
        ["permission_prompt", "elicitation_dialog", "agent_needs_input"].firstIndex(of: type) ?? 99
    }

    func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String {
        var root = try parse(text, path: path)
        remove(from: &root)
        add(to: &root, perch: perch, wait: wait)
        return try Self.render(root)
    }

    func removing(_ text: String, path: String) throws -> (text: String, removed: Int) {
        var root = try parse(text, path: path)
        let removed = remove(from: &root)
        return (try Self.render(root), removed)
    }

    func isPerch(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.contains(" hook \(agent)") && command.contains("perch")
    }

    private func parse(_ text: String?, path: String) throws -> [String: Any] {
        guard let text, !text.allSatisfy(\.isWhitespace) else { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw CLIError("\(path) is not valid JSON (or not an object); fix it first, nothing was changed")
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
                hook = ["type": "command", "command": command, "timeout": timeout]
            }
            var group: [String: Any] = ["hooks": [hook]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [group]
        }
        root["hooks"] = hooks
    }

    static func render(_ root: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// Hermes Agent's shell hooks live in the top-level `hooks:` map of ~/.hermes/config.yaml. Without a YAML
/// library Perch writes one marked block at the end of the file and never edits anything else. Hermes may later
/// rewrite the file with yaml.dump, which drops the markers, so a `hooks:` section is also recognised by its
/// commands: one holding only Perch's hooks is Perch's; one with anyone else's is left alone and install refuses
/// (two `hooks:` keys would clash).
///
/// Hermes runs shell hooks synchronously, so every hook gets a short timeout; the adapter itself is fast.
struct HermesHooks: HookFile {
    let agent = "hermes"
    let eventNames = ["pre_llm_call", "post_llm_call", "on_session_end", "pre_approval_request", "post_approval_response"]
    var defaultPath: String { HookFiles.configFile(dirVariable: "HERMES_HOME", defaultDir: ".hermes", file: "config.yaml") }
    let installNote: String? = """
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

    func installing(_ text: String?, path: String, perch: String, wait: Int) throws -> String {
        var lines = Self.withoutBlock(text ?? "").text.components(separatedBy: "\n")
        switch Self.section(in: lines) {
        case .none: break
        case .empty(let range), .perch(let range, _): lines.removeSubrange(range)
        case .others:
            throw CLIError("\(path) already has a hooks: section; add Perch's to it by hand (`perch hooks install hermes --settings /dev/null --dry-run` prints them)")
        }
        var kept = lines.joined(separator: "\n")
        if !kept.isEmpty && !kept.hasSuffix("\n") { kept += "\n" }
        return kept + block(perch: perch)
    }

    func removing(_ text: String, path: String) throws -> (text: String, removed: Int) {
        let (rest, inBlock) = Self.withoutBlock(text)
        var lines = rest.components(separatedBy: "\n")
        switch Self.section(in: lines) {
        case .perch(let range, let hooks):
            lines.removeSubrange(range)
            return (lines.joined(separator: "\n"), inBlock + hooks)
        case .others(withPerch: true):
            throw CLIError("\(path) mixes Perch's hooks with others under hooks:; remove Perch's entries by hand")
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
        guard let start = text.range(of: begin + "\n"),
              let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return (text, 0) }
        var upper = stop.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        let removed = text[start.lowerBound..<upper].components(separatedBy: "- command:").count - 1
        var kept = text
        kept.removeSubrange(start.lowerBound..<upper)
        return (kept, removed)
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
