import Foundation
import PerchCore

/// The `items` table. Columns map 1:1 to `Item`; dates are ISO-8601 UTC text, `meta` / `options` are JSON text.
/// Only perchd opens this database.
public final class Store {
    public static let schemaVersion = 1

    let db: SQLiteDatabase

    /// `path` may be `":memory:"` for tests.
    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try db.execute("PRAGMA journal_mode = WAL")
        try migrate()
    }

    static let columns = "id, title, kind, status, source, due_at, link, meta, key, options, response, expires_at, created_at, updated_at"

    public func insert(_ item: Item) throws {
        try db.run("INSERT INTO items (\(Self.columns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", values(item))
    }

    /// Overwrites every column of the row with `item.id`.
    public func update(_ item: Item) throws {
        var args = Array(values(item).dropFirst())
        args.append(.text(item.id))
        try db.run("""
        UPDATE items SET title = ?, kind = ?, status = ?, source = ?, due_at = ?, link = ?, meta = ?, key = ?,
            options = ?, response = ?, expires_at = ?, created_at = ?, updated_at = ?
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
            .text(Self.formatDate(item.createdAt)), .text(Self.formatDate(item.updatedAt)),
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
            id: try required(0), title: try required(1), kind: kind, status: status, source: try required(4),
            dueAt: try date(5), link: row.text(6),
            meta: row.text(7).flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) },
            key: row.text(8),
            options: row.text(9).flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) },
            response: row.text(10), expiresAt: try date(11),
            createdAt: try date(12)!, updatedAt: try date(13)!
        )
    }

    private static let dateFormatter = ISO8601DateFormatter()

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
    }
}
