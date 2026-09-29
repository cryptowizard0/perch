import Foundation
import PerchCore

/// What the notch shows (v0.2): agent sessions, one row each, grouped by state.
/// Collapsed: the colour of the most urgent session and how many are running. Expanded: the groups.
/// Hermes sessions stay out until M9 gives them a lifecycle of their own.
public struct Panel: Equatable, Sendable {
    public struct Group: Equatable, Sendable {
        public var status: SessionStatus
        public var sessions: [Session]
        public var title: String { status.label }
    }

    public static let hiddenSources: Set<String> = ["hermes"]

    /// The visible sessions, in no particular order.
    public let sessions: [Session]
    /// Open requests that belong to a session (`meta.session_id`): what Allow / Deny answer.
    private let requests: [String: Item]

    public init(sessions: some Sequence<Session>, requests: some Sequence<Item> = [Item]()) {
        self.sessions = sessions.filter { !Self.hiddenSources.contains($0.source) }
        var bySession: [String: Item] = [:]
        for item in requests where item.kind == .request && (item.status == .waiting || item.status == .open) {
            guard let id = item.meta?["session_id"] else { continue }
            if let other = bySession[id], other.updatedAt > item.updatedAt { continue }
            bySession[id] = item
        }
        self.requests = bySession
    }

    /// The dot's colour: the most urgent state (Needs you > Failed > Running > Done > Idle); nil with no sessions.
    public var signal: SessionStatus? {
        sessions.map(\.status).min { $0.priority < $1.priority }
    }

    public var runningCount: Int {
        sessions.filter { $0.status == .running }.count
    }

    /// Non-empty groups, most urgent first. Needs you: longest waiting first; Running: by turn start;
    /// Failed / Done / Idle: most recent first.
    public var groups: [Group] {
        SessionStatus.allCases.compactMap { status in
            let members = sessions.filter { $0.status == status }
            guard !members.isEmpty else { return nil }
            return Group(status: status, sessions: members.sorted { a, b in
                let (first, second): (Date, Date)
                switch status {
                case .waiting: (first, second) = (a.statusAt, b.statusAt)
                case .running: (first, second) = (a.turnStartedAt, b.turnStartedAt)
                case .failed, .done, .idle: (first, second) = (b.statusAt, a.statusAt)
                }
                return first != second ? first < second : a.id < b.id
            })
        }
    }

    /// The request the notch can answer for this session: only while it needs you, only if allowlisted
    /// (anything else never became a request).
    public func request(for session: Session) -> Item? {
        session.status == .waiting ? requests[session.id] : nil
    }

    /// What ⌥⇧O jumps to: the session that has waited longest.
    public var headSession: Session? {
        groups.first { $0.status == .waiting }?.sessions.first
    }

    /// What ⌥⇧A / ⌥⇧D answer: the first request the panel shows, in panel order. A request no visible session
    /// owns is never answered by a hotkey, since nobody can read it first.
    public var headRequest: Item? {
        groups.first { $0.status == .waiting }?.sessions.lazy.compactMap(request(for:)).first
    }

    /// The notch pulses once when a panel session starts needing you, fails or finishes; never for running or idle.
    public static func pulses(from before: Session?, to after: Session?) -> Bool {
        guard let after, !hiddenSources.contains(after.source), after.status != before?.status else { return false }
        return after.status == .waiting || after.status == .failed || after.status == .done
    }
}

extension SessionStatus {
    /// The English label the notch uses.
    public var label: String {
        switch self {
        case .waiting: return "Needs you"
        case .failed: return "Failed"
        case .running: return "Running"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }
}

/// How one session row reads: a time on the right, a second line under the project name.
public enum SessionRow {
    /// Running: this turn so far. Needs you: how long it has waited. Otherwise: how long ago it got there.
    /// Minute resolution, like the notch's tick.
    public static func time(_ s: Session, now: Date) -> String {
        switch s.status {
        case .running: return elapsed(now.timeIntervalSince(s.turnStartedAt))
        case .waiting: return elapsed(now.timeIntervalSince(s.statusAt))
        case .failed, .done, .idle:
            let seconds = now.timeIntervalSince(s.statusAt)
            return seconds < 60 ? "just now" : "\(RelativeTime.duration(seconds)) ago"
        }
    }

    /// Running: the prompt's first line. Needs you: the full text (the command, never truncated; where to answer).
    /// Failed: the error type. Done / Idle: the last reply's first line.
    public static func detail(_ s: Session) -> String? {
        switch s.status {
        case .running: return s.prompt
        case .waiting: return s.detail ?? HookAdapter.waitingForAnswer
        case .failed: return s.error
        case .done, .idle: return s.lastMessage
        }
    }

    /// A Needs-you row's text: a full command or the agent's question, and, when the notch cannot answer,
    /// the "Answer in the terminal…" line the hook appended.
    public struct NeedsYou: Equatable, Sendable {
        public var text: String
        public var hint: String?
        /// A command (monospaced), not a question.
        public var isCommand: Bool

        public init(text: String, hint: String?, isCommand: Bool) {
            self.text = text
            self.hint = hint
            self.isCommand = isCommand
        }
    }

    /// With a request, its own text: Allow / Deny answer exactly what the row shows, even if the session's detail
    /// has moved on (a question arrived meanwhile).
    public static func needsYou(_ s: Session, request: Item?) -> NeedsYou {
        if let request { return NeedsYou(text: request.title, hint: nil, isCommand: true) }
        let detail = s.detail ?? HookAdapter.waitingForAnswer
        guard let range = detail.range(of: "\n" + HookAdapter.answerInTerminal, options: .backwards) else {
            return NeedsYou(text: detail, hint: nil, isCommand: false)
        }
        return NeedsYou(text: String(detail[..<range.lowerBound]), hint: String(detail[detail.index(after: range.lowerBound)...]),
                        isCommand: true)
    }

    private static func elapsed(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "<1m" : RelativeTime.duration(seconds)
    }
}

/// How tall the expanded list wants to be, estimated from its content (no text measurement outside the view).
/// Past `maxListHeight` the list scrolls, so nothing is ever cut.
public enum PanelLayout {
    public static let messageHeight: CGFloat = 44
    public static let headerHeight: CGFloat = 24
    public static let rowHeight: CGFloat = 46
    public static let lineHeight: CGFloat = 16
    public static let buttonsHeight: CGFloat = 28
    public static let maxListHeight: CGFloat = 460
    /// Monospaced characters per line at the panel's width.
    static let lineLength = 52

    public static func listHeight(_ panel: Panel) -> CGFloat {
        guard !panel.sessions.isEmpty else { return messageHeight }
        let height = panel.groups.reduce(CGFloat(0)) { total, group in
            total + headerHeight + group.sessions.reduce(CGFloat(0)) { sum, s in
                guard s.status == .waiting else { return sum + rowHeight }
                let request = panel.request(for: s)
                let row = SessionRow.needsYou(s, request: request)
                let lines = row.text.split(separator: "\n", omittingEmptySubsequences: false)
                    .reduce(0) { $0 + $1.count / lineLength + 1 } + (row.hint.map { $0.count / lineLength + 1 } ?? 0)
                return sum + rowHeight + CGFloat(min(lines, 12) - 1) * lineHeight + (request == nil ? 0 : buttonsHeight)
            }
        }
        return min(height, maxListHeight)
    }
}
