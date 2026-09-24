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

    public init(config: DaemonConfig, now: @escaping () -> Date = Date.init) throws {
        self.config = config
        try FileManager.default.createDirectory(at: config.home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        service = Service(store: try Store(path: config.databasePath), now: now)
    }

    public func perform(_ request: Request) -> Response {
        queue.sync {
            let (response, events) = service.handle(request)
            publish(events)
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

    private func publish(_ events: [Event]) {
        for event in events {
            let message = Response(ok: true, event: event)
            for sink in subscribers.values { sink(message) }
        }
    }
}
