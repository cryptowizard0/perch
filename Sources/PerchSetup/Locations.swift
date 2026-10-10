import Foundation
import PerchCore

/// Where an agent keeps its hook file: `$<dirVariable>/<file>`, else `~/<defaultDir>/<file>`.
public struct ConfigLocation: Equatable, Sendable {
    public let dirVariable: String
    public let defaultDir: String
    public let file: String

    public init(dirVariable: String, defaultDir: String, file: String) {
        self.dirVariable = dirVariable
        self.defaultDir = defaultDir
        self.file = file
    }

    /// The paths to look at, in order: the one recorded in agents.json (the app can't see the shell's
    /// `$CLAUDE_CONFIG_DIR`, so the path `perch setup` wrote wins), then the environment variable's, then the default.
    public func candidates(recorded: String?, environment: [String: String], userHome: String) -> [String] {
        var paths: [String] = []
        if let recorded, !recorded.isEmpty { paths.append(recorded) }
        if let dir = environment[dirVariable], !dir.isEmpty {
            paths.append(URL(fileURLWithPath: dir).appendingPathComponent(file).path)
        }
        paths.append(URL(fileURLWithPath: userHome).appendingPathComponent(defaultDir).appendingPathComponent(file).path)
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// The first candidate whose directory exists (the agent is set up there), else the first candidate.
    public func resolve(recorded: String?, environment: [String: String], userHome: String,
                        hasDirectory: (_ path: String) -> Bool) -> String {
        let paths = candidates(recorded: recorded, environment: environment, userHome: userHome)
        return paths.first(where: hasDirectory) ?? paths[0]
    }
}

/// The directories setup works with, from the environment so tests can use a scratch home.
public struct SetupEnvironment: Sendable {
    public var variables: [String: String]
    /// `$HOME`, else the account's home directory. Agent configs, `~/Library/LaunchAgents` and `~/.local/bin` live here.
    public var userHome: URL
    /// `$PERCH_HOME`, else `~/.perch`.
    public var perchHome: URL

    public init(variables: [String: String]) {
        self.variables = variables
        let home = variables["HOME"].flatMap { $0.isEmpty ? nil : $0 }
        userHome = home.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.homeDirectoryForCurrentUser
        perchHome = variables["PERCH_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? userHome.appendingPathComponent(".perch", isDirectory: true)
    }

    public static var current: SetupEnvironment { SetupEnvironment(variables: ProcessInfo.processInfo.environment) }

    public var perchHomeOverridden: Bool { !(variables["PERCH_HOME"] ?? "").isEmpty }

    /// The fixed install location. Hooks and the launchd agent always run the copies here.
    public var binDirectory: URL { perchHome.appendingPathComponent("bin", isDirectory: true) }
    public var perchBinary: URL { binDirectory.appendingPathComponent("perch") }
    public var perchdBinary: URL { binDirectory.appendingPathComponent("perchd") }
    /// Which agents the user connected (see `AgentsFile`).
    public var agentsFile: URL { perchHome.appendingPathComponent("agents.json") }
    /// Convenience links for people typing `perch`; never written into a hook.
    public var localBin: URL { userHome.appendingPathComponent(".local/bin", isDirectory: true) }
    public var socket: URL { PerchPaths.socket(in: perchHome) }

    /// Where the agent's hook file is, following `ConfigLocation.resolve`.
    public func configPath(for file: any HookFile, recorded: String?) -> String {
        file.location.resolve(recorded: recorded, environment: variables, userHome: userHome.path, hasDirectory: Self.hasDirectory)
    }

    static func hasDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
