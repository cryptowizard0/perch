import AppKit
import PerchAppCore
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = QueueModel()
    private var notchWindow: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchWindowController(notch: NotchModel(), queue: queue)
        controller.show()
        notchWindow = controller
        queue.connect()
    }
}
