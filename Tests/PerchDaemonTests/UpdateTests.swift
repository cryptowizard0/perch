import Foundation
import PerchCore
import Testing
@testable import PerchDaemon

/// `update`: change title / kind / due of an existing item (M2: ⌥-click snooze, notice → task).
@Suite struct UpdateTests {
    let service: Service
    let clock = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        service = Service(store: try Store(path: ":memory:"))
        let fixed = clock
        service.now = { fixed }
    }

    func add(_ item: Item) throws -> Item {
        try #require(service.handle(Request(op: .add, item: item)).0.item)
    }

    func update(_ id: String, _ patch: Request.Patch?) -> (Response, [Event]) {
        service.handle(Request(op: .update, id: id, patch: patch))
    }

    @Test func changesOnlyTheFieldsThatAreSet() throws {
        let item = try add(Item(title: "old", status: .waiting, source: "codex", link: "https://x", meta: ["a": "b"]))
        let due = clock.addingTimeInterval(1800.7)
        let (response, events) = update(item.id, .init(title: "  new  ", dueAt: due))
        let updated = try #require(response.item)
        #expect(updated.title == "new")
        #expect(updated.dueAt == Date(timeIntervalSince1970: 1_800_001_800))
        #expect(updated.source == "codex" && updated.link == "https://x" && updated.meta == ["a": "b"])
        #expect(updated.id == item.id && updated.createdAt == item.createdAt)
        #expect(events.map(\.type) == [.updated])
        #expect(events.first?.item == updated)
        #expect(try service.store.get(id: item.id) == updated)
    }

    @Test func clearDue() throws {
        let item = try add(Item(title: "t", status: .waiting, dueAt: clock.addingTimeInterval(60)))
        #expect(update(item.id, .init(clearDue: true)).0.item?.dueAt == nil)
        #expect(update(item.id, .init(dueAt: clock, clearDue: true)).0.error
                == "update takes either due_at or clear_due, not both")
    }

    /// A notice kept as a task would be a todo, and todos live in Reminders (#51): refused until #52 hands it to the
    /// bridge. A waiting notice becomes a waiting task, which stays perchd's, and stops expiring.
    @Test func noticeBecomesTaskAndStopsExpiring() throws {
        let notice = try add(Item(title: "codex finished", kind: .notice, source: "codex",
                                  expiresAt: clock.addingTimeInterval(300)))
        #expect(update(notice.id, .init(kind: .task)).0.error == "Todo needs Perch.app running with Reminders access")
        #expect(try service.store.get(id: notice.id) == notice)
        let waiting = try add(Item(title: "approve in Telegram", kind: .notice, status: .waiting, source: "hermes",
                                   expiresAt: clock.addingTimeInterval(300)))
        let task = try #require(update(waiting.id, .init(kind: .task)).0.item)
        #expect(task.kind == .task && task.status == .waiting && task.expiresAt == nil)
        #expect(try service.store.nextExpiry() == clock.addingTimeInterval(300))
    }

    @Test func requestsKeepTheirKind() throws {
        let request = try add(Item(title: "npm test", kind: .request))
        #expect(update(request.id, .init(kind: .task)).0.error
                == "\(request.id) is a request; its kind cannot change")
        let task = try add(Item(title: "t", status: .waiting))
        #expect(update(task.id, .init(kind: .request)).0.error
                == "\(task.id) cannot become a request; add a new one with --kind request")
    }

    @Test func identicalUpdateEmitsNothing() throws {
        let item = try add(Item(title: "same", status: .waiting, dueAt: clock))
        let (response, events) = update(item.id, .init(title: "same", kind: .task, dueAt: clock))
        #expect(response.item == item)
        #expect(events.isEmpty)
    }

    /// `status` (#52) on perchd's own items. Becoming an open or done task makes it a todo, which only the bridge can
    /// do (`TodoWritesTests`); requests are answered or closed, not moved.
    @Test func statusMovesTasksAndNotices() throws {
        let waiting = try add(Item(title: "approve in Telegram", status: .waiting, source: "hermes"))
        #expect(update(waiting.id, .init(status: .dismissed)).0.item?.status == .dismissed)
        #expect(update(waiting.id, .init(status: .open)).0.error == "Todo needs Perch.app running with Reminders access")
        let notice = try add(Item(title: "codex finished", kind: .notice))
        #expect(update(notice.id, .init(status: .done)).0.item?.status == .done)
        let request = try add(Item(title: "npm test", kind: .request))
        #expect(update(request.id, .init(status: .done)).0.error
                == "\(request.id) is a request; answer it with respond, or close it with done or rm")
    }

    @Test func rejectsEmptyPatchesAndBadInput() throws {
        let item = try add(Item(title: "t", status: .waiting))
        let empty = "update needs at least one of: title, kind, status, priority, due_at, clear_due, doing"
        #expect(update(item.id, nil).0.error == empty)
        #expect(update(item.id, .init()).0.error == empty)
        #expect(update(item.id, .init(clearDue: false)).0.error == empty)
        #expect(update(item.id, .init(title: "  ")).0.error == "title must not be empty")
        #expect(update("zzzz", .init(title: "x")).0.error == "no item with id 'zzzz'")
    }

    @Test func patchWireFormatIsSnakeCase() throws {
        let json = #"{"op":"update","id":"t7k2","patch":{"due_at":"2027-01-15T08:00:00Z","clear_due":false,"kind":"task"}}"#
        let request = try PerchJSON.decoder.decode(Request.self, from: Data(json.utf8))
        #expect(request.op == .update)
        #expect(request.patch == .init(kind: .task, dueAt: Date(timeIntervalSince1970: 1_800_000_000), clearDue: false))
    }
}
