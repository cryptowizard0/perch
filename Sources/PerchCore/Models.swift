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

/// One row in the store. Wire format is JSON with snake_case keys and ISO-8601 dates.
public struct Item: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: ItemKind
    public var status: ItemStatus
    /// "human", "claude-code", "codex", "hermes", … — free string, new agents need no code change.
    public var source: String
    public var dueAt: Date?
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
        source: String = "human",
        dueAt: Date? = nil,
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
        self.source = source
        self.dueAt = dueAt
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
        case id, title, kind, status, source, link, meta, key, options, response
        case dueAt = "due_at"
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
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "human"
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        meta = try c.decodeIfPresent([String: String].self, forKey: .meta)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        options = try c.decodeIfPresent([String].self, forKey: .options)
        response = try c.decodeIfPresent(String.self, forKey: .response)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
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
    /// Position in the queue; lower comes first. The notch and `perch ls` share this order:
    /// request → waiting → overdue → due today → other open → notice → done → dismissed.
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
            if due < now { return 2 }
            if calendar.isDate(due, inSameDayAs: now) { return 3 }
        }
        return 4
    }
}

extension Array where Element == Item {
    /// Sorted by `queueRank`; within a rank by due date, then oldest first. Closed items: most recently updated first.
    public func queueOrdered(now: Date = Date(), calendar: Calendar = .current) -> [Item] {
        map { ($0, $0.queueRank(now: now, calendar: calendar)) }
            .sorted { a, b in
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
