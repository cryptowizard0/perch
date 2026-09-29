import Combine
import Foundation
import PerchClient
import PerchCore

/// What the notch shows, fed by `QueueConnection`. Main thread only.
/// The notch renders `panel` (agent sessions); items are kept for the requests Allow / Deny answer.
@MainActor
public final class QueueModel: ObservableObject {
    @Published public private(set) var state = QueueState()
    /// False until the first snapshot, and whenever perchd is unreachable.
    @Published public private(set) var online = false
    @Published public private(set) var offlineReason: String?
    /// "Now" for ordering and colours. Ticks every minute and exactly when the next item falls due;
    /// it only re-sorts — changes themselves always arrive as events.
    @Published public private(set) var now = Date()
    /// Bumped whenever the notch should pulse once: a session starts needing you, fails or finishes
    /// (`Panel.pulses`), or a due reminder fires.
    @Published public private(set) var pulse = 0
    /// Agent sessions by id, in any state (Hermes too; `panel` leaves those out).
    @Published public private(set) var sessions: [String: Session] = [:]
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
    /// The request ⌥⇧A / ⌥⇧D answer: the first one in queue order.
    public var headRequest: Item? { ordered.first { $0.kind == .request } }
    public var panel: Panel { Panel(sessions: sessions.values, requests: state.items.values) }
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
        case .snapshot(let items, let all):
            state.replace(with: items)
            sessions = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            online = true
            offlineReason = nil
        case .event(let event):
            state.apply(event)
        case .session(let event):
            let before = sessions[event.session.id]
            let after = event.type == .ended ? nil : event.session
            sessions[event.session.id] = after
            if !Panel.hiddenSources.contains(event.session.source), Panel.pulses(from: before?.status, to: after?.status) {
                pulse += 1
            }
        case .offline(let reason):
            online = false
            offlineReason = reason
            sessions = [:]
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

    /// Allow / Deny (or any of the request's options). The waiting hook prints the decision.
    public func respond(_ item: Item, _ value: String) {
        send(Request(op: .respond, id: item.id, value: value))
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
