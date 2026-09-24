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
    /// The last failed action, shown briefly in the expanded notch.
    @Published public private(set) var flash: String?

    /// Called after every applied update; used to measure CLI → notch latency.
    public var onApply: ((QueueConnection.Update) -> Void)?
    /// Called when an item's due time arrives (the notch pulses too). The app posts a system notification.
    public var onDue: ((Item) -> Void)?
    private var reminders = DueReminders()

    private var connection: QueueConnection?
    private var client = PerchClient()
    private var ticker: Timer?
    private var flashTimer: Timer?
    private let actions = DispatchQueue(label: "dev.perch.app.actions")

    public init() {}

    public var ordered: [Item] { state.ordered(now: now) }
    public var summary: Summary { state.summary(now: now) }

    public func connect(client: PerchClient = PerchClient()) {
        self.client = client
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
        refresh()
        onApply?(update)
    }

    /// Advances `now`, fires due reminders, re-arms the tick.
    private func refresh() {
        now = Date()
        let due = reminders.take(from: state.items.values, now: now)
        if !due.isEmpty { pulse += 1 }
        for item in due { onDue?(item) }
        scheduleTick()
    }

    /// Clicking a row's title (see `Click`). The result comes back as an event like any other change;
    /// only failures are reported here.
    public func click(_ item: Item, option: Bool) {
        guard let request = Click.on(item, option: option).request(for: item) else { return }
        send(request)
    }

    /// Quick entry: "回复 X 的邮件 @15:00" becomes a task due at 15:00 (see `QuickEntry`).
    /// Returns false, sending nothing, when the text is blank.
    @discardableResult
    public func quickAdd(_ text: String, now: Date = Date()) -> Bool {
        let (title, due) = QuickEntry.parse(text, now: now)
        guard !title.isEmpty else { return false }
        send(Request(op: .add, item: Item(title: title, source: "human", dueAt: due)))
        return true
    }

    /// Sends one request off the main thread; failures go to `flash`.
    public func send(_ request: Request) {
        let client = self.client
        actions.async { [weak self] in
            let failure: String?
            do {
                let response = try client.send(request)
                failure = response.ok ? nil : response.error ?? "perchd returned an error"
            } catch {
                failure = String(describing: error)
            }
            guard let failure else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.show(failure) } }
        }
    }

    private func show(_ message: String) {
        flash = message
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flash = nil }
        }
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
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
