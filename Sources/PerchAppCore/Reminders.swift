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
    /// The incomplete reminders of these lists, plus those completed since `completedSince`, each with its `list`
    /// (#69). A list that is gone meanwhile is skipped; no lists, no reminders.
    func reminders(inLists lists: [String], completedSince: Date) async throws -> [Reminder]
    /// A new reminder with `fields` (`title` is set; unset ones stay EventKit's defaults); returns its external
    /// identifier.
    func createReminder(inList list: String, _ fields: ReminderChange) throws -> String
    /// Whether the reminder is still in the list.
    func containsReminder(_ externalID: String, inList list: String) -> Bool
    /// The reminder's identifier on this Mac (EventKit's `calendarItemIdentifier`), which the Reminders app's links
    /// use; nil when it isn't in the list.
    func localIdentifier(of externalID: String, inList list: String) -> String?
    /// Completing a repeating reminder does whatever EventKit does with it.
    func updateReminder(_ externalID: String, inList list: String, _ change: ReminderChange) throws
    func deleteReminder(_ externalID: String, inList list: String) throws
    /// `handler` runs whenever the Reminders database changes, here or on another device.
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
}

/// What the Todo tab shows, from the bridge app's side of Reminders. It describes the "Perch" list alone (#69): the
/// other checked lists never have a state of their own.
public enum RemindersState: Equatable, Sendable {
    /// Never asked: "Connect Reminders".
    case connect
    /// Denied or restricted: only the user can fix it, in System Settings.
    case openSettings
    /// Access, but the list is gone. Perch never recreates it without being asked.
    case createList
    /// The list is there. Not in iCloud: it works, but only on this Mac (its group says "Not syncing", #69).
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
}

/// Which Reminders lists the Todo tab and the CLI show, and in what order (#69). Kept in the bridge app's defaults,
/// keyed by `calendarIdentifier` (stable across renames) and namespaced by the "Perch" list's name, like the remembered
/// list, so isolated runs ("Perch Dev") keep their own:
///
/// - `RemindersOrder.<name>`: every known list's identifier, in order (an array of strings);
/// - `RemindersChecked.<name>`: the checked lists' identifiers (an array of strings; order doesn't matter).
///
/// "Perch" is always checked, wherever it is in the order. Lists not known yet go at the end, unchecked. Lists that
/// don't exist now are left out but never forgotten: EventKit can miss a list for a moment (an iCloud blip, sources
/// still loading at launch), and one that comes back is checked again, in its old place. Until the Lists… window
/// (#70), only `defaults write dev.perch.app …` changes it.
@MainActor
public struct ListSelection {
    public let defaults: UserDefaults
    /// The "Perch" list's name, which namespaces the keys.
    public let listName: String

    public init(defaults: UserDefaults, listName: String) {
        self.defaults = defaults
        self.listName = listName
    }

    public static func orderKey(listName: String) -> String { "RemindersOrder.\(listName)" }
    public static func checkedKey(listName: String) -> String { "RemindersChecked.\(listName)" }

    /// Every known list's identifier, in order, as stored.
    public var order: [String] {
        get { defaults.stringArray(forKey: Self.orderKey(listName: listName)) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.orderKey(listName: listName)) }
    }

    /// The checked lists' identifiers, as stored ("Perch" is added when resolving).
    public var checked: [String] {
        get { defaults.stringArray(forKey: Self.checkedKey(listName: listName)) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.checkedKey(listName: listName)) }
    }

    /// Checks or unchecks a list (the Lists… window will call this). Unchecking "Perch" has no effect: `resolve`
    /// checks it again.
    public func setChecked(_ id: String, _ isChecked: Bool) {
        var ids = checked.filter { $0 != id }
        if isChecked { ids.append(id) }
        checked = ids
    }

    /// Adds the lists in `lists` (every list there is now) that the stored selection doesn't know yet, checks "Perch"
    /// (`perch`; nil while it is gone), and returns the checked lists that exist, in order. Nothing is ever removed
    /// from the stored selection; only what changed is written back.
    @discardableResult
    public func resolve(lists: [ReminderList], perch: ReminderList?) -> [ReminderList] {
        var newOrder = order
        var seen = Set(newOrder)
        for list in lists where seen.insert(list.id).inserted { newOrder.append(list.id) }
        var newChecked = checked
        if let perch, !newChecked.contains(perch.id) { newChecked.append(perch.id) }
        if newOrder != order { order = newOrder }
        if newChecked != checked { checked = newChecked }
        let byID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let isChecked = Set(newChecked)
        return newOrder.filter { isChecked.contains($0) }.compactMap { byID[$0] }
    }
}

/// The bridge app's hold on Reminders: authorization, finding the "Perch" list, the other checked lists (#69), and
/// every write Perch makes to them. `QueueModel` owns it and tells perchd what the checked lists hold.
@MainActor
public final class RemindersBridge {
    public let store: RemindersStore
    /// "Perch", or "Perch Dev" for isolated runs.
    public let listName: String
    public private(set) var state: RemindersState = .connect
    /// The "Perch" list (nil while there's no access, or it is gone).
    public private(set) var list: ReminderList?
    /// The checked lists that exist, in order ("Perch" among them while it exists); empty without access.
    public private(set) var checkedLists: [ReminderList] = []
    public let selection: ListSelection
    private let defaults: UserDefaults

    /// Done reminders stay in the snapshot this long (`perch ls --status done`, reopening).
    public static let completedWindow: TimeInterval = 7 * 86_400

    /// `defaults` remembers the list's identifier, so a renamed list is still found, and the list selection.
    public init(store: RemindersStore, listName: String, defaults: UserDefaults = .standard) {
        self.store = store
        self.listName = listName
        self.defaults = defaults
        selection = ListSelection(defaults: defaults, listName: listName)
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
    /// created, since getting access is how the user asked for it. Then the selection: which lists are checked.
    public func refresh() {
        switch store.authorization {
        case .notDetermined: return settle(.connect)
        case .denied, .restricted: return settle(.openSettings)
        case .fullAccess: break
        }
        let lists = store.lists()
        if let found = lists.first(where: { $0.id == remembered })
            ?? lists.filter({ $0.title == listName }).sorted(by: { $0.isICloud && !$1.isICloud }).first {
            return adopt(found, among: lists)
        }
        guard remembered == nil else { return settle(.createList, lists: lists) }
        do {
            let created = try store.createList(named: listName)
            adopt(created, among: lists + [created])
        } catch {
            settle(.createList, lists: lists)
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
        let created = try store.createList(named: listName)
        adopt(created, among: store.lists())
    }

    /// What perchd caches: the checked lists, and their incomplete reminders and those done in the last week. While
    /// "Perch" is gone, the other checked lists still count. Nothing without access.
    public func snapshot(now: Date = Date()) async throws -> (lists: [ReminderList], reminders: [Reminder]) {
        let lists = checkedLists
        guard !lists.isEmpty else { return ([], []) }
        let since = now.addingTimeInterval(-Self.completedWindow)
        return (lists, try await store.reminders(inLists: lists.map(\.id), completedSince: since))
    }

    /// A new todo from the add popup: it goes to "Perch".
    public func add(title: String, priority: ItemPriority) throws {
        _ = try store.createReminder(inList: try readyList().id, ReminderChange(title: title, priority: priority.reminderPriority))
    }

    /// A todo write perchd handed over (from the CLI, inbox.md or another app, #52). New reminders go to "Perch";
    /// changes go to the list the reminder is in (#69). Returns the reminder it made or changed.
    public func apply(_ operation: TodoOperation) throws -> String {
        switch operation.action {
        case .create:
            guard operation.change.title?.isEmpty == false else { throw RemindersError("a new todo needs a title") }
            return try store.createReminder(inList: try readyList().id, operation.change)
        case .upsert:
            if let reminder = operation.externalID, let list = try? listOf(reminder, hint: operation.seenInList) {
                try store.updateReminder(reminder, inList: list.id, operation.change)
                return reminder
            }
            return try apply(TodoOperation(id: operation.id, action: .create, change: operation.change))
        case .update, .delete:
            guard let reminder = operation.externalID else { throw RemindersError("no reminder given") }
            let list = try listOf(reminder, hint: operation.seenInList)
            if operation.action == .delete {
                try store.deleteReminder(reminder, inList: list.id)
            } else {
                try store.updateReminder(reminder, inList: list.id, operation.change)
            }
            return reminder
        }
    }

    /// Changes only what is given: the title and priority Perch shows, or completion.
    public func update(_ item: Item, title: String? = nil, priority: ItemPriority? = nil, completed: Bool? = nil) throws {
        try update(item, ReminderChange(title: title, priority: priority?.reminderPriority, completed: completed))
    }

    /// The larger editor's save (#53): exactly `change`, nothing else, in the todo's own list.
    public func update(_ item: Item, _ change: ReminderChange) throws {
        guard !change.isEmpty else { return }
        let (reminder, list) = try locate(item)
        try store.updateReminder(reminder, inList: list.id, change)
    }

    /// ✎ (#53): the Reminders app's link to this reminder, which opens Reminders on its list (checked on macOS 15, see
    /// #50). Nil when it can't be found (no access, not in a checked list): then just open Reminders.
    public func link(for item: Item) -> URL? {
        guard let (reminder, list) = try? locate(item),
              let local = store.localIdentifier(of: reminder, inList: list.id) else { return nil }
        return URL(string: "x-apple-reminderkit://REMCDReminder/\(local)")
    }

    public func delete(_ item: Item) throws {
        let (reminder, list) = try locate(item)
        try store.deleteReminder(reminder, inList: list.id)
    }

    private func requireAccess() throws {
        if state == .connect || state == .openSettings { throw RemindersError("Perch.app doesn't have access to Reminders") }
    }

    /// Where new todos go: "Perch".
    private func readyList() throws -> ReminderList {
        try requireAccess()
        guard state.isReady, let list else { throw RemindersError("\(listName) list not found") }
        return list
    }

    /// The todo's reminder, and the checked list it is in now.
    private func locate(_ item: Item) throws -> (reminder: String, list: ReminderList) {
        let reminder = try reminderID(item)
        return (reminder, try listOf(reminder, hint: item.listID))
    }

    /// The checked list the reminder is in: `hint` (where perchd last saw it) first, then the others, since it may
    /// have moved between checked lists since. Moved to a list that isn't checked, it is out of Perch's reach.
    private func listOf(_ reminder: String, hint: String?) throws -> ReminderList {
        try requireAccess()
        let candidates = checkedLists.filter { $0.id == hint } + checkedLists.filter { $0.id != hint }
        guard let list = candidates.first(where: { store.containsReminder(reminder, inList: $0.id) }) else {
            throw RemindersError("that reminder isn't in a list Perch shows")
        }
        return list
    }

    private func reminderID(_ item: Item) throws -> String {
        guard let id = item.reminderID else { throw RemindersError("\(item.id) is not a reminder") }
        return id
    }

    private func adopt(_ found: ReminderList, among lists: [ReminderList]) {
        if remembered != found.id { remembered = found.id }
        list = found
        state = .ready(iCloud: found.isICloud)
        checkedLists = selection.resolve(lists: lists, perch: found)
    }

    /// `lists`: with access but without "Perch", the other checked lists still count.
    private func settle(_ new: RemindersState, lists: [ReminderList] = []) {
        list = nil
        state = new
        checkedLists = new == .createList ? selection.resolve(lists: lists, perch: nil) : []
    }
}
