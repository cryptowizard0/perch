import Foundation

/// One row of the process table: enough to walk up the parent chain and to tell a reused pid apart.
public struct ProcessEntry: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    /// The name it was started as: argv[0]'s last path component, so `~/.local/bin/claude` (a symlink to
    /// `…/versions/2.1.x`, which is what the kernel calls it) is `claude`.
    public var name: String
    public var startedAt: Date

    public init(pid: Int32, ppid: Int32, name: String, startedAt: Date) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.startedAt = startedAt
    }
}

/// Which process a hook runs under. Agents start hooks through a shell, so the agent is an ancestor of
/// `perch hook`; perchd watches that pid and removes the session when the process is gone (#16).
public enum AgentProcess {
    /// Process names per agent. Hermes (Python) has none: its sessions fall back to the 24-hour rule.
    public static let names: [String: Set<String>] = [
        "claude-code": ["claude"],
        "codex": ["codex"],
    ]

    /// The closest ancestor of `pid` (itself included) named like `agent`'s process, or nil.
    public static func find(agent: String, from pid: Int32, in table: [Int32: ProcessEntry]) -> ProcessEntry? {
        guard let names = names[agent] else { return nil }
        var seen: Set<Int32> = []
        var current = table[pid]
        while let entry = current, seen.insert(entry.pid).inserted {
            if names.contains(entry.name) { return entry }
            guard entry.ppid > 0, entry.ppid != entry.pid else { return nil }
            current = table[entry.ppid]
        }
        return nil
    }
}
