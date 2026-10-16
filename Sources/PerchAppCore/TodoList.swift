import Foundation
import PerchCore

/// The Todo tab (#41): the open todos (the "Perch" Reminders list, #51), grouped High / Normal / Low, oldest first in
/// each group. Notices, requests, waiting and closed items stay out. Due dates are shown (`dueLabel`, #53) but never
/// reorder: priority is the only order besides age.
public struct TodoList: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        public var priority: ItemPriority
        public var items: [Item]
        public var id: String { priority.rawValue }
        public var title: String { priority.label }
    }

    /// Non-empty groups, High first.
    public let groups: [Group]
    public let openCount: Int
    public let highCount: Int

    /// `items`: any items (only open tasks are kept).
    public init(items: some Sequence<Item>) {
        let open = items.filter { $0.kind == .task && $0.status == .open }
        groups = ItemPriority.allCases.compactMap { priority in
            let members = open.filter { $0.priority == priority }
                .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id }
            return members.isEmpty ? nil : Group(priority: priority, items: members)
        }
        openCount = open.count
        highCount = open.filter { $0.priority == .high }.count
    }

    /// The gray line under the title: "6 open · 2 high", "6 open", or "All clear".
    public var summary: String {
        guard openCount > 0 else { return "All clear" }
        return highCount > 0 ? "\(openCount) open · \(highCount) high" : "\(openCount) open"
    }

    public var items: [Item] { groups.flatMap(\.items) }

    /// A row's due date (#53): `text` on the row, `full` in its tooltip; overdue ones are drawn white.
    public struct DueLabel: Equatable, Sendable {
        public var text: String
        public var full: String
        public var overdue: Bool
    }

    /// Today, Tomorrow, a weekday within the week, else "Oct 20" ("Jan 5, 2027" in another year); past days are dates
    /// too. A time follows when the reminder has one ("Today 15:00"). Nil without a due date.
    public static func dueLabel(_ item: Item, now: Date, calendar: Calendar = .current) -> DueLabel? {
        guard let due = item.dueAt else { return nil }
        func format(_ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.dateFormat = pattern
            return f.string(from: due)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        var text: String
        switch days {
        case 0: text = "Today"
        case 1: text = "Tomorrow"
        case 2...6: text = format("EEEE")
        default:
            let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
            text = format(sameYear ? "MMM d" : "MMM d, yyyy")
        }
        var full = format("EEEE, MMMM d, yyyy")
        if !item.dueDateOnly {
            text += " " + format("HH:mm")
            full += " at " + format("HH:mm")
        }
        return DueLabel(text: text, full: full, overdue: item.isOverdue(now: now, calendar: calendar))
    }
}

extension ItemPriority {
    /// The English label the notch uses.
    public var label: String {
        switch self {
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        }
    }
}
