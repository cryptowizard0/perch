import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Running agent turns (Live Activity): in memory only, started by UserPromptSubmit, ended by Stop.
@Suite struct SessionTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func registry(now: Date) -> SessionRegistry {
        SessionRegistry(now: { now })
    }

    func start(_ r: SessionRegistry, _ id: String, at: Date, title: String = "perch") -> (Response, [SessionEvent]) {
        r.handle(Request(op: .sessionStart, session: Session(id: id, source: "claude-code", title: title, startedAt: at)))
    }

    func end(_ r: SessionRegistry, _ id: String, at: Date) -> (Response, [SessionEvent]) {
        r.handle(Request(op: .sessionEnd, id: id, at: at))
    }

    @Test func startListEnd() {
        let r = registry(now: t0.addingTimeInterval(60))
        let (started, events) = start(r, "s1", at: t0)
        #expect(started.ok)
        #expect(events.map(\.type) == [.started])
        #expect(r.handle(Request(op: .sessions)).0.sessions?.map(\.id) == ["s1"])
        let (ended, endEvents) = end(r, "s1", at: t0.addingTimeInterval(60))
        #expect(ended.ok)
        #expect(endEvents.map(\.type) == [.ended])
        #expect(endEvents.first?.session.id == "s1")
        #expect(r.handle(Request(op: .sessions)).0.sessions == [])
    }

    @Test func aNewTurnRestartsTheClock() {
        let r = registry(now: t0.addingTimeInterval(600))
        start(r, "s1", at: t0)
        let (_, events) = start(r, "s1", at: t0.addingTimeInterval(300), title: "renamed")
        #expect(events.map(\.type) == [.started])
        let session = r.handle(Request(op: .sessions)).0.sessions?.first
        #expect(session?.startedAt == t0.addingTimeInterval(300))
        #expect(session?.title == "renamed")
    }

    @Test func lateMessagesFromAsyncHooksAreIgnored() {
        let r = registry(now: t0.addingTimeInterval(10))
        // Stop's hook finished before UserPromptSubmit's hook of the same (short) turn.
        end(r, "s1", at: t0.addingTimeInterval(5))
        let (response, events) = start(r, "s1", at: t0)
        #expect(response.ok)
        #expect(events.isEmpty)
        #expect(r.handle(Request(op: .sessions)).0.sessions == [])

        // Turn 1's Stop arrives after turn 2 already started.
        start(r, "s2", at: t0.addingTimeInterval(8))
        let (_, late) = end(r, "s2", at: t0.addingTimeInterval(7))
        #expect(late.isEmpty)
        #expect(r.handle(Request(op: .sessions)).0.sessions?.map(\.id) == ["s2"])
    }

    @Test func sameSecondStartAfterEndWins() {
        let r = registry(now: t0.addingTimeInterval(10))
        start(r, "s1", at: t0)
        end(r, "s1", at: t0.addingTimeInterval(5))
        #expect(start(r, "s1", at: t0.addingTimeInterval(5)).1.map(\.type) == [.started])
    }

    @Test func endingAnUnknownSessionIsFine() {
        let (response, events) = end(registry(now: t0), "nope", at: t0)
        #expect(response.ok)
        #expect(events.isEmpty)
    }

    @Test func turnsThatNeverStopExpire() {
        var now = t0.addingTimeInterval(SessionRegistry.maxTurn - 60)
        let r = SessionRegistry(now: { now })
        start(r, "stuck", at: t0)
        start(r, "fresh", at: t0.addingTimeInterval(SessionRegistry.maxTurn - 60))
        #expect(r.nextExpiry() == t0.addingTimeInterval(SessionRegistry.maxTurn))
        now = t0.addingTimeInterval(SessionRegistry.maxTurn)
        #expect(r.sweep().map(\.session.id) == ["stuck"])
        #expect(r.handle(Request(op: .sessions)).0.sessions?.map(\.id) == ["fresh"])
    }

    @Test func validation() {
        let r = registry(now: t0)
        #expect(r.handle(Request(op: .sessionStart)).0.error == "session_start needs a session")
        #expect(r.handle(Request(op: .sessionStart, session: Session(id: " ", source: "x", title: "t"))).0.error
                == "session id must not be empty")
        #expect(r.handle(Request(op: .sessionEnd)).0.error == "missing id")
    }

    @Test func wireFormat() throws {
        let json = #"{"op":"session_start","session":{"id":"abc","source":"claude-code","title":"perch","started_at":"2027-01-15T08:00:00Z"}}"#
        let request = try PerchJSON.decoder.decode(Request.self, from: Data(json.utf8))
        #expect(request.op == .sessionStart)
        #expect(request.session == Session(id: "abc", source: "claude-code", title: "perch", startedAt: t0))
        // Only id is required; started_at defaults to now.
        let minimal = try PerchJSON.decoder.decode(Session.self, from: Data(#"{"id":"x"}"#.utf8))
        #expect(minimal.source == "unknown" && minimal.title == "x")
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
        guard case .item(let added) = try stream.nextPush(timeout: 5) else { Issue.record("expected item"); return }
        #expect(added.item.title == "a task")

        let itemsOnly = try d.client.watch()
        _ = try d.client.send(Request(op: .sessionEnd, id: "s1"))
        _ = try d.client.send(Request(op: .add, item: Item(title: "second")))
        #expect(try itemsOnly.next(timeout: 5)?.item.title == "second")
    }

    @Test func cliSessionCommands() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        #expect(try cli.run("session", "start", "s1", "--source", "claude-code", "--title", "perch").status == 0)
        let listed = try cli.run("session", "ls", "--json").json.sessions
        #expect(listed?.map(\.title) == ["perch"])
        #expect(try cli.run("session", "ls").stdout.contains("claude-code  perch"))
        #expect(try cli.run("session", "end", "s1").status == 0)
        #expect(try cli.run("session", "ls", "--json").json.sessions == [])
    }
}
