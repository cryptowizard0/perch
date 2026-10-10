import ArgumentParser
import Foundation
import PerchCore
import PerchSetup

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install Perch and connect the agents it finds.",
        discussion: """
        Copies this perch and the perchd next to it into ~/.perch/bin, installs perchd as a launchd agent \
        running from there, and connects the named agents (default: every agent set up on this Mac that you \
        haven't disconnected with `perch hooks uninstall`). Perch hooks that run another perch or are out of date \
        are rewritten, keeping their --wait. Agents: \(Setup.agentNames.joined(separator: ", ")).
        """
    )
    @Argument(help: "Agents to connect (default: every one found and not disconnected).") var agents: [String] = []
    @Option(help: "Seconds a permission request waits for the notch before the terminal asks (default: keep, else 20).")
    var wait: Int?
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        for name in agents { _ = try Setup.agent(name) }
        if let wait, !(5...300).contains(wait) { throw CLIError("--wait must be between 5 and 300 seconds", code: 64) }
        let installer = Installer()
        let env = installer.environment
        var file = try installer.loadAgents()
        let request = SetupRequest.setup(agents: agents.isEmpty ? nil : agents, wait: wait)
        let plan = Setup.evaluate(installer.snapshot(agents: file, runner: .cli, bundledVersion: PerchVersion.string,
                                                     installedVersion: nil), request: request).plan

        var notes: [String] = []
        if plan.syncBinaries {
            let source = URL(fileURLWithPath: try HookFiles.currentBinary()).deletingLastPathComponent()
            if try installer.syncBinaries(from: source) { notes.append("installed perch, perchd → \(env.binDirectory.path)") }
        }
        for link in try installer.linkOldBinaries() { notes.append("replaced \(link) with a link into \(env.binDirectory.path)") }
        let running = try installer.installLaunchAgent()
        notes.append("perchd: launchd agent \(installer.launchAgent.plistURL.path)\(running ? " (running)" : "")")

        let failures = installer.apply(plan, to: &file)
        try installer.saveAgents(file)
        let statuses = Setup.evaluate(installer.snapshot(agents: file, runner: .cli, bundledVersion: PerchVersion.string,
                                                         installedVersion: nil), request: request).agents
        let lines = statuses.map { status in
            AgentLine(agent: status.agent, state: status.state, config: status.config,
                      error: failures.first { $0.agent == status.agent }?.message ?? status.error)
        }
        let failure = failures.isEmpty ? nil : failures.map { "\($0.agent): \($0.message)" }.joined(separator: "; ")
        if json {
            printJSON(SetupOutput(ok: failure == nil, error: failure, agents: lines))
            if failure != nil { Foundation.exit(1) }
            return
        }
        notes.forEach { print($0) }
        let width = lines.map(\.agent.count).max() ?? 0
        for line in lines {
            print("\(line.agent.padding(toLength: width, withPad: " ", startingAt: 0))  \(Self.label(line.state).padding(toLength: 13, withPad: " ", startingAt: 0))  \(line.config)")
        }
        if statuses.contains(where: { $0.state == .needsTrust }) {
            print("Codex runs Perch's hooks only after you trust them: start codex and review them with /hooks.")
        }
        if let failure { throw CLIError(failure) }
    }

    static func label(_ state: AgentState) -> String {
        switch state {
        case .notDetected: "not found"
        case .notAsked: "not connected"
        case .connected: "connected"
        case .outdated: "outdated"
        case .needsTrust: "needs trust"
        case .off: "off"
        }
    }

    struct AgentLine: Encodable {
        let agent: String
        let state: AgentState
        let config: String
        let error: String?
    }

    struct SetupOutput: Encodable {
        let ok: Bool
        let error: String?
        let agents: [AgentLine]
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove Perch's hooks from every agent, perchd's launchd agent and ~/.perch/bin.",
        discussion: "Keeps ~/.perch (the database, allowlist.json and agents.json) unless --purge. Only Perch's hooks are removed."
    )
    @Flag(help: "Also remove ~/.perch and everything in it.") var purge = false
    @Flag(help: "Print JSON.") var json = false

    func run() throws {
        let installer = Installer()
        let report = try installer.uninstall(purge: purge)
        let failure = report.failures.isEmpty ? nil : report.failures.map { "\($0.agent): \($0.message)" }.joined(separator: "; ")
        if json {
            printJSON(Output(ok: failure == nil, error: failure, purged: report.purged,
                             agents: report.removals.map { Output.Removal(agent: $0.agent, config: $0.config, removed: $0.removed) }))
            if failure != nil { Foundation.exit(1) }
            return
        }
        for removal in report.removals {
            print("removed \(removal.removed) Perch hook\(removal.removed == 1 ? "" : "s") from \(removal.config)")
        }
        print(report.launchAgentRemoved ? "perchd: launchd agent removed, perchd stopped" : "perchd was not installed")
        for link in report.removedLinks { print("removed \(link)") }
        let home = installer.environment.perchHome.path
        print(purge ? "removed \(home)" : "removed \(installer.environment.binDirectory.path); kept \(home) (--purge removes it)")
        if let failure { throw CLIError(failure) }
    }

    struct Output: Encodable {
        struct Removal: Encodable {
            let agent: String
            let config: String
            let removed: Int
        }
        let ok: Bool
        let error: String?
        let purged: Bool
        let agents: [Removal]
    }
}
