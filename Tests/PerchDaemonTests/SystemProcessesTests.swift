import Foundation
import PerchClient
import PerchCore
import Testing

/// Live processes, read with sysctl.
@Suite struct SystemProcessesTests {
    @Test func seesThisProcessAndItsAncestors() throws {
        let table = SystemProcesses.ancestors(of: getpid())
        let me = try #require(table[getpid()])
        #expect(me.ppid == getppid())
        #expect(me.startedAt <= Date() && me.startedAt > Date().addingTimeInterval(-24 * 3600))
        // Whole seconds, like every date perchd stores.
        #expect(me.startedAt.timeIntervalSince1970 == me.startedAt.timeIntervalSince1970.rounded(.down))
        #expect(me.name == CommandLine.arguments[0].split(separator: "/").last.map(String.init))
        #expect(table[getppid()] != nil)
        #expect(table[1]?.name == "launchd")
    }

    @Test func namedAsStartedNotAsTheFileIsCalled() throws {
        // What `~/.local/bin/claude` (a symlink into `versions/`) looks like: the kernel says `bash`.
        let dir = URL(fileURLWithPath: "/tmp/perch-proc-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/bin/bash")
        let process = Process()
        process.executableURL = link
        process.arguments = ["-c", "sleep 5; exit 0"]  // `; exit 0`: bash stays, it does not exec sleep
        try process.run()
        defer { process.terminate() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(SystemProcesses.entry(pid: process.processIdentifier)?.name == "claude")
    }

    @Test func startTimeOrNothing() throws {
        #expect(SystemProcesses.startTime(of: getpid()) == SystemProcesses.entry(pid: getpid())?.startedAt)
        #expect(SystemProcesses.startTime(of: 99_999_999) == nil)
        #expect(SystemProcesses.entry(pid: -1) == nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        let pid = process.processIdentifier
        process.waitUntilExit()
        #expect(SystemProcesses.startTime(of: pid) == nil)
    }
}
