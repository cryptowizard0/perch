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
        #expect(result.stdout.contains("UserPromptSubmit, Notification, Stop, StopFailure, SessionEnd"))
        var json = try read()
        #expect(json["model"] as? String == "opus")
        let ours = "/opt/perch/bin/perch hook claude-code"
        #expect(commands(json, "Stop") == ["other-tool notify", ours])
        #expect(commands(json, "PreToolUse") == ["/usr/local/bin/guard.sh"])
        for event in ["UserPromptSubmit", "Notification", "StopFailure", "SessionEnd"] {
            #expect(commands(json, event) == [ours], "\(event)")
        }
        let notification = ((json["hooks"] as! [String: Any])["Notification"] as! [[String: Any]])[0]
        #expect(notification["matcher"] as? String == "permission_prompt|elicitation_dialog|agent_needs_input")
        let hook = (notification["hooks"] as! [[String: Any]])[0]
        #expect(hook["async"] as? Bool == true)
        #expect(hook["type"] as? String == "command")
        #expect(FileManager.default.fileExists(atPath: settings.path + ".perch-backup"))

        // Installing again replaces instead of duplicating (e.g. after moving the binary).
        try cli.run("hooks", "install", "claude-code", "--settings", settings.path, "--binary", "/new place/perch")
        json = try read()
        #expect(commands(json, "Stop") == ["other-tool notify", "'/new place/perch' hook claude-code"])

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

    @Test func codexIsNotThereYet() throws {
        let result = try cli.run("hooks", "install", "codex", "--settings", settings.path)
        #expect(result.status == 1)
        #expect(result.stderr == "perch: codex hooks arrive in milestone M5")
    }
}
