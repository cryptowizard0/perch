import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Choosing lists and moving todos between them (#70): `--list` on the real `perch`, the Lists… window's model, and the
/// add popup's and editor's list pickers. A real perchd, the notch app's model as the bridge over a fake Reminders
/// database, and the list selection in a throwaway defaults domain. Checked from outside: what `perch` prints, the Todo
/// tab model, todo.md and what lands in the fake store.
@MainActor
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct TodoListFlagTests {
    let lists = TodoListsTests()
    let writes = TodoWritesTests()
    var support: RemindersBridgeTests { lists.support }

    func perch(_ d: TestDaemon, _ args: [String]) async throws -> CLI.Result {
        let cli = CLI(home: d.home)
        return try await Task.detached { try cli.run(args) }.value
    }

    /// The one open todo the model shows, once it shows one.
    func onlyTodo(_ model: QueueModel) async throws -> Item {
        try await support.until { model.todos.openCount == 1 }
        return try #require(model.todos.items.first)
    }

    @Test func addListPutsTheTodoInThatCheckedList() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }

        let added = try await writes.perch(d, "add", "send the invoice", "--list", "Work", "--json")
        #expect(added.status == 0 && added.json.item?.listName == "Work")
        #expect(store.entry(titled: "send the invoice")?.list == store.list("Work")?.id)
        // No --list, or --list Perch: "Perch". So are inbox.md's lines.
        #expect(try await writes.perch(d, "add", "book flights").status == 0)
        #expect(try await writes.perch(d, "add", "call Lin", "--list", "Perch").status == 0)
        try writes.append("- [ ] water the plants\n", to: d.daemon.config.inboxPath)
        try await support.until { store.entry(titled: "water the plants") != nil }
        for title in ["book flights", "call Lin", "water the plants"] {
            #expect(store.entry(titled: title)?.list == store.list("Perch")?.id)
        }
        let listed = try await writes.listed(d)
        #expect(listed.first { $0.title == "send the invoice" }?.listName == "Work")
        try await support.until { model.todos.groups.first { $0.title == "Work" }?.items.map(\.title) == ["send the invoice"] }
    }

    @Test func updateListMovesTheTodoAndKeepsItsShortID() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store(checked: ["Work", "Home"])
        let invoice = store.phoneAdd("send the invoice", priority: 1, url: "https://acme.example", notes: "net 30", flagged: true)
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        let id = try await onlyTodo(model).id

        let moved = try await writes.perch(d, "update", id, "--list", "Work", "--json")
        #expect(moved.status == 0 && moved.json.item?.id == id && moved.json.item?.listName == "Work")
        let entry = try #require(store.entry(invoice))
        #expect(entry.list == store.list("Work")?.id && entry.flagged && entry.reminder.priority == 1)
        #expect(entry.reminder.title == "send the invoice" && entry.reminder.notes == "net 30" && entry.reminder.url == "https://acme.example")
        #expect(try await writes.listed(d).map(\.id) == [id])
        try await support.until { lists.titles(model)["Work"] == ["send the invoice"] }
        #expect(lists.titles(model)["Perch"] == [])

        // Where it already is: nothing to do. Along with another field: both.
        #expect(try await writes.perch(d, "update", id, "--list", "Work").status == 0)
        #expect(try await writes.perch(d, "update", id, "--list", "Home", "--title", "send the invoice to Acme").status == 0)
        #expect(store.entry(invoice)?.list == store.list("Home")?.id && store.entry(invoice)?.reminder.title == "send the invoice to Acme")
        #expect(try await writes.listed(d).map(\.id) == [id])
    }

    @Test func uncheckedUnknownAndAmbiguousListsFailAndWriteNothing() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let errands = [store.phoneCreateList("Errands"), store.phoneCreateList("Errands")]
        let selection = ListSelection(defaults: defaults, listName: "Perch")
        selection.checked = selection.checked + errands.map(\.id)
        store.phoneAdd("send the invoice")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        let id = try await onlyTodo(model).id
        let before = store.entries
        let checked = "checked lists: Perch, Work, Errands, Errands"

        // Not checked, no such list, the wrong case, two lists of that name.
        for name in ["Home", "Nope", "work", "Errands"] {
            for args in [["add", "milk", "--list", name], ["update", id, "--list", name]] {
                let plain = try await perch(d, args)
                #expect(plain.status != 0 && plain.stdout.isEmpty)
                #expect(plain.stderr.split(separator: "\n").count == 1 && plain.stderr.contains(checked), "\(args): \(plain.stderr)")
                // perchd refused it: the bridge never saw it.
                #expect(plain.stderr.contains("checked Reminders list"))
                let json = try await perch(d, args + ["--json"])
                #expect(json.status != 0 && json.json.ok == false && json.json.error?.contains(checked) == true)
            }
        }
        #expect(store.entries == before)

        // Only todos have a list.
        for args in [["add", "milk", "--status", "waiting", "--list", "Work"], ["add", "deployed", "--kind", "notice", "--list", "Nope"],
                     ["add", "run it?", "--kind", "request", "--wait", "--list", "Work"]] {
            let refused = try await perch(d, args)
            #expect(refused.status != 0 && refused.stderr.contains("a list only applies to todos"))
        }
        #expect(try await writes.listed(d, "--all").map(\.id) == [id])
    }

    @Test func theBridgeChecksTheListAgainWhenItWrites() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        store.phoneAdd("send the invoice")
        let (model, bridge) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        let id = try await onlyTodo(model).id
        // Unchecked in the app a moment ago; perchd hasn't heard yet.
        bridge.selection.setChecked(try #require(store.list("Work")).id, false)
        bridge.refresh()
        #expect(d.daemon.service.todoLists().map(\.title) == ["Perch", "Work"])
        let before = store.entries

        let added = try await writes.perch(d, "add", "milk", "--list", "Work")
        #expect(added.status != 0 && added.stderr.contains("isn't checked in Perch; checked lists: Perch"))
        let moved = try await writes.perch(d, "update", id, "--list", "Work")
        #expect(moved.status != 0 && moved.stderr.contains("isn't checked in Perch"))
        #expect(store.entries == before)
    }

    @Test func movesBetweenAccountsAreRefused() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let mac = store.phoneCreateList("On this Mac", iCloud: false)
        let selection = ListSelection(defaults: defaults, listName: "Perch")
        selection.checked = selection.checked + [mac.id]
        let invoice = store.phoneAdd("send the invoice")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        let item = try await onlyTodo(model)

        let moved = try await writes.perch(d, "update", item.id, "--list", "On this Mac")
        #expect(moved.status != 0 && moved.stderr.contains("different Reminders accounts"))
        #expect(store.entry(invoice)?.list == store.list("Perch")?.id)
        // Adding into it is fine.
        #expect(try await writes.perch(d, "add", "back up the photos", "--list", "On this Mac").status == 0)
        #expect(store.entry(titled: "back up the photos")?.list == mac.id)
        // The editor only offers lists it can move to; the add popup offers every checked list.
        model.openEdit(item)
        #expect(model.editorLists.map(\.title) == ["Perch", "Work"])
        model.openAdd(fromPanel: true)
        #expect(model.editorLists.map(\.title) == ["Perch", "Work", "On this Mac"])
    }
}

/// The Lists… window's model (#70), and the add popup's and editor's list pickers, on `QueueModel`.
@MainActor
@Suite struct ListPickerTests {
    let lists = TodoListsTests()
    var support: RemindersBridgeTests { lists.support }

    func id(_ store: FakeRemindersStore, _ name: String) -> String { store.list(name)!.id }

    @Test func theWindowListsEveryListAndChangesApplyAtOnce() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store(checked: ["Work"], order: ["Work", "Perch", "Home", "Shopping"])
        store.phoneAdd("water the plants", list: "Home")
        store.phoneAdd("send the invoice", list: "Work")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        #expect(model.choosesLists)
        #expect(model.listChoices.map(\.list.title) == ["Work", "Perch", "Home", "Shopping"])
        #expect(model.listChoices.map(\.isChecked) == [true, true, false, false])
        #expect(model.listChoices.map(\.isLocked) == [false, true, false, false])

        // Checking: the Todo tab, `list` and todo.md, straight away.
        model.setListChecked(id(store, "Home"), true)
        try await support.until { model.todos.groups.map(\.title) == ["Work", "Perch", "Home"] }
        #expect(lists.titles(model)["Home"] == ["water the plants"])
        try await support.until { support.mirror(d).contains("### Home\n\n- [ ] water the plants") }
        let plants = try #require(model.todos.items.first { $0.title == "water the plants" }).id

        // "Perch" can't be unchecked.
        model.setListChecked(id(store, "Perch"), false)
        #expect(model.listChoices.first { $0.list.title == "Perch" }?.isChecked == true)

        // Dragging, "Perch" too.
        model.reorderLists(["Home", "Perch", "Shopping", "Work"].map { id(store, $0) })
        #expect(model.listChoices.map(\.list.title) == ["Home", "Perch", "Shopping", "Work"])
        try await support.until { model.todos.groups.map(\.title) == ["Home", "Perch", "Work"] }
        #expect(try d.client.send(Request(op: .list)).todoLists?.map(\.title) == ["Home", "Perch", "Work"])
        try await support.until { support.mirror(d).contains("### Home\n\n- [ ] water the plants — reminders · `\(plants)`\n\n### Perch") }

        // Unchecking: its todos leave (Reminders keeps them).
        model.setListChecked(id(store, "Work"), false)
        try await support.until { model.todos.groups.map(\.title) == ["Home", "Perch"] }
        #expect(store.entry(titled: "send the invoice") != nil)

        // A new list comes in at the bottom, unchecked; a deleted one goes.
        store.phoneCreateList("Garden")
        try await support.until { model.listChoices.last?.list.title == "Garden" }
        #expect(model.listChoices.last?.isChecked == false)
        store.deleteList("Shopping")
        try await support.until { !model.listChoices.contains { $0.list.title == "Shopping" } }
        #expect(model.listChoices.map(\.list.title) == ["Home", "Perch", "Work", "Garden"])
    }

    @Test func noListsWindowWithoutAccess() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore(authorization: .notDetermined)
        let (model, _) = support.app(d, store)
        defer { model.disconnect() }
        try await support.until { model.online }
        #expect(!model.choosesLists && model.listChoices.isEmpty)
    }

    @Test func theAddPopupStartsOnPerchAndAddsIntoThePickedList() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }

        model.openAdd(fromPanel: true)
        #expect(model.editor?.list == nil && model.perchList?.title == "Perch")
        // Only checked lists.
        #expect(model.editorLists.map(\.title) == ["Perch", "Work"])
        model.editor?.list = model.editorLists.last
        model.editor?.title = "send the invoice"
        #expect(model.submitEditor())
        try await support.until { store.entry(titled: "send the invoice") != nil }
        #expect(store.entry(titled: "send the invoice")?.list == id(store, "Work"))
        // The popup stays open on that list for the next one; opened again, it's back on "Perch".
        #expect(model.editor?.list?.title == "Work" && model.editor?.title == "")
        model.closeEditor()
        model.openAdd(fromPanel: false)
        #expect(model.editor?.list == nil)
        model.editor?.title = "book flights"
        #expect(model.submitEditor())
        try await support.until { store.entry(titled: "book flights") != nil }
        #expect(store.entry(titled: "book flights")?.list == id(store, "Perch"))
    }

    /// While "Perch" is gone, the picker shows the first checked list, and that is where the todo goes.
    @Test func withoutPerchThePopupAddsWhereThePickerSays() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        store.deleteList("Perch")
        try await support.until { model.todoLists.map(\.title) == ["Work"] }
        model.openAdd(fromPanel: false)
        #expect(model.perchList == nil && model.editorList?.title == "Work")
        model.editor?.title = "send the invoice"
        #expect(model.submitEditor())
        try await support.until { store.entry(titled: "send the invoice") != nil }
        #expect(store.entry(titled: "send the invoice")?.list == id(store, "Work"))
    }

    @Test func theEditorMovesATodoAndLeavesTheRestAlone() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store()
        let invoice = store.phoneAdd("send the invoice", priority: 1, url: "https://acme.example", notes: "net 30", flagged: true)
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 1 }
        let item = try #require(model.todos.items.first)

        model.openEdit(item)
        #expect(model.editor?.list?.title == "Perch" && model.editorLists.map(\.title) == ["Perch", "Work"])
        model.editor?.list = model.editorLists.last
        #expect(model.submitEditor())
        try await support.until { store.entry(invoice)?.list == id(store, "Work") }
        let entry = try #require(store.entry(invoice))
        #expect(entry.flagged && entry.reminder.priority == 1 && entry.reminder.notes == "net 30" && entry.reminder.url == "https://acme.example")
        try await support.until { model.todos.items.first?.listName == "Work" }
        let moved = try #require(model.todos.items.first)
        #expect(moved.id == item.id)

        // Saving without touching the picker leaves it where it is.
        model.openEdit(moved)
        model.editor?.title = "send the invoice to Acme"
        #expect(model.submitEditor())
        try await support.until { store.entry(invoice)?.reminder.title == "send the invoice to Acme" }
        #expect(store.entry(invoice)?.list == id(store, "Work"))
    }

    /// A plain app (not the bridge) adds into a list and moves todos through perchd, which hands them to the bridge.
    @Test func aPlainAppAddsAndMovesThroughPerchd() async throws {
        let d = try TestDaemon()
        let (store, defaults) = lists.store(checked: ["Work", "Home"])
        let invoice = store.phoneAdd("send the invoice")
        let (model, _) = try await lists.bridge(d, store, defaults)
        defer { model.disconnect() }
        let plain = QueueModel()
        plain.connect(client: d.client)
        defer { plain.disconnect() }
        try await support.until { plain.todos.openCount == 1 && plain.todoLists.count == 3 }

        plain.openAdd(fromPanel: true)
        plain.editor?.list = plain.todoLists.first { $0.title == "Home" }
        plain.editor?.title = "water the plants"
        #expect(plain.submitEditor())
        try await support.until { store.entry(titled: "water the plants") != nil }
        #expect(store.entry(titled: "water the plants")?.list == id(store, "Home"))

        let item = try #require(plain.todos.items.first { $0.title == "send the invoice" })
        plain.openEdit(item)
        plain.editor?.list = plain.todoLists.first { $0.title == "Work" }
        #expect(plain.submitEditor())
        try await support.until { store.entry(invoice)?.list == id(store, "Work") }
        try await support.until { plain.todos.items.first { $0.title == "send the invoice" }?.id == item.id && lists.titles(plain)["Work"] == ["send the invoice"] }
    }
}
