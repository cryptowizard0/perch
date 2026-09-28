import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Sessions whose agent process is gone disappear on the next liveness sweep; sessions without a pid after
/// 24 hours without events.
@Suite struct SessionLivenessTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A process table tests can change: pid → start time.
    final class Processes: @unchecked Sendable {
        private var table: [Int32: Date] = [:]
        private let lock = NSLock()
        subscript(pid: Int32) -> Date? {
            get { lock.withLock { table[pid] } }
            set { lock.withLock { table[pid] = newValue } }
        }
    }

    func daemon(_ clock: Clock, _ processes: Processes) throws -> TestDaemon {
        try TestDaemon(now: clock.read, probe: { processes[$0] })
    }

    func report(_ d: TestDaemon, _ id: String, _ kind: SessionReport.Kind = .prompt, at: Date, pid: Int32? = nil,
                pidStartedAt: Date? = nil) throws {
        let r = try d.client.send(Request(op: .sessionReport, report: SessionReport(
            id: id, kind: kind, at: at, source: "claude-code", title: "perch", pid: pid, pidStartedAt: pidStartedAt)))
        #expect(r.ok)
    }

    func ids(_ d: TestDaemon) throws -> Set<String> {
        Set(try d.client.send(Request(op: .sessions)).sessions?.map(\.id) ?? [])
    }

    @Test func aSessionWhoseProcessDiesIsRemoved() throws {
        let clock = Clock(t0)
        let processes = Processes()
        processes[4242] = t0.addingTimeInterval(-60)
        processes[5353] = t0.addingTimeInterval(-30)
        let d = try daemon(clock, processes)
        try report(d, "alive", at: t0, pid: 5353, pidStartedAt: t0.addingTimeInterval(-30))
        try report(d, "dies", at: t0, pid: 4242, pidStartedAt: t0.addingTimeInterval(-60))
        let stored = try #require(try d.client.send(Request(op: .sessions)).sessions?.first { $0.id == "dies" })
        #expect(stored.pid == 4242 && stored.pidStartedAt == t0.addingTimeInterval(-60))

        d.daemon.checkLiveness()
        #expect(try ids(d) == ["alive", "dies"])

        let stream = try d.client.watch()
        processes[4242] = nil
        clock.advance(30)
        d.daemon.checkLiveness()
        #expect(try ids(d) == ["alive"])
        guard case .session(let ended) = try stream.nextPush(timeout: 5) else { Issue.record("expected session event"); return }
        #expect(ended.type == .ended && ended.session.id == "dies")
    }

    @Test func aReusedPidIsNotTheAgent() throws {
        let clock = Clock(t0)
        let processes = Processes()
        processes[4242] = t0.addingTimeInterval(-60)
        let d = try daemon(clock, processes)
        try report(d, "s1", at: t0, pid: 4242, pidStartedAt: t0.addingTimeInterval(-60))

        // The agent exited and something else got its pid.
        processes[4242] = t0.addingTimeInterval(20)
        clock.advance(30)
        d.daemon.checkLiveness()
        #expect(try ids(d).isEmpty)
    }

    @Test func aPidWithoutStartTimeOnlyNeedsToExist() throws {
        let clock = Clock(t0)
        let processes = Processes()
        processes[4242] = t0
        let d = try daemon(clock, processes)
        try report(d, "s1", at: t0, pid: 4242)
        d.daemon.checkLiveness()
        #expect(try ids(d) == ["s1"])
        processes[4242] = nil
        d.daemon.checkLiveness()
        #expect(try ids(d).isEmpty)
    }

    @Test func aRemovedSessionClosesItsRequestAndStaysGone() throws {
        let clock = Clock(t0)
        let processes = Processes()
        processes[4242] = t0
        let d = try daemon(clock, processes)
        try report(d, "s1", .waiting, at: t0, pid: 4242, pidStartedAt: t0)
        let request = try #require(try d.client.send(Request(op: .add, item: Item(
            title: "npm test", kind: .request, source: "claude-code", meta: ["session_id": "s1"]))).item)

        processes[4242] = nil
        clock.advance(30)
        d.daemon.checkLiveness()
        #expect(try d.client.send(Request(op: .get, id: request.id)).item?.status == .done)

        // An async hook from before the process died does not bring it back.
        try report(d, "s1", .stop, at: t0.addingTimeInterval(10), pid: 4242, pidStartedAt: t0)
        #expect(try ids(d).isEmpty)
    }

    @Test func aSessionWithoutPidGoesAfterADayOfSilence() throws {
        let clock = Clock(t0)
        let processes = Processes()
        processes[4242] = t0
        let d = try daemon(clock, processes)
        try report(d, "no-pid", at: t0)
        try report(d, "with-pid", at: t0, pid: 4242, pidStartedAt: t0)

        clock.advance(24 * 3600 - 1)
        d.daemon.checkLiveness()
        #expect(try ids(d) == ["no-pid", "with-pid"])

        // An event resets the day.
        try report(d, "no-pid", .stop, at: clock.read())
        clock.advance(2)
        d.daemon.checkLiveness()
        #expect(try ids(d) == ["no-pid", "with-pid"])

        clock.advance(24 * 3600)
        d.daemon.checkLiveness()
        // A live process keeps its session however quiet it is.
        #expect(try ids(d) == ["with-pid"])
    }

    @Test func theSweepRunsOnItsOwn() throws {
        let processes = Processes()
        processes[4242] = t0
        let d = try TestDaemon(now: { [t0] in t0 }, probe: { processes[$0] }, livenessInterval: 0.1)
        try report(d, "s1", at: t0, pid: 4242, pidStartedAt: t0)
        let stream = try d.client.watch()
        processes[4242] = nil
        guard case .session(let ended) = try stream.nextPush(timeout: 5) else { Issue.record("expected session event"); return }
        #expect(ended.type == .ended && ended.session.id == "s1")
    }
}

/// End to end: `perch hook` reports the agent it runs under, and perchd drops the session once that process exits.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct HookProcessTests {
    @Test func theHookReportsItsAgentAndTheSessionGoesWithIt() throws {
        let d = try TestDaemon()
        // A shell started as `claude` (like ~/.local/bin/claude, a symlink) stands in for Claude Code.
        let dir = URL(fileURLWithPath: "/tmp/perch-agent-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let claude = dir.appendingPathComponent("claude")
        try FileManager.default.createSymbolicLink(atPath: claude.path, withDestinationPath: "/bin/bash")

        let agent = Process()
        agent.executableURL = claude
        // `; exit 0` keeps bash from exec'ing perch in its place.
        agent.arguments = ["-c", #""$PERCH" hook claude-code; exit 0"#]
        agent.environment = ProcessInfo.processInfo.environment.merging([
            "PERCH": CLI.binary!.path, "PERCH_HOME": d.home.path, "TERM_PROGRAM": "Apple_Terminal",
        ]) { $1 }
        let input = Pipe()
        agent.standardInput = input
        agent.standardOutput = FileHandle.nullDevice
        let before = Date()
        try agent.run()
        let pid = agent.processIdentifier
        let started = SystemProcesses.entry(pid: pid)?.startedAt
        input.fileHandleForWriting.write(Data(#"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#.utf8))
        try input.fileHandleForWriting.close()
        agent.waitUntilExit()

        let s = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(s.id == "s1" && s.pid == pid)
        let at = try #require(s.pidStartedAt)
        #expect(started.map { $0 == at } ?? true)
        #expect(at >= before.addingTimeInterval(-1) && at <= Date())

        // The "agent" has exited: the next sweep removes its session.
        d.daemon.checkLiveness()
        #expect(try d.client.send(Request(op: .sessions)).sessions == [])
    }
}
