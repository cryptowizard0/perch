import Foundation
import Testing

/// `perch setup` / `perch uninstall` / `perch hooks …` against a scratch home: HOME, PERCH_HOME and the agents'
/// config dirs all live under /tmp, and launchctl is a script that only logs its arguments.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct SetupCLITests {
    let home = URL(fileURLWithPath: "/tmp/perch-setup-\(UUID().uuidString.prefix(8))")
    var perchHome: URL { home.appendingPathComponent(".perch") }
    var bin: String { perchHome.appendingPathComponent("bin/perch").path }
    var claude: URL { home.appendingPathComponent(".claude/settings.json") }
    var codex: URL { home.appendingPathComponent(".codex/hooks.json") }
    var grok: URL { home.appendingPathComponent(".grok/hooks/perch.json") }
    var dsh: URL { home.appendingPathComponent(".dsh/cordis.patch.yml") }
    var plist: URL { home.appendingPathComponent("Library/LaunchAgents/dev.perch.perchd.plist") }
    var launchctlLog: URL { home.appendingPathComponent("launchctl.log") }
    let fm = FileManager.default

    /// Someone else's hook, which must survive setup and uninstall untouched.
    let other = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other-tool notify"}]}]}}"#

    init() throws {
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let launchctl = home.appendingPathComponent("launchctl")
        try "#!/bin/sh\necho \"$@\" >> \"\(launchctlLog.path)\"\n".write(to: launchctl, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctl.path)
    }

    @discardableResult
    func perch(_ args: String...) throws -> CLI.Result {
        try CLI(home: perchHome).run(args, env: [
            "HOME": home.path, "PERCH_LAUNCHCTL": home.appendingPathComponent("launchctl").path,
            "CLAUDE_CONFIG_DIR": "", "CODEX_HOME": "", "HERMES_HOME": "", "GROK_HOME": "",
        ])
    }

    func cleanUp() { try? fm.removeItem(at: home) }

    func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func json(_ url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    /// Every hook command in the file, per event.
    func commands(_ url: URL) throws -> [String: [String]] {
        let hooks = try json(url)["hooks"] as? [String: Any] ?? [:]
        return hooks.mapValues { groups in
            (groups as? [[String: Any]] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }
    }

    func perchCommands(_ url: URL) throws -> [String] {
        try commands(url).values.flatMap { $0 }.filter { $0 != "other-tool notify" }
    }

    func agents() throws -> [String: [String: Any]] {
        try json(perchHome.appendingPathComponent("agents.json"))["agents"] as! [String: [String: Any]]
    }

    func parse(_ stdout: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as! [String: Any]
    }

    @Test func setupConnectsTheDetectedAgents() throws {
        defer { cleanUp() }
        try write(other, to: claude)
        try fm.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)

        let result = try perch("setup", "--json")
        #expect(result.status == 0, "\(result.stderr)")
        let output = try parse(result.stdout)
        #expect(Set(output.keys) == ["ok", "agents"])
        #expect(output["ok"] as? Bool == true)
        let lines = try #require(output["agents"] as? [[String: String]])
        #expect(lines == [
            ["agent": "claude-code", "state": "connected", "config": claude.path],
            ["agent": "codex", "state": "needsTrust", "config": codex.path],
            ["agent": "grok", "state": "notDetected", "config": grok.path],
            ["agent": "dsh", "state": "notDetected", "config": dsh.path],
        ])

        // Real copies in the fixed location, and every hook runs them.
        for name in ["perch", "perchd"] {
            let path = perchHome.appendingPathComponent("bin/\(name)").path
            #expect(fm.isExecutableFile(atPath: path), "\(name)")
            #expect(try fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType == .typeRegular, "\(name)")
        }
        #expect(try commands(claude)["Stop"] == ["other-tool notify", "\(bin) hook claude-code"])
        #expect(try json(claude)["model"] as? String == "opus")
        for file in [claude, codex] {
            let ours = try perchCommands(file)
            #expect(!ours.isEmpty)
            #expect(ours.allSatisfy { $0.hasPrefix("\(bin) hook ") }, "\(ours)")
        }
        #expect(try commands(codex)["PermissionRequest"] == ["\(bin) hook codex --wait 20"])

        let recorded = try agents()
        #expect(recorded["claude-code"]?["status"] as? String == "on")
        #expect(recorded["claude-code"]?["config"] as? String == claude.path)
        #expect(recorded["codex"]?["status"] as? String == "on")
        let written = try #require(recorded["codex"]?["hooks_written_at"] as? String)

        // perchd's launchd agent runs the fixed copy (launchctl itself is the logging script).
        let agent = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        #expect((agent["ProgramArguments"] as? [String])?.first == perchHome.appendingPathComponent("bin/perchd").path)
        #expect(try String(contentsOf: launchctlLog, encoding: .utf8).contains("bootstrap gui/"))

        // Running it again changes nothing, so Codex is not asked to trust the same hooks twice.
        let again = try perch("setup")
        #expect(again.status == 0, "\(again.stderr)")
        #expect(again.stdout.contains("codex        needs trust"))
        #expect(again.stdout.contains("/hooks"))
        #expect(try agents()["codex"]?["hooks_written_at"] as? String == written)
    }

    /// Grok is detected by ~/.grok alone (it has no ~/.grok/hooks until someone adds one); Perch writes a file of its
    /// own there, which uninstall deletes.
    @Test func grokGetsAHookFileOfItsOwn() throws {
        defer { cleanUp() }
        try fm.createDirectory(at: home.appendingPathComponent(".grok"), withIntermediateDirectories: true)

        let result = try perch("setup", "grok", "--json")
        #expect(result.status == 0, "\(result.stderr)")
        let lines = try #require(try parse(result.stdout)["agents"] as? [[String: String]])
        #expect(lines.first { $0["agent"] == "grok" } == ["agent": "grok", "state": "connected", "config": grok.path])
        #expect(try commands(grok) == [
            "UserPromptSubmit": ["\(bin) hook grok"], "Notification": ["\(bin) hook grok"], "PostToolUse": ["\(bin) hook grok"],
            "PostToolUseFailure": ["\(bin) hook grok"], "Stop": ["\(bin) hook grok"], "StopFailure": ["\(bin) hook grok"],
            "StopCancelled": ["\(bin) hook grok"], "SessionEnd": ["\(bin) hook grok"],
        ])
        // Grok runs every hook in the foreground: no `async` (it logs a load error for it), a short timeout each.
        let hooks = try #require(try json(grok)["hooks"] as? [String: [[String: Any]]])
        for (event, groups) in hooks {
            for handler in groups.flatMap({ $0["hooks"] as? [[String: Any]] ?? [] }) {
                #expect(handler["async"] == nil && handler["statusMessage"] == nil, "\(event)")
                #expect((handler["timeout"] as? Int).map { $0 <= 5 } == true, "\(event)")
            }
        }
        #expect(hooks["Notification"]?.first?["matcher"] as? String == "permission_prompt|elicitation_dialog|agent_needs_input|idle_prompt")
        #expect(try agents()["grok"]?["status"] as? String == "on")

        // Set up again: nothing changes, and no backup lands next to Grok's hook files.
        #expect(try perch("setup", "grok").status == 0)
        #expect(try fm.contentsOfDirectory(atPath: grok.deletingLastPathComponent().path) == ["perch.json"])

        // Disconnecting deletes the file (it held nothing else); `perch uninstall` does too after reconnecting.
        #expect(try perch("hooks", "uninstall", "grok").stdout.contains("removed 8 Perch hooks"))
        #expect(!fm.fileExists(atPath: grok.path))
        #expect(try perch("setup", "grok").status == 0)
        #expect(fm.fileExists(atPath: grok.path))
        #expect(try perch("uninstall").status == 0)
        #expect(!fm.fileExists(atPath: grok.path))
    }

    /// dsh: setup finds ~/.dsh, writes the row into its home patch layer and the plugin next to the installed perch;
    /// uninstall takes both away and leaves the user's own rows.
    @Test func dshIsConnectedThroughItsPatchLayer() throws {
        defer { cleanUp() }
        let mine = "- id: tui\n  config:\n    theme: dark\n"
        try write(mine, to: dsh)
        let result = try perch("setup", "--json")
        #expect(result.status == 0, "\(result.stderr)")
        let lines = try #require(try parse(result.stdout)["agents"] as? [[String: String]])
        #expect(lines.first { $0["agent"] == "dsh" } == ["agent": "dsh", "state": "connected", "config": dsh.path])
        let layer = try String(contentsOf: dsh, encoding: .utf8)
        let plugin = perchHome.appendingPathComponent("bin/perch-dsh.mjs")
        #expect(layer.hasPrefix(mine + "# >>> perch:"))
        #expect(layer.contains("      name: '\(plugin.path)'\n"))
        #expect(layer.contains("        perch: '\(bin)'\n"))
        #expect(try String(contentsOf: plugin, encoding: .utf8).contains("export function apply(ctx, config)"))
        #expect(try agents()["dsh"]?["status"] as? String == "on")

        #expect(try perch("uninstall").status == 0)
        #expect(try String(contentsOf: dsh, encoding: .utf8) == mine)
        #expect(!fm.fileExists(atPath: plugin.path))
    }

    /// Someone else's hook in Perch's file stays (with the file) when Perch's hooks go.
    @Test func grokFileWithSomeoneElsesHookIsKept() throws {
        defer { cleanUp() }
        try fm.createDirectory(at: home.appendingPathComponent(".grok"), withIntermediateDirectories: true)
        #expect(try perch("setup", "grok").status == 0)
        var root = try json(grok)
        var hooks = root["hooks"] as! [String: Any]
        hooks["Stop"] = (hooks["Stop"] as! [[String: Any]]) + [["hooks": [["type": "command", "command": "other-tool notify"]]]]
        root["hooks"] = hooks
        try write(String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self), to: grok)
        #expect(try perch("hooks", "uninstall", "grok").status == 0)
        #expect(try commands(grok) == ["Stop": ["other-tool notify"]])
    }

    @Test func invalidJSONIsLeftAloneAndFails() throws {
        defer { cleanUp() }
        try write("{ not json", to: claude)
        try fm.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)

        let result = try perch("setup")
        #expect(result.status == 1)
        #expect(result.stderr == "perch: claude-code: \(claude.path) is not valid JSON (or not an object); fix it first, nothing was changed")
        #expect(try String(contentsOf: claude, encoding: .utf8) == "{ not json")
        #expect(!(try perchCommands(codex)).isEmpty)  // the other agent is still connected

        let json = try perch("setup", "--json")
        #expect(json.status == 1)
        let output = try parse(json.stdout)
        #expect(output["ok"] as? Bool == false)
        #expect((output["error"] as? String)?.contains("is not valid JSON") == true)

        let removed = try perch("uninstall")
        #expect(removed.status == 1)
        #expect(removed.stderr.contains("claude-code: \(claude.path) is not valid JSON"))
        #expect(try String(contentsOf: claude, encoding: .utf8) == "{ not json")
        #expect(try perchCommands(codex).isEmpty)
        #expect(!fm.fileExists(atPath: bin))
    }

    @Test func hooksUninstallTurnsAnAgentOff() throws {
        defer { cleanUp() }
        try fm.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(try perch("setup").status == 0)

        #expect(try perch("hooks", "uninstall", "codex").stdout.contains("removed 6 Perch hooks"))
        #expect(try agents()["codex"]?["status"] as? String == "off")

        let result = try perch("setup", "--json")
        #expect(result.status == 0, "\(result.stderr)")
        let lines = try #require(try parse(result.stdout)["agents"] as? [[String: String]])
        #expect(lines.map { $0["state"] } == ["connected", "off", "notDetected", "notDetected"])
        #expect(try perchCommands(codex).isEmpty)

        // `hooks install` connects it again, by default against the fixed location.
        #expect(try perch("hooks", "install", "codex").status == 0)
        #expect(try agents()["codex"]?["status"] as? String == "on")
        #expect(try perchCommands(codex).allSatisfy { $0.hasPrefix("\(bin) hook codex") })
    }

    @Test func outdatedHooksAreRewrittenKeepingTheWait() throws {
        defer { cleanUp() }
        try write(other, to: claude)
        #expect(try perch("hooks", "install", "claude-code", "--binary", "/old/place/perch", "--wait", "45").status == 0)
        #expect(try perch("hooks", "install", "codex", "--binary", "/old/place/perch", "--wait", "33").status == 0)
        // An older Perch: no Interrupt hook for Codex.
        var root = try json(codex)
        var hooks = root["hooks"] as! [String: Any]
        hooks["Interrupt"] = nil
        root["hooks"] = hooks
        try write(String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self), to: codex)

        let result = try perch("setup")
        #expect(result.status == 0, "\(result.stderr)")
        #expect(try commands(claude)["PermissionRequest"] == ["\(bin) hook claude-code --wait 45"])
        #expect(try commands(claude)["Stop"] == ["other-tool notify", "\(bin) hook claude-code"])
        #expect(try commands(codex)["PermissionRequest"] == ["\(bin) hook codex --wait 33"])
        #expect(try commands(codex)["Interrupt"] == ["\(bin) hook codex"])
        #expect(try perchCommands(claude).allSatisfy { $0.hasPrefix("\(bin) hook ") })
        #expect(fm.fileExists(atPath: codex.path + ".perch-backup"))
        #expect(result.stdout.contains("codex        needs trust"))

        // An explicit --wait wins.
        #expect(try perch("setup", "claude-code", "--wait", "60").status == 0)
        #expect(try commands(claude)["PermissionRequest"] == ["\(bin) hook claude-code --wait 60"])
    }

    @Test func migratesAV03Install() throws {
        defer { cleanUp() }
        // v0.3: perch / perchd copied into ~/.local/bin, hooks and launchd pointing there, no agents.json.
        let localBin = home.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: localBin, withIntermediateDirectories: true)
        let built = CLI.binary!.deletingLastPathComponent()
        for name in ["perch", "perchd"] {
            try fm.copyItem(at: built.appendingPathComponent(name), to: localBin.appendingPathComponent(name))
        }
        let old = localBin.appendingPathComponent("perch").path
        try write(other, to: claude)
        #expect(try perch("hooks", "install", "claude-code", "--binary", old).status == 0)
        #expect(try perch("hooks", "install", "codex", "--binary", old).status == 0)
        try fm.removeItem(at: perchHome.appendingPathComponent("agents.json"))
        try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["Label": "dev.perch.perchd", "ProgramArguments": [localBin.appendingPathComponent("perchd").path, "run"]],
                                           format: .xml, options: 0).write(to: plist)
        try "notes\n".write(to: localBin.appendingPathComponent("other-tool"), atomically: true, encoding: .utf8)

        let result = try perch("setup")
        #expect(result.status == 0, "\(result.stderr)")
        for file in [claude, codex] {
            #expect(try perchCommands(file).allSatisfy { $0.hasPrefix("\(bin) hook ") }, "\(file.path)")
        }
        #expect(try commands(claude)["Stop"] == ["other-tool notify", "\(bin) hook claude-code"])
        for name in ["perch", "perchd"] {
            #expect(try fm.destinationOfSymbolicLink(atPath: localBin.appendingPathComponent(name).path)
                    == perchHome.appendingPathComponent("bin/\(name)").path)
        }
        #expect(try String(contentsOf: localBin.appendingPathComponent("other-tool"), encoding: .utf8) == "notes\n")
        let agent = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        #expect((agent["ProgramArguments"] as? [String])?.first == perchHome.appendingPathComponent("bin/perchd").path)
        let recorded = try agents()
        #expect(recorded["claude-code"]?["status"] as? String == "on")
        #expect(recorded["codex"]?["status"] as? String == "on")
        #expect(result.stdout.contains("codex        needs trust"))
    }

    @Test func upgradeConnectsNothingNew() throws {
        defer { cleanUp() }
        try write(other, to: claude)
        try write("{}", to: codex)
        #expect(try perch("hooks", "install", "claude-code", "--binary", "/old/perch").status == 0)

        let result = try perch("setup", "--upgrade")
        #expect(result.status == 0, "\(result.stderr)")
        #expect(fm.isExecutableFile(atPath: bin))
        #expect(try perchCommands(claude).allSatisfy { $0.hasPrefix("\(bin) hook ") }, "repaired")
        #expect(try String(contentsOf: codex, encoding: .utf8) == "{}", "never connected, so left alone")
        #expect(try agents()["codex"] == nil)
        #expect(try String(contentsOf: launchctlLog, encoding: .utf8).contains("bootstrap gui/"), "perchd restarted")

        let named = try perch("setup", "--upgrade", "codex")
        #expect(named.status == 64)
        #expect(named.stderr == "perch: --upgrade connects nothing new; it takes no agent names or --wait")
    }

    @Test func uninstallKeepsDataUnlessPurged() throws {
        defer { cleanUp() }
        try write(other, to: claude)
        try fm.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(try perch("setup").status == 0)
        try "{}".write(to: perchHome.appendingPathComponent("allowlist.json"), atomically: true, encoding: .utf8)
        let localBin = home.appendingPathComponent(".local/bin")
        try fm.createDirectory(at: localBin, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: localBin.appendingPathComponent("perch").path, withDestinationPath: bin)
        try fm.createSymbolicLink(atPath: localBin.appendingPathComponent("other").path, withDestinationPath: "/usr/bin/true")

        let result = try perch("uninstall", "--json")
        #expect(result.status == 0, "\(result.stderr)")
        let output = try parse(result.stdout)
        #expect(output["ok"] as? Bool == true)
        #expect(output["purged"] as? Bool == false)
        let removals = try #require(output["agents"] as? [[String: Any]])
        #expect(removals.map { $0["agent"] as? String } == ["claude-code", "codex"])
        #expect(removals.map { $0["removed"] as? Int } == [8, 6])

        #expect(try commands(claude) == ["Stop": ["other-tool notify"]])
        #expect(try json(claude)["model"] as? String == "opus")
        #expect(try perchCommands(codex).isEmpty)
        #expect(!fm.fileExists(atPath: plist.path))
        #expect(try String(contentsOf: launchctlLog, encoding: .utf8).contains("bootout gui/"))
        #expect(!fm.fileExists(atPath: perchHome.appendingPathComponent("bin").path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: localBin.appendingPathComponent("perch").path)) == nil)
        #expect(try fm.destinationOfSymbolicLink(atPath: localBin.appendingPathComponent("other").path) == "/usr/bin/true")
        #expect(fm.fileExists(atPath: perchHome.appendingPathComponent("allowlist.json").path))
        #expect(try agents()["codex"]?["status"] as? String == "on")  // a reinstall picks up where it left off

        let purge = try perch("uninstall", "--purge")
        #expect(purge.status == 0, "\(purge.stderr)")
        #expect(!fm.fileExists(atPath: perchHome.path))
        #expect(try commands(claude) == ["Stop": ["other-tool notify"]])
    }

    @Test func unknownAgentAndBadWait() throws {
        defer { cleanUp() }
        let hermes = try perch("setup", "hermes")
        #expect(hermes.status == 64)
        #expect(hermes.stderr == "perch: unknown agent 'hermes'; use claude-code, codex, grok or dsh")
        let wait = try perch("setup", "--wait", "1", "--json")
        #expect(wait.status == 64)
        #expect(try parse(wait.stdout)["ok"] as? Bool == false)
        #expect(!fm.fileExists(atPath: bin))
    }
}
