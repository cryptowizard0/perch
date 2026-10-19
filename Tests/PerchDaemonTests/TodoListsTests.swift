import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// More Reminders lists than "Perch" (#69): a real perchd, the notch app's model as the bridge over a fake Reminders
/// database (the phone), and the list selection in a throwaway defaults domain. Checked from outside: the Todo tab
/// model, `list`, todo.md and what lands in the fake store.
@MainActor
@Suite struct TodoListsTests {
    let support = RemindersBridgeTests()

    /// Reminders with "Perch", "Work", "Home" and "Shopping"; `checked` (names) are checked besides "Perch", in
    /// `order` (names; the rest after them).
    func store(checked: [String] = ["Work"], order: [String] = ["Perch", "Work", "Home", "Shopping"]) -> (FakeRemindersStore, UserDefaults) {
        let store = FakeRemindersStore(lists: ["Perch", "Work", "Home", "Shopping"])
        let defaults = support.defaults()
        let selection = ListSelection(defaults: defaults, listName: "Perch")
        selection.order = order.compactMap { store.list($0)?.id }
        selection.checked = checked.compactMap { store.list($0)?.id }
        return (store, defaults)
    }

    func bridge(_ d: TestDaemon, _ store: FakeRemindersStore, _ defaults: UserDefaults) async throws -> (QueueModel, RemindersBridge) {
        let (model, bridge) = support.app(d, store, defaults: defaults)
        try await support.until { model.isBridge && d.daemon.hasBridge }
        try await support.until { !model.todoLists.isEmpty }
        return (model, bridge)
    }

    /// The model looks at the selection again (as when the panel opens), so a change to it reaches perchd.
    func reselect(_ model: QueueModel) {
        model.expanded = true
        model.expanded = false
    }

    func titles(_ model: QueueModel) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: model.todos.groups.map { ($0.title, $0.items.map(\.title)) })
    }

    @Test func checkedListsAreGroupsInTheSelectionsOrder() async throws {
        let (store, defaults) = store(checked: ["Work", "Home"], order: ["Home", "Perch", "Work"])
        store.phoneAdd("buy stamps", list: "Shopping")
        let d = try TestDaemon()
        let (model, _) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        // Every checked list has a group, empty ones too; "Shopping" isn't checked.
        #expect(model.todos.groups.map(\.title) == ["Home", "Perch", "Work"])
        #expect(model.todos.groups.map(\.openCount) == [0, 0, 0] && model.todos.summary == "All clear")

        store.phoneAdd("send the invoice", priority: 1, list: "Work")
        store.phoneAdd("water the plants", list: "Home")
        store.phoneAdd("milk", list: "Shopping")
        try await support.until { model.todos.openCount == 2 }
        #expect(titles(model) == ["Home": ["water the plants"], "Perch": [], "Work": ["send the invoice"]])
        #expect(model.todos.groups.first { $0.title == "Work" }?.items.first?.listName == "Work")
    }

    @Test func everyCountCoversEveryCheckedList() async throws {
        let (store, defaults) = store()
        let d = try TestDaemon()
        let (model, _) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        store.phoneAdd("a", priority: 1)
        store.phoneAdd("b", priority: 1, list: "Work")
        store.phoneAdd("c", list: "Work")
        store.phoneAdd("not shown", list: "Home")
        try await support.until { model.todos.openCount == 3 }
        // The summary line, the tab strip's count and the folded notch's (#56) agree.
        #expect(model.todos.summary == "3 open · 2 high")
        #expect(model.showsTodos && model.collapsedTodoCount == 3)
    }

    @Test func tabWritesGoToTheTodosOwnListOnly() async throws {
        let (store, defaults) = store()
        let d = try TestDaemon()
        let (model, bridge) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        let alarm = Date(timeIntervalSince1970: 1_900_000_000)
        let id = store.phoneAdd("send the invoice", list: "Work", notes: "net 30", flagged: true, alarms: [alarm])
        try await support.until { model.todos.openCount == 1 }
        let work = try #require(store.list("Work")).id
        var item = try #require(model.todos.items.first)

        // Priority ▸ High.
        model.setPriority(item, .high)
        try await support.until { model.todos.items.first?.priority == .high }
        // Edit…: title.
        item = try #require(model.todos.items.first)
        model.openEdit(item)
        model.editor?.title = "Send the invoice to Acme"
        #expect(model.submitEditor())
        try await support.until { model.todos.items.first?.title == "Send the invoice to Acme" }
        let entry = try #require(store.entry(id))
        #expect(entry.list == work && entry.reminder.priority == 1 && entry.reminder.title == "Send the invoice to Acme")
        // Fields Perch doesn't manage stay.
        #expect(entry.flagged && entry.alarms == [alarm] && entry.reminder.notes == "net 30")
        // ✎ finds it in its list.
        #expect(bridge.link(for: try #require(model.todos.items.first)) == URL(string: "x-apple-reminderkit://REMCDReminder/local-\(id)"))

        // Completing, undone in time: nothing changes.
        model.completionDelay = 0.2
        model.toggleCompletion(try #require(model.todos.items.first))
        model.undoCompletion(item.id)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(store.entry(id)?.reminder.completed == false)
        // Completing for good.
        model.completionDelay = 0.05
        model.toggleCompletion(try #require(model.todos.items.first))
        try await support.until { model.todos.openCount == 0 }
        #expect(store.entry(id)?.reminder.completed == true && store.entry(id)?.list == work)

        // Delete.
        let other = store.phoneAdd("archive receipts", list: "Work")
        try await support.until { model.todos.openCount == 1 }
        model.delete(try #require(model.todos.items.first))
        try await support.until { model.todos.openCount == 0 }
        #expect(store.entry(other) == nil)
        // Nothing ever landed in "Perch".
        #expect(!store.entries.contains { $0.list == store.list("Perch")?.id })
    }

    @Test func addingFromThePopupStillGoesToPerch() async throws {
        let (store, defaults) = store()
        let d = try TestDaemon()
        let (model, _) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        model.openAdd(fromPanel: true)
        model.editor?.title = "book flights"
        #expect(model.submitEditor())
        try await support.until { model.todos.openCount == 1 }
        #expect(store.entry(titled: "book flights")?.list == store.list("Perch")?.id)
        #expect(titles(model)["Perch"] == ["book flights"])
    }

    @Test func uncheckingHidesAListAndRecheckingBringsTheSameShortIds() async throws {
        let d = try TestDaemon()
        let (store, defaults) = store()
        let (model, bridge) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        store.phoneAdd("send the invoice", list: "Work")
        store.phoneAdd("book flights")
        try await support.until { model.todos.openCount == 2 }
        let before = try support.cached(d).map(\.id).sorted()
        let work = try #require(store.list("Work")).id

        bridge.selection.setChecked(work, false)
        reselect(model)
        try await support.until { model.todos.groups.map(\.title) == ["Perch"] }
        #expect(model.todos.items.map(\.title) == ["book flights"])
        #expect(try support.cached(d).map(\.title) == ["book flights"])
        try await support.until { !support.mirror(d).contains("send the invoice") }
        #expect(!support.mirror(d).contains("### Work"))
        // Reminders is untouched.
        #expect(store.entry(titled: "send the invoice")?.list == work)

        bridge.selection.setChecked(work, true)
        reselect(model)
        try await support.until { model.todos.openCount == 2 }
        #expect(model.todos.groups.map(\.title) == ["Perch", "Work"])
        #expect(try support.cached(d).map(\.id).sorted() == before)
    }

    @Test func aReminderMovedToAnUncheckedListDisappears() async throws {
        let (store, defaults) = store()
        let d = try TestDaemon()
        let (model, _) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        let id = store.phoneAdd("send the invoice", list: "Work")
        try await support.until { model.todos.openCount == 1 }
        // To another checked list: same todo, new group.
        let shortID = try #require(model.todos.items.first).id
        store.phoneMove(id, to: "Perch")
        try await support.until { titles(model)["Perch"] == ["send the invoice"] }
        #expect(model.todos.items.map(\.id) == [shortID])
        // A write follows it there.
        model.setPriority(try #require(model.todos.items.first), .low)
        try await support.until { store.entry(id)?.reminder.priority == 9 }
        // To one that isn't checked: gone from Perch.
        store.phoneMove(id, to: "Home")
        try await support.until { model.todos.openCount == 0 }
        #expect(store.entry(id)?.reminder.title == "send the invoice")
    }

    @Test func aDeletedCheckedListJustDisappears() async throws {
        let (store, defaults) = store()
        let d = try TestDaemon()
        let (model, bridge) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        store.phoneAdd("send the invoice", list: "Work")
        try await support.until { model.todos.openCount == 1 }
        let work = try #require(store.list("Work")).id
        store.deleteList("Work")
        try await support.until { model.todos.groups.map(\.title) == ["Perch"] }
        // No alert, no state of its own: it is simply gone from the tab (the selection still remembers it, in case
        // EventKit only missed it for a moment).
        #expect(model.todos.openCount == 0 && model.reminders == .ready(iCloud: true) && model.flash == nil)
        #expect(!bridge.checkedLists.contains { $0.id == work } && bridge.selection.checked.contains(work))
    }

    /// A checked list EventKit leaves out for one look (an iCloud blip, sources still loading at launch) comes back
    /// checked and in its place.
    @Test func aListMissingForAMomentComesBackCheckedInItsPlace() async throws {
        let (store, defaults) = store(checked: ["Work"], order: ["Work", "Perch"])
        let d = try TestDaemon()
        let (model, bridge) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        store.phoneAdd("send the invoice", list: "Work")
        try await support.until { model.todos.openCount == 1 }
        let work = try #require(store.list("Work"))
        let shortID = try #require(model.todos.items.first).id

        store.hidden = [work.id]
        store.changed()
        try await support.until { model.todos.groups.map(\.title) == ["Perch"] }
        store.hidden = []
        store.changed()
        try await support.until { model.todos.groups.map(\.title) == ["Work", "Perch"] }
        #expect(model.todos.items.map(\.id) == [shortID])
        #expect(bridge.checkedLists.map(\.title) == ["Work", "Perch"])
    }

    @Test func aRenamedListKeepsItsPlaceAndAListOutOfICloudSaysSo() async throws {
        let (store, defaults) = store(checked: ["Work"], order: ["Work", "Perch"])
        let d = try TestDaemon()
        let (model, _) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        store.phoneAdd("send the invoice", list: "Work")
        try await support.until { model.todos.openCount == 1 }
        store.renameList("Work", to: "Office")
        try await support.until { model.todos.groups.map(\.title) == ["Office", "Perch"] }
        #expect(model.todos.items.first?.listName == "Office")

        #expect(model.todos.groups.map(\.notSyncing) == [false, false])
        store.setICloud("Office", false)
        try await support.until { model.todos.groups.map(\.notSyncing) == [true, false] }
    }

    @Test func whilePerchIsGoneTheOtherCheckedListsStay() async throws {
        let d = try TestDaemon()
        let (store, defaults) = store()
        let (model, _) = try await bridge(d, store, defaults)
        defer { model.disconnect() }
        store.phoneAdd("send the invoice", list: "Work")
        store.phoneAdd("x")
        try await support.until { model.todos.openCount == 2 }
        store.deleteList("Perch")
        try await support.until { model.reminders == .createList }
        // The tab shows Create Perch list; perchd still has the other list.
        try await support.until { (try? support.cached(d).map(\.title)) == ["send the invoice"] }
    }

    @Test func theListsSurviveAPerchdRestart() async throws {
        let home = TestDaemon.freshHome()
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            let d = try TestDaemon(home: home, removeHome: false)
            let (store, defaults) = store(checked: ["Work", "Home"])
            store.phoneAdd("send the invoice", list: "Work")
            let (model, _) = try await bridge(d, store, defaults)
            try await support.until { model.todos.openCount == 1 }
            model.disconnect()
            try await support.until { !d.daemon.hasBridge }
            try? FileManager.default.removeItem(atPath: d.daemon.config.socketPath)  // perchd's startup does this
        }
        let d = try TestDaemon(home: home, removeHome: false)
        let listed = try d.client.send(Request(op: .list))
        #expect(listed.todoLists?.map(\.title) == ["Perch", "Work", "Home"])
        // A plain app (no Reminders of its own) groups the cache the same way.
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await support.until { model.todos.groups.count == 3 }
        #expect(model.todos.groups.map(\.title) == ["Perch", "Work", "Home"])
        #expect(titles(model)["Work"] == ["send the invoice"])
    }
}

/// The CLI and todo.md over every checked list (#69), with the real `perch` binary.
@MainActor
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct TodoListsCLITests {
    let lists = TodoListsTests()
    let writes = TodoWritesTests()
    var support: RemindersBridgeTests { lists.support }

    @Test func lsAndTodoMdGroupByListEvenWithoutTheBridge() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store(checked: ["Work", "Home"], order: ["Work", "Perch", "Home"])
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        store.phoneAdd("book flights", createdAt: t0)
        store.phoneAdd("archive receipts", list: "Work", createdAt: t0)
        store.phoneAdd("send the invoice", priority: 1, list: "Work", createdAt: t0.addingTimeInterval(5))
        store.phoneAdd("milk", list: "Shopping")
        let (model, _) = try await lists.bridge(d, store, defaults)
        try await support.until { model.todos.openCount == 3 }

        let plain = try await writes.perch(d, "ls")
        let rows = plain.stdout.split(separator: "\n").map(String.init)
        #expect(rows.count == 5)
        #expect(rows[0] == "[Work]" && rows[1].contains("send the invoice  · high priority") && rows[2].contains("archive receipts"))
        #expect(rows[3] == "[Perch]" && rows[4].contains("book flights"))
        let json = try await writes.perch(d, "ls", "--json")
        #expect(json.stdout.contains(#""list":"Work""#))
        #expect(json.json.items?.map(\.title) == ["send the invoice", "archive receipts", "book flights"])
        #expect(json.json.todoLists?.map(\.title) == ["Work", "Perch", "Home"])

        let mirror = support.mirror(d)
        #expect(mirror.contains("## To do\n\n### Work\n\n- [ ] send the invoice"))
        #expect(mirror.contains("### Perch\n\n- [ ] book flights"))
        #expect(mirror.contains("### Home\n\nAll clear\n"))
        #expect(!mirror.contains("milk"))

        // No bridge: the same, from the cache.
        model.disconnect()
        try await support.until { !d.daemon.hasBridge }
        let stale = try await writes.perch(d, "ls")
        #expect(stale.stdout == plain.stdout && stale.stderr.hasPrefix("Todos as of"))
        try await support.until { support.mirror(d).contains("_As of") }
        #expect(support.mirror(d).contains("### Work\n\n- [ ] send the invoice"))
    }

    @Test func cliWritesWorkOnAnyCheckedList() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let invoice = store.phoneAdd("send the invoice", list: "Work", flagged: true)
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 1 }
        let id = try #require(model.todos.items.first).id
        let work = try #require(store.list("Work")).id

        #expect(try await writes.perch(d, "update", id, "--title", "send the invoice to Acme", "-p", "high").status == 0)
        #expect(store.entry(invoice)?.reminder.title == "send the invoice to Acme" && store.entry(invoice)?.list == work)
        #expect(try await writes.perch(d, "done", id).status == 0)
        #expect(store.entry(invoice)?.reminder.completed == true && store.entry(invoice)?.flagged == true)
        let done = try await writes.listed(d, "--status", "done")
        #expect(done.map(\.id) == [id] && done.first?.listName == "Work")
        #expect(try await writes.perch(d, "update", id, "--status", "open").status == 0)
        #expect(store.entry(invoice)?.reminder.completed == false && store.entry(invoice)?.list == work)
        #expect(try await writes.perch(d, "rm", id).status == 0)
        #expect(store.entry(invoice) == nil)

        // New todos go to "Perch", from the CLI and from inbox.md.
        #expect(try await writes.perch(d, "add", "book flights").status == 0)
        #expect(store.entry(titled: "book flights")?.list == store.list("Perch")?.id)
        try writes.append("- [ ] call Lin\n", to: d.daemon.config.inboxPath)
        try await support.until { store.entry(titled: "call Lin") != nil }
        #expect(store.entry(titled: "call Lin")?.list == store.list("Perch")?.id)
    }
}
