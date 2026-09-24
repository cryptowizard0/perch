import Foundation
import PerchCore

/// The app's copy of the active queue: a `list` snapshot plus every event since.
/// Only open / waiting items are kept; anything closed or removed drops out.
public struct QueueState: Equatable, Sendable {
    public private(set) var items: [String: Item] = [:]

    public init(items: [Item] = []) {
        replace(with: items)
    }

    public mutating func replace(with snapshot: [Item]) {
        items = Dictionary(snapshot.filter(Self.isActive).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    /// Applies one pushed event. Returns true when it puts a new agent in front of the human
    /// (a request, or something newly waiting) — the notch pulses for those.
    @discardableResult
    public mutating func apply(_ event: Event) -> Bool {
        let before = items[event.item.id]
        if event.type == .removed || !Self.isActive(event.item) {
            items[event.item.id] = nil
            return false
        }
        items[event.item.id] = event.item
        return Self.isCalling(event.item) && !(before.map(Self.isCalling) ?? false)
    }

    public func ordered(now: Date = Date(), calendar: Calendar = .current) -> [Item] {
        Array(items.values).queueOrdered(now: now, calendar: calendar)
    }

    public func summary(now: Date = Date()) -> Summary {
        let actionable = items.values.filter(\.isActionable)
        let signal: Signal
        if actionable.contains(where: { $0.dueAt.map { $0 <= now } ?? false }) {
            signal = .overdue
        } else if items.values.contains(where: Self.isCalling) {
            signal = .waiting
        } else if !actionable.isEmpty {
            signal = .todo
        } else {
            signal = .idle
        }
        return Summary(count: actionable.count, signal: signal)
    }

    /// The earliest due time after `now` among actionable items: when the dot turns red next.
    public func nextDue(after now: Date) -> Date? {
        items.values.filter(\.isActionable).compactMap(\.dueAt).filter { $0 > now }.min()
    }

    static func isActive(_ item: Item) -> Bool {
        item.status == .open || item.status == .waiting
    }

    /// An agent is blocked on the human: any open request, or a waiting task.
    static func isCalling(_ item: Item) -> Bool {
        isActive(item) && (item.kind == .request || (item.kind == .task && item.status == .waiting))
    }
}

/// What the collapsed notch shows: a number and one colour.
public struct Summary: Equatable, Sendable {
    /// Items that need the human (tasks, requests, waiting); notices do not count.
    public var count: Int
    public var signal: Signal
}

/// The colour dot. When several apply, the most urgent wins: overdue > waiting > todo > idle.
public enum Signal: Int, Comparable, Sendable {
    /// Grey: nothing to do.
    case idle
    /// Blue: open tasks.
    case todo
    /// Orange: an agent is waiting on you.
    case waiting
    /// Red: something is overdue.
    case overdue

    public static func < (a: Signal, b: Signal) -> Bool { a.rawValue < b.rawValue }
}
