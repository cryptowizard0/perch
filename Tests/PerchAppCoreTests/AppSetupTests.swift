import Foundation
import PerchAppCore
import PerchCore
import PerchSetup
import Testing

/// The app's self-check, Connect, Agents menu and trust recording, on disk in a scratch home. launchctl is a script
/// that only logs its arguments; the bundle's perch / perchd are scripts that print their version.
@MainActor
@Suite struct AppSetupTests {
    let home: URL
    var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
    var codexHooks: URL { home.appendingPathComponent(".codex/hooks.json") }
    var bin: URL { home.appendingPathComponent(".perch/bin") }
    var launchctlLog: URL { home.appendingPathComponent("launchctl.log") }
    var app: URL { home.appendingPathComponent("Applications/Perch.app") }

    final class Memory: @unchecked Sendable {
        var shown = false
        var memory: CardMemory { CardMemory(shown: { self.shown }, markShown: { self.shown = true }) }
    }

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("perch-appsetup-\(UUID().uuidString.prefix(8))")
        let fm = FileManager.default
        for dir in [".claude", ".codex", "Applications/Perch.app/Contents/Helpers"] {
            try fm.createDirectory(at: home.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try script("launchctl", "echo \"$@\" >> '\(launchctlLog.path)'")
        try bundle(version: "0.5.0")
    }

    func script(_ path: String, _ body: String) throws {
        let url = home.appendingPathComponent(path)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The perch / perchd a Perch.app of this version carries.
    func bundle(version: String) throws {
        for name in ["perch", "perchd"] {
            try script("Applications/Perch.app/Contents/Helpers/\(name)", "echo \(version)")
        }
    }

    func setup(app: URL? = nil, version: String = "0.5.0", env: [String: String] = [:]) -> AppSetup {
        let installer = Installer(environment: SetupEnvironment(variables: ["HOME": home.path].merging(env) { $1 }),
                                  launchctl: Launchctl(path: home.appendingPathComponent("launchctl").path))
        return AppSetup(installer: installer, appPath: (app ?? self.app).path, bundledVersion: version)
    }

    func model(_ setup: AppSetup? = nil, memory: Memory = Memory()) -> SetupModel {
        SetupModel(setup: setup ?? self.setup(), memory: memory.memory, inline: true)
    }

    func installed() throws -> String {
        try String(contentsOf: bin.appendingPathComponent("perch"), encoding: .utf8)
    }

    func log() -> String {
        (try? String(contentsOf: launchctlLog, encoding: .utf8)) ?? ""
    }

    func agents() throws -> AgentsFile {
        try AgentsFile.load(from: home.appendingPathComponent(".perch/agents.json"))
    }

    // MARK: Binaries

    @Test func theAppInstallsItsBinariesAndStartsPerchd() throws {
        let report = setup().selfCheck()
        #expect(report.enabled)
        #expect(report.problems.isEmpty)
        #expect(try installed().contains("echo 0.5.0"))
        #expect(FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("perchd").path))
        #expect(log().contains("bootstrap gui/"))
        // Same version again: nothing to copy, perchd left running.
        try FileManager.default.removeItem(at: launchctlLog)
        _ = setup().selfCheck()
        #expect(log().isEmpty)
    }

    @Test func aReplacedAppReplacesTheBinariesEitherWay() throws {
        _ = setup().selfCheck()
        try bundle(version: "0.6.0")
        try FileManager.default.removeItem(at: launchctlLog)
        _ = setup(version: "0.6.0").selfCheck()
        #expect(try installed().contains("echo 0.6.0"))
        #expect(log().contains("bootout") && log().contains("bootstrap"), "perchd restarted")
        // Rolling back to an older app puts its binaries back too: the running app is the authority.
        try bundle(version: "0.4.0")
        _ = setup(version: "0.4.0").selfCheck()
        #expect(try installed().contains("echo 0.4.0"))
    }

    @Test func aDeveloperBuildTouchesNothing() throws {
        let dev = home.appendingPathComponent("src/perch/.build/Perch.app")
        for report in [setup(app: dev).selfCheck(),
                       setup(env: ["PERCH_HOME": home.appendingPathComponent("iso").path]).selfCheck()] {
            #expect(!report.enabled)
            #expect(report.statuses.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: bin.path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("iso/bin").path))
        #expect(log().isEmpty)
        let model = model(setup(app: dev))
        model.start()
        #expect(model.state.card == nil && model.state.rows.isEmpty && model.state.menu.isEmpty)
    }

    // MARK: First run

    @Test func firstRunShowsTheCardAndChangesNoConfigUntilConnect() throws {
        try "{\"model\":\"opus\"}".write(to: claudeSettings, atomically: true, encoding: .utf8)
        let memory = Memory()
        let model = model(memory: memory)
        var opened = 0
        model.onCardAppeared = { opened += 1 }
        model.start()
        #expect(opened == 1)
        #expect(memory.shown, "once")
        #expect(model.state.card?.choices.map(\.agent) == ["claude-code", "codex"])
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8) == "{\"model\":\"opus\"}")
        #expect(!FileManager.default.fileExists(atPath: codexHooks.path))

        model.connectCard()
        let settings = try String(contentsOf: claudeSettings, encoding: .utf8)
        #expect(settings.contains("\(bin.path)/perch hook claude-code"))
        #expect(settings.contains("\"model\" : \"opus\""), "other settings kept")
        #expect(try String(contentsOf: codexHooks, encoding: .utf8).contains("hook codex"))
        #expect(try agents()["claude-code"]?.status == .on)
        guard case .finished(let lines) = model.state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines.map(\.text) == ["Connected Claude Code", "Connected Codex", "Trust Perch's hooks: run /hooks in codex"])

        // The next launch: no card, the trust row.
        let next = self.model(memory: memory)
        next.start()
        #expect(next.state.card == nil)
        #expect(next.state.rows.map(\.kind) == [.trust])
    }

    @Test func notNowLeavesFoundRows() throws {
        let model = model()
        model.start()
        model.closeCard()
        #expect(model.state.rows.map(\.text) == ["Claude Code found", "Codex found"])
        #expect(!FileManager.default.fileExists(atPath: claudeSettings.path))
        let row = try #require(model.state.rows.first)
        model.connect(try #require(row.connects))
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8).contains("hook claude-code"))
        #expect(model.state.rows.map(\.text) == ["Codex found"])
    }

    // MARK: Repair

    @Test func outdatedHooksOfAConnectedAgentAreRepaired() throws {
        let old = try HookSettings.codex.installing(nil, path: codexHooks.path, perch: "/usr/local/bin/perch", wait: 45)
        try old.write(to: codexHooks, atomically: true, encoding: .utf8)
        let model = model()
        model.start()
        let hooks = try String(contentsOf: codexHooks, encoding: .utf8)
        #expect(hooks.contains("\(bin.path)/perch hook codex --wait 45"), "rewritten, keeping --wait")
        #expect(FileManager.default.fileExists(atPath: codexHooks.path + ".perch-backup"))
        #expect(model.state.card == nil, "v0.3 hooks: not a first run")
        #expect(model.state.rows.map(\.text) == ["Trust Perch's hooks: run /hooks in codex", "Claude Code found",
                                                  "Updated Perch's hooks for Codex"])
    }

    @Test func aBrokenHookFileIsLeftAloneAndShown() throws {
        try "{ not json".write(to: claudeSettings, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".perch"), withIntermediateDirectories: true)
        try AgentsFile(agents: ["claude-code": AgentRecord(status: .on, config: claudeSettings.path)])
            .save(to: home.appendingPathComponent(".perch/agents.json"))
        let model = model()
        model.start()
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8) == "{ not json")
        #expect(model.state.rows.first?.text == "Can't read ~/.claude/settings.json")
    }

    @Test func aBrokenAgentsFileShowsNoCardAndSaysSo() throws {
        let file = home.appendingPathComponent(".perch/agents.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ broken".write(to: file, atomically: true, encoding: .utf8)
        let model = model()
        model.start()
        #expect(model.state.card == nil)
        #expect(model.state.rows.first?.text == "Can't read ~/.perch/agents.json")
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ broken", "the user's choices are never overwritten")
    }

    @Test func aConnectThatCantWriteSaysSo() throws {
        let model = model()
        model.start()
        model.closeCard()
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: claude.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path) }
        model.connect("claude-code")
        let row = try #require(model.state.rows.first)
        #expect(row.kind == .problem)
        #expect(row.text == "Can't connect ~/.claude/settings.json")
        // Fixed and refreshed (the notch re-reads on every expand): the error goes, the offer is back.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        model.refresh()
        #expect(model.state.rows.map(\.text) == ["Claude Code found", "Codex found"])
    }

    // MARK: Agents menu

    @Test func theAgentsMenuConnectsAndDisconnects() throws {
        let model = model()
        model.start()
        model.closeCard()
        model.connect("codex")
        #expect(model.state.menu.map(\.on) == [false, true])
        model.disconnect("codex")
        #expect(model.state.menu.map(\.on) == [false, false])
        #expect(try agents()["codex"]?.status == .off, "recorded like `perch hooks uninstall`")
        #expect(!(try String(contentsOf: codexHooks, encoding: .utf8)).contains("hook codex"))
        #expect(model.state.rows.map(\.text) == ["Claude Code found"], "an agent turned off gets no row")
        // The next launch leaves it alone too.
        let next = self.model()
        next.start()
        #expect(!(try String(contentsOf: codexHooks, encoding: .utf8)).contains("hook codex"))
    }

    // MARK: Codex trust

    @Test func aCodexUpdateAfterTheHooksWereWrittenRecordsTrust() throws {
        let model = model()
        model.start()
        model.closeCard()
        model.connect("codex")
        #expect(model.state.rows.contains { $0.kind == .trust })
        let written = try #require(try agents()["codex"]?.hooksWrittenAt)

        func event(_ offset: TimeInterval, source: String = "codex") -> SessionEvent {
            var s = Session(id: "c1", source: source, startedAt: written.addingTimeInterval(offset))
            s.updatedAt = written.addingTimeInterval(offset)
            return SessionEvent(type: .updated, session: s, at: s.updatedAt)
        }
        model.observe(event(-30))
        #expect(model.state.rows.contains { $0.kind == .trust }, "ran before the hooks were written")
        #expect(try agents()["codex"]?.trustedAt == nil)
        model.observe(event(30, source: "claude-code"))
        #expect(try agents()["codex"]?.trustedAt == nil)

        model.observe(event(30))
        #expect(!model.state.rows.contains { $0.kind == .trust })
        #expect(try agents()["codex"]?.trustedAt == written.addingTimeInterval(30))
        let next = self.model()
        next.start()
        #expect(next.state.statuses.first { $0.agent == "codex" }?.state == .connected)
    }
}
