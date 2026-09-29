import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

@Suite struct StartupTests {
    @Test func createsHomeAndItemsTable() throws {
        let d = try TestDaemon()
        #expect(FileManager.default.fileExists(atPath: d.daemon.config.databasePath))
        #expect(try d.daemon.service.store.count() == 0)
        let mode = try FileManager.default.attributesOfItem(atPath: d.daemon.config.socketPath)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func storeReopensExistingDatabase() throws {
        let path = "/tmp/perch-test-\(UUID().uuidString.prefix(8)).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        _ = try Store(path: path)
        #expect(try Store(path: path).count() == 0)
    }

    /// A v1 database (items only, from before sessions were stored) gains the sessions table and keeps its items.
    @Test func migratesAV1Database() throws {
        let path = "/tmp/perch-test-v1-\(UUID().uuidString.prefix(8)).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let v1 = try SQLiteDatabase(path: path)
            try v1.execute("""
            CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
                source TEXT NOT NULL, due_at TEXT, link TEXT, meta TEXT, key TEXT UNIQUE, options TEXT, response TEXT,
                expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
            INSERT INTO items VALUES ('t7k2', 'kept', 'task', 'open', 'human', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z');
            PRAGMA user_version = 1;
            """)
        }
        let store = try Store(path: path)
        #expect(try store.get(id: "t7k2")?.title == "kept")
        try store.save(Session(id: "s1", source: "codex", title: "perch", startedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(try store.sessions().map(\.id) == ["s1"])
        var version = 0
        try store.db.run("PRAGMA user_version") { version = $0.int(0) }
        #expect(version == Store.schemaVersion && version == 2)
    }

    @Test func pingOverUnixSocket() throws {
        let d = try TestDaemon()
        let response = try d.client.send(Request(op: .ping))
        #expect(response.ok)
        #expect(response.version == PerchVersion.string)
    }

    @Test func invalidJSONOverSocketExplainsTheProblem() throws {
        let d = try TestDaemon()
        let socket = try BufferedSocket.connect(unixPath: d.daemon.config.socketPath)
        defer { socket.close() }
        socket.setReadTimeout(5)
        try socket.writeLine(Data(#"{"nope":1}"#.utf8))
        let response = try PerchJSON.decoder.decode(Response.self, from: try #require(try socket.readLine()))
        #expect(!response.ok)
        #expect(response.error?.contains("'op'") == true)
    }

    @Test func pingOverHTTP() throws {
        let d = try TestDaemon()
        let (status, body) = try d.post(#"{"op":"ping"}"#)
        #expect(status == 200)
        #expect(body.contains(#""ok":true"#))
    }

    @Test func httpRefusesBrowsers() throws {
        let d = try TestDaemon()
        #expect(try d.post(#"{"op":"ping"}"#, headers: "Origin: https://evil.example\r\n").0 == 403)
        let textPlain = "POST /rpc HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\n{\"op\":\"ping\"}"
        #expect(try d.http(textPlain).0 == 415)
        let rebound = "POST /rpc HTTP/1.1\r\nHost: evil.example:7331\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"op\":\"ping\"}"
        #expect(try d.http(rebound).0 == 403)
        #expect(try d.http("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n").0 == 404)
    }

    @Test func clientReportsDaemonNotRunning() throws {
        let client = PerchClient(socketPath: "/tmp/perch-test-missing.sock")
        #expect(throws: ClientError.self) { try client.send(Request(op: .ping)) }
        do {
            _ = try client.send(Request(op: .ping))
        } catch {
            #expect(String(describing: error).contains("perchd is not running"))
        }
    }
}

extension StartupTests {
    /// Before #19 the Claude Code / Codex hooks also posted waiting and notice items, and only the hooks closed them.
    /// perchd dismisses whatever an upgrade left behind; everything else stays.
    @Test func dismissesItemsTheOldHooksLeftBehind() throws {
        let home = TestDaemon.freshHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var kept: [String] = []
        var stale: [String] = []
        do {
            let d = try TestDaemon(home: home, removeHome: false)
            func add(_ item: Item) throws -> String { try #require(try d.client.send(Request(op: .add, item: item)).item?.id) }
            stale.append(try add(Item(title: "perch · rm -rf build/", status: .waiting, source: "claude-code",
                                      meta: ["session_id": "s1", "tool": "Bash"], key: "claude-code:s1")))
            stale.append(try add(Item(title: "site · apply_patch", status: .waiting, source: "codex", key: "codex:019a")))
            stale.append(try add(Item(title: "perch · All tests pass.", kind: .notice, source: "claude-code",
                                      key: "claude-code:s1:done", expiresAt: Date().addingTimeInterval(600))))
            // Allowlisted requests are still how the hooks ask; Hermes still posts items; people add their own.
            kept.append(try add(Item(title: "npm test", kind: .request, source: "claude-code", meta: ["session_id": "s2"])))
            kept.append(try add(Item(title: "perch · rm -rf x", status: .waiting, source: "hermes", key: "hermes:default:c1")))
            kept.append(try add(Item(title: "review the PR", source: "claude-code")))
            kept.append(try add(Item(title: "write docs", key: "claude-code:mine")))
            try? FileManager.default.removeItem(atPath: d.daemon.config.socketPath)  // perchd's startup does this
        }
        let restarted = try TestDaemon(home: home, removeHome: false)
        #expect(Set(try restarted.client.send(Request(op: .list)).items?.map(\.id) ?? []) == Set(kept))
        for id in stale {
            #expect(try restarted.client.send(Request(op: .get, id: id)).item?.status == .dismissed)
        }
        let mirror = try String(contentsOfFile: restarted.daemon.config.mirrorPath, encoding: .utf8)
        #expect(!mirror.contains("rm -rf build/") && mirror.contains("review the PR"))
    }
}
