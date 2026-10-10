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

    public init(installer: Installer = Installer(), appPath: String = Bundle.main.bundlePath,
                helpers: URL? = nil, bundledVersion: String = PerchVersion.string) {
        self.installer = installer
        self.appPath = appPath
        self.helpers = helpers ?? URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Helpers", isDirectory: true)
        self.bundledVersion = bundledVersion
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
    /// like `perch setup <agent…>`. The binaries were synced at launch.
    public func connect(_ names: [String]) -> SetupReport {
        var problems: [SetupProblem] = []
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
        return SetupReport(enabled: true, home: home, statuses: statuses, records: agents, problems: problems)
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
