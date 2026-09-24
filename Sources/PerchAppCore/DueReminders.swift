import Foundation
import PerchCore

/// Decides when a `due_at` reminder fires: once per item and due time, for times that arrive while the
/// app is watching. Things already overdue when the app starts are not announced (the dot is red anyway);
/// a snoozed item has a new due time, so it is announced again.
public struct DueReminders: Sendable {
    /// Due times before this are history, not reminders.
    public let armedAt: Date
    private var announced: Set<String> = []

    /// A little slack so an item due right as the app starts still gets its reminder.
    public static let grace: TimeInterval = 60

    public init(armedAt: Date = Date()) {
        self.armedAt = armedAt
    }

    /// The items whose due time has come and that have not been announced yet; marks them announced.
    public mutating func take(from items: some Sequence<Item>, now: Date) -> [Item] {
        let due = items.filter { item in
            guard item.isActionable, let at = item.dueAt else { return false }
            return at <= now && at > armedAt.addingTimeInterval(-Self.grace) && !announced.contains(Self.key(item, at))
        }
        for item in due { announced.insert(Self.key(item, item.dueAt!)) }
        return due.sorted { ($0.dueAt!, $0.id) < ($1.dueAt!, $1.id) }
    }

    private static func key(_ item: Item, _ due: Date) -> String {
        "\(item.id)@\(Int(due.timeIntervalSince1970))"
    }
}
