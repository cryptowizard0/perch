import Foundation
import PerchSetup
import Testing

/// `Setup.evaluate`: the pure core shared by `perch setup` and the app's self-check.
@Suite struct StatusTests {
    static let home = "/Users/me"
    static let bin = "/Users/me/.perch/bin/perch"
    static let claudePath = "/Users/me/.claude/settings.json"
    static let codexPath = "/Users/me/.codex/hooks.json"
    static let app = SetupRunner.app(path: "/Applications/Perch.app")
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func snapshot(agents: AgentsFile = AgentsFile(), files: [String: ConfigFile] = [:], env: [String: String] = [:],
                  installed: String? = "0.4.0", bundled: String = "0.4.0", runner: SetupRunner = .cli) -> SetupSnapshot {
        SetupSnapshot(agents: agents, files: files, environment: env, userHome: Self.home, perchBinary: Self.bin,
                      installedVersion: installed, bundledVersion: bundled, runner: runner)
    }

    /// The hooks `perch setup` writes today.
    func current(_ file: HookSettings, perch: String = bin, wait: Int = 20) throws -> String {
        try file.installing(nil, path: "", perch: perch, wait: wait)
    }

    func state(_ evaluation: SetupEvaluation, _ agent: String) -> AgentState? {
        evaluation.agents.first { $0.agent == agent }?.state
    }

    @Test func notDetectedWithoutAConfigDirectory() {
        let result = Setup.evaluate(snapshot(), request: .setup())
        #expect(result.agents.map(\.agent) == ["claude-code", "codex"])
        #expect(result.agents.map(\.state) == [.notDetected, .notDetected])
        #expect(result.agents.map(\.config) == [Self.claudePath, Self.codexPath])
        #expect(result.plan.changes.isEmpty)
    }

    @Test func notAskedIsConnectedBySetupButNotBySelfCheck() throws {
        let files: [String: ConfigFile] = [Self.claudePath: .missing, Self.codexPath: .text("{}")]
        let check = Setup.evaluate(snapshot(files: files, runner: Self.app), request: .selfCheck)
        #expect(check.agents.map(\.state) == [.notAsked, .notAsked])
        #expect(check.plan.changes.isEmpty)

        let setup = Setup.evaluate(snapshot(files: files), request: .setup())
        #expect(setup.plan.changes.map(\.agent) == ["claude-code", "codex"])
        let claude = try #require(setup.plan.changes.first)
        #expect(claude.config == Self.claudePath)
        #expect(claude.hooksChanged)
        #expect(claude.text == (try current(.claudeCode)))
    }

    @Test func connectedNeedsNothing() throws {
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .on, config: Self.claudePath)])
        let files: [String: ConfigFile] = [Self.claudePath: .text(try current(.claudeCode))]
        for request in [SetupRequest.selfCheck, .setup()] {
            let result = Setup.evaluate(snapshot(agents: agents, files: files, runner: Self.app), request: request)
            #expect(state(result, "claude-code") == .connected)
            #expect(result.plan.changes.isEmpty)
        }
    }

    @Test func connectedWhateverElseIsInTheFile() throws {
        var root = try JSONSerialization.jsonObject(with: Data(try current(.claudeCode).utf8)) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        hooks["Stop"] = [["hooks": [["type": "command", "command": "other-tool notify"]]]] + (hooks["Stop"] as! [[String: Any]])
        root["hooks"] = hooks
        root["model"] = "opus"
        let text = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .on, config: Self.claudePath)])
        let result = Setup.evaluate(snapshot(agents: agents, files: [Self.claudePath: .text(text)]), request: .setup())
        #expect(state(result, "claude-code") == .connected)
        #expect(result.plan.changes.isEmpty)
    }

    @Test func offIsSkippedUnlessNamed() throws {
        let agents = AgentsFile(agents: ["codex": AgentRecord(status: .off, config: Self.codexPath)])
        let files: [String: ConfigFile] = [Self.codexPath: .text("{}"), Self.claudePath: .missing]
        let setup = Setup.evaluate(snapshot(agents: agents, files: files), request: .setup())
        #expect(state(setup, "codex") == .off)
        #expect(setup.plan.changes.map(\.agent) == ["claude-code"])

        let named = Setup.evaluate(snapshot(agents: agents, files: files), request: .setup(agents: ["codex"]))
        #expect(named.plan.changes.map(\.agent) == ["codex"])
        // Naming an agent connects it even where it isn't set up yet.
        let undetected = Setup.evaluate(snapshot(), request: .setup(agents: ["codex"]))
        #expect(undetected.plan.changes.map(\.agent) == ["codex"])
        #expect(undetected.plan.changes.first?.config == Self.codexPath)
    }

    @Test func oldPathIsRepairedKeepingTheWait() throws {
        let old = try current(.claudeCode, perch: "/Users/me/.local/bin/perch", wait: 45)
        // A v0.3 install: hooks but no agents.json entry. Hooks there mean the user connected it.
        for agents in [AgentsFile(), AgentsFile(agents: ["claude-code": AgentRecord(status: .on)])] {
            let result = Setup.evaluate(snapshot(agents: agents, files: [Self.claudePath: .text(old)], runner: Self.app),
                                        request: .selfCheck)
            #expect(state(result, "claude-code") == .outdated)
            let change = try #require(result.plan.changes.first)
            #expect(change.agent == "claude-code")
            #expect(change.text == (try current(.claudeCode, wait: 45)))
        }
    }

    @Test func outdatedEventSetIsRepaired() throws {
        var root = try JSONSerialization.jsonObject(with: Data(try current(.codex).utf8)) as! [String: Any]
        var hooks = root["hooks"] as! [String: Any]
        hooks["Interrupt"] = nil  // an older Perch without Interrupt …
        hooks["SessionStart"] = [["hooks": [["type": "command", "command": "\(Self.bin) hook codex", "async": true]]]]  // … and with SessionStart
        root["hooks"] = hooks
        let text = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        let agents = AgentsFile(agents: ["codex": AgentRecord(status: .on, trustedAt: t0)])
        let result = Setup.evaluate(snapshot(agents: agents, files: [Self.codexPath: .text(text)], runner: Self.app),
                                    request: .selfCheck)
        #expect(state(result, "codex") == .outdated)
        #expect(result.plan.changes.first?.text == (try current(.codex)))
    }

    @Test func offAndUnaskedAgentsAreNeverRepaired() throws {
        let old = try current(.claudeCode, perch: "/old/perch")
        let off = AgentsFile(agents: ["claude-code": AgentRecord(status: .off)])
        let result = Setup.evaluate(snapshot(agents: off, files: [Self.claudePath: .text(old)], runner: Self.app),
                                    request: .selfCheck)
        #expect(state(result, "claude-code") == .off)
        #expect(result.plan.changes.isEmpty)
    }

    @Test func setupWaitReplacesTheInstalledOne() throws {
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .on, config: Self.claudePath)])
        let files: [String: ConfigFile] = [Self.claudePath: .text(try current(.claudeCode, wait: 45))]
        let keep = Setup.evaluate(snapshot(agents: agents, files: files), request: .setup())
        #expect(keep.plan.changes.isEmpty)
        let result = Setup.evaluate(snapshot(agents: agents, files: files), request: .setup(wait: 60))
        #expect(result.plan.changes.first?.text == (try current(.claudeCode, wait: 60)))
    }

    @Test func codexNeedsTrustUntilAnEventAfterTheHooksWereWritten() throws {
        let files: [String: ConfigFile] = [Self.codexPath: .text(try current(.codex)), Self.claudePath: .text(try current(.claudeCode))]
        func codex(written: Date?, trusted: Date?) -> AgentState? {
            let agents = AgentsFile(agents: ["codex": AgentRecord(status: .on, hooksWrittenAt: written, trustedAt: trusted),
                                             "claude-code": AgentRecord(status: .on, hooksWrittenAt: written)])
            let result = Setup.evaluate(snapshot(agents: agents, files: files), request: .selfCheck)
            #expect(state(result, "claude-code") == .connected)  // Claude Code has no trust step
            return state(result, "codex")
        }
        #expect(codex(written: t0, trusted: nil) == .needsTrust)
        #expect(codex(written: nil, trusted: nil) == .needsTrust)
        #expect(codex(written: t0, trusted: t0.addingTimeInterval(-1)) == .needsTrust)
        #expect(codex(written: t0, trusted: t0.addingTimeInterval(1)) == .connected)
        #expect(codex(written: nil, trusted: t0) == .connected)
    }

    @Test func rewritingCodexHooksAsksForTrustAgain() throws {
        let trusted = AgentsFile(agents: ["codex": AgentRecord(status: .on, config: Self.codexPath,
                                                               hooksWrittenAt: t0, trustedAt: t0.addingTimeInterval(60))])
        let old = try current(.codex, perch: "/Users/me/.local/bin/perch")
        let before = Setup.evaluate(snapshot(agents: trusted, files: [Self.codexPath: .text(old)], runner: Self.app),
                                    request: .selfCheck)
        let change = try #require(before.plan.changes.first)
        #expect(change.hooksChanged)

        let later = t0.addingTimeInterval(3600)
        let agents = before.plan.apply(to: trusted, at: later)
        #expect(agents["codex"]?.hooksWrittenAt == later)
        #expect(agents["codex"]?.trustedAt == t0.addingTimeInterval(60))
        let after = Setup.evaluate(snapshot(agents: agents, files: [Self.codexPath: .text(change.text!)]), request: .selfCheck)
        #expect(state(after, "codex") == .needsTrust)
        #expect(after.plan.changes.isEmpty)
    }

    @Test func setupRecordsAnAgentWhoseHooksAreAlreadyRight() throws {
        // `perch hooks install` by hand, then `perch setup` after `hooks uninstall` turned it off and the user named it.
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .off)])
        let files: [String: ConfigFile] = [Self.claudePath: .text(try current(.claudeCode))]
        let result = Setup.evaluate(snapshot(agents: agents, files: files), request: .setup(agents: ["claude-code"]))
        let change = try #require(result.plan.changes.first)
        #expect(change.text == nil)
        #expect(!change.hooksChanged)
        #expect(result.plan.apply(to: agents, at: t0)["claude-code"] == AgentRecord(status: .on, config: Self.claudePath))
    }

    @Test func invalidJSONIsAnErrorAndNeverWritten() {
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .on)])
        let files: [String: ConfigFile] = [Self.claudePath: .text("{ not json"), Self.codexPath: .unreadable("not UTF-8")]
        let check = Setup.evaluate(snapshot(agents: agents, files: files, runner: Self.app), request: .selfCheck)
        let claude = check.agents[0]
        #expect(claude.state == .outdated)
        #expect(claude.error?.hasPrefix("\(Self.claudePath) is not valid JSON") == true)
        #expect(check.agents[1].state == .notAsked)
        #expect(check.agents[1].error == "not UTF-8")
        #expect(check.plan.changes.isEmpty)
        #expect(check.plan.failures.map(\.agent) == ["claude-code"])  // unasked agents aren't the app's business

        let setup = Setup.evaluate(snapshot(agents: agents, files: files), request: .setup())
        #expect(setup.plan.changes.isEmpty)
        #expect(setup.plan.failures.map(\.agent) == ["claude-code", "codex"])
    }

    // MARK: Config paths

    @Test func candidatesRecordedThenEnvironmentThenDefault() {
        let location = HookSettings.claudeCode.location
        #expect(location.candidates(recorded: nil, environment: [:], userHome: Self.home) == [Self.claudePath])
        #expect(location.candidates(recorded: "/r/settings.json", environment: ["CLAUDE_CONFIG_DIR": "/env"], userHome: Self.home)
                == ["/r/settings.json", "/env/settings.json", Self.claudePath])
        #expect(location.candidates(recorded: Self.claudePath, environment: ["CLAUDE_CONFIG_DIR": ""], userHome: Self.home)
                == [Self.claudePath])
    }

    @Test func recordedPathWinsWhenItsDirectoryExists() {
        let recorded = "/custom/claude/settings.json"
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .on, config: recorded)])
        let env = ["CLAUDE_CONFIG_DIR": "/env/claude"]
        func config(_ files: [String: ConfigFile]) -> String? {
            Setup.evaluate(snapshot(agents: agents, files: files, env: env), request: .selfCheck).agents.first?.config
        }
        #expect(config([recorded: .missing, "/env/claude/settings.json": .missing, Self.claudePath: .missing]) == recorded)
        #expect(config(["/env/claude/settings.json": .missing, Self.claudePath: .missing]) == "/env/claude/settings.json")
        #expect(config([Self.claudePath: .text("{}")]) == Self.claudePath)
        #expect(config([:]) == recorded)  // nowhere: the first candidate
    }

    // MARK: Binaries

    @Test func setupFromTheCLIAlwaysSyncs() {
        // Dev builds share a version string, so `perch setup` (install.sh) copies whatever it is run from.
        #expect(Setup.evaluate(snapshot(installed: "0.4.0", bundled: "0.4.0"), request: .setup()).plan.syncBinaries)
        #expect(Setup.evaluate(snapshot(env: ["PERCH_HOME": "/tmp/p"]), request: .setup()).plan.syncBinaries)
    }

    @Test func appSyncsWhenVersionsDifferEitherWay() {
        func syncs(installed: String?, bundled: String, runner: SetupRunner = StatusTests.app) -> Bool {
            Setup.evaluate(snapshot(installed: installed, bundled: bundled, runner: runner), request: .selfCheck).plan.syncBinaries
        }
        #expect(syncs(installed: "0.3.0", bundled: "0.4.0"))
        #expect(syncs(installed: "0.5.0", bundled: "0.4.0"))  // rolling back to an older app
        #expect(syncs(installed: nil, bundled: "0.4.0"))
        #expect(!syncs(installed: "0.4.0", bundled: "0.4.0"))
        #expect(syncs(installed: "0.3.0", bundled: "0.4.0", runner: .app(path: "/Users/me/Applications/Perch.app")))
    }

    @Test func devBuildsTouchNothing() throws {
        let old = try current(.claudeCode, perch: "/old/perch")
        let agents = AgentsFile(agents: ["claude-code": AgentRecord(status: .on)])
        let files: [String: ConfigFile] = [Self.claudePath: .text(old)]
        let cases: [(SetupRunner, [String: String])] = [
            (.app(path: "/Users/me/src/perch/.build/Perch.app"), [:]),
            (.app(path: "/Users/me/Downloads/Perch.app"), [:]),
            (Self.app, ["PERCH_HOME": "/tmp/p"]),
        ]
        for (runner, env) in cases {
            let result = Setup.evaluate(snapshot(agents: agents, files: files, env: env, installed: "0.3.0", runner: runner),
                                        request: .selfCheck)
            #expect(state(result, "claude-code") == .outdated)
            #expect(!result.plan.syncBinaries, "\(runner)")
            #expect(result.plan.changes.isEmpty, "\(runner)")
        }
    }
}
