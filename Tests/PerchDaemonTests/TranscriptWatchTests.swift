import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// #8: Claude Code sends no hook when you answer No (or press Esc) at its permission prompt. perchd watches the
/// transcript of every running / waiting session and turns it idle when the turn ends that way.
@Suite struct TranscriptWatchTests {
    func eventually(_ timeout: TimeInterval = 3, _ condition: () throws -> Bool) rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return try condition()
    }

    static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    func entry(_ type: String, _ content: String? = nil, at: Date = Date(), extra: String = "") -> String {
        let message = content.map { #","message":{"role":"\#(type)","content":\#($0)}"# } ?? ""
        return #"{"type":"\#(type)","timestamp":"\#(Self.stamp(at))"\#(message)\#(extra)}"# + "\n"
    }

    func interrupted(at: Date = Date()) -> String {
        entry("user", #"[{"type":"tool_result","content":"The user doesn't want to proceed with this tool use.","is_error":true}]"#, at: at)
            + entry("user", #"[{"type":"text","text":"[Request interrupted by user for tool use]"}]"#, at: at)
            + entry("system", at: at, extra: #","subtype":"turn_duration""#)
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func report(_ d: TestDaemon, _ kind: SessionReport.Kind, transcript: URL?, at: Date = Date(), detail: String? = nil) throws {
        var r = SessionReport(id: "s1", kind: kind, at: at, source: "claude-code", title: "perch", prompt: kind == .prompt ? "go" : nil,
                              detail: detail)
        r.transcriptPath = transcript?.path
        #expect(try d.client.send(Request(op: .sessionReport, report: r)).ok)
    }

    func status(_ d: TestDaemon) throws -> SessionStatus? {
        try d.client.send(Request(op: .sessions)).sessions?.first { $0.id == "s1" }?.status
    }

    @Test func answeringNoAtThePromptTurnsTheSessionIdle() throws {
        let d = try TestDaemon()
        let transcript = d.home.appendingPathComponent("s1.jsonl")
        try entry("user", #""Run rm -rf build""#).write(to: transcript, atomically: true, encoding: .utf8)
        try report(d, .prompt, transcript: transcript)
        try report(d, .waiting, transcript: transcript, detail: "rm -rf build\nAnswer in the terminal")
        #expect(try status(d) == .waiting)

        Thread.sleep(forTimeInterval: 1)  // the marker comes after the report (whole seconds)
        try append(entry("assistant", #"[{"type":"tool_use","name":"Bash"}]"#) + interrupted(), to: transcript)
        #expect(try eventually { try status(d) == .idle })
        let s = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(s.detail == nil && s.transcriptPath == transcript.path)
    }

    @Test func aNormalEndIsLeftToTheStopHook() throws {
        let d = try TestDaemon()
        let transcript = d.home.appendingPathComponent("s1.jsonl")
        try entry("user", #""hi""#).write(to: transcript, atomically: true, encoding: .utf8)
        try report(d, .prompt, transcript: transcript)
        try append(entry("assistant", #"[{"type":"text","text":"Hello."}]"#) + entry("system", extra: #","subtype":"turn_duration""#),
                   to: transcript)
        Thread.sleep(forTimeInterval: 0.5)
        #expect(try status(d) == .running)
    }

    @Test func anOldInterruptionDoesNotEndTheNextTurn() throws {
        let d = try TestDaemon()
        let transcript = d.home.appendingPathComponent("s1.jsonl")
        // The last turn was interrupted; the new prompt's hook arrives before Claude Code writes the prompt down.
        try interrupted(at: Date().addingTimeInterval(-5)).write(to: transcript, atomically: true, encoding: .utf8)
        try report(d, .prompt, transcript: transcript)
        Thread.sleep(forTimeInterval: 0.5)
        #expect(try status(d) == .running)
    }

    @Test func anInterruptionWhilePerchdWasDownIsFoundAtStartup() throws {
        let home = TestDaemon.freshHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = home.appendingPathComponent("s1.jsonl")
        do {
            let d = try TestDaemon(home: home, removeHome: false)
            try entry("user", #""Run rm -rf build""#).write(to: transcript, atomically: true, encoding: .utf8)
            try report(d, .waiting, transcript: transcript, at: Date().addingTimeInterval(-2), detail: "rm -rf build")
            try? FileManager.default.removeItem(atPath: d.daemon.config.socketPath)  // perchd's startup does this
        }
        try append(interrupted(), to: transcript)
        let restarted = try TestDaemon(home: home, removeHome: false)
        #expect(try eventually { try status(restarted) == .idle })
    }

    /// Sessions that are done, idle or failed are not watched; only running / waiting ones can be stuck.
    @Test func onlyRunningAndWaitingSessionsAreWatched() throws {
        let d = try TestDaemon()
        let transcript = d.home.appendingPathComponent("s1.jsonl")
        try entry("user", #""hi""#).write(to: transcript, atomically: true, encoding: .utf8)
        try report(d, .prompt, transcript: transcript)
        #expect(d.daemon.watchedTranscripts == ["s1": transcript.path])
        try report(d, .stop, transcript: transcript)
        #expect(d.daemon.watchedTranscripts.isEmpty)
    }
}
