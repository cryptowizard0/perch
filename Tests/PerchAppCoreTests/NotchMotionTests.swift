import CoreGraphics
import PerchAppCore
import Testing

/// The notch opening and closing as an animation, not a jump: which frame the window has while the shape moves.
@Suite struct NotchMotionTests {
    @Test func opensFromTheBandAfterTheWindowHasGrown() {
        var motion = NotchMotion()
        #expect(motion.windowHeight == nil)
        #expect(motion.update(expanded: true, height: 300, reduceMotion: false) == .open(fromBand: true))
        #expect(motion.phase == .open)
        #expect(motion.windowHeight == 300)
        #expect(!motion.settling)
        // Later layouts with nothing new do nothing.
        #expect(motion.update(expanded: true, height: 300, reduceMotion: false) == .none)
    }

    @Test func closingKeepsTheExpandedWindowUntilTheShapeIsBack() {
        var motion = NotchMotion()
        _ = motion.update(expanded: true, height: 300, reduceMotion: false)
        #expect(motion.update(expanded: false, height: 0, reduceMotion: false) == .close)
        #expect(motion.phase == .closing)
        #expect(motion.windowHeight == 300)
        #expect(motion.settling)
        #expect(motion.update(expanded: false, height: 0, reduceMotion: false) == .none)
        motion.settle()
        #expect(motion.phase == .collapsed)
        #expect(motion.windowHeight == nil)
        #expect(!motion.settling)
    }

    @Test func aCloseUndoneHalfwayTurnsRound() {
        var motion = NotchMotion()
        _ = motion.update(expanded: true, height: 300, reduceMotion: false)
        _ = motion.update(expanded: false, height: 0, reduceMotion: false)
        #expect(motion.update(expanded: true, height: 300, reduceMotion: false) == .open(fromBand: false))
        #expect(motion.phase == .open)
        // The close's settle, if it still came, would not fold it.
        motion.settle()
        #expect(motion.phase == .open)
        #expect(motion.windowHeight == 300)
    }

    @Test func reopeningShorterHoldsTheWindowUntilTheShapeHasShrunk() {
        var motion = NotchMotion()
        _ = motion.update(expanded: true, height: 300, reduceMotion: false)
        _ = motion.update(expanded: false, height: 0, reduceMotion: false)
        #expect(motion.update(expanded: true, height: 200, reduceMotion: false) == .open(fromBand: false))
        #expect(motion.windowHeight == 300)
        #expect(motion.settling)
        motion.settle()
        #expect(motion.windowHeight == 200)
    }

    @Test func growsTheWindowAtOnceButShrinksItAfterTheShape() {
        var motion = NotchMotion()
        _ = motion.update(expanded: true, height: 300, reduceMotion: false)
        #expect(motion.update(expanded: true, height: 400, reduceMotion: false) == .resize)
        #expect(motion.height == 400)
        #expect(motion.windowHeight == 400)
        #expect(!motion.settling)
        #expect(motion.update(expanded: true, height: 250, reduceMotion: false) == .resize)
        #expect(motion.height == 250)
        #expect(motion.windowHeight == 400)
        #expect(motion.settling)
        // Shrinking again before it settled: still the tallest.
        _ = motion.update(expanded: true, height: 200, reduceMotion: false)
        #expect(motion.windowHeight == 400)
        motion.settle()
        #expect(motion.windowHeight == 200)
    }

    @Test func growingPastTheHeldHeightLetsGo() {
        var motion = NotchMotion()
        _ = motion.update(expanded: true, height: 300, reduceMotion: false)
        _ = motion.update(expanded: true, height: 200, reduceMotion: false)
        _ = motion.update(expanded: true, height: 350, reduceMotion: false)
        #expect(motion.windowHeight == 350)
        #expect(!motion.settling)
    }

    @Test func reduceMotionNeverWaits() {
        var motion = NotchMotion()
        #expect(motion.update(expanded: true, height: 300, reduceMotion: true) == .open(fromBand: true))
        _ = motion.update(expanded: true, height: 200, reduceMotion: true)
        #expect(motion.windowHeight == 200)
        #expect(!motion.settling)
        #expect(motion.update(expanded: false, height: 0, reduceMotion: true) == .close)
        #expect(motion.phase == .collapsed)
        #expect(motion.windowHeight == nil)
        #expect(!motion.settling)
    }

    @Test func collapsedAndNotExpandingDoesNothing() {
        var motion = NotchMotion()
        #expect(motion.update(expanded: false, height: 0, reduceMotion: false) == .none)
        #expect(motion.phase == .collapsed)
    }
}
