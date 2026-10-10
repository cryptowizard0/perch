import Darwin
import Foundation
import PerchCore

/// perchd as a per-user launchd agent: `~/Library/LaunchAgents/dev.perch.perchd.plist`.
/// Starts at login, restarts after a crash, logs to `~/.perch/perchd.log`.
public enum LaunchAgent {
    public static let label = "dev.perch.perchd"

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func logURL(home: URL) -> URL {
        home.appendingPathComponent("perchd.log")
    }

    /// `arguments` are passed to perchd after the executable (e.g. `["run", "--http-port", "7331"]`).
    /// `PERCH_HOME` is pinned when the installing shell has it set, so the agent and the CLI agree.
    public static func plist(executable: String, arguments: [String], home: URL,
                             environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Data {
        var dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable] + arguments,
            "RunAtLoad": true,
            // Restart after crashes, not after a clean exit (SIGTERM from `launchctl bootout`).
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 5,
            // The notch must update within 200 ms of a CLI call; keep perchd off the background QoS.
            "ProcessType": "Interactive",
            "StandardOutPath": logURL(home: home).path,
            "StandardErrorPath": logURL(home: home).path,
        ]
        if let perchHome = environment["PERCH_HOME"], !perchHome.isEmpty {
            dict["EnvironmentVariables"] = ["PERCH_HOME": perchHome]
        }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// Writes the plist and (re)loads it into the user's GUI session.
    public static func install(plist: Data, home: URL) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = launchctl(["bootout", "\(domain)/\(label)"])  // not loaded is fine
        try plist.write(to: plistURL, options: .atomic)
        let (status, output) = launchctl(["bootstrap", domain, plistURL.path])
        guard status == 0 else { throw LaunchAgentError("launchctl bootstrap failed (\(status)): \(output)") }
    }

    /// Unloads the agent and deletes the plist. Returns false if nothing was installed.
    @discardableResult
    public static func uninstall() throws -> Bool {
        let loaded = launchctl(["bootout", "\(domain)/\(label)"]).0 == 0
        let existed = FileManager.default.fileExists(atPath: plistURL.path)
        if existed { try FileManager.default.removeItem(at: plistURL) }
        return loaded || existed
    }

    private static var domain: String { "gui/\(getuid())" }

    private static func launchctl(_ args: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct LaunchAgentError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}
