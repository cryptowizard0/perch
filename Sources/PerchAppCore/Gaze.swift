import Combine
import CoreGraphics
import Foundation

/// Where the mascot looks when the pointer comes near (#63): nil while it is farther than `radius` from the mascot's
/// centre or on another screen, else one of five directions. The notch is at the top of the screen, so the pointer
/// can only be beside or below it.
public enum Gaze: Equatable, Sendable, CaseIterable {
    case left, downLeft, down, downRight, right

    public static let radius: CGFloat = 250

    /// `pointer` and `center` in screen coordinates (y up, like `NSEvent.mouseLocation`); `screen` is the frame of the
    /// screen the mascot is on. Each direction covers 45°, centred on its compass point; a pointer level with the
    /// mascot or above it (inside the band) is beside it.
    public init?(pointer: CGPoint, center: CGPoint, screen: CGRect) {
        guard (screen.minX...screen.maxX).contains(pointer.x), (screen.minY...screen.maxY).contains(pointer.y) else { return nil }
        let dx = pointer.x - center.x, dy = pointer.y - center.y
        guard dx * dx + dy * dy <= Self.radius * Self.radius else { return nil }
        guard dx != 0 || dy < 0 else {
            self = .down
            return
        }
        // 0° is right, 90° straight down, 180° left.
        let angle = atan2(max(-dy, 0), dx) * 180 / .pi
        switch angle {
        case ..<22.5: self = .right
        case ..<67.5: self = .downRight
        case ..<112.5: self = .down
        case ..<157.5: self = .downLeft
        default: self = .left
        }
    }
}

/// Pointer moves, from wherever the app gets them (`NSEvent` monitors). Started only while the gaze is wanted.
@MainActor
public protocol PointerMonitor: AnyObject {
    func start(_ moved: @escaping @MainActor (CGPoint) -> Void)
    func stop()
}

/// Turns pointer moves into the mascot's gaze, publishing only when it changes (not on every move). With Reduce Motion
/// on, no monitor is installed at all and the gaze is nil.
@MainActor
public final class GazeTracker: ObservableObject {
    @Published public private(set) var gaze: Gaze?
    /// The mascot's centre and its screen, in screen coordinates; nil while it isn't showing (the notch is expanded).
    public var locate: () -> (center: CGPoint, screen: CGRect)? = { nil }
    public var reduceMotion: Bool {
        didSet { if reduceMotion != oldValue { update() } }
    }
    private let monitor: PointerMonitor
    private var monitoring = false
    private var pointer: CGPoint?

    public init(monitor: PointerMonitor, reduceMotion: Bool) {
        self.monitor = monitor
        self.reduceMotion = reduceMotion
        update()
    }

    /// The mascot moved, appeared or went away (a layout, the notch folding): looks again from the last pointer.
    public func refresh() {
        set(pointer.flatMap(gaze(at:)))
    }

    func pointerMoved(to point: CGPoint) {
        pointer = point
        set(gaze(at: point))
    }

    private func gaze(at point: CGPoint) -> Gaze? {
        guard let spot = locate() else { return nil }
        return Gaze(pointer: point, center: spot.center, screen: spot.screen)
    }

    private func set(_ new: Gaze?) {
        if gaze != new { gaze = new }
    }

    private func update() {
        if reduceMotion {
            if monitoring { monitor.stop() }
            monitoring = false
            pointer = nil
            set(nil)
        } else if !monitoring {
            monitoring = true
            monitor.start { [weak self] in self?.pointerMoved(to: $0) }
        }
    }
}
