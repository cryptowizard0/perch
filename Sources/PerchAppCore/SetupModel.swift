import Combine
import Foundation
import PerchCore

/// Setup in the notch: runs the self-check on launch, holds the card and rows (`SetupState`), and carries out
/// Connect, the Agents menu and Codex's trust. Main thread only; disk work runs on a serial background queue.
@MainActor
public final class SetupModel: ObservableObject {
    @Published public private(set) var state = SetupState()
    /// "Uninstall Perch…" is under way: nothing else touches the install (a Connect queued behind it would write hooks
    /// for the deleted ~/.perch/bin/perch), and a second uninstall does not start.
    @Published public private(set) var uninstalling = false

    /// Called when the first-run card appears: the notch opens on its own.
    public var onCardAppeared: () -> Void = {}

    private let setup: AppSetup
    private let memory: CardMemory
    private let inline: Bool
    private let queue = DispatchQueue(label: "dev.perch.app.setup")

    /// `inline` runs the disk work on the calling thread (tests).
    public init(setup: AppSetup = AppSetup(), memory: CardMemory = .defaults, inline: Bool = false) {
        self.setup = setup
        self.memory = memory
        self.inline = inline
    }

    /// The launch self-check.
    public func start() {
        run({ $0.selfCheck() }) { [weak self] report in self?.apply(report) }
    }

    /// Re-reads agents.json and the hook files (after the CLI may have changed them).
    public func refresh() {
        guard !uninstalling else { return }
        run({ $0.refresh() }) { [weak self] report in self?.apply(report) }
    }

    // MARK: Card

    public func toggleCardChoice(_ agent: String) {
        state.toggleCardChoice(agent)
    }

    public func toggleCardOpenAtLogin() {
        state.toggleCardOpenAtLogin()
    }

    public func connectCard() {
        let login = state.card?.openAtLogin == true
        guard let agents = state.startConnecting() else { return }
        run({ $0.connect(agents, openAtLogin: login) }) { [weak self] report in
            self?.state.finishConnecting(agents, openAtLogin: login, report: report)
        }
    }

    /// Not now / OK (which take up the Open at login box), or Done.
    public func closeCard() {
        guard state.closeCard() else { return }
        setOpenAtLogin(true)
    }

    // MARK: Rows and menu

    /// A "found · Connect" row, or the Agents menu checked.
    public func connect(_ agent: String) {
        guard !uninstalling else { return }
        run({ $0.connect([agent]) }) { [weak self] report in self?.apply(report) }
    }

    /// The Agents menu unchecked.
    public func disconnect(_ agent: String) {
        guard !uninstalling else { return }
        run({ $0.disconnect(agent) }) { [weak self] report in self?.apply(report) }
    }

    /// The right-click menu's Open at Login item: whatever `state.loginMenu` says it does.
    public func chooseLoginToggle() {
        guard !uninstalling, let toggle = state.loginMenu else { return }
        switch toggle.action {
        case .register: setOpenAtLogin(true)
        case .unregister: setOpenAtLogin(false)
        case .openSettings: setup.loginItem?.openSettings()
        }
    }

    /// "Uninstall Perch…", after the user confirmed: `then` gets the outcome on the main thread (quit when finished).
    public func uninstall(then: @escaping @MainActor (UninstallOutcome) -> Void) {
        guard !uninstalling else { return }
        uninstalling = true
        run({ $0.uninstall() }) { [weak self] outcome in
            // Finished: the app quits next, still "uninstalling". Otherwise Perch stays installed and usable.
            if !outcome.finished { self?.uninstalling = false }
            then(outcome)
        }
    }

    public func dismiss(_ row: SetupRow) {
        state.dismiss(row.id)
    }

    /// Every session event the notch receives: a Codex update after its hooks were written proves trust.
    public func observe(_ event: SessionEvent) {
        guard let agent = state.provesTrust(event) else { return }
        let time = event.session.updatedAt
        state.markTrusted(agent, at: time)
        run({ $0.recordTrust(agent, at: time) }) { [weak self] report in self?.apply(report) }
    }

    /// Returns once the disk work queued so far has finished and been applied. Tests run the model on its real queue
    /// and wait here, so the main thread stays free for the rest of the suite.
    public func settle() async {
        guard !inline else { return }
        await withCheckedContinuation { continuation in
            queue.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }

    // MARK: -

    private func setOpenAtLogin(_ on: Bool) {
        run({ $0.setOpenAtLogin(on) }) { [weak self] report in self?.apply(report) }
    }

    private func apply(_ report: SetupReport) {
        if state.apply(report, cardShownBefore: memory.shown()) {
            memory.markShown()
            onCardAppeared()
        }
    }

    private func run<Result: Sendable>(_ work: @escaping @Sendable (AppSetup) -> Result, then: @escaping @MainActor (Result) -> Void) {
        let setup = self.setup
        guard !inline else { return then(work(setup)) }
        queue.async {
            let result = work(setup)
            DispatchQueue.main.async { MainActor.assumeIsolated { then(result) } }
        }
    }
}

/// Whether the first-run card was ever shown (it appears once). The app keeps it in its user defaults.
public struct CardMemory: Sendable {
    public let shown: @Sendable () -> Bool
    public let markShown: @Sendable () -> Void

    public init(shown: @escaping @Sendable () -> Bool, markShown: @escaping @Sendable () -> Void) {
        self.shown = shown
        self.markShown = markShown
    }

    public static let defaultsKey = "SetupCardShown"

    public static var defaults: CardMemory {
        CardMemory(shown: { UserDefaults.standard.bool(forKey: defaultsKey) },
                   markShown: { UserDefaults.standard.set(true, forKey: defaultsKey) })
    }
}
