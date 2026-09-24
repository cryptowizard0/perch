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
        let (response, events) = call(Request(op: .add, item: Item(id: "zzzz", title: "  write docs  ",
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
        let a = try add(Item(title: "a", source: "human"))
        let b = try add(Item(title: "b", source: "codex"))
        let c = try add(Item(title: "c", kind: .notice, source: "codex"))
        call(Request(op: .done, id: a.id))

        #expect(call(Request(op: .list)).0.items?.map(\.id) == [b.id, c.id])
        #expect(call(Request(op: .list, filter: .init(source: "codex", kind: .notice))).0.items?.map(\.id) == [c.id])
        #expect(call(Request(op: .list, filter: .init(status: .done))).0.items?.map(\.id) == [a.id])
        #expect(call(Request(op: .list, filter: .init(all: true))).0.items?.count == 3)
    }

    @Test func doneIsIdempotent() throws {
        let item = try add(Item(title: "x"))
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
        let task = try add(Item(title: "t"))
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
        let item = try add(Item(title: "gone"))
        let (response, events) = call(Request(op: .remove, id: item.id))
        #expect(response.item == item)
        #expect(events.map(\.type) == [.removed])
        #expect(call(Request(op: .get, id: item.id)).0.error == "no item with id '\(item.id)'")
    }

    @Test func unknownIdsAndMissingIds() {
        #expect(call(Request(op: .done, id: "nope")).0.error == "no item with id 'nope'")
        #expect(call(Request(op: .remove)).0.error == "missing id")
    }

    @Test func pingReportsVersion() {
        #expect(call(Request(op: .ping)).0.version == PerchVersion.string)
    }
}
