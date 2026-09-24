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

    public func count() throws -> Int {
        var n = 0
        try db.run("SELECT COUNT(*) FROM items") { n = $0.int(0) }
        return n
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
