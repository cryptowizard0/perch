import AppKit
import PerchAppCore

/// Pointer moves anywhere on screen, for the mascot's gaze (#63): a global monitor for other apps' windows (it needs no
/// Accessibility permission, checked on macOS 15, see #58) and a local one for Perch's own.
@MainActor
final class AppKitPointerMonitor: PointerMonitor {
    private var monitors: [Any] = []

    func start(_ moved: @escaping @MainActor (CGPoint) -> Void) {
        stop()
        let report = { MainActor.assumeIsolated { moved(NSEvent.mouseLocation) } }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in report() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            report()
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
