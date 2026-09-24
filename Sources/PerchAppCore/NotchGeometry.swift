import CoreGraphics

/// Where the notch panel goes on one screen. Pure: built from `NSScreen` values so it can be tested.
///
/// With a notch, the collapsed panel is the notch itself plus a "wing" on each side, flush with the top
/// edge; the expanded panel drops down from the same top edge. Without a notch it is a small capsule
/// centred in the menu bar.
public struct NotchGeometry: Equatable, Sendable {
    public var screenFrame: CGRect
    /// The camera housing in screen coordinates; nil on screens without a notch.
    public var notch: CGRect?
    public var menuBarHeight: CGFloat

    public static let capsuleHeight: CGFloat = 22
    static let fallbackMenuBarHeight: CGFloat = 24

    public init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?) {
        self.screenFrame = screenFrame
        let menuBar = screenFrame.maxY - visibleFrame.maxY
        // The menu bar may be hidden (full screen, auto-hide): visibleFrame then reaches the top.
        menuBarHeight = menuBar > 0 ? menuBar : Self.fallbackMenuBarHeight
        if safeAreaTop > 0, let left = auxiliaryTopLeft, let right = auxiliaryTopRight, right.minX > left.maxX {
            notch = CGRect(x: left.maxX, y: screenFrame.maxY - safeAreaTop, width: right.minX - left.maxX, height: safeAreaTop)
        } else {
            notch = nil
        }
    }

    public var hasNotch: Bool { notch != nil }

    /// Height of the band the collapsed panel occupies; expanded content starts below it.
    public var bandHeight: CGFloat { notch?.height ?? Self.capsuleHeight }

    /// Top edge of the panel: the screen's top with a notch, a centred capsule inside the menu bar without.
    var top: CGFloat {
        guard notch == nil else { return screenFrame.maxY }
        return screenFrame.maxY - max(0, (menuBarHeight - Self.capsuleHeight) / 2).rounded(.down)
    }

    var centerX: CGFloat { notch?.midX ?? screenFrame.midX }

    /// Collapsed: the notch plus `leftWing` / `rightWing` points on either side (the capsule is just the wings).
    public func collapsedFrame(leftWing: CGFloat, rightWing: CGFloat) -> CGRect {
        let middle = notch?.width ?? 0
        let x = centerX - middle / 2 - leftWing
        return clamped(CGRect(x: x, y: top - bandHeight, width: leftWing + middle + rightWing, height: bandHeight))
    }

    /// Expanded: `size` hanging from the same top edge, centred under the notch, kept on screen.
    public func expandedFrame(size: CGSize) -> CGRect {
        let width = max(size.width, notch.map { $0.width + 40 } ?? 0)
        return clamped(CGRect(x: centerX - width / 2, y: top - size.height, width: width, height: size.height))
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        var r = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
        r.size.width = min(r.width, screenFrame.width)
        r.origin.x = min(max(r.minX, screenFrame.minX), screenFrame.maxX - r.width)
        return r
    }
}
