import Foundation
import PerchCore
import Testing
@testable import PerchDaemon

/// Ops against an in-memory store, no sockets.
@Suite struct ServiceTests {
    let service: Service
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        service = Service(store: try Store(path: ":memory:"))
        let fixed = clock
        service.now = { fixed }
    }

    @discardableResult
    func call(_ request: Request) -> (Response, [Event]) {
        service.handle(request)
    }

    func add(_ item: Item) throws -> Item {
        let (response, _) = call(Request(op: .add, item: item))
        #expect(response.ok, "\(response.error ?? "")")
        return try #require(response.item)
    }

    @Test func addAssignsIdAndTimestampsAndEmitsAdded() throws {
        let (response, events) = call(Request(op: .add, item: Item(id: "zzzz", title: "  write docs  ", status: .waiting,
                                                                        createdAt: .distantPast, updatedAt: .distantPast)))
        let item = try #require(response.item)
        #expect(item.title == "write docs")
        #expect(item.createdAt == clock)
        #expect(item.updatedAt == clock)
        #expect(events.map(\.type) == [.added])
        #expect(events.first?.item == item)
        #expect(try service.store.get(id: item.id) == item)
    }

    @Test func addRejectsEmptyTitle() {
        let (response, events) = call(Request(op: .add, item: Item(title: "   ")))
        #expect(!response.ok)
        #expect(response.error == "title must not be empty")
        #expect(events.isEmpty)
    }

    @Test func requestsDefaultToAllowDeny() throws {
        let item = try add(Item(title: "npm test", kind: .request, status: .waiting))
        #expect(item.options == ["allow", "deny"])
    }

    @Test func getAndListRoundTripEveryField() throws {
        let added = try add(Item(title: "review", kind: .task, status: .waiting, source: "codex",
                                 dueAt: clock.addingTimeInterval(3600), link: "https://x/pr/1",
                                 meta: ["cwd": "/tmp"], key: "k1", expiresAt: clock.addingTimeInterval(60)))
        #expect(call(Request(op: .get, id: added.id.uppercased())).0.item == added)
        #expect(call(Request(op: .list)).0.items == [added])
    }

    @Test func listFiltersAndHidesClosedByDefault() throws {
        let a = try add(Item(title: "a", status: .waiting, source: "human"))
        let b = try add(Item(title: "b", status: .waiting, source: "codex"))
        let c = try add(Item(title: "c", kind: .notice, source: "codex"))
        call(Request(op: .done, id: a.id))

        #expect(call(Request(op: .list)).0.items?.map(\.id) == [b.id, c.id])
        #expect(call(Request(op: .list, filter: .init(source: "codex", kind: .notice))).0.items?.map(\.id) == [c.id])
        #expect(call(Request(op: .list, filter: .init(status: .done))).0.items?.map(\.id) == [a.id])
        #expect(call(Request(op: .list, filter: .init(all: true))).0.items?.count == 3)
    }

    @Test func doneIsIdempotent() throws {
        let item = try add(Item(title: "x", status: .waiting))
        let (first, events) = call(Request(op: .done, id: item.id))
        #expect(first.item?.status == .done)
        #expect(events.map(\.type) == [.updated])
        let (second, again) = call(Request(op: .done, id: item.id))
        #expect(second.ok)
        #expect(again.isEmpty)
    }

    @Test func respondClosesTheRequest() throws {
        let item = try add(Item(title: "rm -rf build", kind: .request, status: .waiting))
        let (response, events) = call(Request(op: .respond, id: item.id, value: "deny"))
        #expect(response.item?.response == "deny")
        #expect(response.item?.status == .done)
        #expect(events.first?.item.response == "deny")
    }

    @Test func respondValidates() throws {
        let task = try add(Item(title: "t", status: .waiting))
        #expect(call(Request(op: .respond, id: task.id, value: "allow")).0.error?.contains("not a request") == true)

        let request = try add(Item(title: "r", kind: .request))
        #expect(call(Request(op: .respond, id: request.id, value: "maybe")).0.error
                == "'maybe' is not an option for \(request.id); choose one of: allow, deny")
        #expect(call(Request(op: .respond, id: request.id)).0.error?.contains("needs a value") == true)
        #expect(call(Request(op: .respond, id: request.id, value: "allow")).0.ok)
        #expect(call(Request(op: .respond, id: request.id, value: "deny")).0.error
                == "request \(request.id) was already answered: allow")
    }

    @Test func removeDeletesAndEmitsRemoved() throws {
        let item = try add(Item(title: "gone", kind: .notice))
        let (response, events) = call(Request(op: .remove, id: item.id))
        #expect(response.item == item)
        #expect(events.map(\.type) == [.removed])
        #expect(call(Request(op: .get, id: item.id)).0.error == "no item with id '\(item.id)'")
    }

    @Test func unknownIdsAndMissingIds() {
        #expect(call(Request(op: .done, id: "nope")).0.error == "no item with id 'nope'")
        #expect(call(Request(op: .remove)).0.error == "missing id")
    }

    /// Todos live in the "Perch" Reminders list (#51); perchd only caches them from the bridge's snapshots. Until it
    /// can hand writes to the bridge (#52), it refuses them and stores nothing.
    @Test func todoWritesAreRefused() throws {
        let refused = "Todo needs Perch.app running with Reminders access"
        for item in [Item(title: "x"), Item(title: "x", status: .done), Item(title: "x", priority: .high, key: "k")] {
            let (response, events) = call(Request(op: .add, item: item))
            #expect(response.error == refused && events.isEmpty)
        }
        #expect(try service.store.count() == 0)

        _ = try service.applySnapshot([Reminder(externalID: "r1", title: "from the phone")])
        let todo = try #require(call(Request(op: .list)).0.items?.first)
        for request in [Request(op: .done, id: todo.id), Request(op: .remove, id: todo.id),
                        Request(op: .update, id: todo.id, patch: .init(priority: .high))] {
            let (response, events) = call(request)
            #expect(response.error == refused && events.isEmpty)
        }
        #expect(call(Request(op: .list)).0.items == [todo])

        // Waiting tasks, notices and requests are perchd's own, as before.
        let waiting = try add(Item(title: "approve in Telegram", status: .waiting, source: "hermes"))
        #expect(call(Request(op: .done, id: waiting.id)).0.item?.status == .done)
        #expect(try add(Item(title: "codex finished", kind: .notice)).kind == .notice)
        #expect(try add(Item(title: "npm test", kind: .request)).status == .open)
    }

    /// The cache follows the snapshot: new reminders get short ids (kept while they come and go), changes update,
    /// missing ones are removed, and an identical snapshot emits nothing.
    @Test func snapshotsReplaceTheCache() throws {
        let due = Date(timeIntervalSince1970: 1_900_000_000)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        var events = try service.applySnapshot([
            Reminder(externalID: "r1", title: "Buy milk", priority: 5, dueAt: due, url: "https://x", createdAt: created),
            Reminder(externalID: "r2", title: "Filed taxes", completed: true),
        ])
        #expect(events.map(\.type) == [.added, .added])
        let milk = try #require(events.first?.item)
        #expect(milk.id.count == 4 && milk.kind == .task && milk.status == .open && milk.priority == .normal)
        #expect(milk.dueAt == due && milk.link == "https://x" && milk.createdAt == created && milk.source == "reminders")
        #expect(events.last?.item.status == .done)
        #expect(try service.applySnapshot([
            Reminder(externalID: "r1", title: "Buy milk", priority: 5, dueAt: due, url: "https://x", createdAt: created),
            Reminder(externalID: "r2", title: "Filed taxes", completed: true),
        ]).isEmpty)

        events = try service.applySnapshot([Reminder(externalID: "r1", title: "Buy oat milk", priority: 1, createdAt: created)])
        #expect(events.map(\.type) == [.updated, .removed])
        #expect(events.first?.item.id == milk.id && events.first?.item.priority == .high && events.first?.item.dueAt == nil)
        // Back again (reopened on the phone): the same short id.
        events = try service.applySnapshot([Reminder(externalID: "r2", title: "Filed taxes")])
        #expect(events.map(\.type) == [.added, .removed])
        #expect(events.first?.item.status == .open && events.last?.item.id == milk.id)
        events = try service.applySnapshot([Reminder(externalID: "r1", title: "Buy oat milk")])
        #expect(events.first { $0.type == .added }?.item.id == milk.id)
    }

    /// Each cached todo knows its list (#69), and `list` groups by the snapshot's lists in their order. A list no longer
    /// checked leaves the cache; checked again, its todos keep their short ids.
    @Test func snapshotsCarryTheirLists() throws {
        let perch = ReminderList(id: "p", title: "Perch", isICloud: true)
        let work = ReminderList(id: "w", title: "Work", isICloud: false)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let invoice = Reminder(externalID: "r1", list: "w", title: "send the invoice", createdAt: created)
        let flights = Reminder(externalID: "r2", list: "p", title: "book flights", createdAt: created)
        _ = try service.applySnapshot([flights, invoice], lists: [work, perch])
        let listed = call(Request(op: .list)).0
        #expect(listed.todoLists == [work, perch])
        #expect(listed.items?.map(\.title) == ["send the invoice", "book flights"])
        #expect(listed.items?.map(\.listName) == ["Work", "Perch"] && listed.items?.map(\.listID) == ["w", "p"])
        let ids = listed.items?.map(\.id) ?? []

        // Renamed: the todos follow.
        let office = ReminderList(id: "w", title: "Office", isICloud: false)
        let renamed = try service.applySnapshot([flights, invoice], lists: [office, perch])
        #expect(renamed.map(\.type) == [.updated] && renamed.first?.item.listName == "Office")
        // Unchecked, then checked again.
        _ = try service.applySnapshot([flights], lists: [perch])
        #expect(call(Request(op: .list)).0.items?.map(\.title) == ["book flights"])
        _ = try service.applySnapshot([flights, invoice], lists: [perch, office])
        #expect(call(Request(op: .list)).0.items?.map(\.id) == [ids[1], ids[0]])
        // perchd keeps them for when no bridge is connected.
        #expect(service.todoLists() == [perch, office])
        // Writes say which list the reminder was last seen in.
        guard case .bridge(let write) = service.planTodoWrite(Request(op: .done, id: ids[0])) else { Issue.record("not a bridge write"); return }
        #expect(write.operation.seenInList == "w" && write.operation.externalID == "r1")
        let wire = String(decoding: try PerchJSON.encoder.encode(write.operation), as: UTF8.self)
        #expect(wire.contains(#""seen_in_list":"w""#) && !wire.contains(#""list""#))
    }

    /// `--list` (#70): the target goes to the bridge as `change.list`, a list id, apart from the `seen_in_list` hint. The
    /// writer hears an error when the snapshot shows the todo elsewhere (a Perch.app older than #70 ignores the field).
    @Test func movesNameTheirTargetAndCheckTheResult() throws {
        let perch = ReminderList(id: "p", title: "Perch", isICloud: true)
        let work = ReminderList(id: "w", title: "Work", isICloud: true)
        let flights = Reminder(externalID: "r1", list: "p", title: "book flights")
        _ = try service.applySnapshot([flights], lists: [perch, work])
        let id = try #require(call(Request(op: .list)).0.items?.first?.id)
        guard case .bridge(let write) = service.planTodoWrite(Request(op: .update, id: id, patch: Request.Patch(list: "Work")))
        else { Issue.record("not a bridge write"); return }
        #expect(write.operation.change == ReminderChange(list: "w") && write.operation.seenInList == "p")
        let wire = String(decoding: try PerchJSON.encoder.encode(write.operation), as: UTF8.self)
        #expect(wire.contains(#""change":{"list":"w"}"#) && wire.contains(#""seen_in_list":"p""#))

        // An old bridge left it where it was.
        let unmoved = service.todoWriteAnswer(write, externalID: "r1")
        #expect(unmoved.ok == false && unmoved.error?.contains("is in 'Perch', not the list asked for") == true)
        // A bridge that knows the field moved it.
        _ = try service.applySnapshot([Reminder(externalID: "r1", list: "w", title: "book flights")], lists: [perch, work])
        let moved = service.todoWriteAnswer(write, externalID: "r1")
        #expect(moved.ok && moved.item?.id == id && moved.item?.listName == "Work")

        // Already there: nothing to do.
        guard case .answer(let same) = service.planTodoWrite(Request(op: .update, id: id, patch: Request.Patch(list: "Work")))
        else { Issue.record("expected an answer"); return }
        #expect(same.ok && same.item?.id == id)
        // A list on a notice is wrong whatever it is called.
        guard case .answer(let notice) = service.planTodoWrite(Request(op: .add, item: Item(title: "fyi", kind: .notice), list: "Nope"))
        else { Issue.record("expected an answer"); return }
        #expect(notice.error == "a list only applies to todos (open or done tasks)")
    }

    @Test func pingReportsVersion() {
        #expect(call(Request(op: .ping)).0.version == PerchVersion.string)
    }
}
