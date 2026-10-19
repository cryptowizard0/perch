import Foundation

/// A Reminders list. The bridge's snapshot carries the checked ones (#69), in the order the Todo tab shows them;
/// perchd keeps the latest of these so it can group todos by list with no bridge connected.
public struct ReminderList: Codable, Equatable, Sendable {
    /// EventKit's `calendarIdentifier`: stable across renames on this Mac.
    public var id: String
    public var title: String
    /// In the iCloud account, so it reaches the phone.
    public var isICloud: Bool
    /// The Reminders account it is in (EventKit's `sourceIdentifier`, #70); nil from a bridge older than that. Perch
    /// only moves todos between lists of one account.
    public var account: String?

    public init(id: String, title: String, isICloud: Bool, account: String? = nil) {
        self.id = id
        self.title = title
        self.isICloud = isICloud
        self.account = account
    }

    enum CodingKeys: String, CodingKey {
        case id, title, account
        case isICloud = "icloud"
    }

    /// What a todo's list is called when nobody said (a todo cached without its list's name).
    public static let untitled = "Reminders"

    /// Each identifier's position in `ids` (the first, if one repeats): the order lists are shown in.
    public static func positions(_ ids: some Sequence<String>) -> [String: Int] {
        Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The checked list called exactly `name` (case matters, #70): where `perch add --list` and `perch update --list`
    /// put a todo. Unknown, unchecked and ambiguous names are refused with the checked lists' names, so an agent can
    /// correct itself. perchd checks against its latest snapshot's lists, the bridge again when it writes.
    public static func checked(named name: String, in checked: [ReminderList]) throws -> ReminderList {
        let matches = checked.filter { $0.title == name }
        let names = checked.isEmpty ? "none yet (is Perch.app running?)" : checked.map(\.title).joined(separator: ", ")
        switch matches.count {
        case 1: return matches[0]
        case 0: throw RemindersListError("no checked Reminders list is called '\(name)' (names match exactly); checked lists: \(names)")
        default: throw RemindersListError("\(matches.count) checked Reminders lists are called '\(name)' (rename one in Reminders); checked lists: \(names)")
        }
    }

    /// Why a todo in `self` can't move to `target`, if it can't: they are in different Reminders accounts (iCloud and
    /// On My Mac, say). EventKit keeps a moved reminder's identifier within an account (checked on macOS 15, #70), so
    /// its short id stays; across accounts that isn't known to hold, so Perch leaves those moves to the Reminders app.
    public func moveRefusal(to target: ReminderList) -> String? {
        guard let account, let other = target.account, account != other else { return nil }
        return "'\(title)' and '\(target.title)' are in different Reminders accounts; Perch only moves todos within one, so move it in the Reminders app"
    }
}

/// A list name Perch can't use (`ReminderList.checked(named:in:)`, `moveRefusal`). The message is for an agent to act on.
public struct RemindersListError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// One reminder in a checked Reminders list ("Perch", and any other the user checked, #69), as the bridge app reads
/// it (#51). The lists are the only truth for todos; perchd keeps the latest snapshot of these as a read-only cache
/// of task items.
public struct Reminder: Codable, Equatable, Sendable {
    /// EventKit's `calendarItemExternalIdentifier`: the same on every device.
    public var externalID: String
    /// The list it is in (`ReminderList.id`); nil from a bridge older than #69.
    public var list: String?
    public var title: String
    /// EventKit's 0–9: 0 none, 1 high … 9 low (see `ItemPriority(reminderPriority:)`).
    public var priority: Int
    public var completed: Bool
    public var dueAt: Date?
    /// The due date components have no time: `dueAt` is that day's midnight here.
    public var dueDateOnly: Bool
    public var url: String?
    public var notes: String?
    public var createdAt: Date?

    public init(externalID: String, list: String? = nil, title: String, priority: Int = 0, completed: Bool = false,
                dueAt: Date? = nil, dueDateOnly: Bool = false, url: String? = nil, notes: String? = nil, createdAt: Date? = nil) {
        self.externalID = externalID
        self.list = list
        self.title = title
        self.priority = priority
        self.completed = completed
        self.dueAt = dueAt
        self.dueDateOnly = dueDateOnly
        self.url = url
        self.notes = notes
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case title, priority, completed, url, notes, list
        case externalID = "external_id"
        case dueAt = "due_at"
        case dueDateOnly = "due_date_only"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        externalID = try c.decode(String.self, forKey: .externalID)
        list = try c.decodeIfPresent(String.self, forKey: .list)
        title = try c.decode(String.self, forKey: .title)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        dueDateOnly = try c.decodeIfPresent(Bool.self, forKey: .dueDateOnly) ?? false
        url = try c.decodeIfPresent(String.self, forKey: .url)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

/// What Perch changes on a reminder. Unset fields stay as they are, and so does everything Perch doesn't manage
/// (repeat rules, subtasks, flags, tags, location reminders, images). Alarms only follow the due time (`alarms`).
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
    /// The notes; empty removes them.
    public var notes: String?
    public var url: String?
    /// Removes the URL. Never together with `url`.
    public var clearURL: Bool?
    /// The list it goes in (`ReminderList.id`, #70): a new reminder is made there instead of in "Perch", and a changed
    /// one moves there. A target, unlike `TodoOperation.seenInList`; always a checked list.
    public var list: String?

    public init(title: String? = nil, priority: Int? = nil, completed: Bool? = nil, dueAt: Date? = nil,
                dueDateOnly: Bool? = nil, clearDue: Bool? = nil, notes: String? = nil, url: String? = nil, clearURL: Bool? = nil,
                list: String? = nil) {
        self.title = title
        self.priority = priority
        self.completed = completed
        self.dueAt = dueAt
        self.dueDateOnly = dueDateOnly
        self.clearDue = clearDue
        self.notes = notes
        self.url = url
        self.clearURL = clearURL
        self.list = list
    }

    enum CodingKeys: String, CodingKey {
        case title, priority, completed, url, notes, list
        case dueAt = "due_at"
        case dueDateOnly = "due_date_only"
        case clearDue = "clear_due"
        case clearURL = "clear_url"
    }

    public var isEmpty: Bool { self == ReminderChange() }

    /// What turns the todo `old` into `new`: only the fields Perch manages that differ (its list too, #70).
    public init(from old: Item, to new: Item) {
        self.init()
        if new.title != old.title { title = new.title }
        if new.priority != old.priority { priority = new.priority.reminderPriority }
        if (new.status == .done) != (old.status == .done) { completed = new.status == .done }
        if new.dueAt != old.dueAt || new.dueDateOnly != old.dueDateOnly {
            if let due = new.dueAt {
                dueAt = due
                dueDateOnly = new.dueDateOnly
            } else {
                clearDue = true
            }
        }
        if new.notes != old.notes { notes = new.notes ?? "" }
        if new.link != old.link {
            if let link = new.link { url = link } else { clearURL = true }
        }
        if let id = new.listID, id != old.listID { list = id }
    }

    /// The reminder's absolute alarm times after this change, the way the Reminders app keeps them (#53): a due time
    /// comes with an alarm at that time, which follows the time when it moves and goes when the time does. Every other
    /// alarm stays. `oldDue`: the due date before the change.
    public func alarms(_ existing: [Date], oldDue: Date?, oldDueDateOnly: Bool) -> [Date] {
        guard dueAt != nil || clearDue == true else { return existing }
        func same(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 1 }
        var alarms = existing
        if let oldDue, !oldDueDateOnly { alarms.removeAll { same($0, oldDue) } }
        if let due = dueAt, dueDateOnly != true, !alarms.contains(where: { same($0, due) }) { alarms.append(due) }
        return alarms
    }
}

/// A todo write perchd hands to the bridge (#52), pushed on the bridge's watch connection. The bridge applies it to the
/// todo's own list (new ones go to "Perch", #69), or to `change.list` (#70: a new one goes there, a changed one moves),
/// answers with `todo_ack` (same `id`), then sends a snapshot; perchd answers the writer after that.
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
    /// A hint, not a target: the list perchd last saw the reminder in (`ReminderList.id`, #69), where the bridge looks
    /// first. Nil for a new reminder. The target, for a new reminder or a move, is `change.list` (#70).
    public var seenInList: String?
    public var change: ReminderChange

    public init(id: String = UUID().uuidString, action: Action, externalID: String? = nil, seenInList: String? = nil,
                change: ReminderChange = ReminderChange()) {
        self.id = id
        self.action = action
        self.externalID = externalID
        self.seenInList = seenInList
        self.change = change
    }

    enum CodingKeys: String, CodingKey {
        case id, action, change
        case externalID = "external_id"
        case seenInList = "seen_in_list"
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

    /// A todo's notes (#53), kept in `meta` like the reminder's identifier. Setting nil or blank removes them.
    public var notes: String? {
        get { meta?[Self.notesMetaKey] }
        set {
            var meta = self.meta ?? [:]
            meta[Self.notesMetaKey] = newValue.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            self.meta = meta.isEmpty ? nil : meta
        }
    }

    public static let notesMetaKey = "notes"

    /// The list a cached todo is in (#69): its identifier and name, kept in `meta` like the reminder's identifier.
    public static let listIDMetaKey = "list_id"
    public static let listNameMetaKey = "list_name"

    /// `ReminderList.id` of the todo's list; nil for anything that isn't a todo (or a todo cached before #69).
    public var listID: String? { meta?[Self.listIDMetaKey] }

    /// The name of the todo's list, as of the latest snapshot. `perch ls --json` carries it as `list`.
    public var listName: String? { meta?[Self.listNameMetaKey] }

    /// `listName`, or `ReminderList.untitled` without one: what headings show.
    public var listTitle: String { listName ?? ReminderList.untitled }
}

/// Open todos by list (#69), for the Todo tab, `perch ls` and todo.md alike.
public struct TodoGroup: Equatable, Sendable {
    /// Nil only without any known lists (a cache from before #69): then every todo is in this one group.
    public var list: ReminderList?
    /// Open todos, High → Normal → Low, then oldest first, then by id. Due dates never reorder (#53).
    public var items: [Item]

    public init(list: ReminderList?, items: [Item]) {
        self.list = list
        self.items = items
    }
}

extension Item {
    /// The order inside a list: priority, then creation time, then id.
    public static func todoOrder(_ a: Item, _ b: Item) -> Bool {
        if a.priority != b.priority { return a.priority.rank < b.priority.rank }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }
}

extension Sequence where Element == Item {
    /// The open todos (open tasks) grouped by list: one group per list in `lists`' order, empty ones included. A todo
    /// whose list isn't among them (the descriptors and the cache can be a moment apart) gets a group of its own after
    /// those, named as cached, unless `includingUnknown` is false (then it is left out). With no lists at all, one group
    /// holds every open todo (none when there are none).
    public func todoGroups(lists: [ReminderList], includingUnknown: Bool = true) -> [TodoGroup] {
        let open = filter { $0.kind == .task && $0.status == .open }.sorted(by: Item.todoOrder)
        guard !lists.isEmpty else { return open.isEmpty ? [] : [TodoGroup(list: nil, items: open)] }
        var groups = lists.map { TodoGroup(list: $0, items: []) }
        var index = ReminderList.positions(lists.map(\.id))
        for item in open {
            let id = item.listID ?? ""
            if index[id] == nil {
                guard includingUnknown else { continue }
                index[id] = groups.count
                groups.append(TodoGroup(list: ReminderList(id: id, title: item.listTitle, isICloud: true), items: []))
            }
            groups[index[id]!].items.append(item)
        }
        return groups
    }
}
