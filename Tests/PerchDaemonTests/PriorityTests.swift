import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Priority (#42) through the real `perch` binary, the wire protocol and the `todo.md` mirror. Todos come from the
/// Reminders list (#51), so they arrive as snapshots; the CLI sets priority on perchd's own items (waiting tasks…).
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct PriorityCLITests {
    @Test func addTakesAPriorityAndDefaultsToNormal() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let high = try cli.run("add", "x", "--status", "waiting", "-p", "high", "--json")
        #expect(high.status == 0 && high.stdout.contains(#""priority":"high""#))
        let plain = try cli.run("add", "y", "--status", "waiting", "--json")
        #expect(plain.stdout.contains(#""priority":"normal""#))
        let long = try cli.run("add", "z", "--status", "waiting", "--priority", "low", "--json").json.item
        #expect(long?.priority == .low)
        let id = try #require(high.json.item?.id)
        #expect(try cli.run("get", id).stdout.contains("priority: high"))
    }

    @Test func updateChangesThePriorityAndPushesAnUpdate() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let id = try cli.run("add", "renew the domain", "--status", "waiting").stdout
        let stream = try d.client.watch()
        let updated = try cli.run("update", id, "--priority", "low", "--json")
        #expect(updated.status == 0 && updated.json.item?.priority == .low)
        let event = try #require(try stream.next(timeout: 5))
        #expect(event.type == .updated && event.item.id == id && event.item.priority == .low)
        #expect(try cli.run("update", id, "-p", "high").stdout == "updated \(id)  renew the domain")
        #expect(try d.client.send(Request(op: .get, id: id)).item?.priority == .high)
    }

    @Test func anInvalidPriorityIsAUsageError() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        for args in [["add", "x", "-p", "urgent"], ["update", "abcd", "--priority", "urgent"]] {
            let plain = try cli.run(args)
            #expect(plain.status == 64)
            #expect(plain.stderr == "perch: --priority must be high, normal or low, got 'urgent'")
            let json = try cli.run(args + ["--json"])
            #expect(json.status == 64)
            #expect(json.stdout == #"{"error":"--priority must be high, normal or low, got 'urgent'","ok":false}"#)
        }
        #expect(try d.client.send(Request(op: .list)).items?.isEmpty == true)
    }

    /// The reminders' priorities as Perch reads them: 1 high, 0 normal, 9 low.
    func cache(_ d: TestDaemon) throws -> (EventStream, [String: String]) {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let bridge = try d.bridge([
            Reminder(externalID: "low", title: "read the doc", priority: 9, createdAt: t0),
            Reminder(externalID: "normal", title: "reply to Sam", createdAt: t0.addingTimeInterval(1)),
            Reminder(externalID: "high", title: "renew the domain", priority: 1, createdAt: t0.addingTimeInterval(2)),
            Reminder(externalID: "overdueLow", title: "old low", priority: 6, dueAt: t0, createdAt: t0.addingTimeInterval(3)),
        ])
        let items = try d.client.send(Request(op: .list, filter: Request.Filter(kind: .task))).items ?? []
        return (bridge, Dictionary(uniqueKeysWithValues: items.map { ($0.reminderID!, $0.id) }))
    }

    @Test func lsListsOpenTasksByPriorityAndMarksHighAndLow() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let (bridge, ids) = try cache(d)
        defer { bridge.close() }
        let (low, normal, high, overdueLow) = (ids["low"]!, ids["normal"]!, ids["high"]!, ids["overdueLow"]!)
        let request = try cli.run("add", "npm test", "--kind", "request").stdout
        #expect(try cli.run("ls", "--json").json.items?.map(\.id) == [request, high, normal, overdueLow, low])
        let lines = try cli.run("ls").stdout.split(separator: "\n").map(String.init)
        #expect(lines.count == 5)
        #expect(lines[1].hasPrefix(high) && lines[1].contains("renew the domain  · high priority"))
        #expect(lines[2].hasPrefix(normal) && !lines[2].contains("priority"))
        #expect(lines[4].hasPrefix(low) && lines[4].hasSuffix("read the doc  · low priority"))
    }

    @Test func theMirrorListsToDoByPriority() throws {
        let d = try TestDaemon()
        let (bridge, ids) = try cache(d)
        defer { bridge.close() }
        let mirror = try String(contentsOfFile: d.daemon.config.mirrorPath, encoding: .utf8)
        #expect(mirror.contains("""
        ## To do

        - [ ] renew the domain — high priority · reminders · `\(ids["high"]!)`
        - [ ] reply to Sam — reminders · `\(ids["normal"]!)`
        - [ ] old low — low priority · due \(local(1_800_000_000)) · reminders · `\(ids["overdueLow"]!)`
        - [ ] read the doc — low priority · reminders · `\(ids["low"]!)`

        """))
    }

    /// How todo.md writes a due time: local, to the minute.
    private func local(_ seconds: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}

@Suite struct PriorityWireTests {
    /// HTTP clients that know nothing about priority keep working; their items are Normal.
    @Test func anAddWithoutPriorityIsNormal() throws {
        let d = try TestDaemon()
        let (status, body) = try d.post(#"{"op":"add","item":{"title":"from a container","status":"waiting"}}"#)
        #expect(status == 200 && body.contains(#""priority":"normal""#))
        let (_, high) = try d.post(#"{"op":"add","item":{"title":"urgent","priority":"high","kind":"notice"}}"#)
        #expect(high.contains(#""priority":"high""#))
    }

    /// Re-adding with the same key takes the new priority like any other field.
    @Test func reAddingAKeyUpdatesThePriority() throws {
        let d = try TestDaemon()
        let first = try #require(try d.client.send(Request(op: .add, item: Item(title: "x", status: .waiting, key: "k"))).item)
        let again = try #require(try d.client.send(Request(op: .add, item: Item(title: "x", status: .waiting, priority: .high, key: "k"))).item)
        #expect(again.id == first.id && again.priority == .high)
        #expect(try d.client.send(Request(op: .get, id: first.id)).item?.priority == .high)
    }
}
