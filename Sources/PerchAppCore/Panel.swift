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
                let (x, y): (Date, Date)
                switch status {
                case .waiting: (x, y) = (a.statusAt, b.statusAt)
                case .running: (x, y) = (a.turnStartedAt, b.turnStartedAt)
                case .failed, .done, .idle: (x, y) = (b.statusAt, a.statusAt)
                }
                return x != y ? x < y : a.id < b.id
            })
        }
    }

    /// The request the notch can answer for this session: only while it needs you, only if allowlisted
    /// (anything else never became a request).
    public func request(for session: Session) -> Item? {
        session.status == .waiting ? requests[session.id] : nil
    }

    /// The notch pulses once when a session starts needing you, fails or finishes; never for running or idle.
    public static func pulses(from before: SessionStatus?, to after: SessionStatus?) -> Bool {
        guard let after, after != before else { return false }
        return after == .waiting || after == .failed || after == .done
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

    /// A Needs-you detail: the text (a full command, or the agent's question) and, when the notch cannot answer,
    /// the "Answer in the terminal…" line the hook appended.
    public struct NeedsYou: Equatable, Sendable {
        public var text: String
        public var hint: String?

        public init(text: String, hint: String?) {
            self.text = text
            self.hint = hint
        }
    }

    public static func needsYou(_ detail: String) -> NeedsYou {
        guard let range = detail.range(of: "\n" + HookAdapter.answerInTerminal, options: .backwards) else {
            return NeedsYou(text: detail, hint: nil)
        }
        return NeedsYou(text: String(detail[..<range.lowerBound]), hint: String(detail[detail.index(after: range.lowerBound)...]))
    }

    private static func elapsed(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "<1m" : RelativeTime.duration(seconds)
    }
}
