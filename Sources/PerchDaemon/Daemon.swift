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
    /// Watchers that can be the bridge (the Unix socket), and so hear when one comes or goes.
    private var bridgeCandidates: Set<UUID> = []
    /// The watcher that is the Reminders bridge (#51): the one app that reads and writes the checked lists (#69).
    private var bridge: UUID?
    /// Todo writes handed to the bridge, by operation id, until its snapshot after the ack answers them (or it leaves).
    private var pendingWrites: [String: PendingWrite] = [:]
    /// How long a todo writer waits for the bridge (ack, then the snapshot showing the change).
    let bridgeTimeout: TimeInterval
    private var expiryTimer: DispatchSourceTimer?
    private var livenessTimer: DispatchSourceTimer?
    private let mirror: MirrorWriter
    private var inbox: InboxWatcher?
    /// Inbox lines are on their way to the bridge; `inboxAgain`: the file changed meanwhile, so look once more after.
    private var inboxBusy = false
    private var inboxAgain = false
    /// Inbox lines whose writes the bridge hasn't settled yet (even after their writer gave up): not sent again.
    private var inboxInFlight: Set<String> = []
    private var transcripts: TranscriptWatcher?

    /// `probe` tells whether a session's agent process still runs; `livenessInterval` is how often it is asked.
    public init(config: DaemonConfig, now: @escaping () -> Date = Date.init, probe: @escaping ProcessProbe = SystemProcesses.startTime(of:),
                livenessInterval: TimeInterval = SessionRegistry.livenessInterval, bridgeTimeout: TimeInterval = 2) throws {
        self.config = config
        self.bridgeTimeout = bridgeTimeout
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
            writeMirror()
            afterChange(service.dismissLegacyHookItems())
            let watcher = InboxWatcher(path: config.inboxPath, queue: queue) { [weak self] in self?.ingestInbox() }
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

    /// Handles one request. Called from the transports' threads; a todo write blocks its caller (not the daemon) until
    /// the bridge has made it, at most `bridgeTimeout`.
    public func perform(_ request: Request) -> Response {
        perform(request, settled: nil)
    }

    /// `settled` runs on `queue` once a todo write is settled for good, with whether the bridge made it: possibly after
    /// the writer gave up waiting (a late ack). For anything else, with whether it succeeded.
    func perform(_ request: Request, settled: ((Bool) -> Void)?) -> Response {
        let started = queue.sync { () -> Started in
            if request.op.isSession { return .answered(applySession(request)) }
            switch request.op {
            case .bridgeRegister: return .answered(registerBridge(request.watcher))
            case .todoSnapshot: return .answered(applySnapshot(request))
            case .todoAck: return .answered(applyAck(request))
            case .list: return .answered(list(request))
            case .add, .done, .update, .remove:
                switch service.planTodoWrite(request) {
                case .local: break
                case .answer(let response): return .answered(response)
                case .bridge(let write): return startTodoWrite(write, settled: settled)
                }
            default: break
            }
            let (response, events) = service.handle(request)
            afterChange(events)
            return .answered(response)
        }
        switch started {
        case .answered(let response):
            if let settled { queue.sync { settled(response.ok) } }
            return response
        case .waiting(let write): return finish(write)
        }
    }

    private enum Started {
        case answered(Response)
        case waiting(PendingWrite)
    }

    /// A todo write on its way through the bridge. Touched only on `queue`, except `done`.
    private final class PendingWrite {
        let write: Service.TodoWrite
        var settled: ((Bool) -> Void)?
        let answered = DispatchSemaphore(value: 0)
        /// The bridge made it: the reminder it made or changed. The next snapshot answers it.
        var reminder: String?
        var response: Response?

        init(_ write: Service.TodoWrite) {
            self.write = write
        }
    }

    /// On `queue`: hands the write to the bridge on its watch connection; with no bridge it is refused, not queued.
    private func startTodoWrite(_ write: Service.TodoWrite, settled: ((Bool) -> Void)?) -> Started {
        guard let bridge, let sink = subscribers[bridge] else { return .answered(.failure(Service.todoWriteRefused)) }
        let pending = PendingWrite(write)
        pending.settled = settled
        pendingWrites[write.operation.id] = pending
        sink(Response(ok: true, todoOp: write.operation))
        return .waiting(pending)
    }

    /// Off `queue`: waits for the bridge. Too late, the writer is told so; the write stays pending, so a late ack
    /// still records the reminder's key (a retry with it finds the reminder instead of making another).
    private func finish(_ pending: PendingWrite) -> Response {
        _ = pending.answered.wait(timeout: .now() + bridgeTimeout)
        return queue.sync {
            if pending.response == nil {
                // An ack this late is lost anyway (the bridge is stuck, or dropped it): stop holding the write.
                queue.asyncAfter(deadline: .now() + Self.lateAckWindow) { [weak self] in
                    guard self?.pendingWrites.removeValue(forKey: pending.write.operation.id) != nil else { return }
                    pending.settled?(false)
                }
            }
            return pending.response ?? .failure(
                "Perch.app didn't confirm the todo change within \(String(format: "%g", bridgeTimeout)) seconds; it may "
                + "still happen, so check `perch ls` before retrying (retrying with the same --key is safe)")
        }
    }

    /// How long a write the writer gave up on still waits for its ack (which records the reminder's key).
    static let lateAckWindow: TimeInterval = 30

    private func answer(_ pending: PendingWrite, _ response: Response) {
        pendingWrites.removeValue(forKey: pending.write.operation.id)
        pending.response = response
        pending.answered.signal()
        pending.settled?(pending.reminder != nil)
    }

    /// On `queue`: the bridge made a write (or couldn't). Made: remember the reminder now, answer after the snapshot.
    /// Made but with an error (it couldn't read the list afterwards): remember it, and answer with the error.
    private func applyAck(_ request: Request) -> Response {
        guard let bridge, request.watcher.flatMap(UUID.init(uuidString:)) == bridge else {
            return .failure("only the Reminders bridge acknowledges todo operations")
        }
        guard let ack = request.ack else { return .failure("todo_ack needs an ack") }
        // Answered already (the bridge left and came back): nothing waits for it.
        guard let pending = pendingWrites[ack.id] else { return Response(ok: true) }
        if let error = ack.error, ack.externalID == nil {
            answer(pending, .failure(error))
            return Response(ok: true)
        }
        guard let made = ack.externalID ?? pending.write.operation.externalID else {
            answer(pending, .failure("Perch.app didn't say which reminder it made"))
            return Response(ok: true)
        }
        do {
            afterChange(try service.recordTodoWrite(pending.write, externalID: made))
            pending.reminder = made
            if let error = ack.error { answer(pending, .failure(error)) }
        } catch {
            answer(pending, .failure("internal error: \(error)"))
        }
        return Response(ok: true)
    }

    /// On `queue`: `list`, saying how old the todos are while no bridge keeps them current.
    private func list(_ request: Request) -> Response {
        var (response, _) = service.handle(request)
        if bridge == nil, let items = response.items, !items.isEmpty,
           let todos = try? Set(service.store.todos().map(\.id)), items.contains(where: { todos.contains($0.id) }) {
            response.todosAsOf = service.todosAsOf()
        }
        return response
    }

    /// On `queue`: a session op, its events, and closing the requests of a session that moved on.
    private func applySession(_ request: Request) -> Response {
        let outcome = sessions.handle(request)
        publish(sessionEvents: outcome.events)
        afterChange(outcome.resolveRequestsOf.map(service.resolveRequests(session:)) ?? [])
        return outcome.response
    }

    /// On `queue`: the first watcher to ask becomes the bridge; later ones stay plain clients until it leaves.
    private func registerBridge(_ watcher: String?) -> Response {
        guard let id = watcher.flatMap(UUID.init(uuidString:)), bridgeCandidates.contains(id) else {
            return .failure("bridge_register needs the watcher id of an open watch connection")
        }
        if bridge == nil {
            bridge = id
            announceBridge(true)
            writeMirror()
            // Lines that waited for a bridge go in now.
            ingestInbox()
        }
        return Response(ok: true, bridge: bridge == id)
    }

    /// On `queue`: only the bridge's snapshots reach the todo cache.
    private func applySnapshot(_ request: Request) -> Response {
        guard let bridge, request.watcher.flatMap(UUID.init(uuidString:)) == bridge else {
            return .failure("only the Reminders bridge sends todo snapshots; register with bridge_register first")
        }
        let before = service.todoLists()
        do {
            let events = try service.applySnapshot(request.reminders ?? [], lists: request.lists ?? [])
            // The lists first, so a client never groups the snapshot's todos under the lists of the one before (#69).
            let lists = service.todoLists()
            if lists != before {
                let message = Response(ok: true, todoLists: lists)
                for sink in subscribers.values { sink(message) }
                writeMirror()
            }
            afterChange(events)
        } catch {
            return .failure("internal error: \(error)")
        }
        // The bridge sends this after acking: the writes it made are in the cache now.
        for pending in pendingWrites.values where pending.reminder != nil {
            answer(pending, service.todoWriteAnswer(pending.write, externalID: pending.reminder))
        }
        // The list may take lines it couldn't before (it was just created again, say).
        ingestInbox()
        return Response(ok: true)
    }

    /// Whether a Reminders bridge is connected.
    var hasBridge: Bool {
        queue.sync { bridge != nil }
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

    /// Registers a watcher. `sink` first receives the `{"ok":true}` acknowledgement (with the watcher's id), then one
    /// `Response` per event. It is called on the daemon queue and must not block. `canBridge`: false for HTTP, whose
    /// watchers can't be the Reminders bridge and so never get its comings and goings.
    public func subscribe(canBridge: Bool = true, _ sink: @escaping (Response) -> Void) -> UUID {
        queue.sync {
            let id = UUID()
            sink(Response(ok: true, version: PerchVersion.string, watcher: id.uuidString))
            subscribers[id] = sink
            if canBridge { bridgeCandidates.insert(id) }
            return id
        }
    }

    /// A watcher hung up. If it was the bridge, everyone hears so, and the next app to register takes over.
    public func unsubscribe(_ id: UUID) {
        queue.sync {
            subscribers.removeValue(forKey: id)
            bridgeCandidates.remove(id)
            guard bridge == id else { return }
            bridge = nil
            announceBridge(false)
            for pending in pendingWrites.values {
                answer(pending, .failure("Perch.app went away before confirming the todo change; check `perch ls`"))
            }
            service.bridgeLeft()
            writeMirror()
        }
    }

    private func announceBridge(_ connected: Bool) {
        let message = Response(ok: true, bridge: connected)
        for id in bridgeCandidates { subscribers[id]?(message) }
    }

    var subscriberCount: Int {
        queue.sync { subscribers.count }
    }

    /// Runs on `queue` after every request (and at startup): broadcast, re-render todo.md,
    /// re-arm the expiry timer.
    private func afterChange(_ events: [Event]) {
        publish(events)
        if !events.isEmpty { writeMirror() }
        scheduleExpiry()
    }

    /// todo.md; while no bridge keeps the todos current, it says how old they are.
    private func writeMirror() {
        mirror.write((try? service.store.list(nil)) ?? [], lists: service.todoLists(),
                     todosAsOf: bridge == nil ? service.todosAsOf() : nil)
    }

    /// How long an unterminated last line must stay unchanged before it counts as finished (#6).
    static let inboxSettle: TimeInterval = 1

    /// On `queue`: `- [ ] …` lines in inbox.md become reminders through the bridge (#52), one at a time, and each
    /// leaves the file once the bridge has made it (anything written around it stays). With no bridge, or when the
    /// bridge can't take one, the lines wait in the file. A last line without its newline may be half written: it waits
    /// until the file has not changed for `inboxSettle` (`settled` is what the file held then).
    private func ingestInbox(settled: String? = nil) {
        guard bridge != nil else { return }
        guard !inboxBusy else { inboxAgain = true; return }
        let url = URL(fileURLWithPath: config.inboxPath)
        guard let before = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = Inbox.parse(before, absorbUnterminated: before == settled)
        if parsed.pending { settleInbox(expecting: parsed.entries.isEmpty ? before : parsed.remainder) }
        let entries = parsed.entries.filter { !inboxInFlight.contains($0) }
        guard !entries.isEmpty else { return }
        inboxBusy = true
        let now = service.now()
        // Off the queue: each line waits for the bridge like any todo write, and leaves the file once the bridge has
        // made it, even if that is after giving up on it here (so it is never sent twice).
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for entry in entries {
                let (title, due) = QuickEntry.parse(entry, now: now)
                guard let self else { return }
                self.queue.sync { _ = self.inboxInFlight.insert(entry) }
                let request = Request(op: .add, item: Item(title: title, source: "human", dueAt: due))
                let response = self.perform(request) { [weak self] made in
                    guard let self else { return }
                    self.inboxInFlight.remove(entry)
                    if made { self.removeInboxLine(entry) }
                }
                guard response.ok else { break }
            }
            self?.queue.async {
                guard let self else { return }
                self.inboxBusy = false
                if self.inboxAgain {
                    self.inboxAgain = false
                    self.ingestInbox()
                }
            }
        }
    }

    /// On `queue`: rewrites inbox.md in place (same inode, so editors and watchers keep the file) without that line.
    private func removeInboxLine(_ entry: String) {
        let url = URL(fileURLWithPath: config.inboxPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let rest = Inbox.removing(entry, from: text)
        guard rest != text, let handle = try? FileHandle(forWritingTo: url) else { return }
        try? handle.truncate(atOffset: 0)
        try? handle.write(contentsOf: Data(rest.utf8))
        try? handle.close()
    }

    /// Looks again once the file has had time to settle; if it still holds `expected`, the last line goes in.
    private func settleInbox(expecting expected: String) {
        queue.asyncAfter(deadline: .now() + Self.inboxSettle) { [weak self] in
            self?.ingestInbox(settled: expected)
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
