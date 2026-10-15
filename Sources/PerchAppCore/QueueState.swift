import Foundation
import PerchCore

/// The app's copy of the active items: a `list` snapshot plus every event since. The agent panel looks at the
/// requests among them (what Allow / Deny answer), the Todo tab at the open tasks. Only open / waiting items are kept;
/// anything closed or removed drops out.
public struct QueueState: Equatable, Sendable {
    public private(set) var items: [String: Item] = [:]
    /// A todo (task) has existed: the snapshot had one (open or done), or an event brought one. The Todo tab says
    /// "All clear" rather than "Nothing to do yet." once it is true.
    public private(set) var hadTodos = false

    public init(items: [Item] = []) {
        replace(with: items)
    }

    /// `snapshot` may include closed items (the app fetches done tasks too); only active ones are kept.
    public mutating func replace(with snapshot: [Item]) {
        hadTodos = snapshot.contains { $0.kind == .task }
        items = Dictionary(snapshot.filter(Self.isActive).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    /// Applies one pushed event.
    public mutating func apply(_ event: Event) {
        if event.item.kind == .task && event.type != .removed { hadTodos = true }
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
