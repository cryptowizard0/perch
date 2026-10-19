import Foundation
import PerchCore
import Testing

/// `perch hook` finds the agent process it runs under by walking up the parent chain.
@Suite struct AgentProcessTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func table(_ entries: [(Int32, Int32, String)]) -> [Int32: ProcessEntry] {
        Dictionary(uniqueKeysWithValues: entries.enumerated().map { i, e in
            (e.0, ProcessEntry(pid: e.0, ppid: e.1, name: e.2, startedAt: t0.addingTimeInterval(TimeInterval(i))))
        })
    }

    @Test func findsClaudeAboveTheHookShell() {
        // perch ← sh -c ← claude ← zsh ← Ghostty ← launchd
        let processes = table([(900, 899, "perch"), (899, 500, "sh"), (500, 400, "claude"), (400, 300, "zsh"),
                               (300, 1, "ghostty"), (1, 0, "launchd")])
        let found = AgentProcess.find(agent: "claude-code", from: 900, in: processes)
        #expect(found?.pid == 500 && found?.name == "claude")
        #expect(found?.startedAt == t0.addingTimeInterval(2))
    }

    @Test func findsCodexNotTheNodeLauncher() {
        // npm's `codex` is a node script that spawns the native binary; hooks run under the binary.
        let processes = table([(900, 800, "perch"), (800, 700, "codex"), (700, 600, "node"), (600, 1, "zsh")])
        #expect(AgentProcess.find(agent: "codex", from: 900, in: processes)?.pid == 800)
    }

    @Test func findsGrokUnderEitherName() {
        // grok runs hooks itself (no leader by default): perch ← sh ← grok ← zsh. `agent` is the same binary.
        for name in ["grok", "agent"] {
            let processes = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, name), (700, 1, "zsh")])
            #expect(AgentProcess.find(agent: "grok", from: 900, in: processes)?.pid == 800)
        }
        let claude = table([(900, 800, "perch"), (800, 700, "claude"), (700, 1, "zsh")])
        #expect(AgentProcess.find(agent: "grok", from: 900, in: claude) == nil)
    }

    @Test func theClosestAgentWins() {
        // A claude started from inside another claude's shell: the hook belongs to the inner one.
        let processes = table([(900, 800, "perch"), (800, 700, "claude"), (700, 600, "zsh"), (600, 1, "claude")])
        #expect(AgentProcess.find(agent: "claude-code", from: 900, in: processes)?.pid == 800)
    }

    @Test func nothingWhenNoAgentIsAbove() {
        let processes = table([(900, 899, "perch"), (899, 1, "zsh"), (1, 0, "launchd")])
        #expect(AgentProcess.find(agent: "claude-code", from: 900, in: processes) == nil)
        // Another agent's process does not count.
        let codex = table([(900, 800, "perch"), (800, 1, "codex")])
        #expect(AgentProcess.find(agent: "claude-code", from: 900, in: codex) == nil)
        // Agents without a known process name (Hermes) never get one.
        let hermes = table([(900, 800, "perch"), (800, 1, "hermes")])
        #expect(AgentProcess.find(agent: "hermes", from: 900, in: hermes) == nil)
    }

    @Test func aBrokenChainEnds() {
        // Parent missing from the table (exited meanwhile), and a loop.
        #expect(AgentProcess.find(agent: "claude-code", from: 900, in: table([(900, 42, "perch")])) == nil)
        #expect(AgentProcess.find(agent: "claude-code", from: 900, in: table([(900, 800, "perch"), (800, 900, "sh")])) == nil)
        #expect(AgentProcess.find(agent: "claude-code", from: 7, in: [:]) == nil)
    }

    /// dsh runs as `node …/bin/dsh <profile>`; its plugin spawns `perch hook dsh` directly and says `process.pid`.
    func dshTable(_ entries: [(Int32, Int32, String, String?)]) -> [Int32: ProcessEntry] {
        Dictionary(uniqueKeysWithValues: entries.enumerated().map { i, e in
            (e.0, ProcessEntry(pid: e.0, ppid: e.1, name: e.2, startedAt: t0.addingTimeInterval(TimeInterval(i)), script: e.3))
        })
    }

    @Test func recognisesDsh() {
        let node = { (script: String?) in ProcessEntry(pid: 1, ppid: 0, name: "node", startedAt: t0, script: script) }
        #expect(AgentProcess.isDsh(node("/Users/me/.nvm/versions/node/v22.23.3/bin/dsh")))
        #expect(AgentProcess.isDsh(node("/opt/homebrew/lib/node_modules/@deepseek-ai/dsh/lib/bin.js")))
        #expect(AgentProcess.isDsh(ProcessEntry(pid: 1, ppid: 0, name: "dsh", startedAt: t0)))
        #expect(!AgentProcess.isDsh(node("/w/server.js")))
        #expect(!AgentProcess.isDsh(node(nil)))
        // dsh's own subprocess runner is node too, but not dsh.
        #expect(!AgentProcess.isDsh(node("/x/node_modules/@deepseek-ai/dsh-subprocess-local/lib/runner.js")))
        #expect(!AgentProcess.isDsh(ProcessEntry(pid: 1, ppid: 0, name: "zsh", startedAt: t0, script: "dsh")))
    }

    @Test func theDshPidIsTrustedOnlyAsTheParent() {
        let parent = ProcessEntry(pid: 60402, ppid: 1, name: "node", startedAt: t0, script: "/n/bin/dsh")
        #expect(AgentProcess.dsh(claimed: 60402, parent: parent) == parent)
        // Anything else (a shell in between, a made-up pid, none at all): no pid, the 24-hour rule applies.
        #expect(AgentProcess.dsh(claimed: 60401, parent: parent) == nil)
        #expect(AgentProcess.dsh(claimed: nil, parent: parent) == nil)
        #expect(AgentProcess.dsh(claimed: 60402, parent: nil) == nil)
    }

    @Test func dshsHooksBridgeIsNotClaudeCode() {
        // dsh's Claude Code / Codex hooks bridge runs ~/.claude/settings.json's commands through its own runner:
        // perch ← sh ← node runner.js ← node dsh ← zsh.
        let bridge = dshTable([(900, 899, "perch", "hook"), (899, 800, "sh", "-c"), (800, 700, "node", "/x/@deepseek-ai/dsh-subprocess-local/lib/runner.js"),
                               (700, 600, "node", "/n/bin/dsh"), (600, 1, "zsh", nil)])
        #expect(AgentProcess.insideDsh(agent: "claude-code", from: 900, in: bridge))
        #expect(AgentProcess.insideDsh(agent: "codex", from: 900, in: bridge))
        // dsh started from Claude Code's shell: the bridge's call still is not Claude Code's.
        let underClaude = dshTable([(900, 800, "perch", "hook"), (800, 700, "node", "/n/bin/dsh"), (700, 600, "zsh", nil), (600, 1, "claude", nil)])
        #expect(AgentProcess.insideDsh(agent: "claude-code", from: 900, in: underClaude))
        // Claude Code started from dsh's bash tool: its own hooks are its own.
        let claudeInside = dshTable([(900, 899, "perch", "hook"), (899, 800, "sh", "-c"), (800, 700, "claude", nil), (700, 600, "node", "/n/bin/dsh")])
        #expect(!AgentProcess.insideDsh(agent: "claude-code", from: 900, in: claudeInside))
        // No dsh anywhere.
        let plain = dshTable([(900, 899, "perch", "hook"), (899, 800, "sh", "-c"), (800, 1, "claude", nil)])
        #expect(!AgentProcess.insideDsh(agent: "claude-code", from: 900, in: plain))
        #expect(!AgentProcess.insideDsh(agent: "claude-code", from: 900, in: [:]))
    }
}
