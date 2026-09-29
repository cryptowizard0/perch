import Foundation
import PerchCore

/// The app's copy of the active items: a `list` snapshot plus every event since. The panel only looks at the
/// requests among them (what Allow / Deny answer). Only open / waiting items are kept; anything closed or removed drops out.
public struct QueueState: Equatable, Sendable {
    public private(set) var items: [String: Item] = [:]

    public init(items: [Item] = []) {
        replace(with: items)
    }

    public mutating func replace(with snapshot: [Item]) {
        items = Dictionary(snapshot.filter(Self.isActive).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    /// Applies one pushed event.
    public mutating func apply(_ event: Event) {
        if event.type == .removed || !Self.isActive(event.item) {
            items[event.item.id] = nil
        } else {
            items[event.item.id] = event.item
        }
    }

    static func isActive(_ item: Item) -> Bool {
        item.status == .open || item.status == .waiting
    }
}
