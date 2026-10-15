import Foundation
import PerchCore

/// The Todo tab (#41): the human's open tasks, grouped High / Normal / Low, oldest first in each group. Notices,
/// requests and closed items stay out, and nothing here reads a date: priority is the only order besides age.
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
    /// Whether there has ever been a todo (open or done), for the empty state.
    public let hadAny: Bool

    /// `items`: any items (only open tasks are kept). `hadAny`: a todo has existed before, even if none is open now.
    public init(items: some Sequence<Item>, hadAny: Bool) {
        let open = items.filter { $0.kind == .task && $0.status == .open }
        groups = ItemPriority.allCases.compactMap { priority in
            let members = open.filter { $0.priority == priority }
                .sorted { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id < $1.id }
            return members.isEmpty ? nil : Group(priority: priority, items: members)
        }
        openCount = open.count
        highCount = open.filter { $0.priority == .high }.count
        self.hadAny = hadAny || !open.isEmpty
    }

    /// The gray line under the title: "6 open · 2 high", "6 open", "All clear", or "Nothing to do yet.".
    public var summary: String {
        guard openCount > 0 else { return hadAny ? "All clear" : "Nothing to do yet." }
        return highCount > 0 ? "\(openCount) open · \(highCount) high" : "\(openCount) open"
    }

    public var items: [Item] { groups.flatMap(\.items) }
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
