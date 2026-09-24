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
        discussion: "claude-code: ~/.claude/settings.json ($CLAUDE_CONFIG_DIR/settings.json if set). A backup is written next to it."
    )
    @Argument(help: "claude-code | codex") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Option(help: "perch binary the hooks run (default: this one).") var binary: String?
    @Flag(help: "Print the resulting settings instead of writing them.") var dryRun = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        try requireClaudeCode(agent)
        let path = settings ?? ClaudeSettings.defaultPath
        let perch = try binary ?? ClaudeSettings.currentBinary()
        var root = try ClaudeSettings.read(path)
        ClaudeSettings.remove(from: &root)
        ClaudeSettings.add(to: &root, command: "\(ClaudeSettings.shellQuote(perch)) hook claude-code")
        if dryRun { return print(try ClaudeSettings.render(root)) }
        if perch.contains("/.build/") {
            FileHandle.standardError.write(Data("perch: warning: hooks run \(perch); `swift package clean` would break them. Copy perch somewhere stable and install with --binary.\n".utf8))
        }
        try ClaudeSettings.write(root, to: path)
        if json { return printJSON(Response(ok: true)) }
        print("installed Perch hooks for claude-code in \(path): \(ClaudeSettings.events.map(\.name).joined(separator: ", "))")
    }
}

struct HooksUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Remove Perch's hooks (only Perch's).")
    @Argument(help: "claude-code | codex") var agent: String
    @Option(help: "Settings file to edit (default: the agent's user settings).") var settings: String?
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        try requireClaudeCode(agent)
        let path = settings ?? ClaudeSettings.defaultPath
        guard FileManager.default.fileExists(atPath: path) else {
            return json ? printJSON(Response(ok: true)) : print("no \(path); nothing to remove")
        }
        var root = try ClaudeSettings.read(path)
        let removed = ClaudeSettings.remove(from: &root)
        if removed > 0 { try ClaudeSettings.write(root, to: path) }
        if json { return printJSON(Response(ok: true)) }
        print(removed > 0 ? "removed \(removed) Perch hook\(removed == 1 ? "" : "s") from \(path)" : "no Perch hooks in \(path)")
    }
}

private func requireClaudeCode(_ agent: String) throws {
    switch agent {
    case "claude-code": return
    case "codex": throw CLIError("codex hooks arrive in milestone M5")
    default: throw CLIError("unknown agent '\(agent)'; use claude-code or codex", code: 64)
    }
}

/// Edits Claude Code's settings.json as plain JSON: only entries whose command runs `perch … hook claude-code`
/// are Perch's; everything else is left as it was (key order may change: the file is rewritten sorted).
enum ClaudeSettings {
    struct HookEvent {
        let name: String
        let matcher: String?
    }

    /// All async: none of them decides anything, so the agent never waits on Perch.
    static let events = [
        HookEvent(name: "UserPromptSubmit", matcher: nil),
        HookEvent(name: "Notification", matcher: HookAdapter.waitingNotifications.sorted { order($0) < order($1) }.joined(separator: "|")),
        HookEvent(name: "Stop", matcher: nil),
        HookEvent(name: "StopFailure", matcher: nil),
        HookEvent(name: "SessionEnd", matcher: nil),
    ]

    private static func order(_ type: String) -> Int {
        ["permission_prompt", "elicitation_dialog", "agent_needs_input"].firstIndex(of: type) ?? 99
    }

    static var defaultPath: String {
        let env = ProcessInfo.processInfo.environment
        let dir = env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path
        return URL(fileURLWithPath: dir).appendingPathComponent("settings.json").path
    }

    static func currentBinary() throws -> String {
        let url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        if FileManager.default.isExecutableFile(atPath: url.path) { return url.path }
        guard let path = Bundle.main.executablePath else { throw CLIError("cannot tell where perch is; pass --binary") }
        return path
    }

    static func isPerch(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        return command.hasSuffix(" hook claude-code") && command.contains("perch")
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
    static func remove(from root: inout [String: Any]) -> Int {
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

    static func add(to root: inout [String: Any], command: String) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "async": true, "timeout": 10]]]
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
