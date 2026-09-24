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
                return try add(request.item)
            case .list:
                return (Response(ok: true, items: try store.list(request.filter).queueOrdered(now: now())), [])
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
            case .sessionStart, .sessionEnd, .sessions:
                return (.failure("session ops are handled by SessionRegistry"), [])
            }
        } catch let error as ServiceError {
            return (.failure(error.message), [])
        } catch {
            return (.failure("internal error: \(error)"), [])
        }
    }

    // MARK: - Ops

    private func add(_ incoming: Item?) throws -> (Response, [Event]) {
        guard var item = incoming else { throw ServiceError("add needs an item") }
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { throw ServiceError("title must not be empty") }
        if let key = item.key?.trimmingCharacters(in: .whitespaces) {
            item.key = key.isEmpty ? nil : key
        }
        let t = timestamp()
        item.dueAt = item.dueAt.map(Self.wholeSeconds)
        // Round up so storing whole seconds never shortens the window an agent asked for.
        item.expiresAt = item.expiresAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.up)) }
        item.response = nil
        if item.kind == .request {
            if (item.options ?? []).isEmpty { item.options = ["allow", "deny"] }
        } else {
            item.options = nil
        }
        return try store.transaction {
            if let key = item.key, let existing = try store.find(key: key) {
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
        try store.delete(id: item.id)
        return (Response(ok: true, item: item), [Event(type: .removed, item: item, at: timestamp())])
    }

    private func update(_ id: String?, _ patch: Request.Patch?) throws -> (Response, [Event]) {
        guard let patch, !patch.isEmpty else {
            throw ServiceError("update needs at least one of: title, kind, due_at, clear_due")
        }
        if patch.dueAt != nil && patch.clearDue == true {
            throw ServiceError("update takes either due_at or clear_due, not both")
        }
        var item = try existing(id)
        let original = item
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
        if let due = patch.dueAt { item.dueAt = Self.wholeSeconds(due) }
        if patch.clearDue == true { item.dueAt = nil }
        guard item != original else { return (Response(ok: true, item: original), []) }
        return try save(item)
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

    public func nextExpiry() -> Date? {
        try? store.nextExpiry()
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
            if try store.get(id: id) == nil { return id }
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
