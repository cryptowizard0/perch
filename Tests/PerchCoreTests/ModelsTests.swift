import XCTest
@testable import PerchCore

final class ModelsTests: XCTestCase {
    func testItemRoundTripsThroughJSONWithSnakeCaseKeys() throws {
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
        XCTAssertTrue(json.contains("\"due_at\""))
        XCTAssertTrue(json.contains("\"created_at\""))
        XCTAssertFalse(json.contains("dueAt"))

        let back = try PerchJSON.decoder.decode(Item.self, from: data)
        XCTAssertEqual(back, item)
    }

    func testNewIDIsFourCharsFromSafeAlphabet() {
        let alphabet = Set("abcdefghjkmnpqrstuvwxyz23456789")
        for _ in 0..<100 {
            let id = Item.newID()
            XCTAssertEqual(id.count, 4)
            XCTAssertTrue(id.allSatisfy { alphabet.contains($0) })
        }
    }

    func testActionable() {
        XCTAssertTrue(Item(title: "a", kind: .task, status: .open).isActionable)
        XCTAssertTrue(Item(title: "a", kind: .request, status: .waiting).isActionable)
        XCTAssertFalse(Item(title: "a", kind: .notice, status: .open).isActionable)
        XCTAssertFalse(Item(title: "a", kind: .task, status: .done).isActionable)
    }

    func testRequestAndResponseEncode() throws {
        let req = Request(op: .add, item: Item(title: "x"))
        let data = try PerchJSON.encoder.encode(req)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"op\":\"add\""))
        let res = Response.failure("nope")
        XCTAssertFalse(res.ok)
        XCTAssertEqual(res.error, "nope")
    }
}
