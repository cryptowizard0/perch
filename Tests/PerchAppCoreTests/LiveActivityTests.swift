import Foundation
import Testing
@testable import PerchAppCore

@Suite struct LiveActivityTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func hiddenWhenNothingRuns() {
        #expect(LiveActivity(sessionStarts: []).text(now: now) == nil)
    }

    @Test func countAndLongestRunning() {
        let two = LiveActivity(sessionStarts: [now.addingTimeInterval(-60), now.addingTimeInterval(-245)])
        #expect(two.text(now: now) == "2 agents · 4m")
        #expect(LiveActivity(sessionStarts: [now.addingTimeInterval(-30)]).text(now: now) == "1 agent · 30s")
    }

    @Test func durations() {
        #expect(RelativeTime.duration(-5) == "0s")
        #expect(RelativeTime.duration(59) == "59s")
        #expect(RelativeTime.duration(60) == "1m")
        #expect(RelativeTime.duration(3600) == "1h")
        #expect(RelativeTime.duration(3600 + 25 * 60) == "1h25m")
        #expect(RelativeTime.duration(11 * 3600 + 60) == "11h")
        #expect(RelativeTime.duration(3 * 86_400 + 5) == "3d")
    }
}
