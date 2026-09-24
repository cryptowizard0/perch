import CoreGraphics
import Testing
@testable import PerchAppCore

@Suite struct NotchGeometryTests {
    /// Measured on a 14" MacBook Pro (1710 × 1107 pt): notch 185 × 33 at x 763.
    let macbook = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1107),
        visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1068),
        safeAreaTop: 33,
        auxiliaryTopLeft: CGRect(x: 0, y: 1074, width: 763, height: 33),
        auxiliaryTopRight: CGRect(x: 948, y: 1074, width: 762, height: 33)
    )

    /// An external 1920 × 1080 display to the right of the laptop, 25 pt menu bar.
    let external = NotchGeometry(
        screenFrame: CGRect(x: 1710, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1710, y: 0, width: 1920, height: 1055),
        safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil
    )

    @Test func findsTheNotch() {
        #expect(macbook.notch == CGRect(x: 763, y: 1074, width: 185, height: 33))
        #expect(macbook.hasNotch)
        #expect(macbook.bandHeight == 33)
        #expect(external.notch == nil)
    }

    @Test func collapsedHugsTheNotch() {
        let frame = macbook.collapsedFrame(leftWing: 40, rightWing: 50)
        #expect(frame == CGRect(x: 723, y: 1074, width: 275, height: 33))
    }

    @Test func noNotchIsACapsuleCentredInTheMenuBar() {
        let frame = external.collapsedFrame(leftWing: 40, rightWing: 40)
        #expect(frame.width == 80)
        #expect(frame.midX == CGFloat(1710 + 960))
        #expect(frame.height == NotchGeometry.capsuleHeight)
        #expect(frame.maxY == CGFloat(1080 - 1))  // (25 - 22) / 2 rounded down
    }

    @Test func expandedHangsFromTheTopUnderTheNotch() {
        let frame = macbook.expandedFrame(size: CGSize(width: 440, height: 300))
        #expect(frame.maxY == 1107)
        #expect(abs(frame.midX - macbook.notch!.midX) <= 0.5)
        #expect(frame.size == CGSize(width: 440, height: 300))
        // Never narrower than the notch it hangs from.
        #expect(macbook.expandedFrame(size: CGSize(width: 100, height: 50)).width == 225)
    }

    @Test func staysOnScreen() {
        let small = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
                                  visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 600),
                                  safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(small.menuBarHeight == 24)  // hidden menu bar falls back to the default height
        let frame = small.expandedFrame(size: CGSize(width: 440, height: 200))
        #expect(frame.minX == 0 && frame.width == 300)
    }
}
