import Combine
import Foundation
import PerchClient
import PerchCore

/// What the notch shows, fed by `QueueConnection`, and what its rows and hotkeys do. Main thread only.
/// The notch renders `panel` (agent sessions); items are kept only for the requests Allow / Deny answer.
@MainActor
public final class QueueModel: ObservableObject {
    @Published public private(set) var state = QueueState()
    /// False until the first snapshot, and whenever perchd is unreachable.
    @Published public private(set) var online = false
    @Published public private(set) var offlineReason: String?
    /// "Now" for the rows' times. Ticks every minute; changes themselves always arrive as events.
    @Published public private(set) var now = Date()
    /// Bumped whenever the notch should pulse once: a session starts needing you, fails or finishes (`Panel.pulses`).
    @Published public private(set) var pulse = 0
    /// The state whose arrival caused the last pulse (its colour rings).
    @Published public private(set) var pulseStatus: SessionStatus?
    /// Agent sessions by id, in any state (Hermes too; `panel` leaves those out).
    @Published public private(set) var sessions: [String: Session] = [:]
    /// The last failed action, shown briefly in the expanded notch.
    @Published public private(set) var flash: String?

    /// Called after every applied update; used to measure CLI → notch latency.
    public var onApply: ((QueueConnection.Update) -> Void)?
    /// Goes to a session's link (its terminal). The app sets it; AppKit stays out of this module.
    public var jump: (String?) -> Void = { _ in }

    private var connection: QueueConnection?
    private var client = PerchClient()
    private var ticker: Timer?
    private var flashTimer: Timer?
    private let actions = DispatchQueue(label: "dev.perch.app.actions")

    public init() {}

    /// What ⌥⇧A / ⌥⇧D answer and ⌥⇧O jumps to (see `Panel`).
    public var headRequest: Item? { panel.headRequest }
    public var headSession: Session? { panel.headSession }
    public var panel: Panel { Panel(sessions: sessions.values, requests: state.items.values) }

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
            if Panel.pulses(from: before, to: after) {
                pulseStatus = after?.status
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

    /// Advances `now` and re-arms the tick.
    private func refresh() {
        now = Date()
        scheduleTick()
    }

    // Row and hotkey actions. Results come back as events like any other change; only failures are reported here.

    /// Clicking a row: back to that session's terminal. A done session has now been seen, so it turns idle.
    public func open(_ session: Session) {
        jump(session.link)
        if session.status == .done { send(Request(op: .sessionSeen, id: session.id)) }
    }

    /// "Remove from Panel": forgets the session until its next event.
    public func remove(_ session: Session) {
        send(Request(op: .sessionRemove, id: session.id))
    }

    /// Allow / Deny (or any of the request's options). The waiting hook prints the decision.
    public func respond(_ item: Item, _ value: String) {
        send(Request(op: .respond, id: item.id, value: value))
    }

    /// ⌥⇧O: the session that has waited longest.
    public func openHead() {
        if let head = headSession { open(head) }
    }

    /// ⌥⇧A / ⌥⇧D: the first request the panel shows, if it offers that answer.
    public func answerHead(_ value: String) {
        guard let head = headRequest, head.options?.contains(value) ?? false else { return }
        respond(head, value)
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

    private func scheduleTick() {
        ticker?.invalidate()
        let current = Date()
        let nextMinute = (current.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60
        let fire = Date(timeIntervalSinceReferenceDate: nextMinute)
        let timer = Timer(fire: fire.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
