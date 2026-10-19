import Combine
import Foundation
import PerchClient
import PerchCore

/// What the notch shows, fed by `QueueConnection`, and what its rows and hotkeys do. Main thread only.
/// The Agents tab renders `panel` (agent sessions, and the requests Allow / Deny answer); the Todo tab renders `todos`
/// (perchd's cache of the "Perch" Reminders list) or, without the list, `reminders`' button.
/// The folded notch (mascot, running count, banner, sounds) only ever follows sessions; the one thing about todos it
/// shows is the right wing's static icon and open count (`collapsedTodoCount`, #56).
///
/// With a `RemindersBridge`, the app offers itself to perchd as the Reminders bridge (#51). perchd takes one: that app
/// sends the list's snapshots, writes its own Todo tab's changes straight to Reminders, and applies the todo writes
/// perchd hands it from the CLI, inbox.md and other apps (#52). Any other app is a plain client (its Todo tab's writes
/// go through perchd to the bridge), and takes over when perchd says the bridge left.
@MainActor
public final class QueueModel: ObservableObject {
    @Published public private(set) var state = QueueState()
    /// False until the first snapshot, and whenever perchd is unreachable.
    @Published public private(set) var online = false
    @Published public private(set) var offlineReason: String?
    /// "Now" for the rows' times. Ticks every minute; changes themselves always arrive as events.
    @Published public private(set) var now = Date()
    /// Bumped whenever the notch should pulse once: a session starts needing you, fails or finishes (`Panel.pulses`).
    @Published public private(set) var pulse = 0
    /// The state whose arrival caused the last pulse (its colour rings).
    @Published public private(set) var pulseStatus: SessionStatus?
    /// Agent sessions by id, in any state (Hermes too; `panel` leaves those out).
    @Published public private(set) var sessions: [String: Session] = [:]
    /// The folded mascot's bow or scratch after an answer (#62), while it plays. Never a pulse: no banner, no sound.
    @Published public private(set) var answerReaction: AnswerReaction?
    /// The collapsed notch's event banner, while one shows (see `Banner`).
    @Published public private(set) var banner: Banner?
    /// The last failed action, shown briefly in the expanded notch.
    @Published public private(set) var flash: String?
    /// Which pulses also play a sound (#35). The Sounds menu edits it; the app keeps it in its user defaults.
    @Published public var chimes = ChimeSettings() {
        didSet { chime.settings = chimes }
    }

    /// The expanded notch's tab. It only changes when the panel opens (`expanded`) or someone picks one (`pick`).
    @Published public private(set) var tab: PanelTab = .agents
    /// Todos whose circle was clicked: crossed out with an Undo until `completionDelay` passes and `done` is sent.
    /// One stays here until its item leaves (the `done` event), so the row never flickers back.
    @Published public private(set) var completing: Set<String> = []
    /// How long a clicked circle waits for Undo before the todo is done.
    public var completionDelay: TimeInterval = 3
    /// A second click this soon after the first is the rest of a double-click, which does nothing more (#53); the app
    /// sets the system's double-click interval.
    public var doubleClickInterval: TimeInterval = 0
    private var lastToggle: (id: String, at: Date)?
    /// The todo popup while it is open (#43). The popup draws it and edits `title`; the rest goes through the methods.
    @Published public var editor: TodoEditor?
    /// The Todo tab's Reminders state; nil without a `RemindersBridge` (then it just shows perchd's todos).
    @Published public private(set) var reminders: RemindersState?
    /// Whether perchd took this app as the Reminders bridge.
    @Published public private(set) var isBridge = false
    /// Todos added while the panel was open, marked new for `highlightDuration`.
    @Published public private(set) var highlighted: Set<String> = []
    public var highlightDuration: TimeInterval = 1

    /// Whether the notch is expanded; the app sets it. Opening picks the tab (`PanelTab.opening`).
    public var expanded = false {
        didSet {
            guard expanded != oldValue else { return }
            // An answer given in the panel plays as it folds; an expanded notch has no mascot to play one.
            playAnswer(expanded ? nil : answers.folded(at: Date()))
            guard expanded else { return }
            // Access may have been revoked in System Settings while nobody looked.
            remindersChanged(listChanged: false)
            let opening = PanelTab.opening(picked: pickedTab, panel: panel)
            if tab != opening { tab = opening }
        }
    }

    /// Called after every applied update; used to measure CLI → notch latency.
    public var onApply: ((QueueConnection.Update) -> Void)?
    /// Every session event, after it is applied (setup watches Codex's to learn its hooks are trusted).
    public var onSession: ((SessionEvent) -> Void)?
    /// Goes to a session's link (its terminal). The app sets it; AppKit stays out of this module.
    public var jump: (String?) -> Void = { _ in }
    /// Opens a reminder in the Reminders app (✎), or just Reminders when nil, and collapses the notch. The app sets it.
    public var openReminder: (URL?) -> Void = { _ in }
    /// Plays a chime. The app sets it, like `jump`.
    public var onChime: (ChimeSound) -> Void = { _ in }
    /// A banner's title and text, laid out, in points: how long it stays depends on whether it has to scroll.
    public var measureBanner: (Banner) -> Double = { _ in 0 }
    /// False while the notch is expanded: the list says it all, so banners are dropped, not saved for later.
    public var showsBanners = true {
        didSet { if !showsBanners { setBanner(nil) } }
    }

    private var chime = Chime()
    private var answers = AnswerReactions()
    private var answerTimer: Timer?
    private var banners = BannerState()
    private var bannerTimer: Timer?
    private var connection: QueueConnection?
    private var client = PerchClient()
    private var ticker: Timer?
    private var flashTimer: Timer?
    private let actions = DispatchQueue(label: "dev.perch.app.actions")
    /// The bridge's acks and snapshots, in order, never stuck behind this app's own todo write (which perchd may be
    /// handing back to this very app).
    private let bridgeActions = DispatchQueue(label: "dev.perch.app.bridge")
    /// The last tab picked by hand; memory only, so a relaunch starts on Agents.
    private var pickedTab: PanelTab = .agents
    /// Pending completions that have not sent `done` yet; cancelling one is Undo.
    private var completions: [String: DispatchWorkItem] = [:]
    private var bridge: RemindersBridge?
    /// This connection's watch id, which bridge requests speak for; nil while offline.
    private var watcher: String?
    private var registering = false
    /// A snapshot is being read or sent; `snapshotAgain`: something changed meanwhile, so read once more after it.
    private var snapshotting = false
    private var snapshotAgain = false
    /// Acks for todo operations applied since the last snapshot read began. Each goes out right before the first
    /// snapshot read after its write, so perchd answers the writer with a cache that shows the change.
    private var acksDue: [TodoAck] = []

    public init() {}

    /// What ⌥⇧A / ⌥⇧D answer and ⌥⇧O jumps to (see `Panel`).
    public var headRequest: Item? { panel.headRequest }
    public var headSession: Session? { panel.headSession }
    public var panel: Panel { Panel(sessions: sessions.values, requests: state.items.values) }

    /// The expanded notch's panel: the sessions with setup above them.
    public func panel(setup: SetupState) -> Panel {
        Panel(sessions: sessions.values, requests: state.items.values, setup: setup)
    }

    /// The Todo tab: open tasks by priority (completing ones included, crossed out, until they are done).
    public var todos: TodoList { TodoList(items: state.items.values) }

    /// Whether the Todo tab shows todos: the list is readable, or this app doesn't use Reminders itself.
    public var showsTodos: Bool { reminders?.isReady ?? true }

    /// The folded notch's todo count (#56): the tab strip's open count, or 0 (the icon alone) while it can't be trusted,
    /// without the list or with perchd away. Completing todos still count until they are done.
    public var collapsedTodoCount: Int { online && showsTodos ? todos.openCount : 0 }

    /// The Reminders list's name, for the Todo tab's messages.
    public var remindersListName: String { bridge?.listName ?? "Perch" }

    /// `reminders`: this app's access to the "Perch" list; nil to only show what perchd caches.
    public func connect(client: PerchClient = PerchClient(), reminders: RemindersBridge? = nil) {
        self.client = client
        if let reminders {
            bridge = reminders
            self.reminders = reminders.state
            reminders.store.observeChanges { [weak self] in self?.remindersChanged() }
        }
        let connection = QueueConnection(client: client) { [weak self] update in
            MainActor.assumeIsolated { self?.handle(update) }
        }
        self.connection = connection
        connection.start()
        scheduleTick()
    }

    public func disconnect() {
        connection?.stop()
        connection = nil
        ticker?.invalidate()
        watcher = nil
        isBridge = false
    }

    public func handle(_ update: QueueConnection.Update) {
        switch update {
        case .snapshot(let items, let all, let watcher):
            state.replace(with: items)
            sessions = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            online = true
            offlineReason = nil
            self.watcher = watcher
            isBridge = false
            acksDue = []
            registerBridge()
        case .event(let event):
            state.apply(event)
            if expanded && event.type == .added && event.item.kind == .task && event.item.status == .open {
                highlight(event.item.id)
            }
        case .session(let event):
            let before = sessions[event.session.id]
            let after = event.type == .ended ? nil : event.session
            sessions[event.session.id] = after
            if Panel.pulses(from: before, to: after) {
                pulseStatus = after?.status
                pulse += 1
                // The entry reaction replaces a bow or scratch.
                playAnswer(nil)
            }
            if let sound = chime.sound(from: before, to: after, now: Date()) { onChime(sound) }
            if showsBanners, banners.update(id: event.session.id, from: before, to: after) { setBanner(banners.current) }
            onSession?(event)
        case .bridge(let connected):
            // The bridge left: offer to take over (the first app to ask wins).
            if !connected { registerBridge() }
        case .todo(let operation):
            applyTodo(operation)
        case .offline(let reason):
            online = false
            offlineReason = reason
            sessions = [:]
            setBanner(nil)
            watcher = nil
            isBridge = false
        }
        // A todo that is done (here or anywhere) or gone has nothing left to undo.
        for id in completing where state.items[id] == nil { finishCompletion(id) }
        // Nothing left to edit (done, deleted, or perchd went away).
        if case .edit(let id)? = editor?.mode, state.items[id] == nil || !online { editor = nil }
        refresh()
        onApply?(update)
    }

    /// Advances `now` and re-arms the tick.
    private func refresh() {
        now = Date()
        scheduleTick()
    }

    // Row and hotkey actions. Results come back as events like any other change; only failures are reported here.

    /// Clicking a row: back to that session's terminal. A done session has now been seen, so it turns idle.
    public func open(_ session: Session) {
        jump(session.link)
        if session.status == .done { send(Request(op: .sessionSeen, id: session.id)) }
    }

    /// "Remove from Panel": forgets the session until its next event.
    public func remove(_ session: Session) {
        send(Request(op: .sessionRemove, id: session.id))
    }

    /// Allow / Deny (or any of the request's options). The waiting hook prints the decision. The mascot bows or
    /// scratches its head: now if the notch is folded (the hotkeys), else as it folds (`AnswerReactions`).
    public func respond(_ item: Item, _ value: String) {
        send(Request(op: .respond, id: item.id, value: value))
        if let answer = answers.answered(value, at: Date(), expanded: expanded) { playAnswer(answer) }
    }

    /// ⌥⇧O: the session that has waited longest.
    public func openHead() {
        if let head = headSession { open(head) }
    }

    /// ⌥⇧A / ⌥⇧D: the first request the panel shows, if it offers that answer.
    public func answerHead(_ value: String) {
        guard let head = headRequest, head.options?.contains(value) ?? false else { return }
        respond(head, value)
    }

    /// Clicking a tab's icon. Remembered (in memory) as the tab to open on next time.
    public func pick(_ tab: PanelTab) {
        pickedTab = tab
        if self.tab != tab { self.tab = tab }
    }

    /// Clicking a todo's circle or title: crosses it out and sends `done` after `completionDelay`, unless it is clicked
    /// again (or Undo) first; a double-click's second click is ignored. The timer lives here, not in the view, so it
    /// still commits after the notch collapses; quitting meanwhile leaves the todo open.
    public func toggleCompletion(_ item: Item) {
        let now = Date()
        if let last = lastToggle, last.id == item.id, now.timeIntervalSince(last.at) < doubleClickInterval { return }
        lastToggle = (item.id, now)
        if completing.contains(item.id) { return undoCompletion(item.id) }
        guard state.items[item.id] != nil else { return }
        completing.insert(item.id)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.commitCompletion(item.id) }
        }
        completions[item.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay, execute: work)
    }

    /// Undo: the todo stays open and no `done` is sent. Too late once `done` has gone out.
    public func undoCompletion(_ id: String) {
        guard let work = completions.removeValue(forKey: id) else { return }
        work.cancel()
        completing.remove(id)
    }

    /// Right-click → Priority: moves the todo to that group (by its creation time, like any other).
    public func setPriority(_ item: Item, _ priority: ItemPriority) {
        guard item.priority != priority else { return }
        write(Request(op: .update, id: item.id, patch: Request.Patch(priority: priority))) {
            try $0.update(item, priority: priority)
        }
    }

    /// ⌥⇧Space (`fromPanel` false) or "+ Add a todo": the popup, empty and on Normal.
    public func openAdd(fromPanel: Bool) {
        editor = .add(fromPanel: fromPanel)
    }

    /// Edit…: the larger editor, prefilled.
    public func openEdit(_ item: Item) {
        editor = .edit(item)
    }

    /// ✎: this todo in the Reminders app, for everything Perch doesn't edit (subtasks, flags, alarms, …).
    public func openInReminders(_ item: Item) {
        openReminder(bridge?.link(for: item))
    }

    /// Tab / Shift-Tab in the popup.
    public func cycleEditorPriority(forward: Bool) {
        editor?.cyclePriority(forward: forward)
    }

    /// Esc, clicking elsewhere: nothing is sent.
    public func closeEditor() {
        if editor != nil { editor = nil }
    }

    /// Return. Adding: `add` (source human, the chosen priority); the popup stays open, empty and back on Normal for
    /// the next one. Editing: what changed of the title, notes, due date, priority and URL, then the editor closes.
    /// False (and nothing sent) while the title is blank.
    @discardableResult
    public func submitEditor() -> Bool {
        guard let editor, let title = editor.submittedTitle else { return false }
        switch editor.mode {
        case .add:
            write(Request(op: .add, item: Item(title: title, kind: .task, priority: editor.priority, source: "human"))) {
                try $0.add(title: title, priority: editor.priority)
            }
            self.editor = .add(fromPanel: editor.fromPanel)
        case .edit(let id):
            self.editor = nil
            guard let item = state.items[id] else {
                show("no todo with id '\(id)'")
                return true
            }
            guard let edited = editor.edited(item) else { return false }
            let patch = Request.Patch(from: item, to: edited)
            guard !patch.isEmpty else { return true }
            write(Request(op: .update, id: id, patch: patch)) { try $0.update(item, ReminderChange(from: item, to: edited)) }
        }
        return true
    }

    /// Right-click → Delete: `rm` at once, no confirmation, no undo.
    public func delete(_ item: Item) {
        undoCompletion(item.id)
        write(Request(op: .remove, id: item.id)) { try $0.delete(item) }
    }

    // MARK: - Reminders (#51)

    /// "Connect Reminders": the system prompt, then the list; then this app offers to be the bridge.
    public func connectReminders() async {
        guard let bridge else { return }
        await bridge.connect()
        remindersChanged()
    }

    /// "Create Perch list", after the list was deleted.
    public func createRemindersList() {
        guard let bridge else { return }
        do {
            try bridge.createList()
        } catch {
            show(String(describing: error))
        }
        remindersChanged()
    }

    /// Reminders changed (here, on the phone, in System Settings): look at the list again and tell perchd.
    /// `listChanged` false: only a look at the access, which tells perchd only if the state moved.
    private func remindersChanged(listChanged: Bool = true) {
        guard let bridge else { return }
        bridge.refresh()
        let moved = reminders != bridge.state
        if moved { reminders = bridge.state }
        guard listChanged || moved else { return }
        isBridge ? sendSnapshot() : registerBridge()
    }

    /// Offers this app as the bridge, once it can read the list. perchd answers whether it took it.
    private func registerBridge() {
        guard let bridge, bridge.state.isReady, let watcher, !isBridge, !registering else { return }
        registering = true
        let client = self.client
        actions.async { [weak self] in
            let taken = (try? client.send(Request(op: .bridgeRegister, watcher: watcher)))?.bridge == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.registering = false
                    // Reconnected meanwhile: offer the new connection instead.
                    guard self.watcher == watcher else { return self.registerBridge() }
                    guard taken else { return }
                    self.isBridge = true
                    self.sendSnapshot()
                }
            }
        }
    }

    /// A todo write perchd handed over: apply it to Reminders, then ack it before the next snapshot (an error at once).
    /// perchd only hands them to its bridge, so this app is one even if `bridge_register`'s answer is still on its way.
    private func applyTodo(_ operation: TodoOperation) {
        guard let bridge, let watcher else { return }
        isBridge = true
        do {
            acksDue.append(TodoAck(id: operation.id, externalID: try bridge.apply(operation)))
            sendSnapshot()
        } catch {
            send(Request(op: .todoAck, watcher: watcher, ack: TodoAck(id: operation.id, error: String(describing: error))),
                 on: bridgeActions)
        }
    }

    /// Reads the list and sends it to perchd, one snapshot at a time and in order; a change meanwhile reads again.
    /// Nothing while access is missing (perchd keeps what it had); an empty list once the list itself is gone.
    /// The acks of writes made before the read go out first.
    private func sendSnapshot() {
        guard isBridge, let bridge, let watcher else { return }
        guard bridge.state.isReady || bridge.state == .createList else {
            return flushAcks(watcher: watcher, error: "Perch.app made the change but lost access to Reminders; check `perch ls`")
        }
        guard !snapshotting else { snapshotAgain = true; return }
        snapshotting = true
        let acks = acksDue
        acksDue = []
        Task { @MainActor [weak self] in
            let read: Result<[Reminder], Error>
            do { read = .success(try await bridge.snapshot()) } catch { read = .failure(error) }
            guard let self else { return }
            // Reconnected (or no longer the bridge) while reading: the new connection sends its own.
            let current = self.isBridge && self.watcher == watcher
            switch read {
            case .success(let reminders):
                guard current else { break }
                // Acks first: perchd answers their writers with the snapshot after them.
                self.sendAcks(acks, watcher: watcher)
                self.send(Request(op: .todoSnapshot, watcher: watcher, reminders: reminders), on: self.bridgeActions)
            case .failure(let error):
                self.show("Couldn't read Reminders: \(error)")
                // No snapshot follows: the writers hear it from the acks.
                if current { self.sendAcks(acks, watcher: watcher, error: "Perch.app made the change but couldn't read Reminders: \(error)") }
            }
            self.snapshotting = false
            if self.snapshotAgain {
                self.snapshotAgain = false
                self.sendSnapshot()
            }
        }
    }

    /// Access went while writes were waiting for a snapshot: ack them now (they were made), there won't be one.
    private func flushAcks(watcher: String, error: String) {
        let acks = acksDue
        acksDue = []
        sendAcks(acks, watcher: watcher, error: error)
    }

    /// `error`: the writes were made, but no snapshot will show them.
    private func sendAcks(_ acks: [TodoAck], watcher: String, error: String? = nil) {
        for var ack in acks {
            ack.error = error
            send(Request(op: .todoAck, watcher: watcher, ack: ack), on: bridgeActions)
        }
    }

    /// A Todo tab change. The bridge writes it to Reminders and sends the snapshot at once (no waiting for EventKit's
    /// change notification); any other app asks perchd (`request`), which hands it to the bridge.
    private func write(_ request: Request, failed: (@MainActor () -> Void)? = nil, _ change: (RemindersBridge) throws -> Void) {
        guard isBridge, let bridge else { return send(request, failed: failed) }
        do {
            try change(bridge)
        } catch {
            failed?()
            show(String(describing: error))
        }
        sendSnapshot()
    }

    private func highlight(_ id: String) {
        highlighted.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + highlightDuration) { [weak self] in
            MainActor.assumeIsolated { _ = self?.highlighted.remove(id) }
        }
    }

    private func commitCompletion(_ id: String) {
        guard completions.removeValue(forKey: id) != nil, let item = state.items[id] else { return finishCompletion(id) }
        // Stays crossed out until the snapshot (or done event) removes the row; a failure brings it back.
        write(Request(op: .done, id: id), failed: { [weak self] in self?.finishCompletion(id) }) {
            try $0.update(item, completed: true)
        }
    }

    private func finishCompletion(_ id: String) {
        completions.removeValue(forKey: id)?.cancel()
        completing.remove(id)
    }

    /// Sends one request off the main thread (in order with the others on `queue`); failures go to `flash` (after
    /// `failed`, if given).
    public func send(_ request: Request, failed: (@MainActor () -> Void)? = nil) {
        send(request, on: actions, failed: failed)
    }

    private func send(_ request: Request, on queue: DispatchQueue, failed: (@MainActor () -> Void)? = nil) {
        let client = self.client
        queue.async { [weak self] in
            let failure: String?
            do {
                let response = try client.send(request)
                failure = response.ok ? nil : response.error ?? "perchd returned an error"
            } catch {
                failure = String(describing: error)
            }
            guard let failure else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    failed?()
                    self?.show(failure)
                }
            }
        }
    }

    /// Plays `answer` from now (nil: stops the one playing) and ends it after its duration.
    private func playAnswer(_ answer: Mascot.Answer?) {
        answerTimer?.invalidate()
        answerTimer = nil
        guard let answer else {
            if answerReaction != nil { answerReaction = nil }
            return
        }
        let playing = AnswerReaction(answer, start: Date())
        answerReaction = playing
        answerTimer = Timer.scheduledTimer(withTimeInterval: answer.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.answerReaction == playing { self?.answerReaction = nil }
            }
        }
    }

    /// Shows `new` (nil: none) and times it out.
    private func setBanner(_ new: Banner?) {
        if new == nil { banners.clear() }
        bannerTimer?.invalidate()
        bannerTimer = nil
        if banner != new { banner = new }
        guard let new else { return }
        let duration = Banner.duration(contentWidth: measureBanner(new))
        bannerTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.banners.dismiss(new.id) else { return }
                self.setBanner(nil)
            }
        }
    }

    private func show(_ message: String) {
        flash = message
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flash = nil }
        }
    }

    private func scheduleTick() {
        ticker?.invalidate()
        let current = Date()
        let nextMinute = (current.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60
        let fire = Date(timeIntervalSinceReferenceDate: nextMinute)
        let timer = Timer(fire: fire.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
