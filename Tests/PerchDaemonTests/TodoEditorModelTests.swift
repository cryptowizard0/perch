import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The entry popup through QueueModel against a real perchd (#43), as the Reminders bridge (#51): add, edit, delete,
/// the highlight. What it writes lands in the (fake) Reminders list.
@MainActor
@Suite struct TodoEditorModelTests {
    func until(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        try await RemindersBridgeTests().until(timeout: timeout, condition)
    }

    func connected(_ d: TestDaemon, _ store: FakeRemindersStore) async throws -> QueueModel {
        try await RemindersBridgeTests().bridge(d, store)
    }

    /// A todo from the phone, once the tab shows it.
    func phoneAdd(_ model: QueueModel, _ store: FakeRemindersStore, _ title: String, priority: Int = 0) async throws -> Item {
        let id = store.phoneAdd(title, priority: priority)
        try await until { model.todos.items.contains { $0.reminderID == id } }
        return try #require(model.todos.items.first { $0.reminderID == id })
    }

    @Test func returnAddsAndTheEditorStaysOpenEmptyOnNormal() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.openAdd(fromPanel: false)
        #expect(model.editor == .add(fromPanel: false))

        model.editor?.title = "Renew the domain"
        model.cycleEditorPriority(forward: false)  // Normal → High
        #expect(model.submitEditor())
        #expect(model.editor == .add(fromPanel: false))
        model.editor?.title = "Book flights"
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 2 }
        #expect(Set(store.entries.map(\.reminder.title)) == ["Renew the domain", "Book flights"])
        #expect(store.entry(titled: "Renew the domain")?.reminder.priority == 1)
        #expect(store.entry(titled: "Book flights")?.reminder.priority == 0)
        #expect(model.todos.items.map(\.priority) == [.high, .normal])
    }

    @Test func whatYouTypeIsTheTitleExactly() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.openAdd(fromPanel: false)
        model.editor?.title = "  Call Lin @15:00 !h  "
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 1 }
        let item = try #require(store.entries.first?.reminder)
        #expect(item.title == "Call Lin @15:00 !h" && item.priority == 0 && item.dueAt == nil)
    }

    @Test func blankInputAddsNothing() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.openAdd(fromPanel: true)
        model.editor?.title = "   "
        #expect(!model.submitEditor())
        #expect(model.editor?.title == "   ")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.entries.isEmpty)
    }

    @Test func escapeClosesWithoutAChange() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        let item = try await phoneAdd(model, store, "x")
        let before = store.entries
        model.openEdit(item)
        model.editor?.title = "changed"
        model.cycleEditorPriority(forward: true)
        model.closeEditor()
        #expect(model.editor == nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.entries == before)
    }

    @Test func returnInEditSavesTitleAndPriorityAndCloses() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        let item = try await phoneAdd(model, store, "Call Lin", priority: 9)
        model.openEdit(item)
        #expect(model.editor == .edit(item))
        model.editor?.title = " Call Lin back "
        model.cycleEditorPriority(forward: true)  // Low → High
        #expect(model.submitEditor())
        #expect(model.editor == nil)
        try await until { model.state.items[item.id]?.title == "Call Lin back" }
        #expect(model.todos.items.first?.priority == .high)
        #expect(store.entry(try #require(item.reminderID))?.reminder.priority == 1)
        #expect(store.entry(try #require(item.reminderID))?.reminder.title == "Call Lin back")
    }

    @Test func anEditedTodoThatGoesAwayClosesTheEditor() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        let item = try await phoneAdd(model, store, "x")
        model.openEdit(item)
        store.phoneComplete(try #require(item.reminderID))
        try await until { model.editor == nil }
    }

    @Test func deleteRemovesTheTodoAtOnce() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        let item = try await phoneAdd(model, store, "x")
        model.delete(item)
        try await until { model.todos.openCount == 0 }
        #expect(store.entries.isEmpty)
        #expect(try d.client.send(Request(op: .list, filter: Request.Filter(all: true))).items == [])
    }

    @Test func aTodoAddedWhileThePanelIsOpenHighlightsBriefly() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.highlightDuration = 0.3
        // Collapsed: no highlight.
        let quiet = try await phoneAdd(model, store, "quiet")
        #expect(model.highlighted.isEmpty)

        model.expanded = true
        model.openAdd(fromPanel: true)
        model.editor?.title = "new"
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 2 }
        let new = try #require(model.todos.items.first { $0.id != quiet.id })
        #expect(model.highlighted == [new.id])
        // Edits, re-ranks and notices don't highlight.
        model.setPriority(try #require(model.state.items[quiet.id]), .high)
        _ = try d.client.send(Request(op: .add, item: Item(title: "fyi", kind: .notice)))
        try await until { model.todos.items.first?.priority == .high && model.state.items.count == 3 }
        #expect(model.highlighted == [new.id])
        try await until { model.highlighted.isEmpty }
    }
}
