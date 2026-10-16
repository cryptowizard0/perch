import Foundation

/// One reminder in the "Perch" Reminders list, as the bridge app reads it (#51). The list is the only truth for
/// todos; perchd keeps the latest snapshot of these as a read-only cache of task items.
public struct Reminder: Codable, Equatable, Sendable {
    /// EventKit's `calendarItemExternalIdentifier`: the same on every device.
    public var externalID: String
    public var title: String
    /// EventKit's 0–9: 0 none, 1 high … 9 low (see `ItemPriority(reminderPriority:)`).
    public var priority: Int
    public var completed: Bool
    public var dueAt: Date?
    /// The due date components have no time: `dueAt` is that day's midnight here.
    public var dueDateOnly: Bool
    public var url: String?
    public var createdAt: Date?

    public init(externalID: String, title: String, priority: Int = 0, completed: Bool = false, dueAt: Date? = nil,
                dueDateOnly: Bool = false, url: String? = nil, createdAt: Date? = nil) {
        self.externalID = externalID
        self.title = title
        self.priority = priority
        self.completed = completed
        self.dueAt = dueAt
        self.dueDateOnly = dueDateOnly
        self.url = url
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case title, priority, completed, url
        case externalID = "external_id"
        case dueAt = "due_at"
        case dueDateOnly = "due_date_only"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        externalID = try c.decode(String.self, forKey: .externalID)
        title = try c.decode(String.self, forKey: .title)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        dueDateOnly = try c.decodeIfPresent(Bool.self, forKey: .dueDateOnly) ?? false
        url = try c.decodeIfPresent(String.self, forKey: .url)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// What Perch changes on a reminder. Unset fields stay as they are, and so does everything Perch doesn't manage
/// (notes, alarms, repeat rules, subtasks, flags, tags, images).
public struct ReminderChange: Codable, Equatable, Sendable {
    public var title: String?
    /// EventKit's 0–9 (`ItemPriority.reminderPriority`).
    public var priority: Int?
    public var completed: Bool?
    /// Sets the due date components: the day alone when `dueDateOnly`, else the day and the time.
    public var dueAt: Date?
    public var dueDateOnly: Bool?
    /// Removes the due date. Never together with `dueAt`.
    public var clearDue: Bool?
    public var url: String?
    /// Removes the URL. Never together with `url`.
    public var clearURL: Bool?

    public init(title: String? = nil, priority: Int? = nil, completed: Bool? = nil, dueAt: Date? = nil,
                dueDateOnly: Bool? = nil, clearDue: Bool? = nil, url: String? = nil, clearURL: Bool? = nil) {
        self.title = title
        self.priority = priority
        self.completed = completed
        self.dueAt = dueAt
        self.dueDateOnly = dueDateOnly
        self.clearDue = clearDue
        self.url = url
        self.clearURL = clearURL
    }

    enum CodingKeys: String, CodingKey {
        case title, priority, completed, url
        case dueAt = "due_at"
        case dueDateOnly = "due_date_only"
        case clearDue = "clear_due"
        case clearURL = "clear_url"
    }

    public var isEmpty: Bool { self == ReminderChange() }
}

/// A todo write perchd hands to the bridge (#52), pushed on the bridge's watch connection. The bridge applies it to the
/// "Perch" list, answers with `todo_ack` (same `id`), then sends a snapshot; perchd answers the writer after that.
public struct TodoOperation: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        /// A new reminder with `change`'s fields (`title` is set).
        case create
        /// `change` on the reminder `external_id`.
        case update
        /// `change` on the reminder `external_id` if it is still in the list, else a new reminder with it (`title` is
        /// set): `add --key` again when perchd knows the key's reminder but hasn't seen it lately.
        case upsert
        /// The reminder `external_id` goes (to Reminders' Recently Deleted).
        case delete
    }

    /// One-time operation id, echoed by the ack.
    public var id: String
    public var action: Action
    public var externalID: String?
    public var change: ReminderChange

    public init(id: String = UUID().uuidString, action: Action, externalID: String? = nil, change: ReminderChange = ReminderChange()) {
        self.id = id
        self.action = action
        self.externalID = externalID
        self.change = change
    }

    enum CodingKeys: String, CodingKey {
        case id, action, change
        case externalID = "external_id"
    }
}

/// The bridge's answer to a `TodoOperation`: the reminder it created or changed, or why it couldn't. Both when it made
/// the change but can't show it (the list became unreadable): perchd remembers the reminder and reports the error.
public struct TodoAck: Codable, Equatable, Sendable {
    public var id: String
    public var externalID: String?
    public var error: String?

    public init(id: String, externalID: String? = nil, error: String? = nil) {
        self.id = id
        self.externalID = externalID
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id, error
        case externalID = "external_id"
    }
}

extension ItemPriority {
    /// Reading a reminder: 1–4 (High, and anything in between) → High; 0 (none) and 5 (Medium) → Normal; 6–9 → Low.
    public init(reminderPriority: Int) {
        switch reminderPriority {
        case 1...4: self = .high
        case 6...9: self = .low
        default: self = .normal
        }
    }

    /// Writing a reminder: High → 1, Normal → 0 (no priority), Low → 9.
    public var reminderPriority: Int {
        switch self {
        case .high: return 1
        case .normal: return 0
        case .low: return 9
        }
    }
}

extension Item {
    /// The reminder a cached todo stands for (perchd sets it from the snapshot; the bridge writes through it).
    public static let reminderMetaKey = "reminder"

    public var reminderID: String? { meta?[Self.reminderMetaKey] }
}
