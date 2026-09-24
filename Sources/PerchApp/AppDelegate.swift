import AppKit
import PerchAppCore
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = QueueModel()
    private var notchWindow: NotchWindowController?
    private var quickEntry: QuickEntryController?
    private var quickEntryHotKey: GlobalHotKey?
    private let notifier = Notifier()

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
        queue.onDue = { [notifier] item in notifier.due(item) }
        if ProcessInfo.processInfo.environment["PERCH_LATENCY_LOG"] == "1" { logLatency() }
        queue.connect()
    }

    /// For scripts/measure-latency.sh: one stderr line per event once the UI has had its turn to update
    /// (the next main-queue pass after the model changed, i.e. after SwiftUI's layout for that change).
    private func logLatency() {
        queue.onApply = { update in
            guard case .event(let event) = update else { return }
            DispatchQueue.main.async {
                let ms = Int((Date().timeIntervalSince1970 * 1000).rounded())
                FileHandle.standardError.write(Data("perch-latency \(event.item.id) \(ms)\n".utf8))
            }
        }
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
