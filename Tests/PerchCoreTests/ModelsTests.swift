import Foundation
import Testing
@testable import PerchCore

@Suite struct ModelsTests {
    @Test func itemRoundTripsThroughJSONWithSnakeCaseKeys() throws {
        let item = Item(
            id: "t7k2",
            title: "review PR #42",
            kind: .request,
            status: .waiting,
            source: "claude-code",
            dueAt: Date(timeIntervalSince1970: 1_800_000_000),
            link: "tmux://main:2",
            meta: ["cwd": "/tmp/repo"],
            key: "session-abc",
            options: ["allow", "deny"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try PerchJSON.encoder.encode(item)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"due_at\""))
        #expect(json.contains("\"created_at\""))
        #expect(!json.contains("dueAt"))

        let back = try PerchJSON.decoder.decode(Item.self, from: data)
        #expect(back == item)
    }

    @Test func newIDIsFourCharsFromSafeAlphabet() {
        let alphabet = Set("abcdefghjkmnpqrstuvwxyz23456789")
        for _ in 0..<100 {
            let id = Item.newID()
            #expect(id.count == 4)
            #expect(id.allSatisfy { alphabet.contains($0) })
        }
    }

    @Test func actionable() {
        #expect(Item(title: "a", kind: .task, status: .open).isActionable)
        #expect(Item(title: "a", kind: .request, status: .waiting).isActionable)
        #expect(!Item(title: "a", kind: .notice, status: .open).isActionable)
        #expect(!Item(title: "a", kind: .task, status: .done).isActionable)
    }

    @Test func requestAndResponseEncode() throws {
        let req = Request(op: .add, item: Item(title: "x"))
        let data = try PerchJSON.encoder.encode(req)
        #expect(String(decoding: data, as: UTF8.self).contains("\"op\":\"add\""))
        let res = Response.failure("nope")
        #expect(!res.ok)
        #expect(res.error == "nope")
    }
}
