import Foundation
import PerchCore

/// A request the client got wrong. The message goes back verbatim, so write it for an agent to act on.
struct ServiceError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Request handling on top of the store. Synchronous and not thread-safe: `Daemon` calls it
/// from its serial queue and broadcasts the returned events.
public final class Service {
    public let store: Store
    /// Injectable for tests.
    public var now: () -> Date

    public init(store: Store, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public func handle(_ request: Request) -> (Response, [Event]) {
        do {
            switch request.op {
            case .ping:
                return (Response(ok: true, version: PerchVersion.string), [])
            case .add:
                return try add(request.item, list: request.list)
            case .list:
                let lists = try store.todoLists()
                let items = try store.list(request.filter).queueOrdered(now: now(), lists: lists.map(\.id))
                return (Response(ok: true, items: items, todoLists: lists.isEmpty ? nil : lists), [])
            case .get:
                return (Response(ok: true, item: try existing(request.id)), [])
            case .done:
                return try done(request.id, key: request.key)
            case .respond:
                return try respond(request.id, request.value)
            case .remove:
                return try remove(request.id)
            case .update:
                return try update(request.id, request.patch)
            case .watch:
                return (.failure("watch streams events; it is handled by the connection, not as a single call"), [])
            case .sessionStart, .sessionEnd, .sessions, .sessionReport, .sessionSeen, .sessionRemove:
                return (.failure("session ops are handled by SessionRegistry"), [])
            case .bridgeRegister, .todoSnapshot, .todoAck:
                return (.failure("bridge ops are handled by the daemon"), [])
            }
        } catch let error as ServiceError {
            return (.failure(error.message), [])
        } catch {
            return (.failure("internal error: \(error)"), [])
        }
    }

    // MARK: - Ops

    /// What `add` stores of `incoming`: trimmed title and key, whole-second dates, no response.
    private func normalized(_ incoming: Item?) throws -> Item {
        guard var item = incoming else { throw ServiceError("add needs an item") }
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { throw ServiceError("title must not be empty") }
        if let key = item.key?.trimmingCharacters(in: .whitespaces) {
            item.key = key.isEmpty ? nil : key
        }
        item.dueAt = item.dueAt.map(Self.wholeSeconds)
        item.dueDateOnly = item.dueAt != nil && item.dueDateOnly
        // Round up so storing whole seconds never shortens the window an agent asked for.
        item.expiresAt = item.expiresAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.up)) }
        item.response = nil
        return item
    }

    private func add(_ incoming: Item?, list: String?) throws -> (Response, [Event]) {
        var item = try normalized(incoming)
        let t = timestamp()
        if Self.isTodoShaped(item) { throw ServiceError(Self.todoWriteRefused) }
        if list != nil { throw ServiceError(Self.listOnlyForTodos) }
        if item.kind == .request {
            if (item.options ?? []).isEmpty { item.options = ["allow", "deny"] }
        } else {
            item.options = nil
        }
        return try store.transaction {
            if let key = item.key, let existing = try store.find(key: key) {
                if try store.isTodo(id: existing.id) { throw ServiceError(Self.todoWriteRefused) }
                return try upsert(existing, with: item, at: t)
            }
            item.id = try freshID()
            item.createdAt = t
            item.updatedAt = t
            try store.insert(item)
            return (Response(ok: true, item: item), [Event(type: .added, item: item, at: t)])
        }
    }

    /// `add` with a key that already exists: the old item takes every field of the new one but keeps its
    /// `id` and `created_at`. Re-adding reopens a closed item (the same agent session is waiting again) and
    /// clears a previous `response` (it is a new question). An identical re-add changes nothing and emits nothing.
    private func upsert(_ existing: Item, with incoming: Item, at t: Date) throws -> (Response, [Event]) {
        var item = incoming
        item.id = existing.id
        item.createdAt = existing.createdAt
        item.updatedAt = existing.updatedAt
        guard item != existing else { return (Response(ok: true, item: existing), []) }
        item.updatedAt = t
        try store.update(item)
        return (Response(ok: true, item: item), [Event(type: .updated, item: item, at: t)])
    }

    private func done(_ id: String?, key: String?) throws -> (Response, [Event]) {
        var item: Item
        if let key = key?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            guard id == nil else { throw ServiceError("give either id or key, not both") }
            guard let found = try store.find(key: key) else { throw ServiceError("no item with key '\(key)'") }
            item = found
        } else {
            item = try existing(id)
        }
        try refuseTodo(item)
        guard item.status != .done else { return (Response(ok: true, item: item), []) }
        item.status = .done
        return try save(item)
    }

    private func respond(_ id: String?, _ value: String?) throws -> (Response, [Event]) {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            throw ServiceError("respond needs a value, e.g. allow or deny")
        }
        var item = try existing(id)
        guard item.kind == .request else {
            throw ServiceError("\(item.id) is a \(item.kind.rawValue), not a request; use done instead")
        }
        if let previous = item.response {
            throw ServiceError("request \(item.id) was already answered: \(previous)")
        }
        guard item.status == .open || item.status == .waiting else {
            throw ServiceError("request \(item.id) is closed (\(item.status.rawValue)); nobody is waiting for an answer")
        }
        if let options = item.options, !options.isEmpty, !options.contains(value) {
            throw ServiceError("'\(value)' is not an option for \(item.id); choose one of: \(options.joined(separator: ", "))")
        }
        item.response = value
        item.status = .done
        return try save(item)
    }

    private func remove(_ id: String?) throws -> (Response, [Event]) {
        let item = try existing(id)
        try refuseTodo(item)
        try store.delete(id: item.id)
        return (Response(ok: true, item: item), [Event(type: .removed, item: item, at: timestamp())])
    }

    private func update(_ id: String?, _ patch: Request.Patch?) throws -> (Response, [Event]) {
        let original = try existing(id)
        try refuseTodo(original)
        let item = try patched(original, patch)
        // A notice kept as a task would be a todo, and todos live in Reminders: only the bridge can make it one.
        if Self.isTodoShaped(item) && !Self.isTodoShaped(original) { throw ServiceError(Self.todoWriteRefused) }
        if patch?.list != nil { throw ServiceError(Self.listOnlyForTodos) }
        guard item != original else { return (Response(ok: true, item: original), []) }
        return try save(item)
    }

    /// `item` with `patch` applied, or why it can't be.
    private func patched(_ original: Item, _ patch: Request.Patch?) throws -> Item {
        guard let patch, !patch.isEmpty else {
            throw ServiceError("update needs at least one of: title, kind, status, priority, due_at, clear_due")
        }
        if patch.dueAt != nil && patch.clearDue == true {
            throw ServiceError("update takes either due_at or clear_due, not both")
        }
        if patch.link != nil && patch.clearLink == true {
            throw ServiceError("update takes either link or clear_link, not both")
        }
        var item = original
        if let title = patch.title?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !title.isEmpty else { throw ServiceError("title must not be empty") }
            item.title = title
        }
        if let kind = patch.kind, kind != item.kind {
            // A request carries options, a response and a blocked --wait caller; it cannot turn into something else.
            if item.kind == .request { throw ServiceError("\(item.id) is a request; its kind cannot change") }
            if kind == .request {
                throw ServiceError("\(item.id) cannot become a request; add a new one with --kind request")
            }
            // A notice promoted to a task is kept on purpose: it must not fade at the notice's expiry.
            if kind == .task { item.expiresAt = nil }
            item.kind = kind
        }
        if let status = patch.status, status != item.status {
            if item.kind == .request {
                throw ServiceError("\(item.id) is a request; answer it with respond, or close it with done or rm")
            }
            item.status = status
        }
        if let priority = patch.priority { item.priority = priority }
        if let due = patch.dueAt {
            item.dueAt = Self.wholeSeconds(due)
            item.dueDateOnly = patch.dueDateOnly ?? false
        }
        if patch.clearDue == true {
            item.dueAt = nil
            item.dueDateOnly = false
        }
        if let notes = patch.notes { item.notes = notes }
        if let link = patch.link?.trimmingCharacters(in: .whitespacesAndNewlines) { item.link = link.isEmpty ? nil : link }
        if patch.clearLink == true { item.link = nil }
        return item
    }

    /// Dismisses every active item past its `expires_at`: notices fade, unanswered requests close
    /// (their `--wait`ers exit without a decision and the terminal's own prompt takes over).
    public func sweepExpired() -> [Event] {
        do {
            return try store.transaction {
                try store.expired(at: now()).map { expired in
                    var item = expired
                    item.status = .dismissed
                    return try save(item).1[0]
                }
            }
        } catch {
            return []
        }
    }

    /// Agents whose hooks, before #19, also posted waiting ("go to terminal") and notice items, keyed
    /// `<agent>:<session>` / `<agent>:<session>:done`. Only those hooks ever closed them.
    static let sessionOnlyAgents: Set<String> = ["claude-code", "codex"]

    /// Dismisses the waiting / notice items those hooks left behind (perchd runs it at startup), so an upgrade does
    /// not leave them in `perch ls` and todo.md for good. Their requests, and everyone else's items, stay.
    public func dismissLegacyHookItems() -> [Event] {
        do {
            return try store.transaction {
                try store.list(nil).filter(Self.isLegacyHookItem).map { stale in
                    var item = stale
                    item.status = .dismissed
                    return try save(item).1[0]
                }
            }
        } catch {
            return []
        }
    }

    static func isLegacyHookItem(_ item: Item) -> Bool {
        guard sessionOnlyAgents.contains(item.source), item.kind != .request, let key = item.key else { return false }
        return key.hasPrefix(item.source + ":")
    }

    public func nextExpiry() -> Date? {
        try? store.nextExpiry()
    }

    /// Closes the session's open requests without an answer (`meta.session_id`): the agent moved on, so nobody is
    /// asking any more. A hook still waiting on one gets no decision.
    public func resolveRequests(session: String) -> [Event] {
        do {
            return try store.transaction {
                try store.list(Request.Filter(kind: .request)).filter { $0.meta?["session_id"] == session }.map { open in
                    var item = open
                    item.status = .done
                    return try save(item).1[0]
                }
            }
        } catch {
            return []
        }
    }

    // MARK: - Todos (#51)

    /// Todos live in the checked Reminders lists ("Perch" and any others, #69); only the bridge app writes them.
    /// `Daemon` hands todo writes to it (`planTodoWrite`, #52); with no bridge connected they are refused, never queued.
    static let todoWriteRefused = "Todo needs Perch.app running with Reminders access"

    /// A list (#70) is where a todo lives in Reminders; nothing else has one.
    static let listOnlyForTodos = "a list only applies to todos (open or done tasks)"

    /// What todos are cached as. Every other item (waiting tasks, notices, requests) stays perchd's own.
    static func isTodoShaped(_ item: Item) -> Bool {
        item.kind == .task && (item.status == .open || item.status == .done)
    }

    private func refuseTodo(_ item: Item) throws {
        if try store.isTodo(id: item.id) { throw ServiceError(Self.todoWriteRefused) }
    }

    /// The source cached todos carry: they come from Reminders, whoever wrote them there.
    public static let remindersSource = "reminders"

    /// Replaces the todo cache with the bridge's full read of the checked lists: new reminders get a short id, changed
    /// ones are updated, and cached todos missing from it are removed (deleted, or in a list no longer checked: their
    /// references stay, so they keep their short ids if they come back, #69). Only what changed emits an event.
    /// `lists`: the checked lists in order, kept for grouping (none from a bridge older than #69).
    public func applySnapshot(_ reminders: [Reminder], lists: [ReminderList] = []) throws -> [Event] {
        try store.transaction {
            try store.setTodoLists(lists)
            let names = Dictionary(lists.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            var refs = Dictionary(try store.todoRefs().map { ($0.externalID, $0) }, uniquingKeysWith: { a, _ in a })
            let cached = Dictionary(try store.todos().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let t = timestamp()
            var events: [Event] = []
            var present: Set<String> = []
            for reminder in reminders {
                let ref: TodoRef
                if let known = refs[reminder.externalID] {
                    ref = known
                } else {
                    ref = TodoRef(id: try freshID(), externalID: reminder.externalID, key: nil)
                    try store.insert(ref)
                    refs[reminder.externalID] = ref
                }
                guard present.insert(ref.id).inserted else { continue }
                let old = cached[ref.id]
                var item = Item(
                    id: ref.id, title: reminder.title, kind: .task, status: reminder.completed ? .done : .open,
                    priority: ItemPriority(reminderPriority: reminder.priority), source: Self.remindersSource,
                    dueAt: reminder.dueAt.map(Self.wholeSeconds), dueDateOnly: reminder.dueAt != nil && reminder.dueDateOnly,
                    link: reminder.url,
                    meta: Self.meta(of: reminder, listName: reminder.list.flatMap { names[$0] }), key: ref.key,
                    createdAt: reminder.createdAt.map(Self.wholeSeconds) ?? old?.createdAt ?? t,
                    updatedAt: old?.updatedAt ?? t
                )
                if let old {
                    guard item != old else { continue }
                    item.updatedAt = t
                    try store.update(item)
                    events.append(Event(type: .updated, item: item, at: t))
                } else {
                    try store.insert(item)
                    events.append(Event(type: .added, item: item, at: t))
                }
            }
            for (id, gone) in cached.sorted(by: { $0.key < $1.key }) where !present.contains(id) {
                try store.delete(id: id)
                events.append(Event(type: .removed, item: gone, at: t))
            }
            try store.setTodosAsOf(t)
            return events
        }
    }

    /// What a cached todo keeps in `meta`: the reminder's identifier, its list (#69) and its notes when it has any.
    static func meta(of reminder: Reminder, listName: String? = nil) -> [String: String] {
        var item = Item(title: "", meta: [Item.reminderMetaKey: reminder.externalID])
        item.meta?[Item.listIDMetaKey] = reminder.list
        item.meta?[Item.listNameMetaKey] = listName
        item.notes = reminder.notes
        return item.meta ?? [:]
    }

    /// The checked lists of the latest snapshot, in order.
    public func todoLists() -> [ReminderList] {
        (try? store.todoLists()) ?? []
    }

    /// When the todo cache was last known to match Reminders (shown while no bridge is connected). A cache from before
    /// perchd kept this falls back to its newest change.
    public func todosAsOf() -> Date? {
        (try? store.todosAsOf()) ?? (try? store.todos().map(\.updatedAt).max()) ?? nil
    }

    /// The bridge left: the cache was current until now.
    public func bridgeLeft() {
        try? store.setTodosAsOf(timestamp())
    }

    // MARK: - Todo writes through the bridge (#52)

    /// A todo write for the bridge, and what to do with its answer.
    public struct TodoWrite {
        public var operation: TodoOperation
        /// The key the reminder answers to afterwards (`add --key`, or the promoted item's).
        var key: String?
        /// A local item becoming this reminder (a waiting task set to open, a notice kept as a task): it goes once the
        /// bridge has made the reminder, which takes its short id.
        var promoted: String?
        /// For a delete: the todo as it was (the answer).
        var removed: Item?
    }

    public enum TodoPlan {
        /// Not a todo write: `handle` it.
        case local
        /// A todo write with nothing to change, or one that can't be made: answer at once.
        case answer(Response)
        case bridge(TodoWrite)
    }

    /// Whether `request` writes a todo (an open or done task, or an item becoming one), and the bridge operation if so.
    /// Only `add`, `done`, `update` and `remove` can.
    public func planTodoWrite(_ request: Request) -> TodoPlan {
        do {
            switch request.op {
            case .add: return try planAdd(request.item, list: request.list)
            case .done: return try planDone(request.id, key: request.key)
            case .update: return try planUpdate(request.id, request.patch)
            case .remove:
                let item = try existing(request.id)
                guard try store.isTodo(id: item.id) else { return .local }
                return try planDelete(item)
            default: return .local
            }
        } catch let error as ServiceError {
            return .answer(.failure(error.message))
        } catch {
            return .answer(.failure("internal error: \(error)"))
        }
    }

    private func planAdd(_ incoming: Item?, list: String?) throws -> TodoPlan {
        let item = try normalized(incoming)
        // Before the name: a list on a notice is wrong whatever it is called.
        if list != nil && !Self.isTodoShaped(item) { throw ServiceError(Self.listOnlyForTodos) }
        let target = try list.map(checkedList(named:))
        let existing = try item.key.flatMap(store.find(key:))
        if let existing, try store.isTodo(id: existing.id) {
            // `add --key` again: the same reminder takes the new fields (and moves, given a list).
            guard Self.isTodoShaped(item) else {
                throw ServiceError("key '\(existing.key ?? "")' is todo \(existing.id), which lives in Reminders; it can't become a \(item.status.rawValue) \(item.kind.rawValue)")
            }
            return try planChange(existing, to: item, list: target)
        }
        guard Self.isTodoShaped(item) else { return .local }
        if existing == nil, let key = item.key, let ref = try store.todoRef(key: key) {
            // The key's reminder isn't cached (its snapshot never came, or it's gone): that one if it's still there.
            var change = Self.fields(of: item)
            if item.dueAt == nil { change.clearDue = true }
            if item.link == nil { change.clearURL = true }
            if item.status == .open { change.completed = false }
            change.list = target?.id
            return .bridge(TodoWrite(operation: TodoOperation(action: .upsert, externalID: ref.externalID, change: change), key: key))
        }
        // New, or re-adding the key of a waiting task as an open one: it moves into Reminders.
        var change = Self.fields(of: item)
        change.list = target?.id
        let operation = TodoOperation(action: .create, change: change)
        return .bridge(TodoWrite(operation: operation, key: item.key, promoted: existing?.id))
    }

    private func planDone(_ id: String?, key: String?) throws -> TodoPlan {
        let item: Item
        if let key = key?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            guard id == nil else { throw ServiceError("give either id or key, not both") }
            guard let found = try store.find(key: key) else { throw ServiceError("no item with key '\(key)'") }
            item = found
        } else {
            item = try existing(id)
        }
        guard try store.isTodo(id: item.id) else { return .local }
        var done = item
        done.status = .done
        return try planChange(item, to: done)
    }

    private func planUpdate(_ id: String?, _ patch: Request.Patch?) throws -> TodoPlan {
        let original = try existing(id)
        guard try store.isTodo(id: original.id) else {
            let item = try patched(original, patch)
            guard Self.isTodoShaped(item) else {
                if patch?.list != nil { throw ServiceError(Self.listOnlyForTodos) }
                return .local
            }
            var change = Self.fields(of: item)
            change.list = try patch?.list.map(checkedList(named:))?.id
            let operation = TodoOperation(action: .create, change: change)
            return .bridge(TodoWrite(operation: operation, key: item.key, promoted: original.id))
        }
        let target = try patch?.list.map(checkedList(named:))
        if patch?.kind == .notice { throw ServiceError("\(original.id) is a todo in Reminders; it stays a task") }
        if patch?.status == .waiting { throw ServiceError("\(original.id) is a todo in Reminders; it can't be waiting") }
        if patch?.status == .dismissed {
            var removed = original
            removed.status = .dismissed
            return try planDelete(removed)
        }
        return try planChange(original, to: try patched(original, patch), list: target)
    }

    /// Deleting the cached todo `item` (answered with `item` itself).
    private func planDelete(_ item: Item) throws -> TodoPlan {
        guard let reminder = item.reminderID else { throw ServiceError("\(item.id) is not a reminder") }
        let operation = TodoOperation(action: .delete, externalID: reminder, seenInList: item.listID)
        return .bridge(TodoWrite(operation: operation, removed: item))
    }

    /// An update to the cached todo `old` so it reads like `new`, in the checked list `list` when given (a move, #70);
    /// nothing to do when they already agree.
    private func planChange(_ old: Item, to new: Item, list: ReminderList? = nil) throws -> TodoPlan {
        guard let reminder = old.reminderID else { throw ServiceError("\(old.id) is not a reminder") }
        var change = ReminderChange(from: old, to: new)
        if let list, list.id != old.listID {
            if let from = todoLists().first(where: { $0.id == old.listID }), let refusal = from.moveRefusal(to: list) {
                throw ServiceError(refusal)
            }
            change.list = list.id
        }
        guard !change.isEmpty else { return .answer(Response(ok: true, item: old)) }
        let operation = TodoOperation(action: .update, externalID: reminder, seenInList: old.listID, change: change)
        return .bridge(TodoWrite(operation: operation))
    }

    /// The checked list (as of the latest snapshot) called exactly `name`, or why there's none (#70). The bridge checks
    /// again when it writes.
    private func checkedList(named name: String) throws -> ReminderList {
        do {
            return try ReminderList.checked(named: name, in: try store.todoLists())
        } catch let error as RemindersListError {
            throw ServiceError(error.description)
        }
    }

    /// A new reminder's fields. `source`, `meta` and `expires_at` are not stored for todos.
    static func fields(of item: Item) -> ReminderChange {
        ReminderChange(title: item.title, priority: item.priority.reminderPriority, completed: item.status == .done ? true : nil,
                       dueAt: item.dueAt, dueDateOnly: item.dueAt.map { _ in item.dueDateOnly }, url: item.link)
    }

    /// The bridge made `write`'s change (`externalID`: the reminder): remember the reminder's short id and key, and
    /// drop the local item it replaces. Also after the writer stopped waiting, so retrying with the key finds it.
    public func recordTodoWrite(_ write: TodoWrite, externalID: String) throws -> [Event] {
        guard write.operation.action == .create || write.operation.action == .upsert else { return [] }
        return try store.transaction {
            var events: [Event] = []
            let t = timestamp()
            var preferred: String?
            if let promoted = write.promoted, let local = try store.get(id: promoted), try !store.isTodo(id: promoted) {
                try store.delete(id: promoted)
                events.append(Event(type: .removed, item: local, at: t))
                preferred = promoted
            }
            var ref: TodoRef
            if let known = try store.todoRef(externalID: externalID) {
                ref = known
            } else {
                ref = TodoRef(id: try preferred.map { try store.isTodo(id: $0) ? try freshID() : $0 } ?? freshID(),
                              externalID: externalID, key: nil)
                try store.insert(ref)
            }
            if let key = write.key, ref.key != key {
                try store.setKey(key, forRef: ref.id)
                ref.key = key
                if var cached = try store.get(id: ref.id), cached.key != key {
                    cached.key = key
                    cached.updatedAt = t
                    try store.update(cached)
                    events.append(Event(type: .updated, item: cached, at: t))
                }
            }
            return events
        }
    }

    /// What the writer gets once the bridge's snapshot shows the change: the todo as cached now (as it was, for a
    /// delete), or an error when it isn't in the list the write asked for.
    public func todoWriteAnswer(_ write: TodoWrite, externalID: String?) -> Response {
        if let removed = write.removed { return Response(ok: true, item: removed) }
        guard let reminder = externalID ?? write.operation.externalID,
              let ref = try? store.todoRef(externalID: reminder), let item = try? store.get(id: ref.id) else {
            return .failure("Perch.app made the change, but the todo isn't in its list now; check with `perch ls`")
        }
        // A Perch.app older than #70 doesn't know the target list and writes into "Perch" (or doesn't move): say so.
        if let target = write.operation.change.list, item.listID != target {
            return .failure("\(item.id) is in '\(item.listTitle)', not the list asked for: Perch.app is older than perch; update it")
        }
        return Response(ok: true, item: item)
    }

    // MARK: - Helpers

    private func save(_ changed: Item) throws -> (Response, [Event]) {
        var item = changed
        item.updatedAt = timestamp()
        try store.update(item)
        return (Response(ok: true, item: item), [Event(type: .updated, item: item, at: item.updatedAt)])
    }

    private func existing(_ id: String?) throws -> Item {
        guard let id = id?.trimmingCharacters(in: .whitespaces).lowercased(), !id.isEmpty else {
            throw ServiceError("missing id")
        }
        guard let item = try store.get(id: id) else { throw ServiceError("no item with id '\(id)'") }
        return item
    }

    private func freshID() throws -> String {
        for _ in 0..<100 {
            let id = Item.newID()
            if try store.get(id: id) == nil, try !store.isTodo(id: id) { return id }
        }
        throw ServiceError("could not allocate a free id")
    }

    /// The wire and the store keep whole seconds; do the same in memory so events equal what `get` returns.
    func timestamp() -> Date {
        Self.wholeSeconds(now())
    }

    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}
