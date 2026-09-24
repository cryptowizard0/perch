import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Every op over the real Unix socket and HTTP.
@Suite struct TransportTests {
    @Test func allOpsOverUnixSocket() throws {
        let d = try TestDaemon()
        let added = try #require(try d.client.send(Request(op: .add, item: Item(title: "a", kind: .request))).item)
        #expect(try d.client.send(Request(op: .get, id: added.id)).item == added)
        #expect(try d.client.send(Request(op: .list)).items == [added])
        #expect(try d.client.send(Request(op: .respond, id: added.id, value: "allow")).item?.response == "allow")
        let other = try #require(try d.client.send(Request(op: .add, item: Item(title: "b"))).item)
        #expect(try d.client.send(Request(op: .done, id: other.id)).item?.status == .done)
        #expect(try d.client.send(Request(op: .remove, id: other.id)).ok)
        #expect(try d.client.send(Request(op: .list, filter: .init(all: true))).items?.map(\.id) == [added.id])
    }

    @Test func minimalJSONOverHTTP() throws {
        let d = try TestDaemon()
        let (status, body) = try d.post(#"{"op":"add","item":{"title":"from hermes","source":"hermes"}}"#)
        #expect(status == 200)
        let item = try #require(try PerchJSON.decoder.decode(Response.self, from: Data(body.utf8)).item)
        #expect(item.source == "hermes")
        #expect(item.kind == .task)
        let (_, listed) = try d.post(#"{"op":"list","filter":{"source":"hermes"}}"#)
        #expect(listed.contains(item.id))
    }

    @Test func applicationErrorsAreOkFalseWith200() throws {
        let d = try TestDaemon()
        let (status, body) = try d.post(#"{"op":"done","id":"nope"}"#)
        #expect(status == 200)
        #expect(body == #"{"error":"no item with id 'nope'","ok":false}"#)
    }

    @Test func survivesRestartOnSameDatabase() throws {
        let d = try TestDaemon()
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "persist"))).item)
        let reopened = try Store(path: d.daemon.config.databasePath)
        #expect(try reopened.get(id: item.id) == item)
    }
}
