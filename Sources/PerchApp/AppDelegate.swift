import AppKit
import PerchAppCore
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = QueueModel()
    private var notchWindow: NotchWindowController?
    private var quickEntry: QuickEntryController?
    private var quickEntryHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let quickEntry = QuickEntryController(queue: queue)
        self.quickEntry = quickEntry
        let hotKey = Self.quickEntryHotKey()
        quickEntryHotKey = GlobalHotKey(hotKey) { [weak quickEntry] in
            DispatchQueue.main.async { MainActor.assumeIsolated { quickEntry?.toggle() } }
        }
        if quickEntryHotKey == nil { NSLog("Perch: could not register quick entry shortcut \(hotKey); is it taken?") }

        let controller = NotchWindowController(notch: NotchModel(), queue: queue, menu: NotchMenu(
            quickEntryShortcut: hotKey.description,
            quickEntry: { [weak quickEntry] in quickEntry?.open() },
            quit: { NSApp.terminate(nil) }
        ))
        controller.show()
        notchWindow = controller
        queue.connect()
    }

    /// ⌥⇧Space unless overridden: `defaults write dev.perch.app QuickEntryHotKey "ctrl+opt+n"`.
    static func quickEntryHotKey() -> HotKey {
        guard let text = UserDefaults.standard.string(forKey: "QuickEntryHotKey") else { return .quickEntryDefault }
        guard let hotKey = HotKey(text) else {
            NSLog("Perch: ignoring QuickEntryHotKey '\(text)'; use e.g. opt+shift+space")
            return .quickEntryDefault
        }
        return hotKey
    }
}
