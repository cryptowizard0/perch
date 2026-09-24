import Foundation
import PerchClient
import PerchCore

/// Keeps the app subscribed to perchd: watch, then snapshot with `list`, then apply events.
/// If perchd is not running or goes away, reports `.offline` and retries with backoff (0.5 s → 5 s);
/// every reconnect starts with a fresh snapshot. Never polls while connected.
public final class QueueConnection: @unchecked Sendable {
    public enum Update: Sendable {
        case snapshot([Item], [Session])
        case event(Event)
        case session(SessionEvent)
        case offline(String)
    }

    private let client: PerchClient
    private let queue: DispatchQueue
    private let deliver: @Sendable (Update) -> Void
    private let lock = NSLock()
    private var stopped = false
    private var stream: EventStream?
    private let wake = DispatchSemaphore(value: 0)

    public static let backoff: ClosedRange<TimeInterval> = 0.5...5

    /// `deliver` runs on `queue` (main by default), in order.
    public init(client: PerchClient = PerchClient(), queue: DispatchQueue = .main,
                deliver: @escaping @Sendable (Update) -> Void) {
        self.client = client
        self.queue = queue
        self.deliver = deliver
    }

    public func start() {
        let thread = Thread { [self] in run() }
        thread.name = "dev.perch.app.connection"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func stop() {
        lock.withLock {
            stopped = true
            stream?.interrupt()
        }
        wake.signal()
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func run() {
        var delay = Self.backoff.lowerBound
        while !isStopped {
            do {
                let stream = try client.watch()
                defer {
                    lock.withLock { self.stream = nil }
                    stream.close()
                }
                guard lock.withLock({ () -> Bool in
                    guard !stopped else { return false }
                    self.stream = stream
                    return true
                }) else { return }
                // Subscribed first, so nothing that happens after the snapshot can be missed.
                let items = try client.send(Request(op: .list)).items ?? []
                let sessions = try client.send(Request(op: .sessions)).sessions ?? []
                send(.snapshot(items, sessions))
                delay = Self.backoff.lowerBound
                while let push = try stream.nextPush() {
                    switch push {
                    case .item(let event): send(.event(event))
                    case .session(let event): send(.session(event))
                    }
                }
                if !isStopped { send(.offline("perchd stopped")) }
            } catch {
                if !isStopped { send(.offline(String(describing: error))) }
            }
            if isStopped { return }
            _ = wake.wait(timeout: .now() + delay)
            delay = min(delay * 2, Self.backoff.upperBound)
        }
    }

    private func send(_ update: Update) {
        queue.async { [deliver] in deliver(update) }
    }
}
