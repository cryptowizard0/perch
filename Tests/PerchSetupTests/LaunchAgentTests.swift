import Foundation
import Testing
@testable import PerchSetup

@Suite struct LaunchAgentTests {
    func decode(_ data: Data) throws -> [String: Any] {
        try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func plistRunsPerchdAtLoginAndRestartsOnCrash() throws {
        let home = URL(fileURLWithPath: "/Users/me/.perch")
        let plist = try decode(LaunchAgent.plist(executable: "/usr/local/bin/perchd",
                                                 arguments: ["run", "--http-port", "7331"], home: home, environment: [:]))
        #expect(plist["Label"] as? String == "dev.perch.perchd")
        #expect(plist["ProgramArguments"] as? [String] == ["/usr/local/bin/perchd", "run", "--http-port", "7331"])
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect((plist["KeepAlive"] as? [String: Bool])?["SuccessfulExit"] == false)
        #expect(plist["StandardErrorPath"] as? String == "/Users/me/.perch/perchd.log")
        #expect(plist["EnvironmentVariables"] == nil)
    }

    @Test func pinsPerchHomeWhenSet() throws {
        let plist = try decode(LaunchAgent.plist(executable: "/x/perchd", arguments: ["run"],
                                                 home: URL(fileURLWithPath: "/tmp/p"), environment: ["PERCH_HOME": "/tmp/p"]))
        #expect(plist["EnvironmentVariables"] as? [String: String] == ["PERCH_HOME": "/tmp/p"])
    }
}

/// Reinstalling: `launchctl bootout` returns before the old perchd has exited, and a bootstrap in that window fails
/// with "5: Input/output error" (seen when the app restarted perchd after syncing binaries, 2026-10-10).
@Suite struct LaunchAgentInstallTests {
    @Test func aBootstrapRefusedWhileTheOldJobIsStillGoingIsRetried() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("perch-launchagent-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        // Refuses the first two bootstraps, like launchd while it is still removing the old job.
        let count = home.appendingPathComponent("bootstraps")
        let script = home.appendingPathComponent("launchctl")
        try """
            #!/bin/sh
            echo "$@" >> '\(home.path)/launchctl.log'
            [ "$1" = bootstrap ] || exit 0
            n=$(($(cat '\(count.path)' 2>/dev/null || echo 0) + 1)); echo $n > '\(count.path)'
            [ $n -ge 3 ] || { echo "Bootstrap failed: 5: Input/output error"; exit 5; }
            """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let agent = LaunchAgent(userHome: home, launchctl: Launchctl(path: script.path))
        try agent.install(plist: Data("<plist/>".utf8), home: home.appendingPathComponent(".perch"))
        #expect(try String(contentsOf: count, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "3")
    }

    @Test func aBootstrapThatKeepsFailingIsReported() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("perch-launchagent-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let script = home.appendingPathComponent("launchctl")
        try "#!/bin/sh\n[ \"$1\" = bootstrap ] || exit 0\necho nope; exit 5\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let agent = LaunchAgent(userHome: home, launchctl: Launchctl(path: script.path), bootstrapTimeout: 0.5)
        #expect(throws: LaunchAgentError.self) {
            try agent.install(plist: Data("<plist/>".utf8), home: home.appendingPathComponent(".perch"))
        }
    }
}
