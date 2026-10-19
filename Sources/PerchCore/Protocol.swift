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
///   item with that key is updated instead (see `Service`). Only `title` is required in the JSON. A todo goes in the
///   checked Reminders list `list` (exact name, #70), "Perch" without one
/// - `list` + optional `filter` → `items`, in queue order (see `Item.queueOrder`; todos by list, #69). While no Reminders
///   bridge is connected and the list holds cached todos, also `todos_as_of`: when that cache was last known current
///   (#52). `todo_lists`: the checked Reminders lists in order, as of the latest snapshot (when perchd knows any)
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
/// - `watch` → stream of events (item events in `event`, session events in `session_event`). The acknowledgement
///   carries `watcher`, the id of this subscription; `bridge` pushes (no `event`) say a bridge came or went;
///   `todo_lists` pushes say the checked lists changed (#69), sent before the item events of the same snapshot
/// - `bridge_register` + `watcher` → `bridge`: true when this watcher is now the Reminders bridge (#51), false when
///   another one already is (the app stays a plain client). The bridge leaves when its watch connection closes
/// - `todo_snapshot` + `watcher` + `reminders` + `lists` → ok; the bridge's full read of the checked lists (#69:
///   "Perch" and any others, in order) replaces perchd's todo cache (open and done task items), assigning short ids to
///   new reminders
/// - Todo writes (`add` / `done` / `update` / `remove` on open or done tasks, #52) go to the bridge: perchd pushes a
///   `todo_op` (`TodoOperation`) on its watch connection, the bridge applies it and answers `todo_ack` + `watcher` +
///   `ack` (`TodoAck`), then sends a snapshot; the writer gets its answer after that snapshot. No bridge, or no answer
///   within 2 seconds: an error, and nothing is queued
public struct Request: Codable, Sendable {
    public enum Op: String, Codable, Sendable {
        case ping, add, list, get, done, respond, remove, update, watch
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case sessions
        case sessionReport = "session_report"
        case sessionSeen = "session_seen"
        case sessionRemove = "session_remove"
        case bridgeRegister = "bridge_register"
        case todoSnapshot = "todo_snapshot"
        case todoAck = "todo_ack"
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
    /// The watch subscription a bridge op speaks for (`bridge_register`, `todo_snapshot`).
    public var watcher: String?
    /// `todo_snapshot`: every reminder in the checked lists (incomplete, and completed in the last 7 days).
    public var reminders: [Reminder]?
    /// `todo_snapshot`: the checked lists, in the order the Todo tab shows them (#69).
    public var lists: [ReminderList]?
    /// `todo_ack`: how a `todo_op` went.
    public var ack: TodoAck?
    /// `add` of a todo (#70): the checked Reminders list it goes in, by exact name; "Perch" when absent.
    public var list: String?

    public init(op: Op, item: Item? = nil, id: String? = nil, value: String? = nil, filter: Filter? = nil,
                patch: Patch? = nil, session: Session? = nil, report: SessionReport? = nil, key: String? = nil, at: Date? = nil,
                watcher: String? = nil, reminders: [Reminder]? = nil, lists: [ReminderList]? = nil, ack: TodoAck? = nil,
                list: String? = nil) {
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
        self.watcher = watcher
        self.reminders = reminders
        self.lists = lists
        self.ack = ack
        self.list = list
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

    /// For `update`. Unset fields stay as they are. `priority` applies to any kind (only open tasks are sorted by it). `kind` switches between task and notice only
    /// (a notice that becomes a task stops expiring); requests keep their kind. `status` (#52) moves tasks and notices:
    /// an open or done task is a todo, so a waiting task set to open moves into Reminders, and a todo set to dismissed
    /// is deleted there.
    public struct Patch: Codable, Sendable, Equatable {
        public var title: String?
        public var kind: ItemKind?
        public var status: ItemStatus?
        public var priority: ItemPriority?
        public var dueAt: Date?
        /// With `due_at`: it is a whole day, not a moment.
        public var dueDateOnly: Bool?
        /// Removes `due_at`. Cannot be combined with `due_at`.
        public var clearDue: Bool?
        /// A todo's notes (#53, `Item.notes`); empty removes them.
        public var notes: String?
        public var link: String?
        /// Removes `link`. Cannot be combined with `link`.
        public var clearLink: Bool?
        /// Moves a todo to the checked Reminders list with this exact name (#70); its short id stays.
        public var list: String?
        /// Marks an open todo as Doing, or clears it (#71). perchd's own, so it goes on its own: no bridge needed.
        public var doing: Bool?

        public init(title: String? = nil, kind: ItemKind? = nil, status: ItemStatus? = nil, priority: ItemPriority? = nil,
                    dueAt: Date? = nil, dueDateOnly: Bool? = nil, clearDue: Bool? = nil, notes: String? = nil,
                    link: String? = nil, clearLink: Bool? = nil, list: String? = nil, doing: Bool? = nil) {
            self.title = title
            self.kind = kind
            self.status = status
            self.priority = priority
            self.dueAt = dueAt
            self.dueDateOnly = dueDateOnly
            self.clearDue = clearDue
            self.notes = notes
            self.link = link
            self.clearLink = clearLink
            self.list = list
            self.doing = doing
        }

        enum CodingKeys: String, CodingKey {
            case title, kind, status, priority, notes, link, list, doing
            case dueAt = "due_at"
            case dueDateOnly = "due_date_only"
            case clearDue = "clear_due"
            case clearLink = "clear_link"
        }

        public var isEmpty: Bool {
            title == nil && kind == nil && status == nil && priority == nil && dueAt == nil && clearDue != true
                && notes == nil && link == nil && clearLink != true && list == nil && doing == nil
        }

        /// What turns `old` into `new`: title, priority, due date, notes, link and list (by name, #70), only where they
        /// differ.
        public init(from old: Item, to new: Item) {
            self.init()
            if new.title != old.title { title = new.title }
            if new.priority != old.priority { priority = new.priority }
            if new.dueAt != old.dueAt || new.dueDateOnly != old.dueDateOnly {
                if let due = new.dueAt {
                    dueAt = due
                    dueDateOnly = new.dueDateOnly
                } else {
                    clearDue = true
                }
            }
            if new.notes != old.notes { notes = new.notes ?? "" }
            if new.link != old.link {
                if let link = new.link { self.link = link } else { clearLink = true }
            }
            if new.listID != nil, new.listID != old.listID { list = new.listName }
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
    /// The watch acknowledgement: this subscription's id, for `bridge_register` / `todo_snapshot`.
    public var watcher: String?
    /// `bridge_register`: whether the caller is now the bridge. On the watch stream (no `event`): whether a bridge
    /// is connected, pushed when one registers or leaves.
    public var bridge: Bool?
    /// On the bridge's watch stream: a todo write to apply (#52).
    public var todoOp: TodoOperation?
    /// `list`, only while no bridge is connected and the list holds cached todos: when the cache was last current.
    public var todosAsOf: Date?
    /// `list`, and pushed on the watch stream when they change: the checked Reminders lists in order (#69).
    public var todoLists: [ReminderList]?

    public init(ok: Bool, error: String? = nil, item: Item? = nil, items: [Item]? = nil, event: Event? = nil, version: String? = nil,
                sessions: [Session]? = nil, sessionEvent: SessionEvent? = nil, watcher: String? = nil, bridge: Bool? = nil,
                todoOp: TodoOperation? = nil, todosAsOf: Date? = nil, todoLists: [ReminderList]? = nil) {
        self.ok = ok
        self.error = error
        self.item = item
        self.items = items
        self.event = event
        self.version = version
        self.sessions = sessions
        self.sessionEvent = sessionEvent
        self.watcher = watcher
        self.bridge = bridge
        self.todoOp = todoOp
        self.todosAsOf = todosAsOf
        self.todoLists = todoLists
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, item, items, event, version, sessions, watcher, bridge
        case sessionEvent = "session_event"
        case todoOp = "todo_op"
        case todosAsOf = "todos_as_of"
        case todoLists = "todo_lists"
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
