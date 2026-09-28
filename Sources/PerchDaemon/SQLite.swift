import Foundation
import CSQLite

public struct SQLiteError: Error, CustomStringConvertible {
    public let description: String
}

enum SQLValue {
    case text(String)
    case int(Int64)
    case null

    init(_ string: String?) {
        self = string.map(SQLValue.text) ?? .null
    }

    init(_ int: Int32?) {
        self = int.map { .int(Int64($0)) } ?? .null
    }
}

/// Minimal wrapper over the system sqlite3. Not thread-safe: perchd uses it from one serial queue.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close_v2(handle)
            throw SQLiteError(description: "cannot open \(path): \(message)")
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements without parameters.
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw SQLiteError(description: message)
        }
    }

    /// Runs one statement; calls `row` for each result row.
    func run(_ sql: String, _ args: [SQLValue] = [], row: ((Row) throws -> Void)? = nil) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError(description: "\(lastError) — in: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case .text(let s): csqlite_bind_text(stmt, index, s)
            case .int(let n): sqlite3_bind_int64(stmt, index, n)
            case .null: sqlite3_bind_null(stmt, index)
            }
        }
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: try row?(Row(stmt: stmt!))
            case SQLITE_DONE: return
            default: throw SQLiteError(description: lastError)
            }
        }
    }

    /// Rows changed by the last INSERT / UPDATE / DELETE.
    var changes: Int { Int(sqlite3_changes(handle)) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    struct Row {
        let stmt: OpaquePointer

        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(stmt, column) != SQLITE_NULL, let c = sqlite3_column_text(stmt, column) else { return nil }
            return String(cString: c)
        }

        func int(_ column: Int32) -> Int {
            Int(sqlite3_column_int64(stmt, column))
        }

        func optionalInt(_ column: Int32) -> Int? {
            sqlite3_column_type(stmt, column) == SQLITE_NULL ? nil : int(column)
        }
    }
}
