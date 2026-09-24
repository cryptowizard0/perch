import Combine
import Foundation
import PerchClient
import PerchCore

/// What the notch shows, fed by `QueueConnection`. Main thread only.
@MainActor
public final class QueueModel: ObservableObject {
    @Published public private(set) var state = QueueState()
    /// False until the first snapshot, and whenever perchd is unreachable.
    @Published public private(set) var online = false
    @Published public private(set) var offlineReason: String?
    /// "Now" for ordering and colours. Ticks every minute and exactly when the next item falls due;
    /// it only re-sorts — changes themselves always arrive as events.
    @Published public private(set) var now = Date()
    /// Bumped whenever the notch should pulse once.
    @Published public private(set) var pulse = 0
    /// Running agent sessions. No data source until M3, so always nil for now.
    @Published public private(set) var liveActivity: LiveActivity?

    /// Called after every applied update; used to measure CLI → notch latency.
    public var onApply: ((QueueConnection.Update) -> Void)?

    private var connection: QueueConnection?
    private var ticker: Timer?

    public init() {}

    public var ordered: [Item] { state.ordered(now: now) }
    public var summary: Summary { state.summary(now: now) }

    public func connect(client: PerchClient = PerchClient()) {
        let connection = QueueConnection(client: client) { [weak self] update in
            MainActor.assumeIsolated { self?.handle(update) }
        }
        self.connection = connection
        connection.start()
        scheduleTick()
    }

    public func disconnect() {
        connection?.stop()
        connection = nil
        ticker?.invalidate()
    }

    public func handle(_ update: QueueConnection.Update) {
        switch update {
        case .snapshot(let items):
            state.replace(with: items)
            online = true
            offlineReason = nil
        case .event(let event):
            if state.apply(event) { pulse += 1 }
        case .offline(let reason):
            online = false
            offlineReason = reason
        }
        now = Date()
        scheduleTick()
        onApply?(update)
    }

    /// For the view layer to request a pulse (e.g. a reminder fired).
    public func requestPulse() {
        pulse += 1
    }

    private func scheduleTick() {
        ticker?.invalidate()
        let current = Date()
        let nextMinute = (current.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60
        var fire = Date(timeIntervalSinceReferenceDate: nextMinute)
        if let due = state.nextDue(after: current), due < fire { fire = due }
        let timer = Timer(fire: fire.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.scheduleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
