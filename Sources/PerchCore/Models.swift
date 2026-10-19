import Foundation

/// What an item is. See docs/PRD.md → 数据模型.
public enum ItemKind: String, Codable, CaseIterable, Sendable {
    /// Needs the human to act.
    case task
    /// Informational only; auto-dismisses at `expiresAt`.
    case notice
    /// An agent is blocked waiting for a decision (`options` → `response`).
    case request
}

public enum ItemStatus: String, Codable, CaseIterable, Sendable {
    case open
    /// An agent is waiting on the human. Sorts first, turns the notch orange.
    case waiting
    case done
    case dismissed
}

/// How much a todo matters (#41). Orders todos inside their list (#69), never by colour: orange and red belong to agents.
public enum ItemPriority: String, Codable, CaseIterable, Sendable {
    case high, normal, low

    /// How `perch ls` and `todo.md` mark it; Normal goes unmarked.
    public var marker: String? {
        switch self {
        case .high: return "high priority"
        case .normal: return nil
        case .low: return "low priority"
        }
    }

    /// High first.
    public var rank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}

/// One row in the store. Wire format is JSON with snake_case keys and ISO-8601 dates.
public struct Item: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: ItemKind
    public var status: ItemStatus
    /// Normal unless someone says otherwise; only open tasks are sorted by it.
    public var priority: ItemPriority
    /// "human", "claude-code", "codex", "hermes", … — free string, new agents need no code change.
    public var source: String
    public var dueAt: Date?
    /// `due_at` is a whole day (its midnight), not a moment: a date-only reminder (#52). On the wire only when true.
    public var dueDateOnly: Bool
    /// URL, file path or terminal session reference. Clicking it jumps back.
    public var link: String?
    /// Free-form bag for agents: cwd, session_id, tool name, …
    public var meta: [String: String]?
    /// Idempotency key. `add` with an existing key updates instead of duplicating.
    public var key: String?
    // request-only
    public var options: [String]?
    public var response: String?
    public var expiresAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = Item.newID(),
        title: String,
        kind: ItemKind = .task,
        status: ItemStatus = .open,
        priority: ItemPriority = .normal,
        source: String = "human",
        dueAt: Date? = nil,
        dueDateOnly: Bool = false,
        link: String? = nil,
        meta: [String: String]? = nil,
        key: String? = nil,
        options: [String]? = nil,
        response: String? = nil,
        expiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.priority = priority
        self.source = source
        self.dueAt = dueAt
        self.dueDateOnly = dueDateOnly
        self.link = link
        self.meta = meta
        self.key = key
        self.options = options
        self.response = response
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, kind, status, priority, source, link, meta, key, options, response
        /// Out only: a todo's list name (#69, from `meta`), for `perch ls --json`.
        case list
        case dueAt = "due_at"
        case dueDateOnly = "due_date_only"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Lenient: only `title` is required, so HTTP clients can send `{"title":"…"}`.
    /// Missing fields get the same defaults as `init`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? Item.newID()
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .task
        status = try c.decodeIfPresent(ItemStatus.self, forKey: .status) ?? .open
        priority = try c.decodeIfPresent(ItemPriority.self, forKey: .priority) ?? .normal
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "human"
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        dueDateOnly = try dueAt != nil && (c.decodeIfPresent(Bool.self, forKey: .dueDateOnly) ?? false)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        meta = try c.decodeIfPresent([String: String].self, forKey: .meta)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        options = try c.decodeIfPresent([String].self, forKey: .options)
        response = try c.decodeIfPresent(String.self, forKey: .response)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    /// Dates go out as whole-second ISO-8601, which truncates. `expires_at` is rounded up instead,
    /// so a client asking for `now + N` never reaches perchd with a shorter window.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(kind, forKey: .kind)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(dueAt, forKey: .dueAt)
        if dueDateOnly { try c.encode(true, forKey: .dueDateOnly) }
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(meta, forKey: .meta)
        try c.encodeIfPresent(listName, forKey: .list)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(options, forKey: .options)
        try c.encodeIfPresent(response, forKey: .response)
        try c.encodeIfPresent(expiresAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.up)) }, forKey: .expiresAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    /// Short, typeable ids like `t7k2`: 4 chars from an alphabet without look-alikes.
    public static func newID() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<4).map { _ in alphabet.randomElement()! })
    }

    /// True when the item still needs the human's attention.
    public var isActionable: Bool {
        switch status {
        case .open, .waiting: return kind != .notice
        case .done, .dismissed: return false
        }
    }
}

extension Item {
    /// Position in the queue; lower comes first. `perch ls` and `todo.md` share this order:
    /// request → waiting → overdue → due today → other open → notice → done → dismissed.
    /// Open tasks (overdue, due today, other) share one place, by list and priority (see `queueOrdered`).
    public func queueRank(now: Date, calendar: Calendar = .current) -> Int {
        switch status {
        case .done: return 6
        case .dismissed: return 7
        case .open, .waiting: break
        }
        if kind == .request { return 0 }
        if kind == .notice { return 5 }
        if status == .waiting { return 1 }
        if let due = dueAt {
            if isOverdue(now: now, calendar: calendar) { return 2 }
            if calendar.isDate(due, inSameDayAs: now) { return 3 }
        }
        return 4
    }

    /// Past its due time; a date-only due (a whole day) only once that day is over.
    public func isOverdue(now: Date, calendar: Calendar = .current) -> Bool {
        guard let due = dueAt else { return false }
        return due < (dueDateOnly ? calendar.startOfDay(for: now) : now)
    }
}

extension Array where Element == Item {
    /// Sorted by `queueRank`, except that open tasks (todos) share one slot: by list in `lists`' order (#69, a list not
    /// among them after those), then High → Normal → Low, then oldest first; due dates don't reorder them. Everything
    /// else: within a rank by due date, then oldest first. Closed items: most recently updated first.
    public func queueOrdered(now: Date = Date(), calendar: Calendar = .current, lists: [String] = []) -> [Item] {
        let position = Dictionary(lists.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        /// Open tasks share one slot (ranks 2…4), split by list.
        func slot(_ item: Item, _ rank: Int) -> (Int, Int) {
            (2...4).contains(rank) ? (2, item.listID.flatMap { position[$0] } ?? lists.count) : (rank, 0)
        }
        return map { ($0, $0.queueRank(now: now, calendar: calendar)) }
            .sorted { a, b in
                let sa = slot(a.0, a.1), sb = slot(b.0, b.1)
                if sa != sb { return sa < sb }
                if sa.0 == 2 {
                    if a.0.listID != b.0.listID { return (a.0.listID ?? "") < (b.0.listID ?? "") }
                    return Item.todoOrder(a.0, b.0)
                }
                if a.1 != b.1 { return a.1 < b.1 }
                if a.1 >= 6 { return a.0.updatedAt > b.0.updatedAt }
                let da = a.0.dueAt ?? .distantFuture, db = b.0.dueAt ?? .distantFuture
                if da != db { return da < db }
                if a.0.createdAt != b.0.createdAt { return a.0.createdAt < b.0.createdAt }
                return a.0.id < b.0.id
            }
            .map(\.0)
    }
}

public enum EventType: String, Codable, Sendable {
    case added = "item.added"
    case updated = "item.updated"
    case removed = "item.removed"
}

/// Pushed by perchd to every `watch` client. The notch UI never polls.
public struct Event: Codable, Equatable, Sendable {
    public var type: EventType
    public var item: Item
    public var at: Date

    public init(type: EventType, item: Item, at: Date = Date()) {
        self.type = type
        self.item = item
        self.at = at
    }
}
