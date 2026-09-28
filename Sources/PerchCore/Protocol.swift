import Foundation

/// Wire protocol between clients (CLI, notch app, Hermes over HTTP) and perchd.
///
/// Transport: newline-delimited JSON over the Unix socket; the same JSON bodies over
/// `POST http://127.0.0.1:<port>/rpc`. One `Request` per line, one `Response` per line;
/// `op: "watch"` keeps the connection open: first `{"ok":true}`, then one `Response` with `event` set per change.
///
/// Ops and their fields:
/// - `ping` → `version`
/// - `add` + `item` → `item`. perchd assigns `id`, `created_at`, `updated_at`; with `item.key` set, an existing
///   item with that key is updated instead (see `Service`). Only `title` is required in the JSON.
/// - `list` + optional `filter` → `items`, in queue order (see `Item.queueOrder`)
/// - `get` / `done` / `remove` + `id` → `item` (`remove` returns the deleted item); `done` also takes `key` instead of `id`
/// - `respond` + `id` + `value` → `item`; the request is closed with `status: done`
/// - `update` + `id` + `patch` → `item`. Only the fields set in `patch` change; see `Request.Patch`
/// - `session_report` + `report` → `sessions` (the session after the report, or the removed one for `end`; empty when
///   the report was older than the last one for that id — async hooks arrive out of order). See `SessionReport`
/// - `session_start` + `session` → like a `prompt` report: the session is running a new turn
/// - `session_end` + `id` (+ `at`) → like an `end` report: the session is removed (and returned)
/// - `session_seen` + `id` → `sessions`; a done session becomes idle (someone looked at the result)
/// - `session_remove` + `id` → `sessions`, the removed one; a later report brings it back
/// - `sessions` → `sessions`, all of them
/// - `watch` → stream of events (item events in `event`, session events in `session_event`)
public struct Request: Codable, Sendable {
    public enum Op: String, Codable, Sendable {
        case ping, add, list, get, done, respond, remove, update, watch
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case sessions
        case sessionReport = "session_report"
        case sessionSeen = "session_seen"
        case sessionRemove = "session_remove"
    }
    public var op: Op
    public var item: Item?
    public var id: String?
    public var value: String?
    public var filter: Filter?
    public var patch: Patch?
    public var session: Session?
    public var report: SessionReport?
    /// `done` by idempotency key instead of id (hook adapters know their key, not the id).
    public var key: String?
    /// When the client observed what it reports (`session_end`); perchd uses its own clock if absent.
    public var at: Date?

    public init(op: Op, item: Item? = nil, id: String? = nil, value: String? = nil, filter: Filter? = nil,
                patch: Patch? = nil, session: Session? = nil, report: SessionReport? = nil, key: String? = nil, at: Date? = nil) {
        self.op = op
        self.item = item
        self.id = id
        self.value = value
        self.filter = filter
        self.patch = patch
        self.session = session
        self.report = report
        self.key = key
        self.at = at
    }

    /// For `list`. Without `status`, only active items (open, waiting) are returned unless `all` is true.
    public struct Filter: Codable, Sendable, Equatable {
        public var status: ItemStatus?
        public var source: String?
        public var kind: ItemKind?
        public var all: Bool?
        public init(status: ItemStatus? = nil, source: String? = nil, kind: ItemKind? = nil, all: Bool? = nil) {
            self.status = status
            self.source = source
            self.kind = kind
            self.all = all
        }
    }

    /// For `update`. Unset fields stay as they are. `kind` switches between task and notice only
    /// (a notice that becomes a task stops expiring); requests keep their kind.
    public struct Patch: Codable, Sendable, Equatable {
        public var title: String?
        public var kind: ItemKind?
        public var dueAt: Date?
        /// Removes `due_at`. Cannot be combined with `due_at`.
        public var clearDue: Bool?

        public init(title: String? = nil, kind: ItemKind? = nil, dueAt: Date? = nil, clearDue: Bool? = nil) {
            self.title = title
            self.kind = kind
            self.dueAt = dueAt
            self.clearDue = clearDue
        }

        enum CodingKeys: String, CodingKey {
            case title, kind
            case dueAt = "due_at"
            case clearDue = "clear_due"
        }

        public var isEmpty: Bool {
            title == nil && kind == nil && dueAt == nil && clearDue != true
        }
    }
}

public struct Response: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var item: Item?
    public var items: [Item]?
    public var event: Event?
    public var version: String?
    public var sessions: [Session]?
    public var sessionEvent: SessionEvent?

    public init(ok: Bool, error: String? = nil, item: Item? = nil, items: [Item]? = nil, event: Event? = nil, version: String? = nil,
                sessions: [Session]? = nil, sessionEvent: SessionEvent? = nil) {
        self.ok = ok
        self.error = error
        self.item = item
        self.items = items
        self.event = event
        self.version = version
        self.sessions = sessions
        self.sessionEvent = sessionEvent
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, item, items, event, version, sessions
        case sessionEvent = "session_event"
    }

    public static func failure(_ message: String) -> Response { Response(ok: false, error: message) }
}

/// Shared JSON settings so every client and the daemon agree on dates.
public enum PerchJSON {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
