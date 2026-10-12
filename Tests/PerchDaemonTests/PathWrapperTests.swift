import Foundation
import Testing

/// `packaging/perch-path.sh`, which Homebrew links onto PATH as `perch`: it runs the copy Perch.app installs in
/// ~/.perch/bin (no quarantine flag there), and until the app has been opened says so.
@Suite struct PathWrapperTests {
    static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("packaging/perch-path.sh")
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("perch-path-\(UUID().uuidString.prefix(8))")

    func run(_ args: [String]) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = Self.script
        process.arguments = args
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: home) }

    @Test func runsThePerchInTheFixedLocationWithTheSameArguments() throws {
        defer { cleanUp() }
        let bin = home.appendingPathComponent(".perch/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let perch = bin.appendingPathComponent("perch")
        try "#!/bin/sh\nprintf '%s|' \"$@\"\nexit 7\n".write(to: perch, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: perch.path)
        let result = try run(["session", "ls", "a b"])
        #expect(result.out == "session|ls|a b|")
        #expect(result.status == 7, "its exit code passes through")
    }

    @Test func beforeTheAppWasOpenedItSaysSo() throws {
        defer { cleanUp() }
        let result = try run(["session", "ls"])
        #expect(result.status == 1)
        #expect(result.out.isEmpty)
        #expect(result.err == "perch: open Perch.app once to finish installing (it puts perch in ~/.perch/bin)\n")
        // --json: the CLI's error shape on stdout.
        let json = try run(["session", "ls", "--json"])
        #expect(json.status == 1)
        #expect(json.out == "{\"ok\":false,\"error\":\"open Perch.app once to finish installing (it puts perch in ~/.perch/bin)\"}\n")
    }
}
