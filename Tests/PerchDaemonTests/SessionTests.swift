import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// `session_start` / `session_end` (what Hermes and `perch session start|end` use): start runs a turn, end removes.
@Suite struct SessionTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func daemon() throws -> TestDaemon {
        try TestDaemon(now: { [t0] in t0.addingTimeInterval(600) })
    }

    @discardableResult
    func start(_ d: TestDaemon, _ id: String, at: Date, title: String = "perch") throws -> Response {
        try d.client.send(Request(op: .sessionStart, session: Session(id: id, source: "claude-code", title: title, startedAt: at)))
    }

    @discardableResult
    func end(_ d: TestDaemon, _ id: String, at: Date) throws -> Response {
        try d.client.send(Request(op: .sessionEnd, id: id, at: at))
    }

    func sessions(_ d: TestDaemon) throws -> [Session] {
        try d.client.send(Request(op: .sessions)).sessions ?? []
    }

    @Test func startListEnd() throws {
        let d = try daemon()
        #expect(try start(d, "s1", at: t0).ok)
        let s = try #require(try sessions(d).first)
        #expect(s.id == "s1" && s.status == .running && s.turnStartedAt == t0 && s.startedAt == t0)
        #expect(try end(d, "s1", at: t0.addingTimeInterval(60)).sessions?.map(\.id) == ["s1"])
        #expect(try sessions(d) == [])
    }

    @Test func aNewTurnRestartsTheClock() throws {
        let d = try daemon()
        try start(d, "s1", at: t0)
        try start(d, "s1", at: t0.addingTimeInterval(300), title: "renamed")
        let s = try #require(try sessions(d).first)
        #expect(s.turnStartedAt == t0.addingTimeInterval(300) && s.startedAt == t0)
        #expect(s.title == "renamed")
    }

    @Test func lateMessagesFromAsyncHooksAreIgnored() throws {
        let d = try daemon()
        // Stop's hook finished before UserPromptSubmit's hook of the same (short) turn.
        try start(d, "s1", at: t0)
        try end(d, "s1", at: t0.addingTimeInterval(5))
        try start(d, "s1", at: t0.addingTimeInterval(2))
        #expect(try sessions(d) == [])

        // Turn 1's end arrives after turn 2 already started.
        try start(d, "s2", at: t0.addingTimeInterval(8))
        try end(d, "s2", at: t0.addingTimeInterval(7))
        #expect(try sessions(d).map(\.id) == ["s2"])
    }

    @Test func sameSecondStartAfterEndWins() throws {
        let d = try daemon()
        try start(d, "s1", at: t0)
        try end(d, "s1", at: t0.addingTimeInterval(5))
        try start(d, "s1", at: t0.addingTimeInterval(5))
        #expect(try sessions(d).map(\.id) == ["s1"])
    }

    @Test func endingAnUnknownSessionIsFine() throws {
        #expect(try end(try daemon(), "nope", at: t0).ok)
    }

    @Test func validation() throws {
        let d = try daemon()
        #expect(try d.client.send(Request(op: .sessionStart)).error == "session_start needs a session")
        #expect(try d.client.send(Request(op: .sessionStart, session: Session(id: " ", source: "x", title: "t"))).error
                == "session id must not be empty")
        #expect(try d.client.send(Request(op: .sessionEnd)).error == "session id must not be empty")
        #expect(try d.client.send(Request(op: .sessionReport)).error == "session_report needs a report")
        #expect(try d.client.send(Request(op: .sessionSeen, id: "nope")).error == "no session with id 'nope'")
        #expect(try d.client.send(Request(op: .sessionRemove)).error == "missing id")
    }

    @Test func wireFormat() throws {
        let json = #"{"op":"session_start","session":{"id":"abc","source":"claude-code","title":"perch","started_at":"2027-01-15T08:00:00Z"}}"#
        let request = try PerchJSON.decoder.decode(Request.self, from: Data(json.utf8))
        #expect(request.op == .sessionStart)
        #expect(request.session == Session(id: "abc", source: "claude-code", title: "perch", startedAt: t0))
        // Only id is required; a session without a status is running.
        let minimal = try PerchJSON.decoder.decode(Session.self, from: Data(#"{"id":"x"}"#.utf8))
        #expect(minimal.source == "unknown" && minimal.title == "x" && minimal.status == .running)

        var s = Session(id: "abc", source: "codex", title: "perch", startedAt: t0, status: .done, cwd: "/w/perch")
        s.lastMessage = "ok"
        let encoded = String(decoding: try PerchJSON.encoder.encode(s), as: UTF8.self)
        #expect(encoded.contains(#""status":"done""#) && encoded.contains(#""last_message":"ok""#)
                && encoded.contains(#""turn_started_at":"2027-01-15T08:00:00Z""#))
        #expect(try PerchJSON.decoder.decode(Session.self, from: Data(encoded.utf8)) == s)

        let report = #"{"op":"session_report","report":{"id":"abc","kind":"waiting","at":"2027-01-15T08:00:00Z","detail":"npm test","keep_detail":true}}"#
        let decoded = try PerchJSON.decoder.decode(Request.self, from: Data(report.utf8))
        #expect(decoded.report == SessionReport(id: "abc", kind: .waiting, at: t0, detail: "npm test", keepDetail: true))
    }

    @Test func statusPriority() {
        #expect(SessionStatus.allCases.sorted { $0.priority < $1.priority } == [.waiting, .failed, .running, .done, .idle])
    }
}

/// Through a real perchd: watchers see session events; old-style `next()` skips them.
@Suite struct SessionWatchTests {
    @Test func watchersGetSessionEvents() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        _ = try d.client.send(Request(op: .sessionStart, session: Session(id: "s1", source: "claude-code", title: "perch")))
        _ = try d.client.send(Request(op: .add, item: Item(title: "a task")))
        guard case .session(let started) = try stream.nextPush(timeout: 5) else { Issue.record("expected session"); return }
        #expect(started.type == .started && started.session.id == "s1")
        guard case .session(let updated) = try stream.nextPush(timeout: 5) else { Issue.record("expected session"); return }
        #expect(updated.type == .updated && updated.session.status == .running)
        guard case .item(let added) = try stream.nextPush(timeout: 5) else { Issue.record("expected item"); return }
        #expect(added.item.title == "a task")

        let itemsOnly = try d.client.watch()
        _ = try d.client.send(Request(op: .sessionEnd, id: "s1"))
        _ = try d.client.send(Request(op: .add, item: Item(title: "second")))
        guard case .session(let ended) = try stream.nextPush(timeout: 5) else { Issue.record("expected session"); return }
        #expect(ended.type == .ended && ended.session.id == "s1")
        #expect(try itemsOnly.next(timeout: 5)?.item.title == "second")
    }

    @Test func cliSessionCommands() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        #expect(try cli.run("session", "start", "s1", "--source", "claude-code", "--title", "perch").status == 0)
        let listed = try cli.run("session", "ls", "--json").json.sessions
        #expect(listed?.map(\.title) == ["perch"])
        #expect(listed?.map(\.status) == [.running])
        #expect(try cli.run("session", "ls").stdout.contains("claude-code  perch"))
        #expect(try cli.run("session", "end", "s1").status == 0)
        #expect(try cli.run("session", "ls", "--json").json.sessions == [])
    }
}
