import Foundation
import PerchCore

/// The `items`, `sessions` and `todo_refs` tables. Columns map 1:1 to `Item` / `Session`; dates are ISO-8601 UTC text,
/// `meta` / `options` are JSON text. Only perchd opens this database.
public final class Store {
    public static let schemaVersion = 6

    let db: SQLiteDatabase

    /// `path` may be `":memory:"` for tests.
    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try db.execute("PRAGMA journal_mode = WAL")
        try migrate()
    }

    static let columns = "id, title, kind, status, source, due_at, link, meta, key, options, response, expires_at, created_at, updated_at, priority, due_date_only"

    public func insert(_ item: Item) throws {
        try db.run("INSERT INTO items (\(Self.columns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", values(item))
    }

    /// Overwrites every column of the row with `item.id`.
    public func update(_ item: Item) throws {
        var args = Array(values(item).dropFirst())
        args.append(.text(item.id))
        try db.run("""
        UPDATE items SET title = ?, kind = ?, status = ?, source = ?, due_at = ?, link = ?, meta = ?, key = ?,
            options = ?, response = ?, expires_at = ?, created_at = ?, updated_at = ?, priority = ?, due_date_only = ?
        WHERE id = ?
        """, args)
    }

    @discardableResult
    public func delete(id: String) throws -> Bool {
        try db.run("DELETE FROM items WHERE id = ?", [.text(id)])
        return db.changes > 0
    }

    public func get(id: String) throws -> Item? {
        try select("WHERE id = ?", [.text(id)]).first
    }

    public func find(key: String) throws -> Item? {
        try select("WHERE key = ?", [.text(key)]).first
    }

    /// Without a status filter only active items (open, waiting) are returned, unless `filter.all`.
    public func list(_ filter: Request.Filter?) throws -> [Item] {
        var clauses: [String] = []
        var args: [SQLValue] = []
        if let status = filter?.status {
            clauses.append("status = ?")
            args.append(.text(status.rawValue))
        } else if filter?.all != true {
            clauses.append("status IN ('open', 'waiting')")
        }
        if let source = filter?.source {
            clauses.append("source = ?")
            args.append(.text(source))
        }
        if let kind = filter?.kind {
            clauses.append("kind = ?")
            args.append(.text(kind.rawValue))
        }
        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        return try select(whereSQL, args)
    }

    /// Active items whose `expires_at` is at or before `date`.
    public func expired(at date: Date) throws -> [Item] {
        try select("WHERE status IN ('open', 'waiting') AND expires_at IS NOT NULL AND expires_at <= ?",
                   [.text(Self.formatDate(date))])
    }

    /// The earliest `expires_at` among active items.
    public func nextExpiry() throws -> Date? {
        var next: String?
        try db.run("SELECT MIN(expires_at) FROM items WHERE status IN ('open', 'waiting') AND expires_at IS NOT NULL") {
            next = $0.text(0)
        }
        return next.flatMap { Self.dateFormatter.date(from: $0) }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try db.transaction(body)
    }

    public func count() throws -> Int {
        var n = 0
        try db.run("SELECT COUNT(*) FROM items") { n = $0.int(0) }
        return n
    }

    private func select(_ tail: String, _ args: [SQLValue]) throws -> [Item] {
        var items: [Item] = []
        try db.run("SELECT \(Self.columns) FROM items \(tail) ORDER BY created_at, id", args) { row in
            items.append(try Self.item(from: row))
        }
        return items
    }

    private func values(_ item: Item) -> [SQLValue] {
        [
            .text(item.id), .text(item.title), .text(item.kind.rawValue), .text(item.status.rawValue), .text(item.source),
            SQLValue(item.dueAt.map(Self.formatDate)), SQLValue(item.link), SQLValue(item.meta.flatMap(Self.json)),
            SQLValue(item.key), SQLValue(item.options.flatMap(Self.json)), SQLValue(item.response),
            SQLValue(item.expiresAt.map(Self.formatDate)),
            .text(Self.formatDate(item.createdAt)), .text(Self.formatDate(item.updatedAt)), .text(item.priority.rawValue),
            .int(item.dueDateOnly ? 1 : 0),
        ]
    }

    private static func item(from row: SQLiteDatabase.Row) throws -> Item {
        func required(_ column: Int32) throws -> String {
            guard let text = row.text(column) else { throw SQLiteError(description: "NULL in required column \(column)") }
            return text
        }
        func date(_ column: Int32) throws -> Date? {
            guard let text = row.text(column) else { return nil }
            guard let date = dateFormatter.date(from: text) else { throw SQLiteError(description: "bad date '\(text)'") }
            return date
        }
        guard let kind = ItemKind(rawValue: try required(2)), let status = ItemStatus(rawValue: try required(3)) else {
            throw SQLiteError(description: "bad kind/status in row \(row.text(0) ?? "?")")
        }
        return Item(
            id: try required(0), title: try required(1), kind: kind, status: status,
            priority: row.text(14).flatMap(ItemPriority.init(rawValue:)) ?? .normal, source: try required(4),
            dueAt: try date(5), dueDateOnly: row.int(15) != 0, link: row.text(6),
            meta: row.text(7).flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) },
            key: row.text(8),
            options: row.text(9).flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) },
            response: row.text(10), expiresAt: try date(11),
            createdAt: try date(12)!, updatedAt: try date(13)!
        )
    }

    static let dateFormatter = ISO8601DateFormatter()

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func json<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func migrate() throws {
        var version = 0
        try db.run("PRAGMA user_version") { version = $0.int(0) }
        guard version <= Self.schemaVersion else {
            throw SQLiteError(description: "database schema v\(version) is newer than this perchd (v\(Self.schemaVersion)); upgrade perchd")
        }
        if version < 1 {
            try db.execute("""
            CREATE TABLE items (
                id         TEXT PRIMARY KEY,
                title      TEXT NOT NULL,
                kind       TEXT NOT NULL CHECK (kind IN ('task', 'notice', 'request')),
                status     TEXT NOT NULL CHECK (status IN ('open', 'waiting', 'done', 'dismissed')),
                source     TEXT NOT NULL,
                due_at     TEXT,
                link       TEXT,
                meta       TEXT,
                key        TEXT UNIQUE,
                options    TEXT,
                response   TEXT,
                expires_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE INDEX items_status ON items (status);
            PRAGMA user_version = 1;
            """)
        }
        if version < 2 {
            try db.execute("""
            CREATE TABLE sessions (
                id              TEXT PRIMARY KEY,
                source          TEXT NOT NULL,
                title           TEXT NOT NULL,
                cwd             TEXT,
                link            TEXT,
                status          TEXT NOT NULL CHECK (status IN ('waiting', 'failed', 'running', 'done', 'idle')),
                prompt          TEXT,
                last_message    TEXT,
                detail          TEXT,
                error           TEXT,
                pid             INTEGER,
                pid_started_at  TEXT,
                started_at      TEXT NOT NULL,
                turn_started_at TEXT NOT NULL,
                status_at       TEXT NOT NULL,
                updated_at      TEXT NOT NULL
            );
            PRAGMA user_version = 2;
            """)
        }
        if version < 3 {
            // Claude Code's transcript, watched for interruptions no hook reports (#8).
            try db.execute("""
            ALTER TABLE sessions ADD COLUMN transcript_path TEXT;
            PRAGMA user_version = 3;
            """)
        }
        if version < 4 {
            // Todo priority (#41); every existing item is Normal.
            try db.execute("""
            ALTER TABLE items ADD COLUMN priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('high', 'normal', 'low'));
            PRAGMA user_version = 4;
            """)
        }
        if version < 5 {
            // Todos live in the "Perch" Reminders list (#51): open and done tasks become a cache of it, with these
            // references (short id ↔ reminder ↔ key). The old local todos go; waiting tasks, notices and requests stay.
            try db.execute("""
            CREATE TABLE todo_refs (
                id          TEXT PRIMARY KEY,
                external_id TEXT NOT NULL UNIQUE,
                key         TEXT UNIQUE
            );
            DELETE FROM items WHERE kind = 'task' AND status IN ('open', 'done');
            PRAGMA user_version = 5;
            """)
        }
        if version < 6 {
            // Date-only due dates (#52), and perchd's own small state (how old the todo cache is).
            try db.execute("""
            ALTER TABLE items ADD COLUMN due_date_only INTEGER NOT NULL DEFAULT 0;
            CREATE TABLE daemon_state (
                name  TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            PRAGMA user_version = 6;
            """)
        }
    }
}

// MARK: - Sessions

extension Store {
    static let sessionColumns = """
    id, source, title, cwd, link, status, prompt, last_message, detail, error, pid, pid_started_at, \
    started_at, turn_started_at, status_at, updated_at, transcript_path
    """

    /// Inserts or overwrites the row with `session.id`.
    public func save(_ s: Session) throws {
        let values: [SQLValue] = [
            .text(s.id), .text(s.source), .text(s.title), SQLValue(s.cwd), SQLValue(s.link), .text(s.status.rawValue),
            SQLValue(s.prompt), SQLValue(s.lastMessage), SQLValue(s.detail), SQLValue(s.error),
            SQLValue(s.pid), SQLValue(s.pidStartedAt.map(Self.formatDate)),
            .text(Self.formatDate(s.startedAt)), .text(Self.formatDate(s.turnStartedAt)),
            .text(Self.formatDate(s.statusAt)), .text(Self.formatDate(s.updatedAt)), SQLValue(s.transcriptPath),
        ]
        let marks = Array(repeating: "?", count: values.count).joined(separator: ", ")
        try db.run("INSERT OR REPLACE INTO sessions (\(Self.sessionColumns)) VALUES (\(marks))", values)
    }

    @discardableResult
    public func deleteSession(id: String) throws -> Bool {
        try db.run("DELETE FROM sessions WHERE id = ?", [.text(id)])
        return db.changes > 0
    }

    public func session(id: String) throws -> Session? {
        try selectSessions("WHERE id = ?", [.text(id)]).first
    }

    /// Oldest first.
    public func sessions() throws -> [Session] {
        try selectSessions("", [])
    }

    /// Done sessions whose `status_at` is at or before `date`.
    public func sessions(doneBefore date: Date) throws -> [Session] {
        try selectSessions("WHERE status = 'done' AND status_at <= ?", [.text(Self.formatDate(date))])
    }

    /// The earliest `status_at` among done sessions.
    public func earliestDone() throws -> Date? {
        var earliest: String?
        try db.run("SELECT MIN(status_at) FROM sessions WHERE status = 'done'") { earliest = $0.text(0) }
        return earliest.flatMap { Self.dateFormatter.date(from: $0) }
    }

    private func selectSessions(_ tail: String, _ args: [SQLValue]) throws -> [Session] {
        var sessions: [Session] = []
        try db.run("SELECT \(Self.sessionColumns) FROM sessions \(tail) ORDER BY started_at, id", args) { row in
            sessions.append(try Self.session(from: row))
        }
        return sessions
    }

    private static func session(from row: SQLiteDatabase.Row) throws -> Session {
        func date(_ column: Int32) throws -> Date {
            guard let text = row.text(column), let date = dateFormatter.date(from: text) else {
                throw SQLiteError(description: "bad date in session \(row.text(0) ?? "?") column \(column)")
            }
            return date
        }
        guard let id = row.text(0), let status = row.text(5).flatMap(SessionStatus.init(rawValue:)) else {
            throw SQLiteError(description: "bad id/status in session \(row.text(0) ?? "?")")
        }
        var s = Session(id: id, source: row.text(1) ?? "unknown", title: row.text(2), link: row.text(4),
                        startedAt: try date(12), status: status, cwd: row.text(3))
        s.prompt = row.text(6)
        s.lastMessage = row.text(7)
        s.detail = row.text(8)
        s.error = row.text(9)
        s.pid = row.optionalInt(10).map { Int32(truncatingIfNeeded: $0) }
        s.pidStartedAt = row.text(11).flatMap { dateFormatter.date(from: $0) }
        s.turnStartedAt = try date(13)
        s.statusAt = try date(14)
        s.updatedAt = try date(15)
        s.transcriptPath = row.text(16)
        return s
    }
}

// MARK: - Todo references

/// A cached todo's short id, the reminder it stands for, and the key it was added with. Kept after the reminder leaves
/// the snapshot, so a reminder that comes back (reopened, back in sync) keeps its id. Losing them only renumbers.
public struct TodoRef: Equatable, Sendable {
    public var id: String
    public var externalID: String
    public var key: String?
}

extension Store {
    public func todoRefs() throws -> [TodoRef] {
        var refs: [TodoRef] = []
        try db.run("SELECT id, external_id, key FROM todo_refs") { row in
            if let id = row.text(0), let external = row.text(1) { refs.append(TodoRef(id: id, externalID: external, key: row.text(2))) }
        }
        return refs
    }

    public func insert(_ ref: TodoRef) throws {
        try db.run("INSERT INTO todo_refs (id, external_id, key) VALUES (?, ?, ?)", [.text(ref.id), .text(ref.externalID), SQLValue(ref.key)])
    }

    public func todoRef(externalID: String) throws -> TodoRef? {
        try todoRefs(where: "external_id = ?", .text(externalID)).first
    }

    public func todoRef(key: String) throws -> TodoRef? {
        try todoRefs(where: "key = ?", .text(key)).first
    }

    /// Gives the reference `id` the key `key`, taking it from any other reference (and that one's cached todo) first:
    /// a key names one reminder.
    public func setKey(_ key: String, forRef id: String) throws {
        try db.run("UPDATE items SET key = NULL WHERE key = ? AND id != ? AND id IN (SELECT id FROM todo_refs)", [.text(key), .text(id)])
        try db.run("UPDATE todo_refs SET key = NULL WHERE key = ? AND id != ?", [.text(key), .text(id)])
        try db.run("UPDATE todo_refs SET key = ? WHERE id = ?", [.text(key), .text(id)])
    }

    private func todoRefs(where clause: String, _ arg: SQLValue) throws -> [TodoRef] {
        var refs: [TodoRef] = []
        try db.run("SELECT id, external_id, key FROM todo_refs WHERE \(clause)", [arg]) { row in
            if let id = row.text(0), let external = row.text(1) { refs.append(TodoRef(id: id, externalID: external, key: row.text(2))) }
        }
        return refs
    }

    /// Whether `id` is (or was) a cached todo: those change only through the bridge.
    public func isTodo(id: String) throws -> Bool {
        var found = false
        try db.run("SELECT 1 FROM todo_refs WHERE id = ?", [.text(id)]) { _ in found = true }
        return found
    }

    /// The cached todos: the items with a reference.
    public func todos() throws -> [Item] {
        try select("WHERE id IN (SELECT id FROM todo_refs)", [])
    }

    /// When the todo cache was last known to match Reminders: the last snapshot, or the moment the bridge left.
    public func todosAsOf() throws -> Date? {
        var value: String?
        try db.run("SELECT value FROM daemon_state WHERE name = 'todos_as_of'") { value = $0.text(0) }
        return value.flatMap { Self.dateFormatter.date(from: $0) }
    }

    public func setTodosAsOf(_ date: Date) throws {
        try db.run("INSERT OR REPLACE INTO daemon_state (name, value) VALUES ('todos_as_of', ?)", [.text(Self.formatDate(date))])
    }

    /// The checked Reminders lists of the latest snapshot, in order (#69): todos are grouped by them with no bridge
    /// connected and across restarts. Kept as JSON in `daemon_state`, so no schema change; empty before any snapshot
    /// that had them.
    public func todoLists() throws -> [ReminderList] {
        var value: String?
        try db.run("SELECT value FROM daemon_state WHERE name = 'todo_lists'") { value = $0.text(0) }
        return value.flatMap { try? JSONDecoder().decode([ReminderList].self, from: Data($0.utf8)) } ?? []
    }

    public func setTodoLists(_ lists: [ReminderList]) throws {
        try db.run("INSERT OR REPLACE INTO daemon_state (name, value) VALUES ('todo_lists', ?)", [SQLValue(Self.json(lists))])
    }
}
