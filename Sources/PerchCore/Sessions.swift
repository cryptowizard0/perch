import Foundation

/// An agent turn in progress: shown as Live Activity ("2 agents · 4m"). Not a queue item and never stored —
/// perchd keeps these in memory. Started when the human submits a prompt, ended when the agent stops.
public struct Session: Codable, Equatable, Identifiable, Sendable {
    /// The agent's own session id (Claude Code / Codex `session_id`).
    public var id: String
    public var source: String
    /// Short label, usually the project directory name.
    public var title: String
    /// Where to jump back to (see `TerminalLink`).
    public var link: String?
    /// When this turn started.
    public var startedAt: Date

    public init(id: String, source: String = "unknown", title: String? = nil, link: String? = nil, startedAt: Date = Date()) {
        self.id = id
        self.source = source
        self.title = title ?? id
        self.link = link
        self.startedAt = startedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, source, title, link
        case startedAt = "started_at"
    }

    /// Lenient like `Item`: only `id` is required.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        link = try c.decodeIfPresent(String.self, forKey: .link)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
    }
}

public enum SessionEventType: String, Codable, Sendable {
    case started = "session.started"
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
