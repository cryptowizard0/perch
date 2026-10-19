import Foundation

/// One row of the process table: enough to walk up the parent chain and to tell a reused pid apart.
public struct ProcessEntry: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32
    /// The name it was started as: argv[0]'s last path component, so `~/.local/bin/claude` (a symlink to
    /// `…/versions/2.1.x`, which is what the kernel calls it) is `claude`.
    public var name: String
    public var startedAt: Date
    /// argv[1]: for an interpreter (`node`), the script it runs (dsh is `node …/bin/dsh <profile>`).
    public var script: String?

    public init(pid: Int32, ppid: Int32, name: String, startedAt: Date, script: String? = nil) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.startedAt = startedAt
        self.script = script
    }
}

/// Which process a hook runs under. Agents start hooks through a shell, so the agent is an ancestor of
/// `perch hook`; perchd watches that pid and removes the session when the process is gone (#16).
public enum AgentProcess {
    /// Process names per agent. Hermes (Python) has none: its sessions fall back to the 24-hour rule.
    public static let names: [String: Set<String>] = [
        "claude-code": ["claude"],
        "codex": ["codex"],
        // ~/.grok/bin/grok and ~/.grok/bin/agent both link to the versioned binary (grok-1.0.x-macos-aarch64).
        "grok": ["grok", "agent"],
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

    // MARK: - dsh

    /// dsh runs as `node`, so the argv[0] rule cannot find it. Its plugin runs inside that process and spawns
    /// `perch hook dsh` directly (no shell), saying `process.pid`: trusted only when that pid is perch's parent.
    public static func dsh(claimed pid: Int32?, parent: ProcessEntry?) -> ProcessEntry? {
        guard let pid, let parent, parent.pid == pid else { return nil }
        return parent
    }

    /// A dsh process: `node` running dsh's `bin/dsh` (npm's link) or its package's script, or a packaged `dsh` binary.
    public static func isDsh(_ entry: ProcessEntry) -> Bool {
        if entry.name == "dsh" { return true }
        guard entry.name.hasPrefix("node"), let script = entry.script else { return false }
        return URL(fileURLWithPath: script).lastPathComponent == "dsh" || script.contains("/@deepseek-ai/dsh/")
    }

    /// Whether `agent`'s hook runs under dsh rather than under `agent` itself: walking up from `pid`, a dsh process
    /// comes before any of `agent`'s own (dsh's Claude Code / Codex hooks bridge runs those agents' hook files).
    /// A `claude` started from dsh's shell is still Claude Code.
    public static func insideDsh(agent: String, from pid: Int32, in table: [Int32: ProcessEntry]) -> Bool {
        let own = names[agent] ?? []
        var seen: Set<Int32> = []
        var current = table[pid]
        while let entry = current, seen.insert(entry.pid).inserted {
            if own.contains(entry.name) { return false }
            if isDsh(entry) { return true }
            guard entry.ppid > 0, entry.ppid != entry.pid else { return false }
            current = table[entry.ppid]
        }
        return false
    }
}
