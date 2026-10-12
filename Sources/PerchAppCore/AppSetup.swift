import Foundation
import PerchCore
import PerchSetup

/// The app's setup work on disk, through `PerchSetup` (the same evaluation and writes as `perch setup`).
/// Synchronous and slow (it runs `perch --version` and launchctl): `SetupModel` calls it off the main thread.
public struct AppSetup: Sendable {
    public let installer: Installer
    /// The running app bundle; only one inside /Applications or ~/Applications maintains the install.
    public let appPath: String
    /// Where the bundle keeps its `perch` and `perchd` (`Contents/Helpers`).
    public let helpers: URL
    public let bundledVersion: String
    /// nil: no login item to manage (an isolated run under another `$HOME`).
    public let loginItem: LoginItem?
    /// Moves a file to the Trash (the app itself, at the end of an uninstall).
    public let trash: @Sendable (URL) throws -> Void

    public init(installer: Installer = Installer(), appPath: String = Bundle.main.bundlePath,
                helpers: URL? = nil, bundledVersion: String = PerchVersion.string,
                loginItem: LoginItem? = LoginItem.mainApp(forHome: SetupEnvironment.current.userHome),
                trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.installer = installer
        self.appPath = appPath
        self.helpers = helpers ?? URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Helpers", isDirectory: true)
        self.bundledVersion = bundledVersion
        self.loginItem = loginItem
        self.trash = trash
    }

    private var home: String { installer.environment.userHome.path }

    /// On launch: copy the bundled binaries into ~/.perch/bin when their version differs (either way) and restart
    /// perchd; repair outdated hooks of connected agents. Connects nothing new. A developer build does nothing.
    public func selfCheck() -> SetupReport {
        var problems: [SetupProblem] = []
        let loaded = loadAgents(&problems)
        var agents = loaded ?? AgentsFile()
        guard Setup.maintainsInstall(snapshot(agents, installed: nil)) else { return SetupReport(enabled: false, home: home) }

        let evaluation = Setup.evaluate(snapshot(agents, installed: installer.installedVersion()), request: .selfCheck)
        var restart = !FileManager.default.fileExists(atPath: installer.launchAgent.plistURL.path)
        if evaluation.plan.syncBinaries {
            do {
                try installer.syncBinaries(from: helpers)
                restart = true
            } catch {
                problems.append(SetupProblem(agent: nil, title: "Can't install perch and perchd", detail: describe(error), lasting: true))
            }
        }
        // A v0.3 install copied perch / perchd into ~/.local/bin: link them to the new ones, as `perch setup` does.
        do {
            try installer.linkOldBinaries()
        } catch {
            problems.append(SetupProblem(agent: nil, title: "Can't replace the old perch in \(tilde(installer.environment.localBin.path))",
                                         detail: describe(error), lasting: true))
        }
        if restart {
            do {
                try installer.installLaunchAgent()
            } catch {
                problems.append(SetupProblem(agent: nil, title: "Can't start perchd", detail: describe(error), lasting: true))
            }
        }

        var repaired: [String] = []
        // A broken agents.json holds the user's choices: repair nothing until it is fixed.
        if loaded != nil, !evaluation.plan.changes.isEmpty {
            let failures = installer.perform(evaluation.plan, recordingIn: &agents)
            problems += writeProblems(failures, statuses: evaluation.agents, title: "Can't update").map { problem in
                var problem = problem
                problem.lasting = true  // the next repair is at the next launch
                return problem
            }
            repaired = evaluation.plan.changes.filter { change in
                change.text != nil && !failures.contains { $0.agent == change.agent }
            }.map(\.agent)
            save(agents, &problems)
        }
        var report = status(agents, problems: problems)
        report.repaired = repaired
        report.choicesUnknown = loaded == nil
        return report
    }

    /// The current state, nothing changed.
    public func refresh() -> SetupReport {
        var problems: [SetupProblem] = []
        let agents = loadAgents(&problems)
        var report = status(agents ?? AgentsFile(), problems: problems)
        report.choicesUnknown = agents == nil
        return report
    }

    /// Connect (the card, a row, the Agents menu): writes Perch's hooks for these agents and records them on,
    /// like `perch setup <agent…>`. The binaries were synced at launch. `openAtLogin`: the card's box was checked.
    public func connect(_ names: [String], openAtLogin: Bool = false) -> SetupReport {
        var problems: [SetupProblem] = []
        if openAtLogin { setOpenAtLogin(true, &problems) }
        guard var agents = loadAgents(&problems) else {
            var report = status(AgentsFile(), problems: problems)
            report.failures = names.map { AgentFailure(agent: $0, config: "", message: problems.first?.detail ?? "agents.json") }
            return report
        }
        let evaluation = Setup.evaluate(snapshot(agents, installed: nil), request: .setup(agents: names))
        let failures = installer.perform(evaluation.plan, recordingIn: &agents)
        problems += writeProblems(failures, statuses: evaluation.agents, title: "Can't connect")
        save(agents, &problems)
        var report = status(agents, problems: problems)
        report.failures = failures
        return report
    }

    /// The Agents menu unchecked: remove Perch's hooks and record the agent off, like `perch hooks uninstall`.
    public func disconnect(_ name: String) -> SetupReport {
        var problems: [SetupProblem] = []
        guard var agents = loadAgents(&problems) else { return status(AgentsFile(), problems: problems) }
        do {
            _ = try installer.disconnect(try Setup.agent(name), recordingIn: &agents)
            save(agents, &problems)
        } catch {
            problems.append(SetupProblem(agent: name, title: "Can't disconnect \(AgentNames.display(name))", detail: describe(error)))
        }
        return status(agents, problems: problems)
    }

    /// The card's box (Not now / OK) or the menu's Open at Login item.
    public func setOpenAtLogin(_ on: Bool) -> SetupReport {
        var problems: [SetupProblem] = []
        setOpenAtLogin(on, &problems)
        let agents = loadAgents(&problems)
        var report = status(agents ?? AgentsFile(), problems: problems)
        report.choicesUnknown = agents == nil
        return report
    }

    /// "Uninstall Perch…": the same uninstall as `perch uninstall` (Perch's hooks, perchd's launchd agent,
    /// ~/.perch/bin; data kept), then no more opening at login, then the app to the Trash. The app quits when
    /// `finished`. A hook file Perch can't clean doesn't stop the rest (like the CLI); a failure past that does,
    /// and the app stays.
    public func uninstall() -> UninstallOutcome {
        guard Setup.maintainsInstall(snapshot((try? installer.loadAgents()) ?? AgentsFile(), installed: nil)) else {
            return UninstallOutcome(finished: false, problem: "This copy of Perch doesn't manage the install; run `perch uninstall`.")
        }
        let removal: Installer.UninstallReport
        do {
            removal = try installer.uninstall(purge: false)
        } catch {
            return UninstallOutcome(finished: false, problem: describe(error))
        }
        var problems = removal.failures.map { "Perch's hooks are still in \(tilde($0.config)): \($0.message)" }
        do {
            try loginItem?.set(false)
        } catch {
            problems.append("Perch still opens at login (\(describe(error))): remove it under System Settings → General → Login Items.")
        }
        do {
            try trash(URL(fileURLWithPath: appPath))
        } catch {
            problems.append("Couldn't move \(tilde(appPath)) to the Trash (\(describe(error))); drag it there yourself.")
        }
        return UninstallOutcome(finished: true, problem: problems.isEmpty ? nil : problems.joined(separator: "\n"))
    }

    /// An event proved the agent runs Perch's current hooks.
    public func recordTrust(_ name: String, at time: Date) -> SetupReport {
        var problems: [SetupProblem] = []
        guard var agents = loadAgents(&problems) else { return status(AgentsFile(), problems: problems) }
        agents.markTrusted(name, at: time)
        save(agents, &problems)
        return status(agents, problems: problems)
    }

    // MARK: -

    private func snapshot(_ agents: AgentsFile, installed: String?) -> SetupSnapshot {
        installer.snapshot(agents: agents, runner: .app(path: appPath), bundledVersion: bundledVersion, installedVersion: installed)
    }

    private func status(_ agents: AgentsFile, problems: [SetupProblem]) -> SetupReport {
        let snapshot = snapshot(agents, installed: nil)
        guard Setup.maintainsInstall(snapshot) else { return SetupReport(enabled: false, home: home) }
        let statuses = Setup.evaluate(snapshot, request: .selfCheck).agents
        return SetupReport(enabled: true, home: home, statuses: statuses, records: agents, problems: problems,
                           openAtLogin: loginItem?.status())
    }

    private func setOpenAtLogin(_ on: Bool, _ problems: inout [SetupProblem]) {
        guard let loginItem else { return }
        do {
            try loginItem.set(on)
        } catch {
            problems.append(SetupProblem(agent: nil, title: SetupState.loginProblemTitle(on: on), detail: describe(error)))
        }
    }

    private func loadAgents(_ problems: inout [SetupProblem]) -> AgentsFile? {
        do {
            return try installer.loadAgents()
        } catch {
            problems.append(SetupProblem(agent: nil, title: "Can't read \(tilde(installer.environment.agentsFile.path))", detail: describe(error)))
            return nil
        }
    }

    private func save(_ agents: AgentsFile, _ problems: inout [SetupProblem]) {
        do {
            try installer.saveAgents(agents)
        } catch {
            problems.append(SetupProblem(agent: nil, title: "Can't write \(tilde(installer.environment.agentsFile.path))",
                                         detail: describe(error)))
        }
    }

    /// Failures other than an unreadable hook file (the status already says that one): "<title> ~/…/hooks.json".
    private func writeProblems(_ failures: [AgentFailure], statuses: [AgentStatus], title: String) -> [SetupProblem] {
        failures.filter { failure in !statuses.contains { $0.agent == failure.agent && $0.error == failure.message } }
            .map { SetupProblem(agent: $0.agent, title: "\(title) \(tilde($0.config))", detail: $0.message) }
    }

    private func tilde(_ path: String) -> String {
        SetupState.tilde(path, home: home)
    }

    /// Setup's own errors carry a readable line; others their localized description.
    private func describe(_ error: Error) -> String {
        (error as? SetupError)?.message ?? error.localizedDescription
    }
}

/// How "Uninstall Perch…" went.
public struct UninstallOutcome: Equatable, Sendable {
    /// Perch is removed and the app is in the Trash (or should be dragged there): quit.
    public var finished: Bool
    /// What to tell the user before quitting (or why nothing was removed), one line per problem.
    public var problem: String?

    public init(finished: Bool, problem: String?) {
        self.finished = finished
        self.problem = problem
    }
}
