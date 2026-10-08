import Foundation
import PerchClient
import PerchCore

/// Where one perchd instance keeps its files. Tests point this at a temp dir.
public struct DaemonConfig {
    public var home: URL
    public var socketPath: String
    public var databasePath: String
    public var mirrorPath: String
    public var inboxPath: String

    public init(home: URL = PerchPaths.home) {
        self.home = home
        socketPath = PerchPaths.socket(in: home).path
        databasePath = PerchPaths.database(in: home).path
        mirrorPath = PerchPaths.mirror(in: home).path
        inboxPath = PerchPaths.inbox(in: home).path
    }
}

/// Thread-safe core of perchd. Every mutation runs on one serial queue; transports call in from
/// their own threads and receive events through subscriber sinks.
public final class Daemon {
    public let config: DaemonConfig
    let queue = DispatchQueue(label: "dev.perch.perchd.core")
    let service: Service
    let sessions: SessionRegistry
    private var subscribers: [UUID: (Response) -> Void] = [:]
    private var expiryTimer: DispatchSourceTimer?
    private var livenessTimer: DispatchSourceTimer?
    private let mirror: MirrorWriter
    private var inbox: InboxWatcher?
    private var transcripts: TranscriptWatcher?

    /// `probe` tells whether a session's agent process still runs; `livenessInterval` is how often it is asked.
    public init(config: DaemonConfig, now: @escaping () -> Date = Date.init, probe: @escaping ProcessProbe = SystemProcesses.startTime(of:),
                livenessInterval: TimeInterval = SessionRegistry.livenessInterval) throws {
        self.config = config
        try FileManager.default.createDirectory(at: config.home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        service = Service(store: try Store(path: config.databasePath), now: now)
        sessions = SessionRegistry(store: service.store, now: now, probe: probe)
        mirror = MirrorWriter(path: config.mirrorPath)
        if !FileManager.default.fileExists(atPath: config.inboxPath) {
            FileManager.default.createFile(atPath: config.inboxPath, contents: nil)
        }
        queue.sync {
            transcripts = TranscriptWatcher(queue: queue) { [weak self] id in self?.checkTranscript(of: id) }
            mirror.write(activeItems())
            afterChange(service.dismissLegacyHookItems())
            afterChange(ingestInbox())
            let watcher = InboxWatcher(path: config.inboxPath, queue: queue) { [weak self] in
                guard let self else { return }
                self.afterChange(self.ingestInbox())
            }
            watcher.start()
            inbox = watcher
            // Right away too: sessions whose agent exited while perchd was down go now, and transcripts get
            // watched (and read once: a turn interrupted while perchd was down).
            reapOnQueue()
            syncTranscripts()
            let liveness = DispatchSource.makeTimerSource(queue: queue)
            liveness.schedule(deadline: .now() + livenessInterval, repeating: livenessInterval, leeway: .milliseconds(100))
            liveness.setEventHandler { [weak self] in self?.reapOnQueue() }
            liveness.resume()
            livenessTimer = liveness
        }
    }

    deinit {
        expiryTimer?.cancel()
        livenessTimer?.cancel()
        inbox?.stop()
        transcripts?.stop()
    }

    public func perform(_ request: Request) -> Response {
        queue.sync {
            if request.op.isSession { return applySession(request) }
            let (response, events) = service.handle(request)
            afterChange(events)
            return response
        }
    }

    /// On `queue`: a session op, its events, and closing the requests of a session that moved on.
    private func applySession(_ request: Request) -> Response {
        let outcome = sessions.handle(request)
        publish(sessionEvents: outcome.events)
        afterChange(outcome.resolveRequestsOf.map(service.resolveRequests(session:)) ?? [])
        return outcome.response
    }

    /// Session id → transcript path perchd is watching (running / waiting Claude Code sessions).
    var watchedTranscripts: [String: String] {
        queue.sync { transcripts?.paths ?? [:] }
    }

    /// Watches the transcripts of running / waiting sessions, and only those; a newly watched one is read at once.
    private func syncTranscripts() {
        guard let transcripts else { return }
        let live = ((try? sessions.store.sessions()) ?? []).filter { $0.status == .running || $0.status == .waiting }
        let wanted = Dictionary(live.compactMap { s in s.transcriptPath.map { (s.id, $0) } }, uniquingKeysWith: { $1 })
        for id in transcripts.watch(wanted) { checkTranscript(of: id) }
    }

    /// The transcript says the turn was interrupted (No or Esc at Claude Code's prompt, #8): the session goes idle,
    /// as of the interruption, so a report from a later turn still wins.
    private func checkTranscript(of id: String) {
        guard let path = transcripts?.paths[id], let tail = TranscriptWatcher.tail(of: path),
              let at = ClaudeTranscript.interruption(tail: tail),
              let session = try? sessions.store.session(id: id), session.status == .running || session.status == .waiting
        else { return }
        _ = applySession(Request(op: .sessionReport, report: SessionReport(id: id, kind: .interrupt, at: at)))
    }

    /// Removes sessions whose agent is gone (see `SessionRegistry.reap`), as the liveness timer does.
    func reapSessions() {
        queue.sync { reapOnQueue() }
    }

    private func reapOnQueue() {
        let ended = sessions.reap()
        publish(sessionEvents: ended)
        afterChange(ended.flatMap { service.resolveRequests(session: $0.session.id) })
    }

    /// Registers a watcher. `sink` first receives the `{"ok":true}` acknowledgement, then one
    /// `Response` per event. It is called on the daemon queue and must not block.
    public func subscribe(_ sink: @escaping (Response) -> Void) -> UUID {
        queue.sync {
            let id = UUID()
            sink(Response(ok: true, version: PerchVersion.string))
            subscribers[id] = sink
            return id
        }
    }

    public func unsubscribe(_ id: UUID) {
        queue.sync { _ = subscribers.removeValue(forKey: id) }
    }

    var subscriberCount: Int {
        queue.sync { subscribers.count }
    }

    /// Runs on `queue` after every request (and at startup): broadcast, re-render todo.md,
    /// re-arm the expiry timer.
    private func afterChange(_ events: [Event]) {
        publish(events)
        if !events.isEmpty { mirror.write(activeItems()) }
        scheduleExpiry()
    }

    private func activeItems() -> [Item] {
        (try? service.store.list(nil)) ?? []
    }

    /// How long an unterminated last line must stay unchanged before it counts as finished (#6).
    static let inboxSettle: TimeInterval = 1

    /// Absorbs `- [ ] …` lines from inbox.md as tasks and rewrites the file without them.
    /// The file is re-read right before rewriting; if it changed meanwhile, start over, so a line
    /// appended during ingestion is never lost. A last line without its newline may be half written: it waits
    /// until the file has not changed for `inboxSettle` (`settled` is what the file held then).
    private func ingestInbox(settled: String? = nil) -> [Event] {
        let url = URL(fileURLWithPath: config.inboxPath)
        for _ in 0..<5 {
            guard let before = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let parsed = Inbox.parse(before, absorbUnterminated: before == settled)
            if parsed.pending { settleInbox(expecting: parsed.entries.isEmpty ? before : parsed.remainder) }
            guard !parsed.entries.isEmpty else { return [] }
            guard (try? String(contentsOf: url, encoding: .utf8)) == before,
                  let handle = try? FileHandle(forWritingTo: url) else { continue }
            // Rewrite in place (same inode) so editors and watchers keep the file.
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: Data(parsed.remainder.utf8))
            try? handle.close()
            return parsed.entries.flatMap { entry -> [Event] in
                let (title, due) = QuickEntry.parse(entry, now: service.now())
                return service.handle(Request(op: .add, item: Item(title: title, source: "human", dueAt: due))).1
            }
        }
        return []
    }

    /// Looks again once the file has had time to settle; if it still holds `expected`, the last line goes in.
    private func settleInbox(expecting expected: String) {
        queue.asyncAfter(deadline: .now() + Self.inboxSettle) { [weak self] in
            guard let self else { return }
            self.afterChange(self.ingestInbox(settled: expected))
        }
    }

    /// One timer for the earliest `expires_at` or done session to idle; it sweeps, broadcasts and re-arms itself.
    /// Measured on the daemon's clock, so tests that move it get the timer they expect.
    private func scheduleExpiry() {
        expiryTimer?.cancel()
        expiryTimer = nil
        guard let next = [service.nextExpiry(), sessions.nextExpiry()].compactMap({ $0 }).min() else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(0, next.timeIntervalSince(service.now())), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.publish(sessionEvents: self.sessions.sweep())
            self.afterChange(self.service.sweepExpired())
        }
        timer.resume()
        expiryTimer = timer
    }

    private func publish(sessionEvents events: [SessionEvent]) {
        for event in events {
            let message = Response(ok: true, sessionEvent: event)
            for sink in subscribers.values { sink(message) }
        }
        if !events.isEmpty { syncTranscripts() }
    }

    private func publish(_ events: [Event]) {
        for event in events {
            let message = Response(ok: true, event: event)
            for sink in subscribers.values { sink(message) }
        }
    }
}
