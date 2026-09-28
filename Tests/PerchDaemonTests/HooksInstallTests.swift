import Foundation
import PerchCore
import Testing

/// `perch hooks install|uninstall claude-code` against a scratch settings.json.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct HooksInstallTests {
    let dir = URL(fileURLWithPath: "/tmp/perch-test-settings-\(UUID().uuidString.prefix(6))")
    var settings: URL { dir.appendingPathComponent("settings.json") }
    var cli: CLI { CLI(home: dir) }

    /// Someone else's hooks, which must survive install and uninstall untouched.
    let existing = #"""
    {
      "model": "opus",
      "hooks": {
        "Stop": [{"hooks": [{"type": "command", "command": "other-tool notify"}]}],
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/guard.sh"}]}]
      }
    }
    """#

    func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
    }

    func commands(_ json: [String: Any], _ event: String) -> [String] {
        let groups = (json["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    @Test func installMergesAndUninstallRestores() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try existing.write(to: settings, atomically: true, encoding: .utf8)

        let result = try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/opt/perch/bin/perch")
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("UserPromptSubmit, Notification, PermissionRequest, PostToolUse, PostToolUseFailure, Stop, StopFailure, SessionEnd"))
        var json = try read()
        #expect(json["model"] as? String == "opus")
        let ours = "/opt/perch/bin/perch hook claude-code"
        #expect(commands(json, "Stop") == ["other-tool notify", ours])
        #expect(commands(json, "PreToolUse") == ["/usr/local/bin/guard.sh"])
        for event in ["UserPromptSubmit", "Notification", "PostToolUse", "PostToolUseFailure", "StopFailure", "SessionEnd"] {
            #expect(commands(json, event) == [ours], "\(event)")
        }
        // PermissionRequest blocks (it answers), with room for the wait.
        #expect(commands(json, "PermissionRequest") == [ours + " --wait 20"])
        let permission = (((json["hooks"] as! [String: Any])["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(permission["async"] == nil)
        #expect(permission["timeout"] as? Int == 30)
        #expect((permission["statusMessage"] as? String)?.contains("Perch") == true)
        let notification = ((json["hooks"] as! [String: Any])["Notification"] as! [[String: Any]])[0]
        #expect(notification["matcher"] as? String == "permission_prompt|elicitation_dialog|agent_needs_input")
        let hook = (notification["hooks"] as! [[String: Any]])[0]
        #expect(hook["async"] as? Bool == true)
        #expect(hook["type"] as? String == "command")
        #expect(FileManager.default.fileExists(atPath: settings.path + ".perch-backup"))

        // Installing again replaces instead of duplicating (e.g. after moving the binary).
        try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/new place/perch", "--wait", "30")
        json = try read()
        #expect(commands(json, "Stop") == ["other-tool notify", "'/new place/perch' hook claude-code"])
        #expect(commands(json, "PermissionRequest") == ["'/new place/perch' hook claude-code --wait 30"])

        let removed = try cli.run("hooks", "uninstall", "claude-code", "--settings", settings.path)
        #expect(removed.status == 0)
        json = try read()
        let hooks = try #require(json["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["Stop", "PreToolUse"])
        #expect(commands(json, "Stop") == ["other-tool notify"])
    }

    @Test func createsTheFileAndDryRunWritesNothing() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let dry = try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/b/perch", "--dry-run")
        #expect(dry.status == 0)
        #expect(dry.stdout.contains(#""command" : "/b/perch hook claude-code""#))
        #expect(!FileManager.default.fileExists(atPath: settings.path))

        try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/b/perch")
        #expect(commands(try read(), "Stop") == ["/b/perch hook claude-code"])
        try cli.run("hooks", "uninstall", "claude-code", "--settings", settings.path)
        #expect(try read().isEmpty)
    }

    @Test func refusesBrokenSettings() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "{ not json".write(to: settings, atomically: true, encoding: .utf8)
        let result = try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/b/perch")
        #expect(result.status == 1)
        #expect(result.stderr.hasPrefix("perch: \(settings.path) is not valid JSON"))
        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ not json")
    }

    @Test func codexHooksJSON() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let hooksFile = dir.appendingPathComponent("hooks.json")
        let other = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"SUPERSET_AGENT_ID=codex \"/x/notify.sh\""}]}]}}"#
        try other.write(to: hooksFile, atomically: true, encoding: .utf8)
        func readCodex() throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile)) as! [String: Any] }
        func hook(_ json: [String: Any], _ event: String) -> [String: Any]? {
            (((json["hooks"] as? [String: Any])?[event] as? [[String: Any]])?.last?["hooks"] as? [[String: Any]])?.first
        }

        let result = try cli.run("hooks", "install", "codex", "--settings", hooksFile.path, "--binary", "/opt/perch/bin/perch")
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("UserPromptSubmit, PermissionRequest, PostToolUse, Stop, Interrupt, SessionEnd"))
        #expect(result.stdout.contains("/hooks"))  // Codex skips hooks until they are trusted
        let json = try readCodex()
        let ours = "/opt/perch/bin/perch hook codex"
        #expect(commands(json, "Stop") == [#"SUPERSET_AGENT_ID=codex "/x/notify.sh""#, ours])
        // Codex has no Notification / StopFailure / PostToolUseFailure.
        let events = Set((json["hooks"] as? [String: Any] ?? [:]).keys)
        #expect(events == ["UserPromptSubmit", "PermissionRequest", "PostToolUse", "Stop", "Interrupt", "SessionEnd"])
        for event in ["UserPromptSubmit", "PostToolUse", "Interrupt"] {
            #expect(commands(json, event) == [ours], "\(event)")
            #expect(hook(json, event)?["async"] as? Bool == true, "\(event)")
        }
        // Codex caps Interrupt (like SessionEnd) at 1–3 s, even in the background.
        #expect(hook(json, "Interrupt")?["timeout"] as? Int == 3)
        #expect(commands(json, "PermissionRequest") == [ours + " --wait 20"])
        #expect(hook(json, "PermissionRequest")?["async"] == nil)
        #expect(hook(json, "PermissionRequest")?["timeout"] as? Int == 30)
        // Codex always runs SessionEnd synchronously, for at most 3 s.
        #expect(commands(json, "SessionEnd") == [ours])
        #expect(hook(json, "SessionEnd")?["async"] == nil)
        #expect(hook(json, "SessionEnd")?["timeout"] as? Int == 3)

        // Codex and Claude Code hooks never touch each other.
        try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/opt/perch/bin/perch")
        let wrong = try cli.run("hooks", "uninstall", "claude-code", "--settings", hooksFile.path)
        #expect(wrong.stdout.contains("no Perch hooks"))

        let removed = try cli.run("hooks", "uninstall", "codex", "--settings", hooksFile.path)
        #expect(removed.stdout.contains("removed 6 Perch hooks"))
        #expect(commands(try readCodex(), "Stop") == [#"SUPERSET_AGENT_ID=codex "/x/notify.sh""#])
        #expect(Set((try readCodex()["hooks"] as? [String: Any] ?? [:]).keys) == ["Stop"])
        #expect(commands(try read(), "Stop") == ["/opt/perch/bin/perch hook claude-code"])
    }

    @Test func unknownAgent() throws {
        let result = try cli.run("hooks", "install", "cursor", "--settings", settings.path)
        #expect(result.status == 64)
        #expect(result.stderr == "perch: unknown agent 'cursor'; use claude-code or codex")
    }
}
