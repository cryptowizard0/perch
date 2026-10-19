import Foundation
import PerchAppCore
import Testing

/// When a bow or scratch plays (#62).
@Suite struct AnswerReactionTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func allowBowsDenyScratchesAnythingElseBows() {
        #expect(Mascot.Answer(response: "allow") == .bow)
        #expect(Mascot.Answer(response: "deny") == .scratch)
        #expect(Mascot.Answer(response: "always") == .bow)
    }

    @Test func aHotkeyAnswerPlaysAtOnce() {
        var state = AnswerReactions()
        #expect(state.answered("allow", at: t0, expanded: false) == .bow)
        #expect(state.answered("deny", at: t0, expanded: false) == .scratch)
        // Nothing left for a later fold.
        #expect(state.folded(at: t0.addingTimeInterval(1)) == nil)
    }

    @Test func aPanelAnswerPlaysWhenTheNotchFoldsWithinFiveSeconds() {
        for (delay, plays) in [(0.0, true), (2, true), (5, true), (5.01, false), (60, false)] {
            var state = AnswerReactions()
            #expect(state.answered("deny", at: t0, expanded: true) == nil)
            #expect(state.folded(at: t0.addingTimeInterval(delay)) == (plays ? .scratch : nil), "\(delay)")
            // Fold, expand, fold again: no replay.
            #expect(state.folded(at: t0.addingTimeInterval(delay + 1)) == nil, "\(delay)")
        }
    }

    @Test func onlyTheLatestAnswerCounts() {
        var state = AnswerReactions()
        _ = state.answered("allow", at: t0, expanded: true)
        _ = state.answered("deny", at: t0.addingTimeInterval(3), expanded: true)
        #expect(state.folded(at: t0.addingTimeInterval(7)) == .scratch)

        // A later hotkey answer wins over one waiting in the panel.
        var hotkey = AnswerReactions()
        _ = hotkey.answered("deny", at: t0, expanded: true)
        #expect(hotkey.answered("allow", at: t0.addingTimeInterval(1), expanded: false) == .bow)
        #expect(hotkey.folded(at: t0.addingTimeInterval(2)) == nil)
    }
}
