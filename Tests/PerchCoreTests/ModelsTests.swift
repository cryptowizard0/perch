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

@Suite struct ItemDecodingTests {
    @Test func onlyTitleIsRequired() throws {
        let item = try PerchJSON.decoder.decode(Item.self, from: Data(#"{"title":"hi"}"#.utf8))
        #expect(item.title == "hi")
        #expect(item.kind == .task)
        #expect(item.status == .open)
        #expect(item.source == "human")
        #expect(item.id.count == 4)
    }

    @Test func missingTitleIsAnError() {
        #expect(throws: DecodingError.self) { try PerchJSON.decoder.decode(Item.self, from: Data("{}".utf8)) }
    }
}

@Suite struct QueueOrderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func fixedOrder() {
        let t = { (s: TimeInterval) in self.now.addingTimeInterval(s) }
        let items = [
            Item(id: "dism", title: "", status: .dismissed, updatedAt: t(-1)),
            Item(id: "done", title: "", status: .done, updatedAt: t(-2)),
            Item(id: "note", title: "", kind: .notice),
            Item(id: "late", title: "", dueAt: t(86_400 * 3)),
            Item(id: "open", title: ""),
            Item(id: "tday", title: "", dueAt: t(3600)),
            Item(id: "over", title: "", dueAt: t(-60)),
            Item(id: "wait", title: "", status: .waiting),
            Item(id: "req2", title: "", kind: .request, status: .waiting, createdAt: t(10)),
            Item(id: "req1", title: "", kind: .request, status: .waiting, createdAt: t(0)),
        ]
        #expect(items.queueOrdered(now: now, calendar: calendar).map(\.id)
                == ["req1", "req2", "wait", "over", "tday", "late", "open", "note", "done", "dism"])
    }
}
