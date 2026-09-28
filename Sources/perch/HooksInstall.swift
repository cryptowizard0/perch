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
        A backup is written next to the file.
        """
    )
    @Argument(help: "claude-code | codex") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Option(help: "perch binary the hooks run (default: this one).") var binary: String?
    @Option(help: "Seconds a permission request waits for the notch before the terminal asks.")
    var wait: Int = Int(HookAdapter.permissionWait)
    @Flag(help: "Print the resulting settings instead of writing them.") var dryRun = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookSettings.for(agent)
        let path = settings ?? target.defaultPath
        let perch = try binary ?? HookSettings.currentBinary()
        var root = try HookSettings.read(path)
        target.remove(from: &root)
        guard (5...300).contains(wait) else { throw CLIError("--wait must be between 5 and 300 seconds", code: 64) }
        target.add(to: &root, perch: HookSettings.shellQuote(perch), wait: wait)
        if dryRun { return print(try HookSettings.render(root)) }
        if perch.contains("/.build/") {
            FileHandle.standardError.write(Data("perch: warning: hooks run \(perch); `swift package clean` would break them. Copy perch somewhere stable and install with --binary.\n".utf8))
        }
        try HookSettings.write(root, to: path)
        if json { return printJSON(Response(ok: true)) }
        print("installed Perch hooks for \(agent) in \(path): \(target.events.map(\.name).joined(separator: ", "))")
        if let note = target.installNote { print(note) }
    }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove Perch's hooks (only Perch's).")
    @Argument(help: "claude-code | codex") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let target = try HookSettings.for(agent)
        let path = settings ?? target.defaultPath
        guard FileManager.default.fileExists(atPath: path) else {
            return json ? printJSON(Response(ok: true)) : print("no \(path); nothing to remove")
        }
        var root = try HookSettings.read(path)
        let removed = target.remove(from: &root)
        if removed > 0 { try HookSettings.write(root, to: path) }
        if json { return printJSON(Response(ok: true)) }
        print(removed > 0 ? "removed \(removed) Perch hook\(removed == 1 ? "" : "s") from \(path)" : "no Perch hooks in \(path)")
    }
}

/// An agent's hook file, edited as plain JSON. Claude Code's settings.json and Codex's hooks.json share the
/// `hooks → event → [{matcher, hooks: [handler]}]` shape. Only handlers whose command runs `perch … hook <agent>`
/// are Perch's; everything else is left as it was (key order may change: the file is rewritten sorted).
struct HookSettings {
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
    /// Printed after a successful install.
    var installNote: String?

    static var all: [HookSettings] { [claudeCode, codex] }

    static func `for`(_ agent: String) throws -> HookSettings {
        guard let settings = all.first(where: { $0.agent == agent }) else {
            throw CLIError("unknown agent '\(agent)'; use \(all.map(\.agent).joined(separator: " or "))", code: 64)
        }
        return settings
    }

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
        ], defaultPath: configFile(dirVariable: "CLAUDE_CONFIG_DIR", defaultDir: ".claude", file: "settings.json"))
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
        ], defaultPath: configFile(dirVariable: "CODEX_HOME", defaultDir: ".codex", file: "hooks.json"),
        installNote: "Codex skips new or changed hooks until you trust them: start codex and review them with /hooks.")
    }

    private static func order(_ type: String) -> Int {
        ["permission_prompt", "elicitation_dialog", "agent_needs_input"].firstIndex(of: type) ?? 99
    }

    /// `$<dirVariable>/<file>`, else `~/<defaultDir>/<file>`.
    private static func configFile(dirVariable: String, defaultDir: String, file: String) -> String {
        let dir = ProcessInfo.processInfo.environment[dirVariable].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(defaultDir).path
        return URL(fileURLWithPath: dir).appendingPathComponent(file).path
    }

    static func currentBinary() throws -> String {
        let url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        if FileManager.default.isExecutableFile(atPath: url.path) { return url.path }
        guard let path = Bundle.main.executablePath else { throw CLIError("cannot tell where perch is; pass --binary") }
        return path
    }

    func isPerch(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.contains(" hook \(agent)") && command.contains("perch")
    }

    static func read(_ path: String) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path) else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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
        return String(decoding: data, as: UTF8.self)
    }

    /// Backs up the old file to `<path>.perch-backup`, then replaces it atomically.
    static func write(_ root: [String: Any], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: path) {
            let backup = URL(fileURLWithPath: path + ".perch-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: url, to: backup)
        }
        try Data((try render(root) + "\n").utf8).write(to: url, options: .atomic)
    }

    /// Single-quotes a path for the hook's shell command when it needs it.
    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+@%:,"))
        if !s.isEmpty && s.unicodeScalars.allSatisfy(safe.contains) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
