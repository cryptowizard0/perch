import Foundation
import PerchCore

/// The Todo tab (#41): the open todos of the checked Reminders lists (#51, #69), one group per list in the order the
/// selection gives (empty ones too: "All clear"); in each, High → Normal → Low, then oldest first, then by id.
/// Notices, requests, waiting and closed items stay out. Due dates are shown (`dueLabel`, #53) but never reorder.
public struct TodoList: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        /// The list's identifier (empty for the one group of a cache from before #69).
        public var id: String
        /// The list's name.
        public var title: String
        public var items: [Item]
        /// The list isn't in iCloud: it works, but only on this Mac.
        public var notSyncing: Bool
        public var openCount: Int { items.count }
    }

    /// One per checked list, in order.
    public let groups: [Group]
    /// Across every checked list: the summary line, the tab strip and the folded notch (#56) count these.
    public let openCount: Int
    public let highCount: Int

    /// `items`: any items (only open tasks are kept). `lists`: the checked lists in order. A todo whose list isn't
    /// among them is left out: perchd sends the lists ahead of the snapshot's todos, so that is a list just unchecked.
    /// Without any lists (a cache from before #69) every todo is in one group named `unlisted`.
    public init(items: some Sequence<Item>, lists: [ReminderList] = [], unlisted: String = "Perch") {
        let grouped = items.todoGroups(lists: lists)
        groups = grouped.prefix(lists.isEmpty ? grouped.count : lists.count).map {
            Group(id: $0.list?.id ?? "", title: $0.list?.title ?? unlisted, items: $0.items, notSyncing: $0.list.map { !$0.isICloud } ?? false)
        }
        openCount = groups.reduce(0) { $0 + $1.items.count }
        highCount = groups.reduce(0) { $0 + $1.items.filter { $0.priority == .high }.count }
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
