import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Doing (#71): Perch's own "working on it now", kept by perchd on the todo's reference and never written to Reminders.
/// A real perchd, the notch app's model as the bridge over a fake Reminders database (the phone). Checked from outside:
/// the Todo tab model, the fake store, and (for the reference of a deleted reminder) perchd's store.
@MainActor
@Suite struct TodoDoingTests {
    let lists = TodoListsTests()
    var support: RemindersBridgeTests { lists.support }

    func item(_ model: QueueModel, _ title: String) throws -> Item {
        try #require(model.todos.items.first { $0.title == title })
    }

    func doing(_ model: QueueModel) -> [String] {
        model.todos.items.filter(\.doing).map(\.title)
    }

    @Test func theTabTogglesDoingAndDoingTodosGoFirstInTheirList() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.phoneAdd("send the invoice", priority: 1, list: "Work", createdAt: t0)
        let report = store.phoneAdd("write the report", priority: 9, list: "Work", createdAt: t0.addingTimeInterval(5))
        store.phoneAdd("book flights", createdAt: t0)
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 3 }
        let before = try #require(store.entry(report))

        model.toggleDoing(try item(model, "write the report"))
        try await support.until { doing(model) == ["write the report"] }
        // First in its own list, ahead of High; the other list is untouched.
        #expect(lists.titles(model) == ["Perch": ["book flights"], "Work": ["write the report", "send the invoice"]])
        // Any number at once.
        model.toggleDoing(try item(model, "book flights"))
        try await support.until { doing(model).count == 2 }
        #expect(doing(model) == ["book flights", "write the report"])
        // Still open everywhere, and counted as such; the summary doesn't mention it.
        #expect(model.todos.summary == "3 open · 1 high" && model.collapsedTodoCount == 3)
        #expect(try support.cached(d).allSatisfy { $0.status == .open })
        // Nothing went to Reminders.
        #expect(store.entry(report) == before)

        model.toggleDoing(try item(model, "write the report"))
        try await support.until { doing(model) == ["book flights"] }
        #expect(lists.titles(model)["Work"] == ["send the invoice", "write the report"])
    }

    @Test func completingClearsItAndReopeningDoesNotBringItBack() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let invoice = store.phoneAdd("send the invoice", list: "Work")
        let flights = store.phoneAdd("book flights")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 2 }
        model.toggleDoing(try item(model, "send the invoice"))
        model.toggleDoing(try item(model, "book flights"))
        try await support.until { doing(model).count == 2 }

        // On the phone.
        store.phoneComplete(invoice)
        try await support.until { model.todos.openCount == 1 }
        #expect(try support.cached(d, status: .done).first?.doing == false)
        store.phoneEdit(invoice) {
            $0.reminder.completed = false
            $0.completedAt = nil
        }
        try await support.until { model.todos.openCount == 2 }
        #expect(doing(model) == ["book flights"])

        // From the tab.
        model.completionDelay = 0.05
        model.toggleCompletion(try item(model, "book flights"))
        try await support.until { store.entry(flights)?.reminder.completed == true }
        try await support.until { model.todos.openCount == 1 }
        #expect(try support.cached(d, status: .done).first { $0.title == "book flights" }?.doing == false)
        store.phoneEdit(flights) {
            $0.reminder.completed = false
            $0.completedAt = nil
        }
        try await support.until { model.todos.openCount == 2 }
        #expect(doing(model).isEmpty)
    }

    @Test func goneFromACheckedListClearsIt() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let invoice = store.phoneAdd("send the invoice", list: "Work")
        let flights = store.phoneAdd("book flights")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 2 }
        let flightsID = try item(model, "book flights").id
        model.toggleDoing(try item(model, "send the invoice"))
        model.toggleDoing(try item(model, "book flights"))
        try await support.until { doing(model).count == 2 }

        // Moved in Reminders to a list that isn't checked: it leaves, and comes back plain.
        store.phoneMove(invoice, to: "Home")
        try await support.until { model.todos.openCount == 1 }
        store.phoneMove(invoice, to: "Work")
        try await support.until { model.todos.openCount == 2 }
        #expect(doing(model) == ["book flights"])

        // Deleted: its reference (kept for the short id) no longer says Doing.
        store.phoneDelete(flights)
        try await support.until { model.todos.openCount == 1 }
        let ref = try d.daemon.queue.sync { try d.daemon.service.store.todoRefs().first { $0.id == flightsID } }
        #expect(ref?.doing == false)
    }

    @Test func itFollowsTheTodoAcrossMovesAndUncheckingItsList() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let invoice = store.phoneAdd("send the invoice", list: "Work")
        let (model, bridge) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 1 }
        model.toggleDoing(try item(model, "send the invoice"))
        try await support.until { doing(model) == ["send the invoice"] }

        // To another checked list, on the phone and from the editor.
        store.phoneMove(invoice, to: "Perch")
        try await support.until { lists.titles(model)["Perch"] == ["send the invoice"] }
        #expect(doing(model) == ["send the invoice"])
        model.openEdit(try item(model, "send the invoice"))
        model.editor?.list = store.list("Work")
        #expect(model.submitEditor())
        try await support.until { lists.titles(model)["Work"] == ["send the invoice"] }
        #expect(doing(model) == ["send the invoice"])

        // Its list unchecked and checked again.
        let work = try #require(store.list("Work")).id
        bridge.selection.setChecked(work, false)
        lists.reselect(model)
        try await support.until { model.todos.openCount == 0 }
        bridge.selection.setChecked(work, true)
        lists.reselect(model)
        try await support.until { model.todos.openCount == 1 }
        #expect(doing(model) == ["send the invoice"])
    }
}

/// `perch update --doing / --no-doing`, `perch ls`, `--json` and todo.md (#71), with the real `perch` binary.
@MainActor
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct TodoDoingCLITests {
    let lists = TodoListsTests()
    let writes = TodoWritesTests()
    var support: RemindersBridgeTests { lists.support }

    @Test func doingWorksWithAndWithoutTheBridgeAndShowsEverywhere() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.phoneAdd("send the invoice", priority: 1, list: "Work", createdAt: t0)
        let report = store.phoneAdd("write the report", list: "Work", createdAt: t0.addingTimeInterval(5))
        store.phoneAdd("book flights", createdAt: t0)
        let (model, _) = try await lists.bridge(d, store, defaults)
        try await support.until { model.todos.openCount == 3 }
        let reportID = try #require(model.todos.items.first { $0.title == "write the report" }).id
        let flightsID = try #require(model.todos.items.first { $0.title == "book flights" }).id
        let before = try #require(store.entry(report))

        // With the bridge connected.
        let set = try await writes.perch(d, "update", reportID, "--doing", "--json")
        #expect(set.status == 0 && set.json.item?.doing == true && set.json.item?.status == .open)
        try await support.until { lists.titles(model)["Work"]?.first == "write the report" }
        #expect(store.entry(report) == before)

        // Without it.
        model.disconnect()
        try await support.until { !d.daemon.hasBridge }
        #expect(try await writes.perch(d, "update", flightsID, "--doing").status == 0)

        let rows = try await writes.perch(d, "ls").stdout.split(separator: "\n").map(String.init)
        #expect(rows.count == 5)
        #expect(rows[0] == "[Perch]" && rows[1].contains("book flights  · doing"))
        #expect(rows[2] == "[Work]" && rows[3].contains("write the report  · doing"))
        #expect(rows[4].contains("send the invoice  · high priority") && !rows[4].contains("doing"))
        let json = try await writes.perch(d, "ls", "--json")
        #expect(json.json.items?.map(\.title) == ["book flights", "write the report", "send the invoice"])
        #expect(json.json.items?.map(\.doing) == [true, true, false])
        #expect(json.stdout.contains(#""doing":false"#))
        try await support.until { support.mirror(d).contains("- [ ] book flights — doing") }
        #expect(support.mirror(d).contains("### Work\n\n- [ ] write the report — doing · reminders"))

        #expect(try await writes.perch(d, "update", reportID, "--no-doing").status == 0)
        #expect(try await writes.listed(d).first { $0.id == reportID }?.doing == false)
        // Again: nothing to change, still fine.
        #expect(try await writes.perch(d, "update", reportID, "--no-doing").status == 0)
    }

    @Test func onlyOpenTodosCanBeDoing() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        store.phoneAdd("filed", completedAt: Date())
        store.phoneAdd("book flights")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 1 }
        let done = try #require(try support.cached(d, status: .done).first).id
        let open = try #require(model.todos.items.first).id

        let refused = try await writes.perch(d, "update", done, "--doing")
        #expect(refused.status != 0 && refused.stderr.contains("isn't open"))
        let json = try await writes.perch(d, "update", done, "--no-doing", "--json")
        #expect(json.status != 0 && json.json.ok == false)

        // Not a todo at all.
        let waiting = try await writes.perch(d, "add", "approve the deploy", "--status", "waiting", "--json")
        let waitingID = try #require(waiting.json.item?.id)
        let notTodo = try await writes.perch(d, "update", waitingID, "--doing")
        #expect(notTodo.status != 0 && notTodo.stderr.contains("only applies to todos"))

        // On its own: it isn't a Reminders write.
        let mixed = try await writes.perch(d, "update", open, "--doing", "--title", "book cheap flights")
        #expect(mixed.status != 0 && mixed.stderr.contains("on its own"))
        #expect(store.entry(titled: "book flights") != nil)
        #expect(try await writes.listed(d).first { $0.id == open }?.doing == false)
    }
}
