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
