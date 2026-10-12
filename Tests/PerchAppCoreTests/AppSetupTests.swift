import Foundation
import PerchAppCore
import PerchCore
import PerchSetup
import Testing

/// The app's self-check, Connect, Agents menu and trust recording, on disk in a scratch home. launchctl is a script
/// that only logs its arguments; the bundle's perch / perchd are scripts that print their version. The disk work runs
/// off the main thread (the model's own queue, then `settle()`), which the latency tests elsewhere need free.
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

    /// Stands in for `SMAppService.mainApp` (tests never register the test runner) and the Trash. Touched from the
    /// model's queue and read on the main thread only after `settle()`, so it needs no lock.
    final class System: @unchecked Sendable {
        var login: LoginItemStatus = .notRegistered
        var calls: [String] = []
        var failRegister: String?
        var trashed: [String] = []

        var loginItem: LoginItem {
            LoginItem(status: { self.login },
                      register: {
                          self.calls.append("register")
                          if let failure = self.failRegister { throw SetupError(failure) }
                          self.login = .enabled
                      },
                      unregister: { self.calls.append("unregister"); self.login = .notRegistered },
                      openSettings: { self.calls.append("settings") })
        }

        func trash(_ url: URL) throws {
            trashed.append(url.path)
        }
    }

    let system = System()

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

    func setup(app: URL? = nil, version: String = "0.5.0", env: [String: String] = [:], login: Bool = true) -> AppSetup {
        let installer = Installer(environment: SetupEnvironment(variables: ["HOME": home.path].merging(env) { $1 }),
                                  launchctl: Launchctl(path: home.appendingPathComponent("launchctl").path))
        let system = self.system
        return AppSetup(installer: installer, appPath: (app ?? self.app).path, bundledVersion: version,
                        loginItem: login ? system.loginItem : nil, trash: { try system.trash($0) })
    }

    func model(_ setup: AppSetup? = nil, memory: Memory = Memory()) -> SetupModel {
        SetupModel(setup: setup ?? self.setup(), memory: memory.memory)
    }

    /// Runs setup work off the main thread.
    func off<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(operation: work).value
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

    @Test func theAppInstallsItsBinariesAndStartsPerchd() async throws {
        let setup = self.setup()
        let report = await off { setup.selfCheck() }
        #expect(report.enabled)
        #expect(report.problems.isEmpty)
        #expect(try installed().contains("echo 0.5.0"))
        #expect(FileManager.default.isExecutableFile(atPath: bin.appendingPathComponent("perchd").path))
        #expect(log().contains("bootstrap gui/"))
        // Same version again: nothing to copy, perchd left running.
        try FileManager.default.removeItem(at: launchctlLog)
        _ = await off { setup.selfCheck() }
        #expect(log().isEmpty)
    }

    @Test func aReplacedAppReplacesTheBinariesEitherWay() async throws {
        let first = setup()
        _ = await off { first.selfCheck() }
        try bundle(version: "0.6.0")
        try FileManager.default.removeItem(at: launchctlLog)
        let newer = setup(version: "0.6.0")
        _ = await off { newer.selfCheck() }
        #expect(try installed().contains("echo 0.6.0"))
        #expect(log().contains("bootout") && log().contains("bootstrap"), "perchd restarted")
        // Rolling back to an older app puts its binaries back too: the running app is the authority.
        try bundle(version: "0.4.0")
        let older = setup(version: "0.4.0")
        _ = await off { older.selfCheck() }
        #expect(try installed().contains("echo 0.4.0"))
    }

    @Test func aV03InstallIsMigratedByReplacingTheApp() async throws {
        // v0.3 copied perch / perchd into ~/.local/bin (every Perch binary carries the todo.md mirror's header).
        let localBin = home.appendingPathComponent(".local/bin")
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        for name in ["perch", "perchd"] {
            try "<!-- Generated by perchd. Read-only (v0.3)".write(to: localBin.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let setup = self.setup()
        let report = await off { setup.selfCheck() }
        #expect(report.problems.isEmpty)
        for name in ["perch", "perchd"] {
            let link = try FileManager.default.destinationOfSymbolicLink(atPath: localBin.appendingPathComponent(name).path)
            #expect(link == bin.appendingPathComponent(name).path, "typing perch runs the new one")
        }
    }

    @Test func aDeveloperBuildTouchesNothing() async throws {
        let dev = home.appendingPathComponent("src/perch/.build/Perch.app")
        let devSetup = setup(app: dev), isolated = setup(env: ["PERCH_HOME": home.appendingPathComponent("iso").path])
        for report in [await off { devSetup.selfCheck() }, await off { isolated.selfCheck() }] {
            #expect(!report.enabled)
            #expect(report.statuses.isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: bin.path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("iso/bin").path))
        #expect(log().isEmpty)
        let model = model(setup(app: dev))
        model.start()
        await model.settle()
        #expect(model.state.card == nil && model.state.rows.isEmpty && model.state.menu.isEmpty)
        #expect(model.state.loginMenu == nil && !model.state.canUninstall)
        model.chooseLoginToggle()
        await model.settle()
        #expect(system.calls.isEmpty, "a developer build never registers a login item")
    }

    // MARK: First run

    @Test func firstRunShowsTheCardAndChangesNoConfigUntilConnect() async throws {
        try "{\"model\":\"opus\"}".write(to: claudeSettings, atomically: true, encoding: .utf8)
        let memory = Memory()
        let model = model(memory: memory)
        var opened = 0
        model.onCardAppeared = { opened += 1 }
        model.start()
        await model.settle()
        #expect(opened == 1)
        #expect(memory.shown, "once")
        #expect(model.state.card?.choices.map(\.agent) == ["claude-code", "codex"])
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8) == "{\"model\":\"opus\"}")
        #expect(!FileManager.default.fileExists(atPath: codexHooks.path))

        model.connectCard()
        await model.settle()
        let settings = try String(contentsOf: claudeSettings, encoding: .utf8)
        #expect(settings.contains("\(bin.path)/perch hook claude-code"))
        #expect(settings.contains("\"model\" : \"opus\""), "other settings kept")
        #expect(try String(contentsOf: codexHooks, encoding: .utf8).contains("hook codex"))
        #expect(try agents()["claude-code"]?.status == .on)
        guard case .finished(let lines) = model.state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines.map(\.text) == ["Connected Claude Code", "Connected Codex", "Perch opens at login",
                                     "Trust Perch's hooks: run /hooks in codex"])

        // The next launch: no card, the trust row.
        let next = self.model(memory: memory)
        next.start()
        await next.settle()
        #expect(next.state.card == nil)
        #expect(next.state.rows.map(\.kind) == [.trust])
    }

    @Test func notNowLeavesFoundRows() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        #expect(model.state.rows.map(\.text) == ["Claude Code found", "Codex found"])
        #expect(!FileManager.default.fileExists(atPath: claudeSettings.path))
        let row = try #require(model.state.rows.first)
        model.connect(try #require(row.connects))
        await model.settle()
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8).contains("hook claude-code"))
        #expect(model.state.rows.map(\.text) == ["Codex found"])
    }

    // MARK: Repair

    @Test func outdatedHooksOfAConnectedAgentAreRepaired() async throws {
        let old = try HookSettings.codex.installing(nil, path: codexHooks.path, perch: "/usr/local/bin/perch", wait: 45)
        try old.write(to: codexHooks, atomically: true, encoding: .utf8)
        let model = model()
        model.start()
        await model.settle()
        let hooks = try String(contentsOf: codexHooks, encoding: .utf8)
        #expect(hooks.contains("\(bin.path)/perch hook codex --wait 45"), "rewritten, keeping --wait")
        #expect(FileManager.default.fileExists(atPath: codexHooks.path + ".perch-backup"))
        #expect(model.state.card == nil, "v0.3 hooks: not a first run")
        #expect(model.state.rows.map(\.text) == ["Trust Perch's hooks: run /hooks in codex", "Claude Code found",
                                                  "Updated Perch's hooks for Codex"])
    }

    @Test func aBrokenHookFileIsLeftAloneAndShown() async throws {
        try "{ not json".write(to: claudeSettings, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".perch"), withIntermediateDirectories: true)
        try AgentsFile(agents: ["claude-code": AgentRecord(status: .on, config: claudeSettings.path)])
            .save(to: home.appendingPathComponent(".perch/agents.json"))
        let model = model()
        model.start()
        await model.settle()
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8) == "{ not json")
        #expect(model.state.rows.first?.text == "Can't read ~/.claude/settings.json")
    }

    @Test func aBrokenAgentsFileShowsNoCardAndSaysSo() async throws {
        let file = home.appendingPathComponent(".perch/agents.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ broken".write(to: file, atomically: true, encoding: .utf8)
        let model = model()
        model.start()
        await model.settle()
        #expect(model.state.card == nil)
        #expect(model.state.rows.first?.text == "Can't read ~/.perch/agents.json")
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ broken", "the user's choices are never overwritten")
    }

    @Test func aConnectThatCantWriteSaysSo() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: claude.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path) }
        model.connect("claude-code")
        await model.settle()
        let row = try #require(model.state.rows.first)
        #expect(row.kind == .problem)
        #expect(row.text == "Can't connect ~/.claude/settings.json")
        // Fixed and refreshed (the notch re-reads on every expand): the error goes, the offer is back.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)
        model.refresh()
        await model.settle()
        #expect(model.state.rows.map(\.text) == ["Claude Code found", "Codex found"])
    }

    // MARK: Agents menu

    @Test func theAgentsMenuConnectsAndDisconnects() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        model.connect("codex")
        await model.settle()
        #expect(model.state.menu.map(\.on) == [false, true, false])
        model.disconnect("codex")
        await model.settle()
        #expect(model.state.menu.map(\.on) == [false, false, false])
        #expect(model.state.menu.map(\.available) == [true, true, false], "Grok is not installed here")
        #expect(try agents()["codex"]?.status == .off, "recorded like `perch hooks uninstall`")
        #expect(!(try String(contentsOf: codexHooks, encoding: .utf8)).contains("hook codex"))
        #expect(model.state.rows.map(\.text) == ["Claude Code found"], "an agent turned off gets no row")
        // The next launch leaves it alone too.
        let next = self.model()
        next.start()
        await next.settle()
        #expect(!(try String(contentsOf: codexHooks, encoding: .utf8)).contains("hook codex"))
    }

    // MARK: Codex trust

    @Test func aCodexUpdateAfterTheHooksWereWrittenRecordsTrust() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        model.connect("codex")
        await model.settle()
        #expect(model.state.rows.contains { $0.kind == .trust })
        let written = try #require(try agents()["codex"]?.hooksWrittenAt)

        func event(_ offset: TimeInterval, source: String = "codex") -> SessionEvent {
            var s = Session(id: "c1", source: source, startedAt: written.addingTimeInterval(offset))
            s.updatedAt = written.addingTimeInterval(offset)
            return SessionEvent(type: .updated, session: s, at: s.updatedAt)
        }
        model.observe(event(-30))
        await model.settle()
        #expect(model.state.rows.contains { $0.kind == .trust }, "ran before the hooks were written")
        #expect(try agents()["codex"]?.trustedAt == nil)
        model.observe(event(30, source: "claude-code"))
        await model.settle()
        #expect(try agents()["codex"]?.trustedAt == nil)

        model.observe(event(30))
        await model.settle()
        #expect(!model.state.rows.contains { $0.kind == .trust })
        #expect(try agents()["codex"]?.trustedAt == written.addingTimeInterval(30))
        let next = self.model()
        next.start()
        await next.settle()
        #expect(next.state.statuses.first { $0.agent == "codex" }?.state == .connected)
    }

    // MARK: Open at login

    @Test func connectOnTheCardTurnsOnOpenAtLoginWhenChecked() async throws {
        let model = model()
        model.start()
        await model.settle()
        #expect(model.state.card?.openAtLogin == true)
        model.connectCard()
        await model.settle()
        #expect(system.calls == ["register"])
        #expect(model.state.loginMenu?.on == true)
        guard case .finished(let lines) = model.state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines.map(\.text).contains("Perch opens at login"))
        model.closeCard()
        await model.settle()
        #expect(system.calls == ["register"], "Done registers nothing more")
    }

    @Test func uncheckedTheCardLeavesLoginAlone() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.toggleCardOpenAtLogin()
        model.connectCard()
        await model.settle()
        #expect(system.calls.isEmpty)
        #expect(model.state.loginMenu?.on == false)
    }

    @Test func notNowStillTakesUpTheOpenAtLoginBox() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        #expect(system.calls == ["register"])
        #expect(model.state.loginMenu?.on == true)
        #expect(!FileManager.default.fileExists(atPath: claudeSettings.path), "but no agent was connected")
    }

    @Test func aFailedRegistrationIsShown() async throws {
        system.failRegister = "Operation not permitted"
        let model = model()
        model.start()
        await model.settle()
        model.connectCard()
        await model.settle()
        guard case .finished(let lines) = model.state.card?.phase else { Issue.record("not finished"); return }
        #expect(lines.contains { $0.text == "Can't turn on Open at Login" && $0.detail == "Operation not permitted" })
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8).contains("hook claude-code"), "the agents still connected")
    }

    @Test func theMenuItemTurnsOpenAtLoginOnAndOff() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        #expect(model.state.loginMenu?.on == true)
        model.chooseLoginToggle()
        await model.settle()
        #expect(system.calls == ["register", "unregister"])
        #expect(model.state.loginMenu?.on == false)
        model.chooseLoginToggle()
        await model.settle()
        #expect(model.state.loginMenu?.on == true)
        // Switched off in System Settings behind Perch's back: the notch re-reads on expand, the item opens Settings.
        system.login = .requiresApproval
        model.refresh()
        await model.settle()
        #expect(model.state.loginMenu?.action == .openSettings)
        model.chooseLoginToggle()
        await model.settle()
        #expect(system.calls.last == "settings")
    }

    // MARK: Uninstall

    @Test func uninstallRemovesPerchKeepsDataAndTrashesTheApp() async throws {
        try "{\"model\":\"opus\"}".write(to: claudeSettings, atomically: true, encoding: .utf8)
        let model = model()
        model.start()
        await model.settle()
        model.connectCard()
        await model.settle()
        model.closeCard()
        await model.settle()
        #expect(system.login == .enabled)
        let plist = home.appendingPathComponent("Library/LaunchAgents/dev.perch.perchd.plist")
        #expect(FileManager.default.fileExists(atPath: plist.path))

        var outcome: UninstallOutcome?
        model.uninstall { outcome = $0 }
        await model.settle()
        #expect(outcome == UninstallOutcome(finished: true, problem: nil))
        let settings = try String(contentsOf: claudeSettings, encoding: .utf8)
        #expect(!settings.contains("hook claude-code") && settings.contains("opus"), "only Perch's hooks removed")
        #expect(!(try String(contentsOf: codexHooks, encoding: .utf8)).contains("hook codex"))
        #expect(!FileManager.default.fileExists(atPath: plist.path))
        #expect(log().contains("bootout"))
        #expect(!FileManager.default.fileExists(atPath: bin.path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".perch/agents.json").path), "data kept")
        #expect(system.login == .notRegistered)
        #expect(system.trashed == [app.path])
    }

    @Test func uninstallSaysWhichHookFilesItCouldNotClean() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        try "{ not json".write(to: codexHooks, atomically: true, encoding: .utf8)
        var outcome: UninstallOutcome?
        model.uninstall { outcome = $0 }
        await model.settle()
        let result = try #require(outcome)
        #expect(result.finished, "everything else went: the app still goes")
        #expect(result.problem?.contains("~/.codex/hooks.json") == true)
        #expect(!FileManager.default.fileExists(atPath: bin.path))
        #expect(system.trashed == [app.path])
    }

    @Test func anUninstallThatFailsKeepsTheApp() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        let perchHome = home.appendingPathComponent(".perch")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: perchHome.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: perchHome.path) }
        var outcome: UninstallOutcome?
        model.uninstall { outcome = $0 }
        await model.settle()
        let result = try #require(outcome)
        #expect(!result.finished)
        #expect(result.problem?.contains("cannot remove") == true)
        #expect(system.login == .enabled, "still opens at login: Perch is still installed")
        #expect(system.trashed.isEmpty)
    }

    @Test func aDeveloperBuildCannotUninstall() async throws {
        let dev = home.appendingPathComponent("src/perch/.build/Perch.app")
        var outcome: UninstallOutcome?
        let devModel = model(setup(app: dev))
        devModel.uninstall { outcome = $0 }
        await devModel.settle()
        #expect(outcome?.finished == false)
        #expect(system.trashed.isEmpty && log().isEmpty)
    }

    @Test func anIsolatedRunLeavesTheRealLoginItemAlone() async throws {
        // SMAppService belongs to the user logged in, whatever $HOME says: no login item under a scratch home.
        #expect(LoginItem.mainApp(forHome: home) == nil)
        let model = model(setup(login: false))
        model.start()
        await model.settle()
        #expect(model.state.card != nil && model.state.card?.openAtLogin == nil, "no box on the card")
        #expect(model.state.loginMenu == nil)
        model.connectCard()
        await model.settle()
        model.closeCard()
        await model.settle()
        var outcome: UninstallOutcome?
        model.uninstall { outcome = $0 }
        await model.settle()
        #expect(outcome == UninstallOutcome(finished: true, problem: nil), "uninstall works without a login item")
        #expect(system.calls.isEmpty)
    }

    @Test func nothingElseTouchesTheInstallOnceItIsUninstalled() async throws {
        let model = model()
        model.start()
        await model.settle()
        model.closeCard()
        await model.settle()
        var outcomes = 0
        model.uninstall { _ in outcomes += 1 }
        // Clicked again, or Agents → Claude Code, while the first uninstall is still running.
        model.uninstall { _ in outcomes += 1 }
        model.connect("claude-code")
        model.chooseLoginToggle()
        await model.settle()
        #expect(model.uninstalling, "finished: the app is about to quit")
        model.connect("claude-code")
        await model.settle()
        #expect(outcomes == 1)
        #expect(!FileManager.default.fileExists(atPath: claudeSettings.path), "no hooks for the deleted ~/.perch/bin/perch")
        #expect(system.calls == ["register", "unregister"])
    }
}
