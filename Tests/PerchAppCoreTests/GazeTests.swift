import CoreGraphics
import PerchAppCore
import Testing

/// Where the mascot looks (#63).
@Suite struct GazeTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// The mascot on the left wing, just under the top edge.
    let center = CGPoint(x: 600, y: 966)

    func gaze(_ dx: CGFloat, _ dy: CGFloat) -> Gaze? {
        Gaze(pointer: CGPoint(x: center.x + dx, y: center.y + dy), center: center, screen: screen)
    }

    /// Below and to the side at `degrees` (0 right, 90 down, 180 left), `distance` away.
    func gaze(at degrees: Double, _ distance: CGFloat = 100) -> Gaze? {
        let r = degrees * .pi / 180
        return gaze(distance * CGFloat(cos(r)), -distance * CGFloat(sin(r)))
    }

    @Test func onlyWithin250Points() {
        #expect(gaze(0, -249) == .down)
        #expect(gaze(0, -250) == .down)
        #expect(gaze(0, -250.5) == nil)
        #expect(gaze(250, 0) == .right && gaze(251, 0) == nil)
        #expect(gaze(-176, -176) == .downLeft && gaze(-177, -177) == nil)
        #expect(gaze(900, -600) == nil)
    }

    @Test func fiveDirectionsOf45Degrees() {
        let table: [(Double, Gaze)] = [
            (0, .right), (22.4, .right), (22.6, .downRight), (45, .downRight), (67.4, .downRight),
            (67.6, .down), (90, .down), (112.4, .down), (112.6, .downLeft), (135, .downLeft),
            (157.4, .downLeft), (157.6, .left), (180, .left),
        ]
        for (degrees, expected) in table {
            #expect(gaze(at: degrees) == expected, "\(degrees)°")
        }
    }

    /// The band is a few points tall: a pointer level with the mascot or above it is beside it, never "up".
    @Test func aboveIsBeside() {
        #expect(gaze(40, 10) == .right)
        #expect(gaze(-40, 10) == .left)
        #expect(gaze(0, 10) == .down)
        #expect(gaze(0, 0) == .down)
    }

    @Test func anotherScreenIsAway() {
        // Just over the top edge onto a screen above, or past the side onto the next one.
        #expect(gaze(0, 20) == nil)
        let leftEdge = CGPoint(x: 100, y: 966)
        #expect(Gaze(pointer: CGPoint(x: -1, y: 900), center: leftEdge, screen: screen) == nil)
        #expect(Gaze(pointer: CGPoint(x: 0, y: 900), center: leftEdge, screen: screen) == .downLeft)
    }
}

@MainActor
final class FakePointer: PointerMonitor {
    var moved: (@MainActor (CGPoint) -> Void)?
    var starts = 0, stops = 0

    func start(_ moved: @escaping @MainActor (CGPoint) -> Void) {
        starts += 1
        self.moved = moved
    }

    func stop() {
        stops += 1
        moved = nil
    }
}

@MainActor
@Suite struct GazeTrackerTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func tracker(_ pointer: FakePointer, reduceMotion: Bool = false) -> GazeTracker {
        let tracker = GazeTracker(monitor: pointer, reduceMotion: reduceMotion)
        tracker.locate = { [screen] in (CGPoint(x: 600, y: 966), screen) }
        return tracker
    }

    @Test func publishesOnlyWhenTheGazeChanges() {
        let pointer = FakePointer()
        let tracker = tracker(pointer)
        var published: [Gaze?] = []
        let sink = tracker.$gaze.dropFirst().sink { published.append($0) }
        defer { sink.cancel() }
        for y in stride(from: 700.0, to: 760, by: 5) { pointer.moved?(CGPoint(x: 600, y: y)) }
        for x in stride(from: 600.0, to: 640, by: 5) { pointer.moved?(CGPoint(x: x, y: 800)) }
        pointer.moved?(CGPoint(x: 1400, y: 300))
        pointer.moved?(CGPoint(x: 1300, y: 300))
        #expect(published == [.down, nil])
    }

    @Test func reduceMotionInstallsNoMonitor() {
        let pointer = FakePointer()
        let tracker = tracker(pointer, reduceMotion: true)
        #expect(pointer.starts == 0 && pointer.moved == nil && tracker.gaze == nil)
        tracker.reduceMotion = false
        #expect(pointer.starts == 1)
        pointer.moved?(CGPoint(x: 600, y: 800))
        #expect(tracker.gaze == .down)
        // Turned on while looking: the monitor goes and the eye comes back.
        tracker.reduceMotion = true
        #expect(pointer.stops == 1 && pointer.moved == nil && tracker.gaze == nil)
    }

    /// The notch expanding hides the mascot: no gaze; folding looks again from where the pointer last was.
    @Test func noGazeWhileTheMascotIsHidden() {
        let pointer = FakePointer()
        let tracker = tracker(pointer)
        pointer.moved?(CGPoint(x: 700, y: 900))
        #expect(tracker.gaze == .downRight)
        tracker.locate = { nil }
        tracker.refresh()
        #expect(tracker.gaze == nil)
        tracker.locate = { [screen] in (CGPoint(x: 600, y: 966), screen) }
        tracker.refresh()
        #expect(tracker.gaze == .downRight)
    }
}
