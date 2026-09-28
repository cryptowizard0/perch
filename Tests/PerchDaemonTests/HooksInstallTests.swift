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

    /// Hermes keeps its hooks in config.yaml: Perch owns one marked block and never touches the rest.
    @Test func hermesConfigYAML() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config.yaml")
        let original = "model:\n  default: hermes-4\nterminal:\n  backend: local\nhooks_auto_accept: false\n"
        try original.write(to: config, atomically: true, encoding: .utf8)
        func text() throws -> String { try String(contentsOf: config, encoding: .utf8) }

        let result = try cli.run("hooks", "install", "hermes", "--settings", config.path, "--binary", "/opt/perch/bin/perch")
        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.stdout.contains("pre_llm_call, post_llm_call, on_session_end, pre_approval_request, post_approval_response"))
        #expect(result.stdout.contains("hermes gateway restart"))  // new hooks need consent and a gateway restart
        var yaml = try text()
        #expect(yaml.hasPrefix(original))
        let block = String(yaml.dropFirst(original.count))
        #expect(block.contains("\nhooks:\n  pre_llm_call:\n    - command: \"/opt/perch/bin/perch hook hermes\"\n      timeout: 10\n"))
        for event in ["post_llm_call", "on_session_end", "pre_approval_request", "post_approval_response"] {
            #expect(block.contains("  \(event):\n    - command: \"/opt/perch/bin/perch hook hermes\"\n"), "\(event)")
        }
        #expect(FileManager.default.fileExists(atPath: config.path + ".perch-backup"))

        // Reinstalling replaces the block (a path with a space, quoted for shlex inside a YAML string).
        try cli.run("hooks", "install", "hermes", "--settings", config.path, "--binary", "/new place/perch")
        yaml = try text()
        #expect(yaml.components(separatedBy: "hooks:\n").count == 2)
        #expect(yaml.contains(#"- command: "'/new place/perch' hook hermes""#))

        let removed = try cli.run("hooks", "uninstall", "hermes", "--settings", config.path)
        #expect(removed.stdout.contains("removed 5 Perch hooks"))
        #expect(try text() == original)
        #expect(try cli.run("hooks", "uninstall", "hermes", "--settings", config.path).stdout.contains("no Perch hooks"))
    }

    @Test func hermesWithItsOwnHooksIsLeftAlone() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config.yaml")
        let mine = "model: x\nhooks:\n  post_tool_call:\n    - command: ~/.hermes/agent-hooks/fmt.sh\n"
        try mine.write(to: config, atomically: true, encoding: .utf8)
        let result = try cli.run("hooks", "install", "hermes", "--settings", config.path, "--binary", "/b/perch")
        #expect(result.status == 1)
        #expect(result.stderr.hasPrefix("perch: \(config.path) already has a hooks: section"))
        #expect(try String(contentsOf: config, encoding: .utf8) == mine)

        // An empty one is fine: it is replaced.
        try "model: x\nhooks: {}\nother: 1\n".write(to: config, atomically: true, encoding: .utf8)
        #expect(try cli.run("hooks", "install", "hermes", "--settings", config.path, "--binary", "/b/perch").status == 0)
        let yaml = try String(contentsOf: config, encoding: .utf8)
        #expect(yaml.hasPrefix("model: x\nother: 1\n"))
        #expect(yaml.components(separatedBy: "\nhooks:\n").count == 2)
    }

    /// Hermes rewrites config.yaml with yaml.dump (e.g. after `hermes config set`), dropping Perch's marker
    /// comments. A `hooks:` section holding only Perch's hooks is still recognised by its commands.
    @Test func hermesAfterHermesRewroteTheFile() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config.yaml")
        let rewritten = #"""
        model: x
        hooks:
          pre_llm_call:
          - command: /opt/perch/bin/perch hook hermes
            timeout: 10
          post_llm_call:
          - command: '''/new place/perch'' hook hermes'
            timeout: 10
        other: 1

        """#
        try rewritten.write(to: config, atomically: true, encoding: .utf8)
        let removed = try cli.run("hooks", "uninstall", "hermes", "--settings", config.path)
        #expect(removed.status == 0, "\(removed.stderr)")
        #expect(removed.stdout.contains("removed 2 Perch hooks"))
        #expect(try String(contentsOf: config, encoding: .utf8) == "model: x\nother: 1\n")

        try rewritten.write(to: config, atomically: true, encoding: .utf8)
        #expect(try cli.run("hooks", "install", "hermes", "--settings", config.path, "--binary", "/b/perch").status == 0)
        let yaml = try String(contentsOf: config, encoding: .utf8)
        #expect(yaml.hasPrefix("model: x\nother: 1\n"))
        #expect(yaml.components(separatedBy: "\nhooks:\n").count == 2)
        #expect(!yaml.contains("/opt/perch"))

        // Mixed with someone else's hook: Perch will not guess which lines are whose.
        try rewritten.replacingOccurrences(of: "  post_llm_call:", with: "  post_tool_call:\n  - command: ~/.hermes/agent-hooks/fmt.sh\n  post_llm_call:")
            .write(to: config, atomically: true, encoding: .utf8)
        let mixed = try cli.run("hooks", "uninstall", "hermes", "--settings", config.path)
        #expect(mixed.status == 1)
        #expect(mixed.stderr.contains("remove Perch's entries by hand"))
    }

    @Test func unknownAgent() throws {
        let result = try cli.run("hooks", "install", "cursor", "--settings", settings.path)
        #expect(result.status == 64)
        #expect(result.stderr == "perch: unknown agent 'cursor'; use claude-code, codex or hermes")
    }
}
