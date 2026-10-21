import CoreGraphics

/// How the notch opens and closes, so the panel never just pops out. Opening, the window takes the expanded frame first
/// (the band still drawn where it was), then the black shape grows out of the band to the panel's size, uncovering the
/// content as it fades in. Closing is the same backwards, and the window goes back to the band only once the shape is
/// back on it. While open, the shape follows the panel's height (rows come and go); the window grows at once but keeps
/// the taller height until a shrinking shape has finished. Under Reduce Motion nothing animates and nothing waits.
///
/// The controller calls `update` on every layout, animates what the returned step says, and calls `settle` once that
/// animation is over (for the step's `duration`) whenever `settling`.
public struct NotchMotion: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// The window is the band.
        case collapsed
        /// Drawn open (or opening).
        case open
        /// Shrinking back onto the band inside the expanded window.
        case closing
    }

    public enum Step: Equatable, Sendable {
        case none
        /// Draw open. `fromBand`: the window was the band until now, so it has to take the expanded frame before the
        /// shape starts to grow; otherwise (a close undone halfway) the shape just turns round.
        case open(fromBand: Bool)
        case close
        /// The open panel's height changed.
        case resize
    }

    public static let openDuration = 0.4
    public static let closeDuration = 0.26
    public static let resizeDuration = 0.25

    public private(set) var phase = Phase.collapsed
    /// The open panel's height as drawn (band included).
    public private(set) var height: CGFloat = 0
    /// The window's height while the drawn panel is shorter than it (shortening, closing).
    private var held: CGFloat?

    public init() {}

    /// The window's height: nil for the band's frame, else the expanded frame this tall.
    public var windowHeight: CGFloat? {
        phase == .collapsed ? nil : max(height, held ?? 0)
    }

    /// Something is still animating and `settle` should follow.
    public var settling: Bool { phase == .closing || held != nil }

    /// The notch is now `expanded` with a panel `height` tall (ignored when collapsed).
    public mutating func update(expanded: Bool, height: CGFloat, reduceMotion: Bool) -> Step {
        if expanded {
            if phase != .open {
                let fromBand = phase == .collapsed
                let window = windowHeight ?? 0
                phase = .open
                self.height = height
                held = !reduceMotion && window > height ? window : nil
                return .open(fromBand: fromBand)
            }
            guard height != self.height else { return .none }
            if reduceMotion {
                held = nil
            } else if height < self.height {
                held = max(held ?? 0, self.height)
            } else if let held, height >= held {
                self.held = nil
            }
            self.height = height
            return .resize
        }
        guard phase == .open else { return .none }
        if reduceMotion {
            phase = .collapsed
            held = nil
        } else {
            phase = .closing
        }
        return .close
    }

    /// The last step's animation is over: a closing shape is on the band, a shortening one at its height.
    public mutating func settle() {
        if phase == .closing { phase = .collapsed }
        held = nil
    }
}

extension NotchMotion.Step {
    /// How long the step's animation runs, before `settle`.
    public var duration: Double {
        switch self {
        case .none: return 0
        case .open: return NotchMotion.openDuration
        case .close: return NotchMotion.closeDuration
        case .resize: return NotchMotion.resizeDuration
        }
    }
}
