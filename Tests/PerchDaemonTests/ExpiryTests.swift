import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

@Suite struct ExpiryTests {
    @Test func sweepDismissesOnlyExpiredActiveItems() throws {
        let service = Service(store: try Store(path: ":memory:"))
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        service.now = { now }
        func add(_ item: Item) -> Item { service.handle(Request(op: .add, item: item)).0.item! }

        let expiring = add(Item(title: "npm test", kind: .request, expiresAt: now.addingTimeInterval(30)))
        let later = add(Item(title: "notice", kind: .notice, expiresAt: now.addingTimeInterval(90)))
        let answered = add(Item(title: "answered", kind: .request, expiresAt: now.addingTimeInterval(30)))
        _ = service.handle(Request(op: .respond, id: answered.id, value: "allow"))
        _ = add(Item(title: "no expiry"))

        #expect(service.nextExpiry() == now.addingTimeInterval(30))
        now = now.addingTimeInterval(30)
        let events = service.sweepExpired()
        #expect(events.map(\.item.id) == [expiring.id])
        #expect(events.first?.type == .updated)
        #expect(events.first?.item.status == .dismissed)
        #expect(service.nextExpiry() == later.expiresAt)
        #expect(service.sweepExpired().isEmpty)
    }

    @Test func expiresIsRoundedUpNotDown() throws {
        let service = Service(store: try Store(path: ":memory:"))
        let asked = Date(timeIntervalSince1970: 1_800_000_000.4)
        let item = service.handle(Request(op: .add, item: Item(title: "r", kind: .request, expiresAt: asked))).0.item!
        #expect(item.expiresAt == Date(timeIntervalSince1970: 1_800_000_001))
    }

    @Test func daemonDismissesOnTimeAndTellsWatchers() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        let added = try #require(try d.client.send(Request(op: .add, item: Item(
            title: "short-lived", kind: .request, expiresAt: Date().addingTimeInterval(1)))).item)
        #expect(try stream.next(timeout: 1)?.type == .added)
        let expired = try #require(try stream.next(timeout: 3))
        #expect(expired.item.id == added.id)
        #expect(expired.item.status == .dismissed)
        #expect(Date() >= added.expiresAt!)
    }
}
