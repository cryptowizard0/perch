import EventKit
import PerchAppCore
import PerchCore

/// `RemindersStore` on EventKit (#51), as thin as it can be: the logic is in `RemindersBridge` and `QueueModel`.
/// Perch.app is the only part of Perch that can get Reminders access (perchd, started by launchd, can't).
@MainActor
final class EventKitRemindersStore: RemindersStore {
    private var store = EKEventStore()
    /// The authorization `store` was made under: one made before access was granted doesn't see the lists, whether
    /// access came from the prompt or from System Settings.
    private var madeUnder: RemindersAuthorization
    private var observers: [@MainActor () -> Void] = []
    private var changes: NSObjectProtocol?

    init() {
        madeUnder = .notDetermined
        madeUnder = authorization
        watch()
    }

    var authorization: RemindersAuthorization {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .fullAccess: return .fullAccess
        default: return .denied  // denied, or write-only (no reading)
        }
    }

    func requestAccess() async -> RemindersAuthorization {
        _ = try? await store.requestFullAccessToReminders()
        return authorization
    }

    func lists() -> [ReminderList] {
        renewIfAuthorizationChanged()
        return store.calendars(for: .reminder).map(Self.list)
    }

    func createList(named name: String) throws -> ReminderList {
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: Self.isICloud)
            ?? store.sources.first(where: { $0.sourceType == .local })
        else { throw RemindersError("there is no Reminders account to create the list in") }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return Self.list(calendar)
    }

    func reminders(inList list: String, completedSince: Date) async throws -> [Reminder] {
        let calendars = [try calendar(list)]
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: completedSince, ending: nil, calendars: calendars)
        return await fetch(open) + fetch(done)
    }

    func createReminder(inList list: String, title: String, priority: Int) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = try calendar(list)
        reminder.title = title
        reminder.priority = priority
        try store.save(reminder, commit: true)
        return reminder.calendarItemExternalIdentifier
    }

    func updateReminder(_ externalID: String, inList list: String, _ change: ReminderChange) throws {
        let reminder = try self.reminder(externalID, inList: list)
        if let title = change.title { reminder.title = title }
        if let priority = change.priority { reminder.priority = priority }
        if let completed = change.completed { reminder.isCompleted = completed }
        try store.save(reminder, commit: true)
    }

    func deleteReminder(_ externalID: String, inList list: String) throws {
        try store.remove(try reminder(externalID, inList: list), commit: true)
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    // MARK: -

    private func renewIfAuthorizationChanged() {
        let now = authorization
        guard now != madeUnder else { return }
        madeUnder = now
        store = EKEventStore()
        watch()
    }

    private func watch() {
        if let changes { NotificationCenter.default.removeObserver(changes) }
        changes = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.observers.forEach { $0() } }
        }
    }

    private func calendar(_ id: String) throws -> EKCalendar {
        guard let calendar = store.calendar(withIdentifier: id) else { throw RemindersError("the Reminders list is gone") }
        return calendar
    }

    private func reminder(_ externalID: String, inList list: String) throws -> EKReminder {
        let found = store.calendarItems(withExternalIdentifier: externalID)
            .compactMap { $0 as? EKReminder }
            .first { $0.calendar?.calendarIdentifier == list }
        guard let found else { throw RemindersError("that reminder is gone") }
        return found
    }

    private func fetch(_ predicate: NSPredicate) async -> [Reminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.reminder))
            }
        }
    }

    private nonisolated static func reminder(_ r: EKReminder) -> Reminder {
        Reminder(
            externalID: r.calendarItemExternalIdentifier ?? r.calendarItemIdentifier,
            title: r.title ?? "",
            priority: r.priority,
            completed: r.isCompleted,
            dueAt: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            url: r.url?.absoluteString,
            createdAt: r.creationDate
        )
    }

    private static func list(_ calendar: EKCalendar) -> ReminderList {
        ReminderList(id: calendar.calendarIdentifier, title: calendar.title, isICloud: isICloud(calendar.source))
    }

    private static func isICloud(_ source: EKSource?) -> Bool {
        source?.sourceType == .calDAV && source?.title == "iCloud"
    }
}
