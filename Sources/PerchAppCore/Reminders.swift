import Foundation
import PerchCore

/// Whether Perch may read and write Reminders.
public enum RemindersAuthorization: Equatable, Sendable {
    case notDetermined
    /// Denied, or write-only (Perch can't read the list then either).
    case denied
    case restricted
    case fullAccess
}

/// A Reminders list.
public struct ReminderList: Equatable, Sendable {
    /// EventKit's `calendarIdentifier`: stable across renames on this Mac.
    public var id: String
    public var title: String
    /// In the iCloud account, so it reaches the phone.
    public var isICloud: Bool

    public init(id: String, title: String, isICloud: Bool) {
        self.id = id
        self.title = title
        self.isICloud = isICloud
    }
}

/// What Perch changes on a reminder. Unset fields stay as they are, and so does everything Perch doesn't manage
/// (notes, dates, URL, alarms, repeat rules, subtasks, flags, tags, images).
public struct ReminderChange: Equatable, Sendable {
    public var title: String?
    /// EventKit's 0–9 (`ItemPriority.reminderPriority`).
    public var priority: Int?
    public var completed: Bool?

    public init(title: String? = nil, priority: Int? = nil, completed: Bool? = nil) {
        self.title = title
        self.priority = priority
        self.completed = completed
    }
}

public struct RemindersError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// The only seam to EventKit (#51). The app's implementation stays thin; tests use an in-memory fake that stands in
/// for the phone. Main actor only, like the model that drives it.
@MainActor
public protocol RemindersStore: AnyObject {
    var authorization: RemindersAuthorization { get }
    /// Shows the system prompt when not determined yet; the authorization afterwards.
    func requestAccess() async -> RemindersAuthorization
    /// Every Reminders list.
    func lists() -> [ReminderList]
    /// A new list in the default source for new reminders.
    func createList(named name: String) throws -> ReminderList
    /// The list's incomplete reminders, plus those completed since `completedSince`.
    func reminders(inList list: String, completedSince: Date) async throws -> [Reminder]
    /// A new incomplete reminder; returns its external identifier.
    func createReminder(inList list: String, title: String, priority: Int) throws -> String
    /// Completing a repeating reminder does whatever EventKit does with it.
    func updateReminder(_ externalID: String, inList list: String, _ change: ReminderChange) throws
    func deleteReminder(_ externalID: String, inList list: String) throws
    /// `handler` runs whenever the Reminders database changes, here or on another device.
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
}

/// What the Todo tab shows, from the bridge app's side of Reminders.
public enum RemindersState: Equatable, Sendable {
    /// Never asked: "Connect Reminders".
    case connect
    /// Denied or restricted: only the user can fix it, in System Settings.
    case openSettings
    /// Access, but the list is gone. Perch never recreates it without being asked.
    case createList
    /// The list is there. Not in iCloud: it works, but only on this Mac.
    case ready(iCloud: Bool)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The line above the button (nil when ready).
    public func message(listName: String) -> String? {
        switch self {
        case .connect: return "Todos live in the \u{201C}\(listName)\u{201D} list in Reminders, on all your devices."
        case .openSettings: return "Perch doesn't have access to Reminders."
        case .createList: return "The \u{201C}\(listName)\u{201D} list in Reminders is gone."
        case .ready: return nil
        }
    }

    /// The one button the tab shows instead of todos (nil when ready).
    public func button(listName: String) -> String? {
        switch self {
        case .connect: return "Connect Reminders"
        case .openSettings: return "Open System Settings"
        case .createList: return "Create \(listName) list"
        case .ready: return nil
        }
    }

    /// The gray note next to the summary while ready.
    public var note: String? {
        self == .ready(iCloud: false) ? "Not syncing \u{2014} no iCloud" : nil
    }
}

/// The bridge app's hold on the "Perch" list: authorization, finding the list, and every write Perch makes to it.
/// `QueueModel` owns it and tells perchd what the list holds.
@MainActor
public final class RemindersBridge {
    public let store: RemindersStore
    /// "Perch", or "Perch Dev" for isolated runs.
    public let listName: String
    public private(set) var state: RemindersState = .connect
    public private(set) var list: ReminderList?
    private let defaults: UserDefaults

    /// Done reminders stay in the snapshot this long (`perch ls --status done`, reopening).
    public static let completedWindow: TimeInterval = 7 * 86_400

    /// `defaults` remembers the list's identifier, so a renamed list is still found.
    public init(store: RemindersStore, listName: String, defaults: UserDefaults = .standard) {
        self.store = store
        self.listName = listName
        self.defaults = defaults
        refresh()
    }

    /// Isolated runs (`PERCH_HOME` set) use their own list, so testing never touches real todos.
    public static func listName(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        (environment["PERCH_HOME"] ?? "").isEmpty ? "Perch" : "Perch Dev"
    }

    private var rememberedKey: String { "RemindersList.\(listName)" }

    private var remembered: String? {
        get { defaults.string(forKey: rememberedKey) }
        set { defaults.set(newValue, forKey: rememberedKey) }
    }

    /// Reads the authorization again and looks for the list: by its remembered identifier, then by name (iCloud
    /// first). A list that was found before and is gone now stays gone (`createList`); one never found before is
    /// created, since getting access is how the user asked for it.
    public func refresh() {
        switch store.authorization {
        case .notDetermined: return settle(.connect)
        case .denied, .restricted: return settle(.openSettings)
        case .fullAccess: break
        }
        let lists = store.lists()
        if let found = lists.first(where: { $0.id == remembered })
            ?? lists.filter({ $0.title == listName }).sorted(by: { $0.isICloud && !$1.isICloud }).first {
            return adopt(found)
        }
        guard remembered == nil else { return settle(.createList) }
        do {
            adopt(try store.createList(named: listName))
        } catch {
            settle(.createList)
        }
    }

    /// "Connect Reminders": the system prompt, then the list (found or created).
    public func connect() async {
        _ = await store.requestAccess()
        refresh()
    }

    /// "Create Perch list", after the old one was deleted.
    public func createList() throws {
        guard store.authorization == .fullAccess else { throw RemindersError("Perch doesn't have access to Reminders") }
        adopt(try store.createList(named: listName))
    }

    /// What perchd caches: the list's incomplete reminders and those done in the last week. Nothing when the list is
    /// gone (its todos went with it).
    public func snapshot(now: Date = Date()) async throws -> [Reminder] {
        guard let list else { return [] }
        return try await store.reminders(inList: list.id, completedSince: now.addingTimeInterval(-Self.completedWindow))
    }

    /// A new todo from the add popup.
    public func add(title: String, priority: ItemPriority) throws {
        _ = try store.createReminder(inList: try readyList().id, title: title, priority: priority.reminderPriority)
    }

    /// Changes only what is given: the title and priority Perch shows, or completion.
    public func update(_ item: Item, title: String? = nil, priority: ItemPriority? = nil, completed: Bool? = nil) throws {
        let change = ReminderChange(title: title, priority: priority?.reminderPriority, completed: completed)
        try store.updateReminder(try reminderID(item), inList: try readyList().id, change)
    }

    public func delete(_ item: Item) throws {
        try store.deleteReminder(try reminderID(item), inList: try readyList().id)
    }

    private func readyList() throws -> ReminderList {
        guard state.isReady, let list else { throw RemindersError("The \u{201C}\(listName)\u{201D} list in Reminders is gone") }
        return list
    }

    private func reminderID(_ item: Item) throws -> String {
        guard let id = item.reminderID else { throw RemindersError("\(item.id) is not a reminder") }
        return id
    }

    private func adopt(_ found: ReminderList) {
        if remembered != found.id { remembered = found.id }
        list = found
        state = .ready(iCloud: found.isICloud)
    }

    private func settle(_ new: RemindersState) {
        list = nil
        state = new
    }
}
