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
    public var url: String?
    public var createdAt: Date?

    public init(externalID: String, title: String, priority: Int = 0, completed: Bool = false, dueAt: Date? = nil,
                url: String? = nil, createdAt: Date? = nil) {
        self.externalID = externalID
        self.title = title
        self.priority = priority
        self.completed = completed
        self.dueAt = dueAt
        self.url = url
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case title, priority, completed, url
        case externalID = "external_id"
        case dueAt = "due_at"
        case createdAt = "created_at"
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
