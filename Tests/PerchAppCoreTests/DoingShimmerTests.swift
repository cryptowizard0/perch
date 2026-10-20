import Foundation
import PerchAppCore
import Testing

/// The light sweeping across Doing rows (#86): where it is at a given time.
@Suite struct DoingShimmerTests {
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func sweepsLeftToRightOncePerPeriod() {
        let start = 1_000 * DoingShimmer.period
        #expect(close(DoingShimmer.center(at: start), DoingShimmer.from))
        #expect(close(DoingShimmer.center(at: start + DoingShimmer.period / 2), (DoingShimmer.from + DoingShimmer.to) / 2))
        #expect(close(DoingShimmer.center(at: start + DoingShimmer.period), DoingShimmer.from))
        var last = -Double.infinity
        for step in 0..<30 {
            let center = DoingShimmer.center(at: start + Double(step) / 30 * DoingShimmer.period)
            #expect(center > last)
            last = center
        }
    }

    @Test func theBandIsOffTheRowWhenItWrapsAround() {
        // So the jump back to the left is never seen.
        #expect(DoingShimmer.from + DoingShimmer.band / 2 <= 0)
        #expect(DoingShimmer.to - DoingShimmer.band / 2 >= 1)
    }

    @Test func dependsOnlyOnTheClockSoRowsSweepTogether() {
        #expect(close(DoingShimmer.center(at: 12.25), DoingShimmer.center(at: 12.25 + 7 * DoingShimmer.period)))
        #expect(close(DoingShimmer.center(at: -0.5), DoingShimmer.center(at: DoingShimmer.period - 0.5)))
    }
}
