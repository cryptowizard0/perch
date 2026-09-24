import AppKit
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindow: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchWindowController(notch: NotchModel())
        controller.show()
        notchWindow = controller
    }
}
