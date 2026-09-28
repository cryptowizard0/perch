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
}
