import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Todo priority (#42) through the real `perch` binary, the wire protocol and the `todo.md` mirror.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct PriorityCLITests {
    @Test func addTakesAPriorityAndDefaultsToNormal() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let high = try cli.run("add", "x", "-p", "high", "--json")
        #expect(high.status == 0 && high.stdout.contains(#""priority":"high""#))
        let plain = try cli.run("add", "y", "--json")
        #expect(plain.stdout.contains(#""priority":"normal""#))
        let long = try cli.run("add", "z", "--priority", "low", "--json").json.item
        #expect(long?.priority == .low)
        let id = try #require(high.json.item?.id)
        #expect(try cli.run("get", id).stdout.contains("priority: high"))
    }

    @Test func updateChangesThePriorityAndPushesAnUpdate() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let id = try cli.run("add", "renew the domain").stdout
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

    @Test func lsListsOpenTasksByPriorityAndMarksHighAndLow() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let low = try cli.run("add", "read the doc", "-p", "low").stdout
        let normal = try cli.run("add", "reply to Sam").stdout
        let high = try cli.run("add", "renew the domain", "-p", "high").stdout
        let overdueLow = try cli.run("add", "old low", "-p", "low", "--due", "+1m").stdout
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
        let cli = CLI(home: d.home)
        let low = try cli.run("add", "read the doc", "-p", "low").stdout
        let normal = try cli.run("add", "reply to Sam").stdout
        let high = try cli.run("add", "renew the domain", "-p", "high").stdout
        let mirror = try String(contentsOfFile: d.daemon.config.mirrorPath, encoding: .utf8)
        #expect(mirror.contains("""
        ## To do

        - [ ] renew the domain — high priority · human · `\(high)`
        - [ ] reply to Sam — human · `\(normal)`
        - [ ] read the doc — low priority · human · `\(low)`

        """))
    }
}

@Suite struct PriorityWireTests {
    /// HTTP clients that know nothing about priority keep working; their todos are Normal.
    @Test func anAddWithoutPriorityIsNormal() throws {
        let d = try TestDaemon()
        let (status, body) = try d.post(#"{"op":"add","item":{"title":"from a container"}}"#)
        #expect(status == 200 && body.contains(#""priority":"normal""#))
        let (_, high) = try d.post(#"{"op":"add","item":{"title":"urgent","priority":"high"}}"#)
        #expect(high.contains(#""priority":"high""#))
    }

    /// Re-adding with the same key takes the new priority like any other field.
    @Test func reAddingAKeyUpdatesThePriority() throws {
        let d = try TestDaemon()
        let first = try #require(try d.client.send(Request(op: .add, item: Item(title: "x", key: "k"))).item)
        let again = try #require(try d.client.send(Request(op: .add, item: Item(title: "x", priority: .high, key: "k"))).item)
        #expect(again.id == first.id && again.priority == .high)
        #expect(try d.client.send(Request(op: .get, id: first.id)).item?.priority == .high)
    }
}
