import Foundation

/// Where an agent session stands. Wire values; the notch says "Needs you" for `waiting`.
public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case waiting, failed, running, done, idle

    /// Most urgent first: waiting > failed > running > done > idle.
    public var priority: Int { Self.allCases.firstIndex(of: self)! }
}

/// One agent session (a Claude Code / Codex `session_id`), stored by perchd in the `sessions` table.
/// Hook events move it between the five `SessionStatus` states (see `SessionReport`); `session_end` or
/// `perch session rm` removes it. JSON is snake_case like `Item`.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    /// The agent's own session id.
    public var id: String
    public var source: String
    /// Short label, usually the project directory name.
    public var title: String
    public var cwd: String?
    /// Where to jump back to (see `TerminalLink`).
    public var link: String?
    public var status: SessionStatus
    /// First line of this turn's prompt (shown while running).
    public var prompt: String?
    /// First line of the agent's last reply (shown when done / idle).
    public var lastMessage: String?
    /// While waiting: the full command, the question, where to answer.
    public var detail: String?
    /// When failed: the error type (`rate_limit`, …).
    public var error: String?
    /// The agent process and its start time, for liveness checks (a reused pid has another start time).
    public var pid: Int32?
    public var pidStartedAt: Date?
    /// Claude Code's session log: perchd watches its end while the session runs or waits (`ClaudeTranscript`).
    public var transcriptPath: String?
    /// First seen.
    public var startedAt: Date
    /// When this turn started (the last prompt).
    public var turnStartedAt: Date
    /// When the session entered its current status. Done → idle keeps it: an idle row still says when it finished.
    public var statusAt: Date
    /// When the last event was observed; older events are ignored (hooks run async and can arrive out of order).
    public var updatedAt: Date

    /// A running turn that started at `startedAt` (what `session_start` reports).
    public init(id: String, source: String = "unknown", title: String? = nil, link: String? = nil, startedAt: Date = Date(),
                status: SessionStatus = .running, cwd: String? = nil) {
        self.id = id
        self.source = source
        self.title = title ?? id
        self.cwd = cwd
        self.link = link
        self.status = status
        self.startedAt = startedAt
        turnStartedAt = startedAt
        statusAt = startedAt
        updatedAt = startedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, source, title, cwd, link, status, prompt, detail, error, pid
        case lastMessage = "last_message"
        case pidStartedAt = "pid_started_at"
        case transcriptPath = "transcript_path"
        case startedAt = "started_at"
        case turnStartedAt = "turn_started_at"
        case statusAt = "status_at"
        case updatedAt = "updated_at"
    }

    /// Lenient like `Item`: only `id` is required; missing times default to `started_at`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        status = try c.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .running
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        pidStartedAt = try c.decodeIfPresent(Date.self, forKey: .pidStartedAt)
        transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        turnStartedAt = try c.decodeIfPresent(Date.self, forKey: .turnStartedAt) ?? startedAt
        statusAt = try c.decodeIfPresent(Date.self, forKey: .statusAt) ?? startedAt
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
    }
}

/// What a hook adapter tells perchd about a session (op `session_report`). Agent-neutral: the adapter maps its
/// agent's hook events onto these kinds, perchd runs the state machine. A report for an unknown session creates it.
///
/// | kind | effect |
/// | --- | --- |
/// | prompt | → running; `prompt`, turn start; clears detail / error |
/// | waiting | → waiting with `detail`; with `keep_detail`, a detail already recorded while waiting stays |
/// | resume | waiting → running (a tool ran, or the notch answered); resolves the session's request |
/// | stop | → done with `last_message`; resolves the request |
/// | failure | → failed with `error`; resolves the request |
/// | interrupt | → idle; resolves the request |
/// | end | removes the session; resolves the request |
public struct SessionReport: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case prompt, waiting, resume, stop, failure, interrupt, end
    }

    public var id: String
    public var kind: Kind
    /// When the hook observed the event.
    public var at: Date
    public var source: String?
    public var title: String?
    public var cwd: String?
    public var link: String?
    public var prompt: String?
    public var detail: String?
    public var keepDetail: Bool?
    public var lastMessage: String?
    public var error: String?
    public var pid: Int32?
    public var pidStartedAt: Date?
    public var transcriptPath: String?

    public init(id: String, kind: Kind, at: Date, source: String? = nil, title: String? = nil, cwd: String? = nil,
                link: String? = nil, prompt: String? = nil, detail: String? = nil, keepDetail: Bool? = nil,
                lastMessage: String? = nil, error: String? = nil, pid: Int32? = nil, pidStartedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.at = at
        self.source = source
        self.title = title
        self.cwd = cwd
        self.link = link
        self.prompt = prompt
        self.detail = detail
        self.keepDetail = keepDetail
        self.lastMessage = lastMessage
        self.error = error
        self.pid = pid
        self.pidStartedAt = pidStartedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, at, source, title, cwd, link, prompt, detail, error, pid
        case keepDetail = "keep_detail"
        case lastMessage = "last_message"
        case pidStartedAt = "pid_started_at"
        case transcriptPath = "transcript_path"
    }
}

public enum SessionEventType: String, Codable, Sendable {
    /// A turn started (kept for older clients; `session.updated` follows).
    case started = "session.started"
    /// The session was created or changed.
    case updated = "session.updated"
    /// The session was removed.
    case ended = "session.ended"
}

/// Pushed to `watch` clients as `{"ok":true,"session_event":{…}}`, next to item events.
public struct SessionEvent: Codable, Equatable, Sendable {
    public var type: SessionEventType
    public var session: Session
    public var at: Date

    public init(type: SessionEventType, session: Session, at: Date = Date()) {
        self.type = type
        self.session = session
        self.at = at
    }
}
