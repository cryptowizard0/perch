import Foundation
import PerchCore

/// Request handling on top of the store. Synchronous and not thread-safe: `Daemon` calls it
/// from its serial queue and broadcasts the returned events.
public final class Service {
    public let store: Store
    /// Injectable for tests.
    public var now: () -> Date

    public init(store: Store, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func handle(_ request: Request) -> (Response, [Event]) {
        switch request.op {
        case .ping:
            return (Response(ok: true, version: PerchVersion.string), [])
        default:
            return (.failure("\(request.op.rawValue) is not implemented yet"), [])
        }
    }
}
