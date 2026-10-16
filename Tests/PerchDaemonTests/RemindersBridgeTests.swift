import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The Reminders bridge (#51): a real perchd, the notch app's model as the bridge, and a fake Reminders database
/// standing in for the phone. Checked from outside only: the Todo tab model, `list` / `perch ls`, todo.md, the store.
@MainActor
@Suite struct RemindersBridgeTests {
    func until(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { Issue.record("timed out"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// A fresh defaults domain, so nothing remembered leaks between tests (or from the real app).
    func defaults() -> UserDefaults {
        let name = "perch-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func app(_ d: TestDaemon, _ store: FakeRemindersStore, listName: String = "Perch",
             defaults: UserDefaults? = nil) -> (QueueModel, RemindersBridge) {
        let model = QueueModel()
        let bridge = RemindersBridge(store: store, listName: listName, defaults: defaults ?? self.defaults())
        model.connect(client: d.client, reminders: bridge)
        return (model, bridge)
    }

    /// The model, once it is the bridge and perchd has its first snapshot.
    func bridge(_ d: TestDaemon, _ store: FakeRemindersStore) async throws -> QueueModel {
        let (model, _) = app(d, store)
        try await until { model.isBridge && d.daemon.hasBridge }
        return model
    }

    func cached(_ d: TestDaemon, status: ItemStatus? = nil) throws -> [Item] {
        (try d.client.send(Request(op: .list, filter: Request.Filter(status: status, kind: .task))).items ?? [])
            .filter { $0.status == .open || $0.status == .done }
    }

    func mirror(_ d: TestDaemon) -> String {
        (try? String(contentsOfFile: d.daemon.config.mirrorPath, encoding: .utf8)) ?? ""
    }

    @Test func aReminderFromThePhoneReachesTheTabLsAndTodoMd() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await bridge(d, store)
        defer { model.disconnect() }
        #expect(model.todos.summary == "All clear")

        let milk = store.phoneAdd("Buy milk", priority: 1, url: "https://shop.example")
        try await until { model.todos.openCount == 1 }
        let item = try #require(model.todos.items.first)
        #expect(item.id.count == 4 && item.title == "Buy milk" && item.priority == .high && item.link == "https://shop.example")
        #expect(try cached(d).map(\.id) == [item.id])
        #expect(mirror(d).contains("- [ ] Buy milk — high priority · reminders · https://shop.example · `\(item.id)`"))

        // Edited on the phone: same short id, new title and priority.
        store.phoneEdit(milk) {
            $0.reminder.title = "Buy oat milk"
            $0.reminder.priority = 9
        }
        try await until { model.todos.items.first?.title == "Buy oat milk" }
        #expect(model.todos.items.map(\.id) == [item.id] && model.todos.groups.map(\.priority) == [.low])
        #expect(mirror(d).contains("- [ ] Buy oat milk — low priority · reminders · https://shop.example · `\(item.id)`"))

        // Completed on the phone: out of the tab and todo.md, listed as done.
        store.phoneComplete(milk)
        try await until { model.todos.openCount == 0 }
        #expect(model.todos.summary == "All clear")
        #expect(try cached(d, status: .done).map(\.id) == [item.id])
        #expect(!mirror(d).contains("Buy oat milk"))

        // Deleted on the phone: gone everywhere.
        store.phoneDelete(milk)
        try await until { (try? cached(d, status: .done))?.isEmpty == true }
        #expect(try d.client.send(Request(op: .get, id: item.id)).error == "no item with id '\(item.id)'")
    }

    @Test func remindersAlreadyInTheListArriveWithTheFirstSnapshot() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        store.phoneAdd("Renew the domain", priority: 1)
        store.phoneAdd("Reply to Sam")
        // Done within the week: listed as done; done before that: not at all.
        store.phoneAdd("Filed taxes", completedAt: Date().addingTimeInterval(-2 * 86_400))
        store.phoneAdd("Old news", completedAt: Date().addingTimeInterval(-8 * 86_400))
        let model = try await bridge(d, store)
        defer { model.disconnect() }
        try await until { model.todos.openCount == 2 }
        #expect(model.todos.items.map(\.title) == ["Renew the domain", "Reply to Sam"])
        #expect(try cached(d, status: .done).map(\.title) == ["Filed taxes"])
    }

    @Test func notchWritesReachTheStore() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await bridge(d, store)
        defer { model.disconnect() }

        // Adding from the popup.
        model.openAdd(fromPanel: true)
        model.editor?.title = "Book flights"
        model.cycleEditorPriority(forward: false)  // High
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 1 }
        let added = try #require(store.entry(titled: "Book flights"))
        #expect(added.reminder.priority == 1 && !added.reminder.completed)
        let item = try #require(model.todos.items.first)
        #expect(item.title == "Book flights" && item.priority == .high)

        // Editing (title and priority).
        model.openEdit(item)
        model.editor?.title = "Book flights to Lisbon"
        model.cycleEditorPriority(forward: true)  // Normal
        #expect(model.submitEditor())
        try await until { model.todos.items.first?.title == "Book flights to Lisbon" }
        #expect(store.entry(added.reminder.externalID)?.reminder.title == "Book flights to Lisbon")
        #expect(store.entry(added.reminder.externalID)?.reminder.priority == 0)

        // Priority ▸ Low.
        model.setPriority(try #require(model.todos.items.first), .low)
        try await until { model.todos.groups.map(\.priority) == [.low] }
        #expect(store.entry(added.reminder.externalID)?.reminder.priority == 9)

        // Completing.
        model.completionDelay = 0.05
        model.toggleCompletion(try #require(model.todos.items.first))
        try await until { model.todos.openCount == 0 }
        #expect(model.completing.isEmpty)
        #expect(store.entry(added.reminder.externalID)?.reminder.completed == true)

        // Deleting.
        model.openAdd(fromPanel: true)
        model.editor?.title = "Throwaway"
        model.submitEditor()
        try await until { model.todos.openCount == 1 }
        model.delete(try #require(model.todos.items.first))
        try await until { model.todos.openCount == 0 }
        #expect(store.entry(titled: "Throwaway") == nil)
        #expect(try cached(d).isEmpty)
    }

    @Test func undoWithinTheDelayLeavesTheStoreAlone() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let id = store.phoneAdd("x")
        let model = try await bridge(d, store)
        defer { model.disconnect() }
        try await until { model.todos.openCount == 1 }
        model.completionDelay = 0.3
        let before = store.entries

        let item = try #require(model.todos.items.first)
        model.toggleCompletion(item)
        model.undoCompletion(item.id)
        model.toggleCompletion(item)
        model.toggleCompletion(item)  // clicking again is Undo too
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(store.entries == before && store.entry(id)?.reminder.completed == false)
        #expect(model.todos.openCount == 1 && model.completing.isEmpty)
    }

    @Test func priorityMapsBothWays() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        for (title, priority) in [("none", 0), ("high", 1), ("high4", 4), ("medium", 5), ("low6", 6), ("low", 9)] {
            store.phoneAdd(title, priority: priority)
        }
        let model = try await bridge(d, store)
        defer { model.disconnect() }
        try await until { model.todos.openCount == 6 }
        let read = Dictionary(uniqueKeysWithValues: model.todos.items.map { ($0.title, $0.priority) })
        #expect(read == ["none": .normal, "high": .high, "high4": .high, "medium": .normal, "low6": .low, "low": .low])

        // Writing: High → 1, Normal → 0, Low → 9 (Medium from the phone becomes none once Perch sets Normal).
        let medium = try #require(model.todos.items.first { $0.title == "medium" })
        for (priority, expected) in [(ItemPriority.high, 1), (.low, 9), (.normal, 0)] {
            model.setPriority(try #require(model.state.items[medium.id]), priority)
            try await until { model.state.items[medium.id]?.priority == priority }
            #expect(store.entry(titled: "medium")?.reminder.priority == expected)
        }
    }

    @Test func fieldsPerchDoesNotManageSurviveItsWrites() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        let id = store.phoneAdd("Call Lin", priority: 5, dueAt: due, url: "https://x.example", notes: "ask about Friday",
                                flagged: true)
        let original = try #require(store.entry(id))
        let model = try await bridge(d, store)
        defer { model.disconnect() }
        try await until { model.todos.openCount == 1 }
        let item = try #require(model.todos.items.first)
        #expect(item.dueAt == due)

        model.openEdit(item)
        model.editor?.title = "Call Lin back"
        model.submitEditor()
        try await until { model.todos.items.first?.title == "Call Lin back" }
        model.setPriority(try #require(model.todos.items.first), .high)
        try await until { model.todos.items.first?.priority == .high }
        model.completionDelay = 0.05
        model.toggleCompletion(try #require(model.todos.items.first))
        try await until { model.todos.openCount == 0 }

        let after = try #require(store.entry(id))
        #expect(after.reminder.notes == original.reminder.notes && after.flagged && after.list == original.list)
        #expect(after.reminder.dueAt == due && after.reminder.url == "https://x.example")
        #expect(after.reminder.createdAt == original.reminder.createdAt)
        #expect(after.reminder.title == "Call Lin back" && after.reminder.priority == 1 && after.reminder.completed)
    }

    @Test func oneBridgeAtATimeAndTheNextTakesOver() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let first = try await bridge(d, store)
        defer { first.disconnect() }
        let (second, _) = app(d, store)
        defer { second.disconnect() }
        try await until { second.online }

        // Both show what the bridge sends; only one is the bridge.
        store.phoneAdd("from the phone")
        try await until { first.todos.openCount == 1 && second.todos.openCount == 1 }
        #expect(first.isBridge && !second.isBridge)
        // The plain client's Todo tab writes go through perchd to the bridge (#52).
        second.setPriority(try #require(second.todos.items.first), .high)
        try await until { store.entry(titled: "from the phone")?.reminder.priority == 1 }
        try await until { first.todos.items.first?.priority == .high && second.todos.items.first?.priority == .high }
        second.openAdd(fromPanel: true)
        second.editor?.title = "from the second app"
        #expect(second.submitEditor())
        try await until { store.entry(titled: "from the second app") != nil && first.todos.openCount == 2 }
        second.completionDelay = 0.05
        second.toggleCompletion(try #require(second.todos.items.first { $0.title == "from the second app" }))
        try await until { store.entry(titled: "from the second app")?.reminder.completed == true }
        second.delete(try #require(second.todos.items.first))
        try await until { store.entries.filter { !$0.reminder.completed }.isEmpty && second.todos.openCount == 0 }
        #expect(second.flash == nil)
        store.phoneDelete(try #require(store.entry(titled: "from the second app")).reminder.externalID)

        // The bridge quits: the other app takes over and keeps the cache current.
        first.disconnect()
        try await until { second.isBridge }
        store.phoneAdd("after the handover")
        try await until { second.todos.openCount == 1 }
        #expect(try cached(d).map(\.title) == ["after the handover"])
    }

    @Test func aSnapshotFromAnAppThatIsNotTheBridgeIsRefused() async throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        let request = Request(op: .todoSnapshot, watcher: stream.watcher, reminders: [Reminder(externalID: "x", title: "sneaky")])
        #expect(try d.client.send(request).ok == false)
        #expect(try d.client.send(Request(op: .bridgeRegister, watcher: "not-a-watcher")).ok == false)
        #expect(try d.client.send(Request(op: .bridgeRegister, watcher: stream.watcher)).bridge == true)
        #expect(try d.client.send(request).ok)
        #expect(try cached(d).map(\.title) == ["sneaky"])
    }
}

/// The Todo tab's states, from the bridge's side of Reminders (#51).
@MainActor
@Suite struct RemindersStateTests {
    let support = RemindersBridgeTests()

    @Test func connectAsksThenFindsOrCreatesTheList() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore(authorization: .notDetermined, lists: [])
        let (model, _) = support.app(d, store)
        defer { model.disconnect() }
        try await support.until { model.online }
        #expect(model.reminders == .connect && !model.isBridge)
        #expect(model.reminders?.button(listName: model.remindersListName) == "Connect Reminders")

        await model.connectReminders()
        #expect(model.reminders == .ready(iCloud: true))
        #expect(store.allLists.map(\.title) == ["Perch"])
        try await support.until { model.isBridge }
    }

    @Test func connectFindsAnExistingListByNamePreferringICloud() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore(authorization: .notDetermined, lists: [])
        store.defaultSourceIsICloud = false
        _ = try store.createList(named: "Perch")  // on this Mac only
        store.defaultSourceIsICloud = true
        let icloud = try store.createList(named: "Perch")
        let (model, bridge) = support.app(d, store)
        defer { model.disconnect() }
        await model.connectReminders()
        #expect(bridge.list == icloud && store.allLists.count == 2)
    }

    @Test func deniedOrRestrictedSendsYouToSystemSettings() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore(authorization: .notDetermined)
        store.grant = .denied
        let (model, _) = support.app(d, store)
        defer { model.disconnect() }
        await model.connectReminders()
        #expect(model.reminders == .openSettings)
        #expect(model.reminders?.button(listName: "Perch") == "Open System Settings")

        let restricted = FakeRemindersStore(authorization: .restricted)
        let (other, _) = support.app(d, restricted)
        defer { other.disconnect() }
        #expect(other.reminders == .openSettings)
    }

    @Test func aDeletedListIsNeverRecreatedSilently() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        store.phoneAdd("x")
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 1 }

        store.deleteList("Perch")
        try await support.until { model.reminders == .createList }
        #expect(model.reminders?.button(listName: "Perch") == "Create Perch list")
        // Its todos went with it, and nothing came back on its own.
        try await support.until { model.todos.openCount == 0 }
        model.expanded = true
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.allLists.isEmpty && model.reminders == .createList)

        model.createRemindersList()
        #expect(model.reminders == .ready(iCloud: true) && store.allLists.map(\.title) == ["Perch"])
        store.phoneAdd("in the new list")
        try await support.until { model.todos.items.map(\.title) == ["in the new list"] }
    }

    @Test func aRenamedListIsStillTheList() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        store.phoneAdd("x")
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        try await support.until { model.todos.openCount == 1 }
        store.renameList("Perch", to: "Work")
        store.phoneAdd("y", list: "Work")
        try await support.until { model.todos.openCount == 2 }
        #expect(model.reminders == .ready(iCloud: true) && store.allLists.map(\.title) == ["Work"])
    }

    @Test func aListOutsideICloudWorksButSaysItIsNotSyncing() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore(authorization: .notDetermined, lists: [])
        store.defaultSourceIsICloud = false
        let (model, _) = support.app(d, store)
        defer { model.disconnect() }
        await model.connectReminders()
        #expect(model.reminders == .ready(iCloud: false))
        #expect(model.reminders?.note == "Not syncing — no iCloud")
        #expect(RemindersState.ready(iCloud: true).note == nil)
        try await support.until { model.isBridge }
    }

    @Test func revokingAccessGoesBackToConnect() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        store.setAuthorization(.denied)
        try await support.until { model.reminders == .openSettings }
        store.setAuthorization(.notDetermined)
        try await support.until { model.reminders == .connect }
        // Noticed when the panel opens, too, without any change notification.
        store.authorization = .fullAccess
        model.expanded = true
        #expect(model.reminders == .ready(iCloud: true))
    }

    @Test func isolatedRunsUsePerchDev() async throws {
        #expect(RemindersBridge.listName(environment: [:]) == "Perch")
        #expect(RemindersBridge.listName(environment: ["PERCH_HOME": ""]) == "Perch")
        #expect(RemindersBridge.listName(environment: ["PERCH_HOME": "/tmp/perch-dev"]) == "Perch Dev")

        let d = try TestDaemon()
        let store = FakeRemindersStore()
        store.phoneAdd("a real todo")
        let (model, bridge) = support.app(d, store, listName: RemindersBridge.listName(environment: ["PERCH_HOME": "/tmp/x"]))
        defer { model.disconnect() }
        try await support.until { model.isBridge }
        #expect(bridge.list?.title == "Perch Dev" && store.allLists.map(\.title) == ["Perch", "Perch Dev"])
        store.phoneAdd("a test todo", list: "Perch Dev")
        try await support.until { model.todos.openCount == 1 }
        #expect(model.todos.items.map(\.title) == ["a test todo"])
    }
}
