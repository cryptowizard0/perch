import Foundation
import PerchAppCore
import PerchCore

/// An in-memory Reminders database for the bridge tests (#51): never the real one. The `phone…` methods change it the
/// way another device would, then fire the change callback like EKEventStoreChanged. The app's own writes don't fire
/// it (unless `notifiesOwnWrites`), so the tests prove the bridge sends a snapshot after writing without waiting.
@MainActor
final class FakeRemindersStore: RemindersStore {
    /// A reminder with the fields Perch never manages, to check they survive its writes.
    struct Entry: Equatable {
        var reminder: Reminder
        var list: String
        var flagged = false
        var completedAt: Date?
        /// Absolute alarms.
        var alarms: [Date] = []
    }

    var authorization: RemindersAuthorization
    /// What the system prompt ends in.
    var grant: RemindersAuthorization = .fullAccess
    /// The default source for new reminders is iCloud.
    var defaultSourceIsICloud = true
    var notifiesOwnWrites = false
    /// How long reading the list takes: the bridge acks perchd's todo writes with its next read, so this delays acks.
    var readDelay: TimeInterval = 0
    /// Reading the list fails (writes still work).
    var readFails = false
    private(set) var allLists: [ReminderList] = []
    /// The lists the last snapshot read covered.
    private(set) var lastRead: [String] = []
    /// Lists `lists()` leaves out for now (they still exist): EventKit missing them for a moment.
    var hidden: Set<String> = []
    private(set) var entries: [Entry] = []
    private var observers: [@MainActor () -> Void] = []
    private var serial = 0

    /// The accounts lists are in: iCloud, and On My Mac.
    static let iCloud = "icloud-account"
    static let onMyMac = "local-account"

    /// `lists`: names of lists that already exist (in iCloud), in this order.
    init(authorization: RemindersAuthorization = .fullAccess, lists: [String] = ["Perch"]) {
        self.authorization = authorization
        for name in lists { allLists.append(ReminderList(id: nextID("list"), title: name, isICloud: true, account: Self.iCloud)) }
    }

    // MARK: RemindersStore

    func requestAccess() async -> RemindersAuthorization {
        if authorization == .notDetermined { authorization = grant }
        return authorization
    }

    func lists() -> [ReminderList] {
        authorization == .fullAccess ? allLists.filter { !hidden.contains($0.id) } : []
    }

    func createList(named name: String) throws -> ReminderList {
        let list = ReminderList(id: nextID("list"), title: name, isICloud: defaultSourceIsICloud,
                                account: defaultSourceIsICloud ? Self.iCloud : Self.onMyMac)
        allLists.append(list)
        ownWrite()
        return list
    }

    func reminders(inLists lists: [String], completedSince: Date) async throws -> [Reminder] {
        if readDelay > 0 { try await Task.sleep(nanoseconds: UInt64(readDelay * 1e9)) }
        if readFails { throw RemindersError("the database is busy") }
        guard authorization == .fullAccess else { throw RemindersError("no access to Reminders") }
        /// Read lists: the readers asked, each tagged; lists gone meanwhile are skipped.
        lastRead = lists
        return entries.filter { lists.contains($0.list) && (!$0.reminder.completed || ($0.completedAt ?? .distantPast) >= completedSince) }
            .map { var reminder = $0.reminder; reminder.list = $0.list; return reminder }
    }

    func createReminder(inList list: String, _ fields: ReminderChange) throws -> String {
        try readable(list)
        let id = nextID("rem")
        entries.append(Entry(reminder: Reminder(externalID: id, title: "", createdAt: Date()), list: list))
        apply(fields, to: entries.count - 1)
        ownWrite()
        return id
    }

    func containsReminder(_ externalID: String, inList list: String) -> Bool {
        entries.contains { $0.reminder.externalID == externalID && $0.list == list }
    }

    func localIdentifier(of externalID: String, inList list: String) -> String? {
        containsReminder(externalID, inList: list) ? "local-\(externalID)" : nil
    }

    func updateReminder(_ externalID: String, inList list: String, _ change: ReminderChange) throws {
        try readable(list)
        guard let i = entries.firstIndex(where: { $0.reminder.externalID == externalID && $0.list == list }) else {
            throw RemindersError("no reminder \(externalID)")
        }
        if let target = change.list, target != list {
            try readable(target)
            entries[i].list = target
        }
        apply(change, to: i)
        ownWrite()
    }

    private func apply(_ change: ReminderChange, to i: Int) {
        entries[i].alarms = change.alarms(entries[i].alarms, oldDue: entries[i].reminder.dueAt,
                                          oldDueDateOnly: entries[i].reminder.dueDateOnly)
        if let notes = change.notes { entries[i].reminder.notes = notes.isEmpty ? nil : notes }
        if let title = change.title { entries[i].reminder.title = title }
        if let priority = change.priority { entries[i].reminder.priority = priority }
        if let completed = change.completed {
            entries[i].reminder.completed = completed
            entries[i].completedAt = completed ? Date() : nil
        }
        if let due = change.dueAt {
            entries[i].reminder.dueAt = due
            entries[i].reminder.dueDateOnly = change.dueDateOnly ?? false
        }
        if change.clearDue == true {
            entries[i].reminder.dueAt = nil
            entries[i].reminder.dueDateOnly = false
        }
        if let url = change.url { entries[i].reminder.url = url }
        if change.clearURL == true { entries[i].reminder.url = nil }
    }

    func deleteReminder(_ externalID: String, inList list: String) throws {
        try readable(list)
        guard entries.contains(where: { $0.reminder.externalID == externalID && $0.list == list }) else {
            throw RemindersError("no reminder \(externalID)")
        }
        entries.removeAll { $0.reminder.externalID == externalID }
        ownWrite()
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    // MARK: The phone (and System Settings)

    @discardableResult
    func phoneAdd(_ title: String, priority: Int = 0, list name: String = "Perch", dueAt: Date? = nil, url: String? = nil,
                  notes: String? = nil, flagged: Bool = false, alarms: [Date] = [], completedAt: Date? = nil,
                  createdAt: Date = Date()) -> String {
        let id = nextID("rem")
        let list = allLists.first { $0.title == name }!.id
        let reminder = Reminder(externalID: id, title: title, priority: priority, completed: completedAt != nil, dueAt: dueAt,
                                url: url, notes: notes, createdAt: createdAt)
        entries.append(Entry(reminder: reminder, list: list, flagged: flagged, completedAt: completedAt, alarms: alarms))
        changed()
        return id
    }

    func phoneEdit(_ id: String, _ edit: (inout Entry) -> Void) {
        edit(&entries[entries.firstIndex { $0.reminder.externalID == id }!])
        changed()
    }

    func phoneComplete(_ id: String) {
        phoneEdit(id) {
            $0.reminder.completed = true
            $0.completedAt = Date()
        }
    }

    func phoneDelete(_ id: String) {
        entries.removeAll { $0.reminder.externalID == id }
        changed()
    }

    /// Moves a reminder to another list, as dragging it in the Reminders app does (the identifier stays).
    func phoneMove(_ id: String, to name: String) {
        phoneEdit(id) { $0.list = self.allLists.first { $0.title == name }!.id }
    }

    /// A list made on the phone (or in the Reminders app). `iCloud` false: on this Mac only (the On My Mac account).
    @discardableResult
    func phoneCreateList(_ name: String, iCloud: Bool = true) -> ReminderList {
        let list = ReminderList(id: nextID("list"), title: name, isICloud: iCloud, account: iCloud ? Self.iCloud : Self.onMyMac)
        allLists.append(list)
        changed()
        return list
    }

    /// The list moves out of iCloud (or back): it stays, but only on this Mac.
    func setICloud(_ name: String, _ iCloud: Bool) {
        allLists[allLists.firstIndex { $0.title == name }!].isICloud = iCloud
        changed()
    }

    func renameList(_ name: String, to new: String) {
        allLists[allLists.firstIndex { $0.title == name }!].title = new
        changed()
    }

    func deleteList(_ name: String) {
        guard let list = allLists.first(where: { $0.title == name }) else { return }
        allLists.removeAll { $0.id == list.id }
        entries.removeAll { $0.list == list.id }
        changed()
    }

    func setAuthorization(_ new: RemindersAuthorization) {
        authorization = new
        changed()
    }

    // MARK: Looking

    func entry(_ id: String) -> Entry? {
        entries.first { $0.reminder.externalID == id }
    }

    func entry(titled title: String) -> Entry? {
        entries.first { $0.reminder.title == title }
    }

    func list(_ name: String) -> ReminderList? {
        allLists.first { $0.title == name }
    }

    /// Fires the change callbacks, as EKEventStoreChanged does (asynchronously).
    func changed() {
        let observers = observers
        DispatchQueue.main.async { MainActor.assumeIsolated { observers.forEach { $0() } } }
    }

    private func ownWrite() {
        if notifiesOwnWrites { changed() }
    }

    private func readable(_ list: String) throws {
        guard authorization == .fullAccess else { throw RemindersError("no access to Reminders") }
        guard allLists.contains(where: { $0.id == list }) else { throw RemindersError("no list \(list)") }
    }

    private func nextID(_ prefix: String) -> String {
        serial += 1
        return "\(prefix)-\(serial)"
    }
}
