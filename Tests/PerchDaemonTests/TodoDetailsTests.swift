import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The Todo tab's details (#53): the larger editor (title, notes, date, time, priority, URL), ✎ to Reminders, and the
/// alarm a time brings. A real perchd, the notch app's model as the bridge, a fake Reminders database.
@MainActor
@Suite struct TodoDetailsTests {
    let support = RemindersBridgeTests()

    func todo(_ model: QueueModel, _ store: FakeRemindersStore, _ external: String) async throws -> Item {
        try await support.until { model.todos.items.contains { $0.reminderID == external } }
        return try #require(model.todos.items.first { $0.reminderID == external })
    }

    @Test func theEditorSavesEveryFieldAndLeavesTheRestAlone() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let custom = Date(timeIntervalSince1970: 1_950_000_000)
        let id = store.phoneAdd("Call Lin", priority: 9, notes: "ask about Friday", flagged: true, alarms: [custom])
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        let item = try await todo(model, store, id)
        #expect(item.notes == "ask about Friday")
        let original = try #require(store.entry(id))

        model.openEdit(item)
        #expect(model.editor?.notes == "ask about Friday" && model.editor?.isLarge == true)
        model.editor?.title = "Call Lin back"
        model.editor?.notes = "ask about Friday\nand the deck"
        model.editor?.setHasDate(true, now: Date(), calendar: .current)
        model.editor?.setHasTime(true, now: Date(), calendar: .current)
        let due = try #require(model.editor?.date)
        model.editor?.url = "https://deck.example"
        model.editor?.priority = .high
        #expect(model.submitEditor())
        #expect(model.editor == nil)

        try await support.until { model.todos.items.first?.title == "Call Lin back" }
        let after = try #require(store.entry(id))
        #expect(after.reminder.title == "Call Lin back" && after.reminder.priority == 1)
        #expect(after.reminder.notes == "ask about Friday\nand the deck" && after.reminder.url == "https://deck.example")
        #expect(after.reminder.dueAt == Service.wholeSeconds(due) && !after.reminder.dueDateOnly)
        // A time notifies like one set in Reminders: an alarm at that time, next to the one already there.
        #expect(after.alarms == [custom, Service.wholeSeconds(due)])
        // What Perch doesn't manage is untouched.
        #expect(after.flagged && after.list == original.list && after.reminder.createdAt == original.reminder.createdAt)
        #expect(after.reminder.completed == false)
        let shown = try #require(model.todos.items.first)
        #expect(shown.notes == "ask about Friday\nand the deck" && shown.link == "https://deck.example" && shown.priority == .high)

        // Back to a whole day: the time's alarm goes, the other stays.
        model.openEdit(shown)
        model.editor?.setHasTime(false, now: Date(), calendar: .current)
        #expect(model.submitEditor())
        try await support.until { store.entry(id)?.reminder.dueDateOnly == true }
        #expect(store.entry(id)?.alarms == [custom])
    }

    @Test func escapeChangesNothing() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let id = store.phoneAdd("Call Lin", notes: "keep")
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        let item = try await todo(model, store, id)
        let before = store.entries

        model.openEdit(item)
        model.editor?.title = "changed"
        model.editor?.notes = "changed"
        model.editor?.url = "https://changed.example"
        model.closeEditor()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(model.editor == nil && store.entries == before)
    }

    /// A plain app (not the bridge) edits through perchd, which hands it to the bridge.
    @Test func aPlainAppsEditorReachesTheStore() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let id = store.phoneAdd("Call Lin", url: "https://old.example")
        let bridge = try await support.bridge(d, store)
        defer { bridge.disconnect() }
        let (plain, _) = support.app(d, store)
        defer { plain.disconnect() }
        let item = try await todo(plain, store, id)
        #expect(!plain.isBridge)

        plain.openEdit(item)
        plain.editor?.notes = "from the other app"
        plain.editor?.url = ""
        plain.editor?.setHasDate(true, now: Date(), calendar: .current)
        #expect(plain.submitEditor())
        try await support.until { store.entry(id)?.reminder.notes == "from the other app" }
        let after = try #require(store.entry(id))
        #expect(after.reminder.url == nil && after.reminder.dueDateOnly && after.reminder.dueAt != nil)
        #expect(plain.flash == nil)
    }

    /// A double-click on a row does nothing more than its first click; a later click is Undo.
    @Test func aDoubleClickIsOneClick() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let id = store.phoneAdd("Call Lin")
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        model.doubleClickInterval = 0.3
        model.completionDelay = 5
        let item = try await todo(model, store, id)
        model.toggleCompletion(item)
        model.toggleCompletion(item)
        #expect(model.completing == [item.id])
        try await Task.sleep(nanoseconds: 400_000_000)
        model.toggleCompletion(item)
        #expect(model.completing.isEmpty)
    }

    /// ✎: the reminder in the Reminders app, by its local identifier; without access to it, just Reminders.
    @Test func thePencilOpensTheReminder() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let id = store.phoneAdd("Call Lin")
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        var opened: [URL?] = []
        model.openReminder = { opened.append($0) }
        let item = try await todo(model, store, id)

        model.openInReminders(item)
        #expect(opened == [URL(string: "x-apple-reminderkit://REMCDReminder/\(store.localIdentifier(of: id, inList: store.list("Perch")!.id)!)")])
        store.phoneDelete(id)
        model.openInReminders(item)
        #expect(opened.last == .some(nil))
    }

    /// `perch add --due @HH:MM`: the CLI's time brings the same alarm.
    @Test(.enabled(if: CLI.binary != nil, "perch binary not built"))
    func aTimeFromTheCLINotifiesToo() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        let cli = CLI(home: d.home)
        let added = try await Task.detached { try cli.run("add", "Stand-up", "--due", "2030-11-03T09:30:00Z", "--json") }.value
        let due = try #require(added.json.item?.dueAt)
        #expect(store.entry(titled: "Stand-up")?.alarms == [due])
        _ = try await Task.detached { try cli.run("add", "Dentist", "--due", "2030-11-03") }.value
        #expect(store.entry(titled: "Dentist")?.alarms == [])
    }
}
