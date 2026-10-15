import Combine
import Foundation
import PerchClient
import PerchCore

/// What the notch shows, fed by `QueueConnection`, and what its rows and hotkeys do. Main thread only.
/// The Agents tab renders `panel` (agent sessions, and the requests Allow / Deny answer); the Todo tab renders `todos`.
/// The folded notch (mascot, running count, banner, sounds) only ever follows sessions.
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
    /// The todo popup while it is open (#43). The popup draws it and edits `title`; the rest goes through the methods.
    @Published public var editor: TodoEditor?
    /// Todos added while the panel was open, marked new for `highlightDuration`.
    @Published public private(set) var highlighted: Set<String> = []
    public var highlightDuration: TimeInterval = 1

    /// Whether the notch is expanded; the app sets it. Opening picks the tab (`PanelTab.opening`).
    public var expanded = false {
        didSet {
            guard expanded != oldValue, expanded else { return }
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
    /// Plays a chime. The app sets it, like `jump`.
    public var onChime: (ChimeSound) -> Void = { _ in }
    /// A banner's title and text, laid out, in points: how long it stays depends on whether it has to scroll.
    public var measureBanner: (Banner) -> Double = { _ in 0 }
    /// False while the notch is expanded: the list says it all, so banners are dropped, not saved for later.
    public var showsBanners = true {
        didSet { if !showsBanners { setBanner(nil) } }
    }

    private var chime = Chime()
    private var banners = BannerState()
    private var bannerTimer: Timer?
    private var connection: QueueConnection?
    private var client = PerchClient()
    private var ticker: Timer?
    private var flashTimer: Timer?
    private let actions = DispatchQueue(label: "dev.perch.app.actions")
    /// The last tab picked by hand; memory only, so a relaunch starts on Agents.
    private var pickedTab: PanelTab = .agents
    /// Pending completions that have not sent `done` yet; cancelling one is Undo.
    private var completions: [String: DispatchWorkItem] = [:]

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
    public var todos: TodoList { TodoList(items: state.items.values, hadAny: state.hadTodos) }

    public func connect(client: PerchClient = PerchClient()) {
        self.client = client
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
    }

    public func handle(_ update: QueueConnection.Update) {
        switch update {
        case .snapshot(let items, let all):
            state.replace(with: items)
            sessions = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            online = true
            offlineReason = nil
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
            }
            if let sound = chime.sound(from: before, to: after, now: Date()) { onChime(sound) }
            if showsBanners, banners.update(id: event.session.id, from: before, to: after) { setBanner(banners.current) }
            onSession?(event)
        case .offline(let reason):
            online = false
            offlineReason = reason
            sessions = [:]
            setBanner(nil)
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

    /// Allow / Deny (or any of the request's options). The waiting hook prints the decision.
    public func respond(_ item: Item, _ value: String) {
        send(Request(op: .respond, id: item.id, value: value))
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

    /// Clicking a todo's circle: crosses it out and sends `done` after `completionDelay`, unless it is clicked again
    /// (or Undo) first. The timer lives here, not in the view, so it still commits after the notch collapses;
    /// quitting meanwhile leaves the todo open.
    public func toggleCompletion(_ item: Item) {
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
        send(Request(op: .update, id: item.id, patch: Request.Patch(priority: priority)))
    }

    /// ⌥⇧Space (`fromPanel` false) or "+ Add a todo": the popup, empty and on Normal.
    public func openAdd(fromPanel: Bool) {
        editor = .add(fromPanel: fromPanel)
    }

    /// A double-click on a title, or Edit…: the popup, prefilled.
    public func openEdit(_ item: Item) {
        editor = .edit(item)
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
    /// the next one. Editing: `update` with the title and priority, then the popup closes. False (and nothing sent)
    /// while the title is blank.
    @discardableResult
    public func submitEditor() -> Bool {
        guard let editor, let title = editor.submittedTitle else { return false }
        switch editor.mode {
        case .add:
            send(Request(op: .add, item: Item(title: title, kind: .task, priority: editor.priority, source: "human")))
            self.editor = .add(fromPanel: editor.fromPanel)
        case .edit(let id):
            send(Request(op: .update, id: id, patch: Request.Patch(title: title, priority: editor.priority)))
            self.editor = nil
        }
        return true
    }

    /// Right-click → Delete: `rm` at once, no confirmation, no undo.
    public func delete(_ item: Item) {
        undoCompletion(item.id)
        send(Request(op: .remove, id: item.id))
    }

    private func highlight(_ id: String) {
        highlighted.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + highlightDuration) { [weak self] in
            MainActor.assumeIsolated { _ = self?.highlighted.remove(id) }
        }
    }

    private func commitCompletion(_ id: String) {
        guard completions.removeValue(forKey: id) != nil else { return }
        // Stays crossed out until the done event removes the row; a failure brings it back.
        send(Request(op: .done, id: id)) { [weak self] in self?.finishCompletion(id) }
    }

    private func finishCompletion(_ id: String) {
        completions.removeValue(forKey: id)?.cancel()
        completing.remove(id)
    }

    /// Sends one request off the main thread; failures go to `flash` (after `failed`, if given).
    public func send(_ request: Request, failed: (@MainActor () -> Void)? = nil) {
        let client = self.client
        actions.async { [weak self] in
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
