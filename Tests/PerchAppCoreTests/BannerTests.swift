import Foundation
import PerchAppCore
import PerchCore
import Testing

/// The collapsed notch's event banner: what it says, which one wins, when it goes away, how long it stays.
@Suite struct BannerTests {
    func session(_ id: String, _ status: SessionStatus, source: String = "claude-code", detail: String? = nil,
                 error: String? = nil, lastMessage: String? = nil) -> Session {
        var s = Session(id: id, source: source, title: "proj-\(id)", startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        s.status = status
        s.detail = detail
        s.error = error
        s.lastMessage = lastMessage
        return s
    }

    @Test func aPulseShowsTheProjectAndOneLine() {
        var state = BannerState()
        let waiting = session("a", .waiting, detail: "npm test\n" + HookAdapter.answerInTerminal)
        let changed1 = state.update(id: "a", from: session("a", .running), to: waiting)
        #expect(changed1)
        #expect(state.current?.title == "proj-a")
        #expect(state.current?.status == .waiting)
        #expect(state.current?.text == "npm test")

        var failed = BannerState()
        failed.update(id: "b", from: session("b", .running), to: session("b", .failed, error: "rate_limit"))
        #expect(failed.current?.text == "rate_limit")
    }

    @Test func theTextIsTheFirstNonEmptyLineOrTheLabel() {
        var state = BannerState()
        state.update(id: "a", from: nil, to: session("a", .done, lastMessage: "\n  Pushed PR #42  \nDetails…"))
        #expect(state.current?.text == "Pushed PR #42")
        state.update(id: "b", from: nil, to: session("b", .failed))
        #expect(state.current?.text == "Failed")
        state.update(id: "c", from: nil, to: session("c", .waiting))
        #expect(state.current?.text == HookAdapter.waitingForAnswer)
    }

    /// Only what pulses the notch: never running or idle, never the same state again, never hidden sources.
    @Test func onlyPulsesShowABanner() {
        var state = BannerState()
        let changed2 = state.update(id: "a", from: nil, to: session("a", .running))
        #expect(!changed2)
        let changed3 = state.update(id: "a", from: session("a", .running), to: session("a", .idle))
        #expect(!changed3)
        let changed4 = state.update(id: "h", from: nil, to: session("h", .done, source: "hermes"))
        #expect(!changed4)
        #expect(state.current == nil)
        state.update(id: "a", from: session("a", .running), to: session("a", .done, lastMessage: "one"))
        let first = state.current
        let changed5 = state.update(id: "a", from: session("a", .done), to: session("a", .done, lastMessage: "two"))
        #expect(!changed5)
        #expect(state.current == first)
    }

    /// A finish never covers a command waiting for you; the same or more urgent replaces.
    @Test func aLessUrgentBannerNeverCoversAMoreUrgentOne() {
        var state = BannerState()
        state.update(id: "a", from: session("a", .running), to: session("a", .waiting, detail: "rm -rf build"))
        let changed6 = state.update(id: "b", from: session("b", .running), to: session("b", .done))
        #expect(!changed6)
        let changed7 = state.update(id: "c", from: session("c", .running), to: session("c", .failed))
        #expect(!changed7)
        #expect(state.current?.sessionID == "a")
        let changed8 = state.update(id: "d", from: session("d", .running), to: session("d", .waiting, detail: "git push"))
        #expect(changed8)
        #expect(state.current?.sessionID == "d")

        var done = BannerState()
        done.update(id: "a", from: session("a", .running), to: session("a", .done))
        let changed9 = done.update(id: "b", from: session("b", .running), to: session("b", .done))
        #expect(changed9)
        #expect(done.current?.sessionID == "b")
        let changed10 = done.update(id: "c", from: session("c", .running), to: session("c", .failed))
        #expect(changed10)
        #expect(done.current?.sessionID == "c")
    }

    /// Its own session moving on (answered, removed) ends it; it may move on to a less urgent banner of its own.
    @Test func itGoesWhenItsSessionMovesOn() {
        var state = BannerState()
        state.update(id: "a", from: session("a", .running), to: session("a", .waiting))
        let changed11 = state.update(id: "b", from: session("b", .waiting), to: session("b", .running))
        #expect(!changed11)
        #expect(state.current != nil)
        let changed12 = state.update(id: "a", from: session("a", .waiting), to: session("a", .running))
        #expect(changed12)
        #expect(state.current == nil)

        state.update(id: "a", from: session("a", .running), to: session("a", .waiting))
        let changed13 = state.update(id: "a", from: session("a", .waiting), to: nil)
        #expect(changed13)
        #expect(state.current == nil)

        state.update(id: "a", from: session("a", .running), to: session("a", .waiting))
        let changed14 = state.update(id: "a", from: session("a", .waiting), to: session("a", .done))
        #expect(changed14)
        #expect(state.current?.status == .done)
    }

    @Test func onlyItsOwnTimerDismissesIt() {
        var state = BannerState()
        state.update(id: "a", from: nil, to: session("a", .done))
        let old = state.current!.id
        state.update(id: "a", from: session("a", .done), to: session("a", .running))
        state.update(id: "a", from: session("a", .running), to: session("a", .done))
        #expect(state.current!.id != old)
        let changed15 = state.dismiss(old)
        #expect(!changed15)
        #expect(state.current != nil)
        let changed16 = state.dismiss(state.current!.id)
        #expect(changed16)
        #expect(state.current == nil)
    }

    @Test func aLineThatFitsStaysFourSecondsALongOneScrollsOnce() {
        #expect(Banner.duration(contentWidth: 80) == Banner.minDuration)
        #expect(Banner.duration(contentWidth: Banner.maxContentWidth) == Banner.minDuration)
        let long = Banner.maxContentWidth + 200
        #expect(Banner.overflow(contentWidth: long) == 200)
        #expect(Banner.duration(contentWidth: long) == Banner.scrollDelay + 200 / Banner.scrollSpeed + Banner.endHold)
        #expect(Banner.duration(contentWidth: 10_000) == Banner.maxDuration)
        #expect(Banner.wing(contentWidth: 80) == 100)
        // The Done run's mascot stands at its end (#64).
        #expect(Banner.wing(contentWidth: 80, carried: true) == 100 + Double(Mascot.width))
        #expect(Banner.wing(contentWidth: 10_000) == Banner.maxContentWidth + 2 * Banner.inset)
    }
}
