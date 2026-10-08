import Foundation
import PerchClient
import PerchCore

/// Agent sessions and their state machine (see `SessionReport`), stored in the `sessions` table so a restart
/// keeps them. Not thread-safe: `Daemon` calls it from its serial queue.
///
/// Hooks run asynchronously, so events can arrive out of order. Every report carries the time it was observed;
/// one older than the last event seen for that session is ignored (ties are applied: times travel as whole
/// seconds, and events of one second usually arrive in order). A removed session remembers its removal time for
/// a while, so a straggler from before does not bring it back.
///
/// Sessions also end without an event (a closed terminal tab sends no SessionEnd): `reap()` removes those whose
/// agent process is gone, and those without a known process after `silenceLifetime` without events.
public final class SessionRegistry {
    /// Done turns to idle after this long without anyone looking.
    public static let doneLifetime: TimeInterval = 10 * 60
    /// How long a removed id remembers when it was removed.
    static let tombstoneLifetime: TimeInterval = 10 * 60
    /// How often perchd checks that sessions' agent processes are still there.
    public static let livenessInterval: TimeInterval = 30
    /// A session without a pid (Hermes, a node-launched agent) goes after this long without events.
    public static let silenceLifetime: TimeInterval = 24 * 3600

    public struct Outcome {
        public var response: Response
        public var events: [SessionEvent] = []
        /// This session's requests should be resolved (the agent moved on, nobody is asking any more).
        public var resolveRequestsOf: String?
    }

    let store: Store
    private var removedAt: [String: Date] = [:]
    var now: () -> Date
    let probe: ProcessProbe

    public init(store: Store, now: @escaping () -> Date = Date.init, probe: @escaping ProcessProbe = SystemProcesses.startTime(of:)) {
        self.store = store
        self.now = now
        self.probe = probe
    }

    public func handle(_ request: Request) -> Outcome {
        do {
            switch request.op {
            case .sessionReport:
                guard let report = request.report else { throw ServiceError("session_report needs a report") }
                return try apply(report)
            case .sessionStart:
                guard let s = request.session else { throw ServiceError("session_start needs a session") }
                return try apply(SessionReport(id: s.id, kind: .prompt, at: s.turnStartedAt, source: s.source, title: s.title,
                                               cwd: s.cwd, link: s.link, prompt: s.prompt))
            case .sessionEnd:
                return try apply(SessionReport(id: request.id ?? "", kind: .end, at: request.at ?? now()))
            case .sessionSeen:
                return try seen(request.id)
            case .sessionRemove:
                return try remove(request.id)
            case .sessions:
                return Outcome(response: Response(ok: true, sessions: try store.sessions()))
            default:
                throw ServiceError("not a session op: \(request.op.rawValue)")
            }
        } catch let error as ServiceError {
            return Outcome(response: .failure(error.message))
        } catch {
            return Outcome(response: .failure("internal error: \(error)"))
        }
    }

    private func apply(_ report: SessionReport) throws -> Outcome {
        let id = report.id.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { throw ServiceError("session id must not be empty") }
        let at = Service.wholeSeconds(min(report.at, now()))
        let ignored = Outcome(response: Response(ok: true, sessions: []))
        pruneTombstones()
        if let removed = removedAt[id], at < removed { return ignored }
        let existing = try store.session(id: id)
        if let existing, at < existing.updatedAt { return ignored }
        // A hook that outlived its agent (a PermissionRequest still waiting when the process died) speaks for a
        // session that is over: it must not bring it back.
        if report.kind != .end, let pid = report.pid, !isAlive(pid: pid, startedAt: report.pidStartedAt) { return ignored }

        if report.kind == .end {
            removedAt[id] = max(removedAt[id] ?? .distantPast, at)
            var outcome = Outcome(response: Response(ok: true, sessions: []), resolveRequestsOf: id)
            if let existing {
                try store.deleteSession(id: id)
                outcome.response.sessions = [existing]
                outcome.events = [SessionEvent(type: .ended, session: existing, at: at)]
            }
            return outcome
        }

        var s = existing ?? Session(id: id, startedAt: at)
        s.source = report.source ?? s.source
        s.title = report.title ?? s.title
        s.cwd = report.cwd ?? s.cwd
        s.link = report.link ?? s.link
        s.transcriptPath = report.transcriptPath ?? s.transcriptPath
        if let pid = report.pid {
            s.pid = pid
            s.pidStartedAt = report.pidStartedAt
        }
        s.updatedAt = at
        func enter(_ status: SessionStatus) {
            if s.status != status { s.statusAt = at }
            s.status = status
        }
        var resolves = true
        switch report.kind {
        case .prompt:
            enter(.running)
            s.turnStartedAt = at
            s.prompt = report.prompt
            s.detail = nil
            s.error = nil
            resolves = false
        case .waiting:
            // A late "needs your permission" notification must not replace the command it is about.
            let keep = report.keepDetail == true && existing?.status == .waiting && existing?.detail != nil
            if !keep { s.detail = report.detail }
            enter(.waiting)
            resolves = false
        case .resume:
            if s.status == .waiting {
                enter(.running)
                s.detail = nil
            }
        case .stop:
            enter(.done)
            s.lastMessage = report.lastMessage
            s.detail = nil
        case .failure:
            enter(.failed)
            s.error = report.error ?? "unknown"
            s.detail = nil
        case .interrupt:
            enter(.idle)
            s.detail = nil
        case .end:
            break
        }
        var outcome = Outcome(response: Response(ok: true, sessions: [s]), resolveRequestsOf: resolves ? id : nil)
        guard s != existing else { return outcome }
        try store.save(s)
        removedAt[id] = nil
        if report.kind == .prompt { outcome.events.append(SessionEvent(type: .started, session: s, at: at)) }
        outcome.events.append(SessionEvent(type: .updated, session: s, at: at))
        return outcome
    }

    /// Someone looked at the result: done → idle. Other states stay.
    private func seen(_ rawID: String?) throws -> Outcome {
        var s = try existing(rawID)
        guard s.status == .done else { return Outcome(response: Response(ok: true, sessions: [s])) }
        s.status = .idle
        try store.save(s)
        return Outcome(response: Response(ok: true, sessions: [s]), events: [SessionEvent(type: .updated, session: s, at: now())])
    }

    /// Manual removal (a session whose end never arrived). The next event for it brings it back.
    private func remove(_ rawID: String?) throws -> Outcome {
        let s = try existing(rawID)
        return Outcome(response: Response(ok: true, sessions: [s]), events: [try delete(s)])
    }

    /// Removes it and remembers when, so events observed before then do not bring it back.
    private func delete(_ s: Session) throws -> SessionEvent {
        try store.deleteSession(id: s.id)
        removedAt[s.id] = Service.wholeSeconds(now())
        return SessionEvent(type: .ended, session: s, at: now())
    }

    /// Removes sessions that ended without telling: the agent process is gone, or its pid now belongs to a process
    /// started at another time (reuse); without a pid, no events for `silenceLifetime`. Returns their end events;
    /// the caller resolves their requests.
    public func reap() -> [SessionEvent] {
        guard let all = try? store.sessions() else { return [] }
        let silentSince = now().addingTimeInterval(-Self.silenceLifetime)
        return all.filter { s in
            guard let pid = s.pid else { return s.updatedAt < silentSince }
            return !isAlive(pid: pid, startedAt: s.pidStartedAt)
        }.compactMap { try? delete($0) }
    }

    /// The process runs and, if we know when it started, is the same one (not a reused pid).
    private func isAlive(pid: Int32, startedAt: Date?) -> Bool {
        guard let started = probe(pid) else { return false }
        return startedAt.map { Service.wholeSeconds($0) == Service.wholeSeconds(started) } ?? true
    }

    /// Done sessions nobody looked at for `doneLifetime` go idle.
    public func sweep() -> [SessionEvent] {
        guard let stale = try? store.sessions(doneBefore: now().addingTimeInterval(-Self.doneLifetime)) else { return [] }
        return stale.compactMap { done in
            var s = done
            s.status = .idle
            guard (try? store.save(s)) != nil else { return nil }
            return SessionEvent(type: .updated, session: s, at: now())
        }
    }

    public func nextExpiry() -> Date? {
        (try? store.earliestDone())?.addingTimeInterval(Self.doneLifetime)
    }

    private func existing(_ rawID: String?) throws -> Session {
        guard let id = rawID?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { throw ServiceError("missing id") }
        guard let s = try store.session(id: id) else { throw ServiceError("no session with id '\(id)'") }
        return s
    }

    private func pruneTombstones() {
        let cutoff = now().addingTimeInterval(-Self.tombstoneLifetime)
        removedAt = removedAt.filter { $0.value > cutoff }
    }
}

/// When the process with this pid started, or nil if there is none. `SystemProcesses.startTime(of:)` in perchd.
public typealias ProcessProbe = (Int32) -> Date?

extension Request.Op {
    var isSession: Bool {
        switch self {
        case .sessionStart, .sessionEnd, .sessions, .sessionReport, .sessionSeen, .sessionRemove: return true
        default: return false
        }
    }
}
