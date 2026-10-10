import Combine
import Foundation
import PerchCore

/// Setup in the notch: runs the self-check on launch, holds the card and rows (`SetupState`), and carries out
/// Connect, the Agents menu and Codex's trust. Main thread only; disk work runs on a serial background queue.
@MainActor
public final class SetupModel: ObservableObject {
    @Published public private(set) var state = SetupState()

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
        run({ $0.refresh() }) { [weak self] report in self?.apply(report) }
    }

    // MARK: Card

    public func toggleCardChoice(_ agent: String) {
        state.toggleCardChoice(agent)
    }

    public func connectCard() {
        guard let agents = state.startConnecting() else { return }
        run({ $0.connect(agents) }) { [weak self] report in self?.state.finishConnecting(agents, report: report) }
    }

    /// Not now, or Done.
    public func closeCard() {
        state.closeCard()
    }

    // MARK: Rows and menu

    /// A "found · Connect" row, or the Agents menu checked.
    public func connect(_ agent: String) {
        run({ $0.connect([agent]) }) { [weak self] report in self?.apply(report) }
    }

    /// The Agents menu unchecked.
    public func disconnect(_ agent: String) {
        run({ $0.disconnect(agent) }) { [weak self] report in self?.apply(report) }
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

    // MARK: -

    private func apply(_ report: SetupReport) {
        if state.apply(report, cardShownBefore: memory.shown()) {
            memory.markShown()
            onCardAppeared()
        }
    }

    private func run(_ work: @escaping @Sendable (AppSetup) -> SetupReport, then: @escaping @MainActor (SetupReport) -> Void) {
        let setup = self.setup
        guard !inline else { return then(work(setup)) }
        queue.async {
            let report = work(setup)
            DispatchQueue.main.async { MainActor.assumeIsolated { then(report) } }
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
