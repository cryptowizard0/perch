import Foundation
import PerchCore

/// What clicking a row's title does.
public enum Click: Equatable, Sendable {
    /// Tasks and waiting items: mark done.
    case complete
    /// ⌥-click: due in 30 minutes from now.
    case snooze
    /// A notice: keep it as a task (it stops expiring).
    case keep
    /// Requests are answered with their own buttons (M4), never by clicking the text.
    case none

    public static let snoozeInterval: TimeInterval = 30 * 60

    public static func on(_ item: Item, option: Bool) -> Click {
        switch item.kind {
        case .request: return .none
        case .notice: return .keep
        case .task: return option ? .snooze : .complete
        }
    }

    /// The perchd request this click sends, or nil if it does nothing.
    public func request(for item: Item, now: Date = Date()) -> Request? {
        switch self {
        case .complete: return Request(op: .done, id: item.id)
        case .snooze: return Request(op: .update, id: item.id, patch: .init(dueAt: now.addingTimeInterval(Self.snoozeInterval)))
        case .keep: return Request(op: .update, id: item.id, patch: .init(kind: .task))
        case .none: return nil
        }
    }
}
