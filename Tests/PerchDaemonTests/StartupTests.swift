import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

@Suite struct StartupTests {
    @Test func createsHomeAndItemsTable() throws {
        let d = try TestDaemon()
        #expect(FileManager.default.fileExists(atPath: d.daemon.config.databasePath))
        // On perchd's queue: the connection is single-threaded, and startup work may still be using it.
        #expect(try d.daemon.queue.sync { try d.daemon.service.store.count() } == 0)
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
            INSERT INTO items VALUES ('t7k2', 'kept', 'task', 'waiting', 'hermes', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
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
        #expect(version == Store.schemaVersion && version == 7)
    }

    /// A v3 database (before todo priority, #41) gains the priority column; every existing item is Normal.
    @Test func migratesAV3DatabaseToNormalPriority() throws {
        let path = "/tmp/perch-test-v3-\(UUID().uuidString.prefix(8)).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let v3 = try SQLiteDatabase(path: path)
            try v3.execute("""
            CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
                source TEXT NOT NULL, due_at TEXT, link TEXT, meta TEXT, key TEXT UNIQUE, options TEXT, response TEXT,
                expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
            CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL, cwd TEXT, link TEXT,
                status TEXT NOT NULL, prompt TEXT, last_message TEXT, detail TEXT, error TEXT, pid INTEGER, pid_started_at TEXT,
                started_at TEXT NOT NULL, turn_started_at TEXT NOT NULL, status_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                transcript_path TEXT);
            INSERT INTO items VALUES ('t7k2', 'waiting task', 'task', 'waiting', 'hermes', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z');
            INSERT INTO items VALUES ('d0ne', 'a notice', 'notice', 'open', 'codex', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                '2027-01-15T08:00:00Z', '2027-01-15T09:00:00Z');
            INSERT INTO items VALUES ('rq22', 'npm test', 'request', 'waiting', 'claude-code', NULL, NULL, NULL, NULL,
                '["allow","deny"]', NULL, NULL, '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z');
            PRAGMA user_version = 3;
            """)
        }
        let store = try Store(path: path)
        let items = try store.list(Request.Filter(all: true))
        #expect(Set(items.map(\.id)) == ["t7k2", "d0ne", "rq22"])
        #expect(items.allSatisfy { $0.priority == .normal })
        var version = 0
        try store.db.run("PRAGMA user_version") { version = $0.int(0) }
        #expect(version == Store.schemaVersion)
        var high = try #require(try store.get(id: "t7k2"))
        high.priority = .high
        try store.update(high)
        #expect(try Store(path: path).get(id: "t7k2")?.priority == .high)
    }

    /// v5 (#51): todos move to the "Perch" Reminders list. The old open and done tasks are deleted (no migration into
    /// Reminders); waiting and dismissed tasks, notices and requests stay, and the cache starts empty.
    @Test func migratingToV5DropsTheOldTodosOnly() throws {
        let path = "/tmp/perch-test-v4-\(UUID().uuidString.prefix(8)).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let v4 = try SQLiteDatabase(path: path)
            try v4.execute("""
            CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
                source TEXT NOT NULL, due_at TEXT, link TEXT, meta TEXT, key TEXT UNIQUE, options TEXT, response TEXT,
                expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'normal');
            CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL, cwd TEXT, link TEXT,
                status TEXT NOT NULL, prompt TEXT, last_message TEXT, detail TEXT, error TEXT, pid INTEGER, pid_started_at TEXT,
                started_at TEXT NOT NULL, turn_started_at TEXT NOT NULL, status_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                transcript_path TEXT);
            INSERT INTO items (id, title, kind, status, source, created_at, updated_at) VALUES
                ('open', 'buy milk', 'task', 'open', 'human', '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z'),
                ('done', 'filed taxes', 'task', 'done', 'human', '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z'),
                ('wait', 'approve in Telegram', 'task', 'waiting', 'hermes', '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z'),
                ('gone', 'old', 'task', 'dismissed', 'human', '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z'),
                ('note', 'codex finished', 'notice', 'open', 'codex', '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z'),
                ('rq22', 'npm test', 'request', 'done', 'claude-code', '2027-01-15T08:00:00Z', '2027-01-15T08:00:00Z');
            PRAGMA user_version = 4;
            """)
        }
        let store = try Store(path: path)
        #expect(Set(try store.list(Request.Filter(all: true)).map(\.id)) == ["wait", "gone", "note", "rq22"])
        #expect(try store.todos().isEmpty && store.todoRefs().isEmpty)
        // Reopening leaves everything as it is.
        #expect(try Store(path: path).count() == 4)
    }

    /// v6 (#52): items gain `due_date_only` (false for everything already there), and perchd remembers how old its
    /// todo cache is across restarts.
    @Test func migratingToV6KeepsItemsAndRemembersTheCacheAge() throws {
        let path = "/tmp/perch-test-v5-\(UUID().uuidString.prefix(8)).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let v5 = try SQLiteDatabase(path: path)
            try v5.execute("""
            CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
                source TEXT NOT NULL, due_at TEXT, link TEXT, meta TEXT, key TEXT UNIQUE, options TEXT, response TEXT,
                expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'normal');
            CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL, cwd TEXT, link TEXT,
                status TEXT NOT NULL, prompt TEXT, last_message TEXT, detail TEXT, error TEXT, pid INTEGER, pid_started_at TEXT,
                started_at TEXT NOT NULL, turn_started_at TEXT NOT NULL, status_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                transcript_path TEXT);
            CREATE TABLE todo_refs (id TEXT PRIMARY KEY, external_id TEXT NOT NULL UNIQUE, key TEXT UNIQUE);
            INSERT INTO items (id, title, kind, status, source, due_at, created_at, updated_at) VALUES
                ('wait', 'approve in Telegram', 'task', 'waiting', 'hermes', '2027-01-16T00:00:00Z', '2027-01-15T08:00:00Z',
                 '2027-01-15T08:00:00Z');
            PRAGMA user_version = 5;
            """)
        }
        let store = try Store(path: path)
        let item = try #require(try store.get(id: "wait"))
        #expect(item.dueAt != nil && !item.dueDateOnly)
        #expect(try store.todosAsOf() == nil)
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        try store.setTodosAsOf(asOf)
        #expect(try Store(path: path).todosAsOf() == asOf)
    }

    /// v7 (#71): todo references gain `doing` (false for every one already there); short ids and keys stay.
    @Test func migratingToV7AddsDoingToTodoReferences() throws {
        let path = "/tmp/perch-test-v6-\(UUID().uuidString.prefix(8)).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let v6 = try SQLiteDatabase(path: path)
            try v6.execute("""
            CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, status TEXT NOT NULL,
                source TEXT NOT NULL, due_at TEXT, link TEXT, meta TEXT, key TEXT UNIQUE, options TEXT, response TEXT,
                expires_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'normal',
                due_date_only INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, title TEXT NOT NULL, cwd TEXT, link TEXT,
                status TEXT NOT NULL, prompt TEXT, last_message TEXT, detail TEXT, error TEXT, pid INTEGER, pid_started_at TEXT,
                started_at TEXT NOT NULL, turn_started_at TEXT NOT NULL, status_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                transcript_path TEXT);
            CREATE TABLE todo_refs (id TEXT PRIMARY KEY, external_id TEXT NOT NULL UNIQUE, key TEXT UNIQUE);
            CREATE TABLE daemon_state (name TEXT PRIMARY KEY, value TEXT NOT NULL);
            INSERT INTO todo_refs VALUES ('t7k2', 'R-1', 'k1');
            INSERT INTO items (id, title, kind, status, source, meta, key, created_at, updated_at) VALUES
                ('t7k2', 'buy milk', 'task', 'open', 'reminders', '{"reminder":"R-1"}', 'k1', '2027-01-15T08:00:00Z',
                 '2027-01-15T08:00:00Z');
            PRAGMA user_version = 6;
            """)
        }
        let store = try Store(path: path)
        #expect(try store.todoRefs() == [TodoRef(id: "t7k2", externalID: "R-1", key: "k1", doing: false)])
        #expect(try store.get(id: "t7k2")?.doing == false)
        try store.setDoing(true, forRef: "t7k2")
        let reopened = try Store(path: path)
        #expect(try reopened.todoRef(externalID: "R-1")?.doing == true)
        #expect(try reopened.get(id: "t7k2")?.doing == true)
        var version = 0
        try reopened.db.run("PRAGMA user_version") { version = $0.int(0) }
        #expect(version == 7)
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
            kept.append(try add(Item(title: "review the PR", status: .waiting, source: "claude-code")))
            kept.append(try add(Item(title: "write docs", status: .waiting, key: "claude-code:mine")))
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
