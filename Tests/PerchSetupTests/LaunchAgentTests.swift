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
