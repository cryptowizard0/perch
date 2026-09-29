import AppKit
import Combine
import PerchAppCore
import PerchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = QueueModel()
    private var notchWindow: NotchWindowController?
    /// ⌥⇧A / ⌥⇧D exist only while the panel shows a request, ⌥⇧O while a session needs you,
    /// so the rest of the time those keys type Å / Î / Ø as usual.
    private var approveHotKey: GlobalHotKey?
    private var denyHotKey: GlobalHotKey?
    private var jumpHotKey: GlobalHotKey?
    private var queueWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        queue.jump = { Jumper.jump($0) }
        let controller = NotchWindowController(notch: NotchModel(), queue: queue, menu: NotchMenu(
            quit: { NSApp.terminate(nil) }
        ))
        controller.show()
        notchWindow = controller
        if ProcessInfo.processInfo.environment["PERCH_LATENCY_LOG"] == "1" { logLatency() }
        queueWatch = queue.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateQueueHotKeys() } }
        }
        queue.connect()
    }

    private func updateQueueHotKeys() {
        let pending = queue.headRequest != nil
        if pending && approveHotKey == nil {
            approveHotKey = GlobalHotKey(.approve) { [weak self] in self?.onMain { $0.answerHead("allow") } }
            denyHotKey = GlobalHotKey(.deny) { [weak self] in self?.onMain { $0.answerHead("deny") } }
        } else if !pending && approveHotKey != nil {
            approveHotKey = nil
            denyHotKey = nil
        }
        let any = queue.headSession != nil
        if any && jumpHotKey == nil {
            jumpHotKey = GlobalHotKey(.jump) { [weak self] in self?.onMain { $0.openHead() } }
        } else if !any {
            jumpHotKey = nil
        }
    }

    /// Hot keys fire from Carbon's handler; act on the model on the next main-queue pass.
    private func onMain(_ action: @escaping @MainActor (QueueModel) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { action(self.queue) }
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
}
