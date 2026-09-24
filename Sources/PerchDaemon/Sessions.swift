import Foundation
import PerchCore

/// Running agent turns, in memory only (a restart forgets them; the next prompt brings them back).
/// Not thread-safe: `Daemon` calls it from its serial queue.
///
/// Hooks run asynchronously, so a turn's `session_end` can arrive before its `session_start`, or the previous
/// turn's end after the next turn's start. Every message carries the time it was observed; anything older
/// than the last message seen for that id is ignored (ties go to the start).
public final class SessionRegistry {
    /// A turn that never reports its end (interrupted, terminal closed) drops out after this long.
    public static let maxTurn: TimeInterval = 3 * 3600
    /// How long an ended id remembers its end time, to reject a start that arrives late.
    static let tombstoneLifetime: TimeInterval = 10 * 60

    private var running: [String: Session] = [:]
    private var endedAt: [String: Date] = [:]
    var now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func handle(_ request: Request) -> (Response, [SessionEvent]) {
        switch request.op {
        case .sessionStart: return start(request.session)
        case .sessionEnd: return end(request.id, at: request.at ?? now())
        case .sessions: return (Response(ok: true, sessions: list()), [])
        default: return (.failure("not a session op: \(request.op.rawValue)"), [])
        }
    }

    public func list() -> [Session] {
        running.values.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    private func start(_ incoming: Session?) -> (Response, [SessionEvent]) {
        guard var session = incoming else { return (.failure("session_start needs a session"), []) }
        session.id = session.id.trimmingCharacters(in: .whitespaces)
        guard !session.id.isEmpty else { return (.failure("session id must not be empty"), []) }
        session.startedAt = min(session.startedAt, now())
        pruneTombstones()
        // Times travel as whole seconds; on a tie the start wins (a whole turn inside one second does not happen).
        if let ended = endedAt[session.id], session.startedAt < ended { return (Response(ok: true), []) }
        if let current = running[session.id], session.startedAt < current.startedAt { return (Response(ok: true), []) }
        endedAt[session.id] = nil
        running[session.id] = session
        return (Response(ok: true, sessions: [session]), [SessionEvent(type: .started, session: session, at: now())])
    }

    private func end(_ rawID: String?, at: Date) -> (Response, [SessionEvent]) {
        guard let id = rawID?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return (.failure("missing id"), []) }
        endedAt[id] = max(endedAt[id] ?? .distantPast, at)
        guard let session = running[id], session.startedAt <= at else { return (Response(ok: true), []) }
        running[id] = nil
        return (Response(ok: true, sessions: [session]), [SessionEvent(type: .ended, session: session, at: now())])
    }

    /// Drops turns older than `maxTurn`.
    public func sweep() -> [SessionEvent] {
        let cutoff = now().addingTimeInterval(-Self.maxTurn)
        return running.values.filter { $0.startedAt <= cutoff }.sorted { $0.id < $1.id }.map { session in
            running[session.id] = nil
            return SessionEvent(type: .ended, session: session, at: now())
        }
    }

    public func nextExpiry() -> Date? {
        running.values.map(\.startedAt).min()?.addingTimeInterval(Self.maxTurn)
    }

    private func pruneTombstones() {
        let cutoff = now().addingTimeInterval(-Self.tombstoneLifetime)
        endedAt = endedAt.filter { $0.value > cutoff }
    }
}

extension Request.Op {
    var isSession: Bool { self == .sessionStart || self == .sessionEnd || self == .sessions }
}
