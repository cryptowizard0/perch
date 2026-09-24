import Foundation
import PerchCore

/// Where one perchd instance keeps its files. Tests point this at a temp dir.
public struct DaemonConfig {
    public var home: URL
    public var socketPath: String
    public var databasePath: String
    public var mirrorPath: String
    public var inboxPath: String

    public init(home: URL = PerchPaths.home) {
        self.home = home
        socketPath = PerchPaths.socket(in: home).path
        databasePath = PerchPaths.database(in: home).path
        mirrorPath = PerchPaths.mirror(in: home).path
        inboxPath = PerchPaths.inbox(in: home).path
    }
}

/// Thread-safe core of perchd. Every mutation runs on one serial queue; transports call in from
/// their own threads and receive events through subscriber sinks.
public final class Daemon {
    public let config: DaemonConfig
    let queue = DispatchQueue(label: "dev.perch.perchd.core")
    let service: Service
    private var subscribers: [UUID: (Response) -> Void] = [:]
    private var expiryTimer: DispatchSourceTimer?

    public init(config: DaemonConfig, now: @escaping () -> Date = Date.init) throws {
        self.config = config
        try FileManager.default.createDirectory(at: config.home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        service = Service(store: try Store(path: config.databasePath), now: now)
        queue.sync { afterChange([]) }
    }

    deinit {
        expiryTimer?.cancel()
    }

    public func perform(_ request: Request) -> Response {
        queue.sync {
            let (response, events) = service.handle(request)
            afterChange(events)
            return response
        }
    }

    /// Registers a watcher. `sink` first receives the `{"ok":true}` acknowledgement, then one
    /// `Response` per event. It is called on the daemon queue and must not block.
    public func subscribe(_ sink: @escaping (Response) -> Void) -> UUID {
        queue.sync {
            let id = UUID()
            sink(Response(ok: true, version: PerchVersion.string))
            subscribers[id] = sink
            return id
        }
    }

    public func unsubscribe(_ id: UUID) {
        queue.sync { _ = subscribers.removeValue(forKey: id) }
    }

    var subscriberCount: Int {
        queue.sync { subscribers.count }
    }

    /// Runs on `queue` after every request (and at startup): broadcast, then re-arm the expiry timer.
    private func afterChange(_ events: [Event]) {
        publish(events)
        scheduleExpiry()
    }

    /// One timer for the earliest `expires_at`; it sweeps, broadcasts and re-arms itself.
    private func scheduleExpiry() {
        expiryTimer?.cancel()
        expiryTimer = nil
        guard let next = service.nextExpiry() else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(0, next.timeIntervalSinceNow), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.afterChange(self.service.sweepExpired())
        }
        timer.resume()
        expiryTimer = timer
    }

    private func publish(_ events: [Event]) {
        for event in events {
            let message = Response(ok: true, event: event)
            for sink in subscribers.values { sink(message) }
        }
    }
}
