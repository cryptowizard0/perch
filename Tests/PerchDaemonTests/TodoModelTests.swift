import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The Todo tab's model (#42), as the Reminders bridge (#51): QueueModel driven by a real perchd and a fake
/// Reminders database, where `add` stands in for the phone.
@MainActor
@Suite struct TodoModelTests {
    func until(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        try await RemindersBridgeTests().until(timeout: timeout, condition)
    }

    func connected(_ d: TestDaemon, _ store: FakeRemindersStore) async throws -> QueueModel {
        try await RemindersBridgeTests().bridge(d, store)
    }

    /// A reminder added on the phone, a second older than the next one (todos are ordered by creation), once the
    /// tab shows it.
    @discardableResult
    func add(_ model: QueueModel, _ store: FakeRemindersStore, _ title: String, _ priority: ItemPriority = .normal) async throws -> Item {
        let before = model.todos.openCount
        let created = Date(timeIntervalSince1970: 1_800_000_000 + Double(store.entries.count))
        let id = store.phoneAdd(title, priority: priority.reminderPriority, createdAt: created)
        try await until { model.todos.openCount > before }
        return try #require(model.todos.items.first { $0.reminderID == id })
    }

    func report(_ d: TestDaemon, _ id: String, _ kind: SessionReport.Kind) throws {
        let r = try d.client.send(Request(op: .sessionReport, report: SessionReport(
            id: id, kind: kind, at: Date(), source: "claude-code", title: id, prompt: kind == .prompt ? "go" : nil,
            detail: kind == .waiting ? "rm -rf build/" : nil)))
        #expect(r.ok)
    }

    @Test func openTodosAreSortedByPriorityThenOldestFirst() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        #expect(model.todos.summary == "All clear")
        // "Perch" is there before it holds anything (#69).
        try await until { model.todos.groups.map(\.title) == ["Perch"] }
        #expect(model.todos.groups.map(\.openCount) == [0])

        let low = try await add(model, store, "read the doc", .low)
        let first = try await add(model, store, "reply to Sam")
        let high = try await add(model, store, "renew the domain", .high)
        let second = try await add(model, store, "book flights")
        // Agents' items never join the Todo tab.
        _ = try d.client.send(Request(op: .add, item: Item(title: "codex finished", kind: .notice)))
        _ = try d.client.send(Request(op: .add, item: Item(title: "npm test", kind: .request)))
        _ = try d.client.send(Request(op: .add, item: Item(title: "approve in Telegram", status: .waiting, source: "hermes")))
        try await until { model.state.items.count == 7 }
        // One group per list: no High / Normal / Low headers any more.
        #expect(model.todos.groups.map(\.title) == ["Perch"])
        #expect(model.todos.items.map(\.id) == [high.id, first.id, second.id, low.id])
        #expect(model.todos.summary == "4 open · 1 high")

        for item in [low, first, high, second] { store.phoneComplete(try #require(item.reminderID)) }
        try await until { model.todos.openCount == 0 }
        #expect(model.todos.summary == "All clear")
    }

    @Test func reRankingMovesATodoWithinItsList() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        let older = try await add(model, store, "older")
        let item = try await add(model, store, "x")
        let newest = try await add(model, store, "newest", .high)

        // From the phone.
        store.phoneEdit(try #require(item.reminderID)) { $0.reminder.priority = 9 }
        try await until { model.todos.items.last?.id == item.id }
        #expect(model.todos.items.map(\.id) == [newest.id, older.id, item.id])

        // From the right-click menu: back to High, before the newer High todo (it is older).
        model.setPriority(try #require(model.state.items[item.id]), .high)
        try await until { model.todos.items.first?.id == item.id }
        #expect(model.todos.items.map(\.id) == [item.id, newest.id, older.id])
        #expect(store.entry(try #require(item.reminderID))?.reminder.priority == 1)
    }

    @Test func undoWithinTheDelayLeavesTheTodoOpen() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.completionDelay = 0.3
        let item = try await add(model, store, "x")
        let stream = try d.client.watch()

        model.toggleCompletion(item)
        #expect(model.completing == [item.id])
        model.undoCompletion(item.id)
        #expect(model.completing.isEmpty)
        // Clicking the circle again cancels too.
        model.toggleCompletion(item)
        model.toggleCompletion(item)
        #expect(model.completing.isEmpty)

        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(model.todos.items.map(\.id) == [item.id])
        #expect(store.entry(try #require(item.reminderID))?.reminder.completed == false)
        // Nothing was written: nothing changed at all.
        #expect(throws: ClientError.self) { try stream.next(timeout: 0.1) }
    }

    @Test func aCompletionCommitsAfterTheDelayEvenCollapsed() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.completionDelay = 0.3
        model.expanded = true
        let item = try await add(model, store, "x")
        let other = try await add(model, store, "y")

        model.toggleCompletion(item)
        model.expanded = false
        // Still crossed out (and listed) until the delay passes.
        #expect(model.todos.items.map(\.id) == [item.id, other.id] && model.completing == [item.id])
        try await until { model.todos.openCount == 1 }
        #expect(model.completing.isEmpty)
        #expect(store.entry(try #require(item.reminderID))?.reminder.completed == true)
        #expect(try d.client.send(Request(op: .get, id: item.id)).item?.status == .done)
        #expect(model.todos.items.map(\.id) == [other.id])
        // Too late to undo once it is done.
        model.undoCompletion(item.id)
        #expect(store.entry(try #require(item.reminderID))?.reminder.completed == true)
    }

    @Test func aTodoDoneElsewhereStopsItsPendingCompletion() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        model.completionDelay = 5
        let item = try await add(model, store, "x")
        model.toggleCompletion(item)
        store.phoneDelete(try #require(item.reminderID))
        try await until { model.completing.isEmpty }
        #expect(model.todos.openCount == 0)
    }

    @Test func todosNeverTouchTheFoldedNotch() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        var chimes: [ChimeSound] = []
        model.onChime = { chimes.append($0) }
        model.completionDelay = 0.05
        let item = try await add(model, store, "x", .high)
        try await add(model, store, "y")
        model.setPriority(item, .low)
        try await until { model.todos.groups.last?.items.first?.id == item.id }
        model.toggleCompletion(item)
        try await until { model.todos.openCount == 1 }
        #expect(model.pulse == 0 && model.banner == nil && chimes.isEmpty)
        #expect(model.panel.signal == nil && model.panel.runningCount == 0)
    }

    /// The folded notch's right wing (#56): the open count, the same as the tab strip's; 0 whenever it can't be trusted.
    @Test func theFoldedNotchCountsOpenTodos() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        #expect(model.collapsedTodoCount == 0)
        model.completionDelay = 0.3
        let item = try await add(model, store, "x", .high)
        try await add(model, store, "y", .low)
        #expect(model.collapsedTodoCount == 2)

        // Still counted while it can be undone; gone once done.
        model.toggleCompletion(item)
        #expect(model.collapsedTodoCount == 2)
        try await until { model.collapsedTodoCount == 1 }
        #expect(model.collapsedTodoCount == model.todos.openCount)

        // No access: the tab shows a button, the wing no number.
        store.setAuthorization(.denied)
        try await until { !model.showsTodos }
        #expect(model.collapsedTodoCount == 0)
        store.setAuthorization(.fullAccess)
        model.expanded = true
        try await until { model.collapsedTodoCount == 1 }
    }

    @Test func theFoldedNotchCountsNothingWhilePerchdIsAway() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await connected(d, store)
        defer { model.disconnect() }
        try await add(model, store, "x")
        #expect(model.collapsedTodoCount == 1)
        d.server.stop()
        try await until { !model.online }
        #expect(model.collapsedTodoCount == 0)
    }
}
