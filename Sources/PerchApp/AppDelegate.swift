import AppKit
import Combine
import PerchAppCore
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = QueueModel()
    private var notchWindow: NotchWindowController?
    private var quickEntry: QuickEntryController?
    private var quickEntryHotKey: GlobalHotKey?
    /// ⌥⇧A / ⌥⇧D exist only while the panel shows a request, ⌥⇧O while a session needs you,
    /// so the rest of the time those keys type Å / Î / Ø as usual.
    private var approveHotKey: GlobalHotKey?
    private var denyHotKey: GlobalHotKey?
    private var jumpHotKey: GlobalHotKey?
    private var queueWatch: AnyCancellable?
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
        queueWatch = queue.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateQueueHotKeys() } }
        }
        queue.connect()
    }

    private func updateQueueHotKeys() {
        let pending = queue.headRequest != nil
        if pending && approveHotKey == nil {
            approveHotKey = GlobalHotKey(.approve) { [weak self] in self?.answerHead("allow") }
            denyHotKey = GlobalHotKey(.deny) { [weak self] in self?.answerHead("deny") }
        } else if !pending && approveHotKey != nil {
            approveHotKey = nil
            denyHotKey = nil
        }
        let any = queue.headSession != nil
        if any && jumpHotKey == nil {
            jumpHotKey = GlobalHotKey(.jump) { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { Jumper.jump(self?.queue.headSession?.link) } }
            }
        } else if !any {
            jumpHotKey = nil
        }
    }

    private func answerHead(_ value: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let head = self.queue.headRequest, head.options?.contains(value) ?? false else { return }
                self.queue.respond(head, value)
            }
        }
    }

    /// For scripts/measure-latency.sh: one stderr line per event once the UI has had its turn to update
    /// (the next main-queue pass after the model changed, i.e. after SwiftUI's layout for that change).
    private func logLatency() {
        queue.onApply = { update in
            let id: String
            switch update {
            case .event(let event): id = event.item.id
            case .session(let event): id = event.session.id
            default: return
            }
            DispatchQueue.main.async {
                let ms = Int((Date().timeIntervalSince1970 * 1000).rounded())
                FileHandle.standardError.write(Data("perch-latency \(id) \(ms)\n".utf8))
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
