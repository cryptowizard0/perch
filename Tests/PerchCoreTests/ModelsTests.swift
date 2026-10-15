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

    @Test func expiryIsRoundedUpOnTheWire() throws {
        // The wire carries whole-second ISO-8601; truncating would shorten the window an agent asked for.
        let asked = Item(title: "r", kind: .request, expiresAt: Date(timeIntervalSince1970: 1_800_000_000.2))
        let json = String(decoding: try PerchJSON.encoder.encode(asked), as: UTF8.self)
        #expect(json.contains("\"expires_at\":\"2027-01-15T08:00:01Z\""))
        let back = try PerchJSON.decoder.decode(Item.self, from: Data(json.utf8))
        #expect(back.expiresAt == Date(timeIntervalSince1970: 1_800_000_001))

        let whole = Item(title: "r", kind: .request, expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try PerchJSON.decoder.decode(Item.self, from: PerchJSON.encoder.encode(whole)).expiresAt == whole.expiresAt)
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
        #expect(item.priority == .normal)
        #expect(item.kind == .task)
        #expect(item.status == .open)
        #expect(item.source == "human")
        #expect(item.id.count == 4)
    }

    @Test func priorityRoundTripsAndAPatchCarriesIt() throws {
        let item = try PerchJSON.decoder.decode(Item.self, from: Data(#"{"title":"hi","priority":"low"}"#.utf8))
        #expect(item.priority == .low)
        #expect(String(decoding: try PerchJSON.encoder.encode(item), as: UTF8.self).contains(#""priority":"low""#))
        let patch = try PerchJSON.decoder.decode(Request.Patch.self, from: Data(#"{"priority":"high"}"#.utf8))
        #expect(patch.priority == .high && !patch.isEmpty)
        #expect(throws: DecodingError.self) {
            try PerchJSON.decoder.decode(Item.self, from: Data(#"{"title":"hi","priority":"urgent"}"#.utf8))
        }
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

    /// Open tasks go High, Normal, Low (#41), each in the usual order; requests, waiting items and notices don't move.
    @Test func openTasksGoByPriorityFirst() {
        let t = { (s: TimeInterval) in self.now.addingTimeInterval(s) }
        let items = [
            Item(id: "lowo", title: "", priority: .low, dueAt: t(-60)),
            Item(id: "low1", title: "", priority: .low, createdAt: t(-10)),
            Item(id: "norm", title: "", dueAt: t(3600)),
            Item(id: "nrm2", title: ""),
            Item(id: "hig2", title: "", priority: .high, createdAt: t(5)),
            Item(id: "hig1", title: "", priority: .high, createdAt: t(0)),
            Item(id: "note", title: "", kind: .notice, priority: .high),
            Item(id: "wait", title: "", status: .waiting, priority: .low),
            Item(id: "reqq", title: "", kind: .request, status: .waiting, priority: .low),
            Item(id: "done", title: "", status: .done, priority: .high),
        ]
        #expect(items.queueOrdered(now: now, calendar: calendar).map(\.id)
                == ["reqq", "wait", "hig1", "hig2", "norm", "nrm2", "lowo", "low1", "note", "done"])
    }
}
