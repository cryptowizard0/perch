import Foundation
import PerchCore
import Testing
@testable import PerchDaemon

@Suite struct KeyTests {
    let service: Service
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let clock: Clock

    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    init() throws {
        service = Service(store: try Store(path: ":memory:"))
        clock = Clock(start)
        let clock = clock
        service.now = { clock.now }
    }

    func add(_ item: Item) -> (Item, [Event]) {
        let (response, events) = service.handle(Request(op: .add, item: item))
        #expect(response.ok, "\(response.error ?? "")")
        return (response.item!, events)
    }

    @Test func sameKeyUpdatesInsteadOfDuplicating() throws {
        let (first, e1) = add(Item(title: "needs permission", status: .waiting, source: "claude-code", key: "session-1"))
        clock.now = start.addingTimeInterval(30)
        let (second, e2) = add(Item(title: "needs input", status: .waiting, source: "claude-code", key: "session-1"))

        #expect(e1.map(\.type) == [.added])
        #expect(e2.map(\.type) == [.updated])
        #expect(second.id == first.id)
        #expect(second.title == "needs input")
        #expect(second.createdAt == start)
        #expect(second.updatedAt == start.addingTimeInterval(30))
        #expect(try service.store.count() == 1)
    }

    @Test func identicalReAddIsANoOp() {
        let (first, _) = add(Item(title: "same", key: "k"))
        clock.now = start.addingTimeInterval(5)
        let (second, events) = add(Item(title: "same", key: "k"))
        #expect(second == first)
        #expect(events.isEmpty)
    }

    @Test func reAddReopensAClosedItemAndClearsTheOldAnswer() {
        let (request, _) = add(Item(title: "npm test", kind: .request, status: .waiting, key: "perm-1"))
        _ = service.handle(Request(op: .respond, id: request.id, value: "allow"))
        let (again, events) = add(Item(title: "npm test", kind: .request, status: .waiting, key: "perm-1"))
        #expect(again.id == request.id)
        #expect(again.status == .waiting)
        #expect(again.response == nil)
        #expect(events.map(\.type) == [.updated])
    }

    @Test func differentKeysAndNoKeyStaySeparate() throws {
        _ = add(Item(title: "a", key: "k1"))
        _ = add(Item(title: "a", key: "k2"))
        _ = add(Item(title: "a"))
        _ = add(Item(title: "a"))
        _ = add(Item(title: "a", key: "  "))  // blank key = no key
        #expect(try service.store.count() == 5)
    }
}

/// `done --key`: hook adapters know their session key, not the item id.
@Suite struct DoneByKeyTests {
    @Test func doneByKey() throws {
        let service = Service(store: try Store(path: ":memory:"))
        let item = try #require(service.handle(Request(op: .add, item: Item(title: "claude needs input", status: .waiting,
                                                                              key: "claude-code:s1"))).0.item)
        let (response, events) = service.handle(Request(op: .done, key: "claude-code:s1"))
        #expect(response.item?.id == item.id && response.item?.status == .done)
        #expect(events.map(\.type) == [.updated])
        #expect(service.handle(Request(op: .done, key: "nope")).0.error == "no item with key 'nope'")
        #expect(service.handle(Request(op: .done, id: item.id, key: "claude-code:s1")).0.error == "give either id or key, not both")
    }

    @Test func cli() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let id = try cli.run("add", "waiting", "--status", "waiting", "--key", "k1").stdout
        let done = try cli.run("done", "--key", "k1", "--json").json.item
        #expect(done?.id == id && done?.status == .done)
        let neither = try cli.run("done")
        #expect(neither.status == 64)
        #expect(neither.stderr == "perch: give an id or --key")
        #expect(try cli.run("done", "--key", "zzz").stderr == "perch: no item with key 'zzz'")
    }
}
