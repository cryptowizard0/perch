import Foundation
import PerchCore

/// What runs the evaluation: `perch setup` (explicit consent, always installs) or the notch app's self-check.
public enum SetupRunner: Equatable, Sendable {
    case cli
    /// The app bundle's path. Only an app inside /Applications or ~/Applications maintains the install.
    case app(path: String)
}

/// One candidate hook file as read from disk.
public enum ConfigFile: Equatable, Sendable {
    /// Its directory does not exist: the agent is not set up there.
    case noDirectory
    case missing
    case text(String)
    /// Exists but cannot be read; the message says why.
    case unreadable(String)
}

/// Everything the evaluation looks at, read up front so `Setup.evaluate` is a pure function.
public struct SetupSnapshot: Equatable, Sendable {
    public var agents: AgentsFile
    /// Every candidate hook file path (see `ConfigLocation.candidates`). Missing paths count as `.noDirectory`.
    public var files: [String: ConfigFile]
    public var environment: [String: String]
    public var userHome: String
    /// The binary hooks must run: the fixed install location.
    public var perchBinary: String
    /// `perch --version` of the installed copy; nil when there is none.
    public var installedVersion: String?
    /// The version of the binaries that would be installed (the running app's or CLI's).
    public var bundledVersion: String
    public var runner: SetupRunner

    public init(agents: AgentsFile, files: [String: ConfigFile], environment: [String: String], userHome: String,
                perchBinary: String, installedVersion: String?, bundledVersion: String, runner: SetupRunner) {
        self.agents = agents
        self.files = files
        self.environment = environment
        self.userHome = userHome
        self.perchBinary = perchBinary
        self.installedVersion = installedVersion
        self.bundledVersion = bundledVersion
        self.runner = runner
    }
}

public enum SetupRequest: Equatable, Sendable {
    /// The app on launch: sync binaries and repair connected agents; never connect anything new.
    case selfCheck
    /// `perch setup [agent…] [--wait N]`: connect the named agents, or every detected one not turned off.
    case setup(agents: [String]? = nil, wait: Int? = nil)
}

public enum AgentState: String, Codable, Equatable, Sendable {
    /// No config directory: the agent is not set up on this Mac.
    case notDetected
    /// Set up, but the user never chose (no agents.json entry and no Perch hooks).
    case notAsked
    case connected
    /// Connected, but Perch's hooks run another binary or differ from the current ones.
    case outdated
    /// Codex: current hooks that no event has proved trusted yet (`/hooks` in codex).
    case needsTrust
    /// The user disconnected it: not suggested, not repaired.
    case off
}

public struct AgentStatus: Equatable, Sendable {
    public let agent: String
    public let state: AgentState
    /// The hook file in use (or the one that would be written).
    public let config: String
    /// The hook file can't be read or parsed; Perch leaves it alone.
    public let error: String?
}

/// One agent's change in a plan: write `text` to `config` (nil: the hooks are right, only record the choice).
public struct AgentChange: Equatable, Sendable {
    public let agent: String
    public let config: String
    public let text: String?
    /// Perch's hooks get new content (Codex must trust them again).
    public let hooksChanged: Bool
}

public struct AgentFailure: Equatable, Sendable {
    public let agent: String
    public let config: String
    public let message: String
}

public struct SetupPlan: Equatable, Sendable {
    /// Copy the running binaries into the fixed location.
    public var syncBinaries = false
    public var changes: [AgentChange] = []
    /// Agents the plan should change but whose hook file Perch must not touch.
    public var failures: [AgentFailure] = []

    /// agents.json after the changes were written at `now`.
    public func apply(to agents: AgentsFile, at now: Date) -> AgentsFile {
        var agents = agents
        for change in changes { agents.turnOn(change.agent, config: change.config, hooksChanged: change.hooksChanged, at: now) }
        return agents
    }
}

public struct SetupEvaluation: Equatable, Sendable {
    public let agents: [AgentStatus]
    public let plan: SetupPlan
}

public enum Setup {
    /// The agents setup detects and connects. Hermes is not supported for now (`perch hooks install hermes` still works).
    public static let agents: [any HookFile] = [HookSettings.claudeCode, HookSettings.codex]
    public static var agentNames: [String] { agents.map(\.agent) }
    public static let defaultWait = Int(HookAdapter.permissionWait)

    public static func agent(_ name: String) throws -> any HookFile {
        guard let file = agents.first(where: { $0.agent == name }) else {
            let names = agentNames
            throw SetupError("unknown agent '\(name)'; use \(names.dropLast().joined(separator: ", ")) or \(names.last!)", code: 64)
        }
        return file
    }

    /// Each agent's state, and what `request` should do about it.
    public static func evaluate(_ snapshot: SetupSnapshot, request: SetupRequest) -> SetupEvaluation {
        let inspections = agents.map { inspect($0, in: snapshot) }
        var plan = SetupPlan()
        switch request {
        case .selfCheck:
            guard maintainsInstall(snapshot) else { break }
            plan.syncBinaries = snapshot.installedVersion != snapshot.bundledVersion
            for inspection in inspections where inspection.isOn {
                if let error = inspection.status.error {
                    plan.failures.append(inspection.failure(error))
                } else if inspection.status.state == .outdated {
                    plan.changes += inspection.change(wait: inspection.wait, perch: snapshot.perchBinary).map { [$0] } ?? []
                }
            }
        case .setup(let names, let wait):
            plan.syncBinaries = true
            let targets = inspections.filter { inspection in
                names.map { $0.contains(inspection.file.agent) }
                    ?? ![.off, .notDetected].contains(inspection.status.state)
            }
            for inspection in targets {
                if let error = inspection.status.error {
                    plan.failures.append(inspection.failure(error))
                } else if let change = inspection.change(wait: wait ?? inspection.wait, perch: snapshot.perchBinary) {
                    plan.changes.append(change)
                }
            }
        }
        return SetupEvaluation(agents: inspections.map(\.status), plan: plan)
    }

    /// Developer builds (`.build/Perch.app`, anything run with PERCH_HOME) never touch the real install.
    static func maintainsInstall(_ snapshot: SetupSnapshot) -> Bool {
        guard case .app(let path) = snapshot.runner else { return true }
        guard (snapshot.environment["PERCH_HOME"] ?? "").isEmpty else { return false }
        let folders = ["/Applications/", URL(fileURLWithPath: snapshot.userHome).appendingPathComponent("Applications").path + "/"]
        return folders.contains { path.hasPrefix($0) }
    }

    private struct Inspection {
        let file: any HookFile
        let record: AgentRecord?
        let status: AgentStatus
        let text: String?
        /// Perch's hooks as they are (canonical; empty: none).
        let ours: String
        let wait: Int?

        var isOn: Bool { record?.status == .on || (record == nil && !ours.isEmpty) }

        func failure(_ message: String) -> AgentFailure {
            AgentFailure(agent: file.agent, config: status.config, message: message)
        }

        /// Perch's hooks as they should be; nil when they already are and the choice is already recorded.
        func change(wait: Int?, perch: String) -> AgentChange? {
            guard let new = try? file.installing(text, path: status.config, perch: HookFiles.shellQuote(perch),
                                                 wait: wait ?? Setup.defaultWait),
                  let theirs = try? file.perchHooks(in: new, path: status.config) else { return nil }
            if theirs != ours {
                return AgentChange(agent: file.agent, config: status.config, text: new, hooksChanged: true)
            }
            if record?.status != .on || record?.config != status.config {
                return AgentChange(agent: file.agent, config: status.config, text: nil, hooksChanged: false)
            }
            return nil
        }
    }

    private static func inspect(_ file: any HookFile, in snapshot: SetupSnapshot) -> Inspection {
        let record = snapshot.agents[file.agent]
        let config = file.location.resolve(recorded: record?.config, environment: snapshot.environment,
                                           userHome: snapshot.userHome) { (snapshot.files[$0] ?? .noDirectory) != .noDirectory }
        let contents = snapshot.files[config] ?? .noDirectory
        var text: String?
        var problem: String?
        switch contents {
        case .noDirectory, .missing: break
        case .text(let t): text = t
        case .unreadable(let message): problem = message
        }
        var ours = ""
        var current = true
        let wait = file.wait(in: text)
        if problem == nil {
            do {
                ours = try file.perchHooks(in: text, path: config)
                let expected = try file.installing(text, path: config, perch: HookFiles.shellQuote(snapshot.perchBinary),
                                                   wait: wait ?? defaultWait)
                current = try file.perchHooks(in: expected, path: config) == ours
            } catch let failure as SetupError {
                problem = failure.message
            } catch {
                problem = "\(config): \(error)"
            }
        }
        let on = record?.status == .on || (record == nil && !ours.isEmpty)
        let state: AgentState
        if record?.status == .off {
            state = .off
        } else if contents == .noDirectory {
            state = .notDetected
        } else if !on {
            state = .notAsked
        } else if problem != nil || !current {
            state = .outdated
        } else if file.needsTrust, !(record?.trustedAt.map { $0 >= record?.hooksWrittenAt ?? .distantPast } ?? false) {
            state = .needsTrust
        } else {
            state = .connected
        }
        return Inspection(file: file, record: record, status: AgentStatus(agent: file.agent, state: state, config: config, error: problem),
                          text: text, ours: ours, wait: wait)
    }
}
