import Foundation
import PerchAppCore
import PerchCore
import Testing

/// What the notch shows for a set of sessions: one colour, a running count, grouped rows.
@Suite struct PanelTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ id: String, _ status: SessionStatus, source: String = "claude-code", turn: TimeInterval = 0,
                 since: TimeInterval = 0) -> Session {
        var s = Session(id: id, source: source, title: id, startedAt: t0)
        s.status = status
        s.turnStartedAt = t0.addingTimeInterval(turn)
        s.statusAt = t0.addingTimeInterval(since)
        return s
    }

    @Test func theMostUrgentSessionColoursTheDot() {
        #expect(Panel(sessions: []).signal == nil)
        #expect(Panel(sessions: [session("a", .idle)]).signal == .idle)
        #expect(Panel(sessions: [session("a", .idle), session("b", .done)]).signal == .done)
        #expect(Panel(sessions: [session("a", .done), session("b", .running)]).signal == .running)
        #expect(Panel(sessions: [session("a", .running), session("b", .failed)]).signal == .failed)
        #expect(Panel(sessions: [session("a", .failed), session("b", .waiting), session("c", .running)]).signal == .waiting)
    }

    @Test func onlyRunningSessionsAreCounted() {
        let panel = Panel(sessions: [session("a", .running), session("b", .running), session("c", .waiting), session("d", .done)])
        #expect(panel.runningCount == 2)
        #expect(Panel(sessions: [session("a", .done)]).runningCount == 0)
    }

    @Test func groupedByStateInPriorityOrderEmptyGroupsHidden() {
        let panel = Panel(sessions: [
            session("run-late", .running, turn: 50), session("run-early", .running, turn: 10),
            session("wait-new", .waiting, since: 40), session("wait-old", .waiting, since: 5),
            session("done-old", .done, since: 1), session("done-new", .done, since: 30),
            session("idle-old", .idle, since: 2), session("idle-new", .idle, since: 20),
        ])
        #expect(panel.groups.map(\.status) == [.waiting, .running, .done, .idle])
        #expect(panel.groups.map(\.title) == ["Needs you", "Running", "Done", "Idle"])
        // Needs you: longest waiting first. Running: by turn start. Done / Idle: most recent first.
        #expect(panel.groups.map { $0.sessions.map(\.id) } == [
            ["wait-old", "wait-new"], ["run-early", "run-late"], ["done-new", "done-old"], ["idle-new", "idle-old"],
        ])
        #expect(Panel(sessions: [session("f", .failed)]).groups.map(\.title) == ["Failed"])
    }

    @Test func hermesSessionsWaitForM9() {
        let panel = Panel(sessions: [session("h", .running, source: "hermes"), session("c", .done)])
        #expect(panel.sessions.map(\.id) == ["c"])
        #expect(panel.signal == .done && panel.runningCount == 0)
    }

    @Test func aNeedsYouSessionFindsItsRequest() {
        let waiting = session("s1", .waiting)
        let request = Item(id: "r1", title: "npm test", kind: .request, status: .waiting, meta: ["session_id": "s1"])
        let other = Item(id: "r2", title: "ls", kind: .request, status: .waiting, meta: ["session_id": "s2"])
        let answered = Item(id: "r3", title: "npm test", kind: .request, status: .done, meta: ["session_id": "s1"])
        let task = Item(id: "t1", title: "x", kind: .task, status: .waiting, meta: ["session_id": "s1"])
        let panel = Panel(sessions: [waiting, session("s2", .running)], requests: [other, answered, task, request])
        #expect(panel.request(for: waiting)?.id == "r1")
        // Only a session that needs you is answered from the notch.
        #expect(panel.request(for: session("s2", .running)) == nil)
        #expect(Panel(sessions: [waiting]).request(for: waiting) == nil)
    }

    @Test func enteringNeedsYouFailedOrDonePulses() {
        for status in [SessionStatus.waiting, .failed, .done] {
            #expect(Panel.pulses(from: nil, to: status))
            #expect(Panel.pulses(from: .running, to: status))
            #expect(!Panel.pulses(from: status, to: status), "staying \(status) does not pulse again")
        }
        #expect(!Panel.pulses(from: nil, to: .running))
        #expect(!Panel.pulses(from: .waiting, to: .running))
        #expect(!Panel.pulses(from: .done, to: .idle))
        #expect(!Panel.pulses(from: .done, to: nil))
    }
}

/// One row's time and second line.
@Suite struct SessionRowTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func session(_ status: SessionStatus) -> Session {
        var s = Session(id: "s1", source: "claude-code", title: "perch", startedAt: t0)
        s.status = status
        s.turnStartedAt = t0
        s.statusAt = t0.addingTimeInterval(60)
        s.prompt = "Refactor the state machine"
        s.detail = "rm -rf build/\nAnswer in the terminal: rm is never approved from the notch"
        s.error = "rate_limit"
        s.lastMessage = "All 12 tests pass."
        return s
    }

    @Test func timeSaysHowLongInTheCurrentState() {
        let now = t0.addingTimeInterval(60 + 4 * 60)
        #expect(SessionRow.time(session(.running), now: now) == "5m")      // this turn so far
        #expect(SessionRow.time(session(.waiting), now: now) == "4m")      // waited
        #expect(SessionRow.time(session(.failed), now: now) == "4m ago")
        #expect(SessionRow.time(session(.done), now: now) == "4m ago")
        #expect(SessionRow.time(session(.idle), now: now) == "4m ago")
        #expect(SessionRow.time(session(.waiting), now: t0.addingTimeInterval(90)) == "<1m")
        #expect(SessionRow.time(session(.done), now: t0.addingTimeInterval(90)) == "just now")
    }

    @Test func secondLineFollowsTheState() {
        #expect(SessionRow.detail(session(.running)) == "Refactor the state machine")
        // Needs you: the full text, every line of it.
        #expect(SessionRow.detail(session(.waiting)) == "rm -rf build/\nAnswer in the terminal: rm is never approved from the notch")
        #expect(SessionRow.detail(session(.failed)) == "rate_limit")
        #expect(SessionRow.detail(session(.done)) == "All 12 tests pass.")
        #expect(SessionRow.detail(session(.idle)) == "All 12 tests pass.")

        var bare = Session(id: "s2", startedAt: t0)
        #expect(SessionRow.detail(bare) == nil)
        bare.status = .waiting
        #expect(SessionRow.detail(bare) == "Waiting for your answer")
    }
}

@Suite struct NeedsYouTests {
    @Test func theCommandAndWhereToAnswerSplitApart() {
        let heredoc = "cat <<EOF > notes.txt\nline one\nEOF"
        let parts = SessionRow.needsYou(heredoc + "\nAnswer in the terminal: uses shell operators")
        #expect(parts.text == heredoc && parts.hint == "Answer in the terminal: uses shell operators")
        #expect(SessionRow.needsYou("npm test\nAnswer in the terminal") == .init(text: "npm test", hint: "Answer in the terminal"))
        // Allowlisted (a request carries the buttons) or a question: nothing to split.
        #expect(SessionRow.needsYou("npm test") == .init(text: "npm test", hint: nil))
        #expect(SessionRow.needsYou("Which database?") == .init(text: "Which database?", hint: nil))
    }
}
