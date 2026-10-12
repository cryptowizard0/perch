import Foundation
import PerchCore

/// `~/.perch/agents.json`: which agents the user connected to Perch. Read and written by the CLI and the app
/// (a user config file like allowlist.json; only perchd touches SQLite). An agent with no entry is "not asked".
public struct AgentsFile: Codable, Equatable, Sendable {
    public var agents: [String: AgentRecord]

    public init(agents: [String: AgentRecord] = [:]) {
        self.agents = agents
    }

    public subscript(agent: String) -> AgentRecord? {
        get { agents[agent] }
        set { agents[agent] = newValue }
    }

    /// Missing file = nobody asked yet. A broken file is an error: it holds the user's choices, so never overwrite it.
    public static func load(from url: URL) throws -> AgentsFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentsFile() }
        do {
            return try PerchJSON.decoder.decode(AgentsFile.self, from: Data(contentsOf: url))
        } catch {
            throw SetupError("\(url.path) is not valid; fix or delete it, nothing was changed")
        }
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = PerchJSON.encoder
        encoder.outputFormatting.insert(.prettyPrinted)
        try (encoder.encode(self) + Data("\n".utf8)).write(to: url, options: .atomic)
    }

    /// Records that the user connected the agent with hooks in `config`. `hooksChanged`: Perch's hooks were
    /// (re)written with different content, which Codex must trust again.
    public mutating func turnOn(_ agent: String, config: String, hooksChanged: Bool, at now: Date) {
        var record = agents[agent] ?? AgentRecord(status: .on)
        record.status = .on
        record.config = config
        if hooksChanged { record.hooksWrittenAt = now }
        agents[agent] = record
    }

    /// Records that an event proved the agent runs Perch's current hooks (Codex after `/hooks`).
    public mutating func markTrusted(_ agent: String, at time: Date) {
        guard var record = agents[agent] else { return }
        record.trustedAt = time
        agents[agent] = record
    }

    /// Records that the user disconnected the agent: Perch stops suggesting it and does not repair its hooks.
    public mutating func turnOff(_ agent: String, config: String) {
        var record = agents[agent] ?? AgentRecord(status: .off)
        record.status = .off
        record.config = config
        agents[agent] = record
    }
}

public struct AgentRecord: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case on, off }

    public var status: Status
    /// The hook file Perch actually wrote.
    public var config: String?
    /// When Perch's hooks were last written with new content.
    public var hooksWrittenAt: Date?
    /// Codex: when Perch saw an event proving the current hooks are trusted.
    public var trustedAt: Date?

    public init(status: Status, config: String? = nil, hooksWrittenAt: Date? = nil, trustedAt: Date? = nil) {
        self.status = status
        self.config = config
        self.hooksWrittenAt = hooksWrittenAt
        self.trustedAt = trustedAt
    }

    enum CodingKeys: String, CodingKey {
        case status, config
        case hooksWrittenAt = "hooks_written_at"
        case trustedAt = "trusted_at"
    }
}
