import AppKit
import Combine
import PerchAppCore
import PerchClient
import PerchCore
import PerchSetup

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let queue = QueueModel()
    private let setup = SetupModel()
    private var notchWindow: NotchWindowController?
    private var todoPopup: TodoPopupController?
    /// ⌥⇧Space (or `QuickEntryHotKey`): the todo popup, from anywhere.
    private var popupHotKey: GlobalHotKey?
    /// ⌥⇧A / ⌥⇧D exist only while the panel shows a request, ⌥⇧O while a session needs you,
    /// so the rest of the time those keys type Å / Î / Ø as usual.
    private var approveHotKey: GlobalHotKey?
    private var denyHotKey: GlobalHotKey?
    private var jumpHotKey: GlobalHotKey?
    private var queueWatch: AnyCancellable?
    private let chimePlayer = ChimePlayer()
    private var chimesWatch: AnyCancellable?
    private var displayWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        queue.jump = { Jumper.jump($0) }
        queue.chimes = ChimeSettings(defaults: .standard)
        queue.onChime = { [weak self] sound in
            guard let self else { return }
            chimePlayer.play(sound, volume: queue.chimes.volume)
        }
        queue.measureBanner = { BannerView.contentWidth($0) }
        chimesWatch = queue.$chimes.dropFirst().sink { $0.save(to: .standard) }
        let notch = NotchModel()
        notch.display = DisplayChoice(defaults: .standard)
        displayWatch = notch.$display.dropFirst().sink { $0.save(to: .standard) }
        let controller = NotchWindowController(notch: notch, queue: queue, setup: setup, menu: NotchMenu(
            uninstall: { [weak self] in self?.confirmUninstall() },
            quit: { NSApp.terminate(nil) }
        ))
        controller.show()
        notchWindow = controller
        let popup = TodoPopupController(queue: queue, notchWindow: controller)
        todoPopup = popup
        let (hotKey, problem) = HotKey.quickEntry(UserDefaults.standard.string(forKey: HotKey.quickEntryDefaultsKey))
        if let problem { NSLog("Perch: \(problem)") }
        popupHotKey = GlobalHotKey(hotKey) { [weak popup] in
            DispatchQueue.main.async { MainActor.assumeIsolated { popup?.toggle() } }
        }
        if popupHotKey == nil { NSLog("Perch: could not register the todo shortcut \(hotKey); is it taken?") }
        // The self-check (binaries, perchd, hook repairs) and, on a first run, the setup card.
        queue.onSession = { [weak self] event in self?.setup.observe(event) }
        setup.onCardAppeared = { [weak notch] in notch?.open() }
        setup.start()
        if ProcessInfo.processInfo.environment["PERCH_LATENCY_LOG"] == "1" { logLatency() }
        queueWatch = queue.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateQueueHotKeys() } }
        }
        // The perchd the self-check installs: ~/.perch, or under $HOME / $PERCH_HOME when they are overridden. The app
        // offers itself as the Reminders bridge (#51): "Perch Dev" for isolated runs, so they never touch real todos.
        let reminders = RemindersBridge(store: EventKitRemindersStore(), listName: RemindersBridge.listName())
        queue.connect(client: PerchClient(socketPath: SetupEnvironment.current.socket.path), reminders: reminders)
    }

    /// "Uninstall Perch…": the same uninstall as `perch uninstall` (data kept), no more opening at login, the app to
    /// the Trash, quit. A failure that keeps Perch installed is shown and the app stays.
    private func confirmUninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Perch?"
        alert.informativeText = "Removes Perch's hooks from your agents, stops perchd and deletes ~/.perch/bin. "
            + "Perch.app moves to the Trash. Your data in ~/.perch stays."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setup.uninstall { outcome in
            if let problem = outcome.problem {
                NSApp.activate(ignoringOtherApps: true)
                let report = NSAlert()
                report.alertStyle = outcome.finished ? .informational : .warning
                report.messageText = outcome.finished ? "Perch is uninstalled, with a problem" : "Couldn't uninstall Perch"
                report.informativeText = problem
                report.runModal()
            }
            if outcome.finished { NSApp.terminate(nil) }
        }
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
