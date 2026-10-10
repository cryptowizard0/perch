import Darwin
import Foundation
import PerchClient
import PerchCore

/// Carries out setup on disk: reads the snapshot `Setup.evaluate` works on, then performs its plan. Also uninstall.
public struct Installer {
    public let environment: SetupEnvironment
    public let launchAgent: LaunchAgent

    public init(environment: SetupEnvironment = .current, launchctl: Launchctl = .current) {
        self.environment = environment
        launchAgent = LaunchAgent(userHome: environment.userHome, launchctl: launchctl)
    }

    // MARK: agents.json

    public func loadAgents() throws -> AgentsFile {
        try AgentsFile.load(from: environment.agentsFile)
    }

    public func saveAgents(_ agents: AgentsFile) throws {
        try agents.save(to: environment.agentsFile)
    }

    // MARK: Snapshot

    public func snapshot(agents: AgentsFile, runner: SetupRunner, bundledVersion: String,
                         installedVersion: String?) -> SetupSnapshot {
        var files: [String: ConfigFile] = [:]
        for file in Setup.agents {
            for path in file.location.candidates(recorded: agents[file.agent]?.config, environment: environment.variables,
                                                 userHome: environment.userHome.path) {
                files[path] = Self.readConfig(path)
            }
        }
        return SetupSnapshot(agents: agents, files: files, environment: environment.variables,
                             userHome: environment.userHome.path, perchBinary: environment.perchBinary.path,
                             installedVersion: installedVersion, bundledVersion: bundledVersion, runner: runner)
    }

    public static func readConfig(_ path: String) -> ConfigFile {
        guard SetupEnvironment.hasDirectory(path) else { return .noDirectory }
        do {
            return try HookFiles.read(path).map(ConfigFile.text) ?? .missing
        } catch let error as SetupError {
            return .unreadable(error.message)
        } catch {
            return .unreadable("cannot read \(path): \(error.localizedDescription)")
        }
    }

    /// `perch --version` of the installed copy; nil when there is none or it does not answer.
    public func installedVersion() -> String? {
        let binary = environment.perchBinary
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let version = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    // MARK: Binaries

    public static let binaries = ["perch", "perchd"]

    /// Copies `perch` and `perchd` from `directory` into the fixed location: real files (not links), replaced
    /// atomically, without the quarantine flag (macOS would block an agent running them in the background).
    /// Returns false when `directory` already is the fixed location.
    @discardableResult
    public func syncBinaries(from directory: URL) throws -> Bool {
        let fm = FileManager.default
        let bin = environment.binDirectory
        guard directory.resolvingSymlinksInPath().path != bin.resolvingSymlinksInPath().path else { return false }
        for name in Self.binaries where !fm.isExecutableFile(atPath: directory.appendingPathComponent(name).path) {
            throw SetupError("no \(name) next to \(directory.appendingPathComponent("perch").path); build both (swift build) and run setup from there")
        }
        try fm.createDirectory(at: environment.perchHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in Self.binaries {
            let target = bin.appendingPathComponent(name)
            let temporary = bin.appendingPathComponent(".\(name).\(UUID().uuidString.prefix(8))")
            do {
                try fm.copyItem(at: directory.appendingPathComponent(name).resolvingSymlinksInPath(), to: temporary)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
                removexattr(temporary.path, "com.apple.quarantine", XATTR_NOFOLLOW)
                guard rename(temporary.path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            } catch {
                try? fm.removeItem(at: temporary)
                throw SetupError("cannot install \(target.path): \(error.localizedDescription)")
            }
        }
        return true
    }

    /// An old Perch install (v0.3) copied `perch` / `perchd` into ~/.local/bin. Those regular files are replaced
    /// with links into the fixed location so typing `perch` doesn't run a stale version. Returns the replaced paths.
    @discardableResult
    public func linkOldBinaries() throws -> [String] {
        var replaced: [String] = []
        for name in Self.binaries {
            let path = environment.localBin.appendingPathComponent(name).path
            guard Self.isOldPerchBinary(path) else { continue }
            do {
                try FileManager.default.removeItem(atPath: path)
                try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: environment.binDirectory.appendingPathComponent(name).path)
            } catch {
                throw SetupError("cannot replace \(path) with a link: \(error.localizedDescription)")
            }
            replaced.append(path)
        }
        return replaced
    }

    /// A regular file (not a link) built from Perch: every perch / perchd knows the socket's name.
    static func isOldPerchBinary(_ path: String) -> Bool {
        guard let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType,
              type == .typeRegular,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return false }
        return data.range(of: Data("perchd.sock".utf8)) != nil
    }

    // MARK: launchd

    /// Installs (or reinstalls, restarting it) perchd's launchd agent against the fixed location.
    /// Returns whether perchd answers afterwards (only waited for with the real launchctl).
    @discardableResult
    public func installLaunchAgent(httpPort: Int = PerchPaths.defaultHTTPPort) throws -> Bool {
        let plist: Data
        do {
            plist = try LaunchAgent.plist(executable: environment.perchdBinary.path, arguments: ["run", "--http-port", String(httpPort)],
                                          home: environment.perchHome, environment: environment.variables)
        } catch {
            throw SetupError("cannot write the launchd plist: \(error.localizedDescription)")
        }
        let client = PerchClient(socketPath: environment.socket.path)
        if !FileManager.default.fileExists(atPath: launchAgent.plistURL.path), answers(client) {
            throw SetupError("a perchd is already running outside launchd; stop it first, then run setup again")
        }
        do {
            try launchAgent.install(plist: plist, home: environment.perchHome)
        } catch {
            throw SetupError("\(error)")
        }
        guard launchAgent.launchctl.isSystem else { return false }
        for _ in 0..<30 {
            if answers(client) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func answers(_ client: PerchClient) -> Bool {
        (try? client.send(Request(op: .ping), timeout: 1))?.ok == true
    }

    // MARK: Hooks

    /// Writes the plan's hook changes (each file backed up first) and records them in `agents`.
    /// A file that can't be written is reported and its agent left as it was.
    public func perform(_ plan: SetupPlan, recordingIn agents: inout AgentsFile, at now: Date = Date()) -> [AgentFailure] {
        var failures = plan.failures
        for change in plan.changes {
            if let text = change.text {
                do {
                    try HookFiles.write(text, to: change.config)
                } catch {
                    failures.append(AgentFailure(agent: change.agent, config: change.config,
                                                 message: "cannot write \(change.config): \(error.localizedDescription)"))
                    continue
                }
            }
            agents.turnOn(change.agent, config: change.config, hooksChanged: change.hooksChanged, at: now)
        }
        return failures
    }

    // MARK: Uninstall

    public struct Removal: Equatable, Sendable {
        public let agent: String
        public let config: String
        public let removed: Int
    }

    public struct UninstallReport: Equatable, Sendable {
        public var removals: [Removal] = []
        public var failures: [AgentFailure] = []
        public var launchAgentRemoved = false
        public var removedLinks: [String] = []
        public var purged = false
    }

    /// Removes Perch's hooks from every agent (Hermes too), perchd's launchd agent, the fixed location and the
    /// ~/.local/bin links into it. Keeps ~/.perch (database, allowlist.json, agents.json) unless `purge`.
    /// A hook file Perch can't parse is left alone and reported; everything else still goes.
    public func uninstall(purge: Bool) throws -> UninstallReport {
        var report = UninstallReport()
        let agents = (try? loadAgents()) ?? AgentsFile()
        for file in HookFiles.all {
            let paths = file.location.candidates(recorded: agents[file.agent]?.config, environment: environment.variables,
                                                 userHome: environment.userHome.path)
            for path in paths {
                do {
                    guard let text = try HookFiles.read(path) else { continue }
                    let (kept, removed) = try file.removing(text, path: path)
                    guard removed > 0 else { continue }
                    try HookFiles.write(kept, to: path)
                    report.removals.append(Removal(agent: file.agent, config: path, removed: removed))
                } catch let error as SetupError {
                    report.failures.append(AgentFailure(agent: file.agent, config: path, message: error.message))
                } catch {
                    report.failures.append(AgentFailure(agent: file.agent, config: path, message: "\(path): \(error.localizedDescription)"))
                }
            }
        }
        do {
            report.launchAgentRemoved = try launchAgent.uninstall()
        } catch {
            throw SetupError("cannot remove \(launchAgent.plistURL.path): \(error.localizedDescription)")
        }
        let fm = FileManager.default
        let bin = environment.binDirectory.standardizedFileURL.path + "/"
        for name in (try? fm.contentsOfDirectory(atPath: environment.localBin.path)) ?? [] {
            let link = environment.localBin.appendingPathComponent(name).path
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: link) else { continue }
            let absolute = URL(fileURLWithPath: destination, relativeTo: environment.localBin).standardizedFileURL.path
            guard absolute.hasPrefix(bin) else { continue }
            do {
                try fm.removeItem(atPath: link)
            } catch {
                throw SetupError("cannot remove \(link): \(error.localizedDescription)")
            }
            report.removedLinks.append(link)
        }
        let target = purge ? environment.perchHome : environment.binDirectory
        if fm.fileExists(atPath: target.path) {
            do {
                try fm.removeItem(at: target)
            } catch {
                throw SetupError("cannot remove \(target.path): \(error.localizedDescription)")
            }
        }
        report.purged = purge
        return report
    }
}
