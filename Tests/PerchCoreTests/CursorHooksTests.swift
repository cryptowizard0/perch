import Foundation
import PerchCore
import Testing

/// What Cursor sends ~/.cursor/hooks.json commands (#98). Payloads follow Cursor's hooks docs (3.24); the
/// `sessionEnd` one is a real payload from this Mac's Cursor hooks log (an empty Agent pane closing).
@Suite struct CursorHooksTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let link = "perch-terminal://cursor?cwd=/w/perch"

    func decode(_ event: String, _ fields: String = "") throws -> HookInput {
        let json = #"{"conversation_id":"c-1","generation_id":"g-1","model":"grok-4.7-high","hook_event_name":"\#(event)","cursor_version":"3.24.18","workspace_roots":["/w/perch"],"user_email":"me@example.com","transcript_path":null\#(fields)}"#
        return try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
    }

    func reports(_ event: String, _ fields: String = "") throws -> [SessionReport] {
        HookAdapter.requests(for: try decode(event, fields), agent: "cursor", link: link, now: now).compactMap(\.report)
    }

    @Test func decodesThePayload() throws {
        let input = try decode("beforeSubmitPrompt", #","prompt":"fix the build","attachments":[]"#)
        #expect(input.sessionID == "c-1")
        #expect(input.cwd == "/w/perch")
        #expect(input.prompt == "fix the build")
        #expect(HookAdapter.startsTurn(input))

        // A tool event's own cwd wins over the workspace.
        #expect(try decode("afterShellExecution", #","cwd":"/w/perch/sub""#).cwd == "/w/perch/sub")
        // An empty window: no workspace, no directory.
        let empty = try JSONDecoder().decode(HookInput.self, from: Data(#"{"conversation_id":"c-2","hook_event_name":"stop","workspace_roots":[],"status":"completed"}"#.utf8))
        #expect(empty.cwd == nil && empty.status == "completed")
    }

    @Test func realSessionEndPayload() throws {
        let json = #"{"conversation_id":"empty-state-draft","generation_id":"","model":"grok-4.7-high","model_id":"grok-4.7","model_params":[{"id":"context","value":"256k"}],"reason":"window_close","duration_ms":252445,"is_background_agent":false,"final_status":"none","session_id":"empty-state-draft","hook_event_name":"sessionEnd","cursor_version":"3.24.18","workspace_roots":[],"user_email":"me@example.com","transcript_path":null}"#
        let input = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        let r = HookAdapter.requests(for: input, agent: "cursor", link: nil, now: now).compactMap(\.report)
        #expect(r.map(\.kind) == [.end] && r.first?.id == "empty-state-draft")
    }

    @Test func aTurn() throws {
        let prompt = try reports("beforeSubmitPrompt", #","prompt":"**fix** the build\nplease","attachments":[]"#)
        #expect(prompt.map(\.kind) == [.prompt])
        #expect(prompt.first?.prompt == "fix the build" && prompt.first?.source == "cursor")
        #expect(prompt.first?.title == "perch" && prompt.first?.cwd == "/w/perch" && prompt.first?.link == link)

        let reply = try reports("afterAgentResponse", ###","text":"## Fixed\nThe build passes now.""###)
        #expect(reply.map(\.kind) == [.reply] && reply.first?.lastMessage == "Fixed")
        #expect(try reports("afterAgentResponse", #","text":"  \n""#).isEmpty)

        // The stop carries no reply: perchd uses the one it was told.
        let stop = try reports("stop", #","status":"completed","loop_count":0"#)
        #expect(stop.map(\.kind) == [.stop] && stop.first?.lastMessage == nil)
        #expect(try reports("stop", #","loop_count":0"#).map(\.kind) == [.stop])
    }

    @Test func abortedAndFailedTurns() throws {
        #expect(try reports("stop", #","status":"aborted","loop_count":0"#).map(\.kind) == [.interrupt])
        let failed = try reports("stop", #","status":"error","loop_count":0"#)
        #expect(failed.map(\.kind) == [.failure] && failed.first?.error == "error")
    }

    @Test func sessionEndRemoves() throws {
        for reason in ["completed", "aborted", "error", "window_close", "user_close"] {
            #expect(try reports("sessionEnd", #","session_id":"c-1","reason":"\#(reason)","duration_ms":1"#).map(\.kind) == [.end])
        }
    }

    @Test func unhandledEvents() throws {
        for event in ["sessionStart", "preToolUse", "beforeShellExecution", "afterShellExecution", "beforeMCPExecution",
                      "afterFileEdit", "afterAgentThought", "subagentStart", "subagentStop", "preCompact"] {
            #expect(try reports(event).isEmpty, "\(event)")
        }
    }

    // MARK: - Cursor running Claude Code's hooks

    func table(_ entries: [(Int32, Int32, String)]) -> [Int32: ProcessEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.0, ProcessEntry(pid: $0.0, ppid: $0.1, name: $0.2, startedAt: now)) })
    }

    @Test func cursorCallingClaudeCodesHookIsForeign() {
        let cursor = ["CURSOR_VERSION": "3.24.18", "CLAUDE_PROJECT_DIR": "/w/perch"]
        // Cursor's Third-Party Imports run ~/.claude/settings.json: perch ← sh ← Cursor Helper (Plugin) ← Cursor.
        let ide = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "Cursor Helper (Plugin)"), (700, 1, "Cursor")])
        #expect(HookAdapter.isForeign(agent: "claude-code", environment: cursor, processes: ide, from: 900))
        #expect(HookAdapter.isForeign(agent: "codex", environment: cursor, processes: ide, from: 900))
        #expect(!HookAdapter.isForeign(agent: "cursor", environment: cursor, processes: ide, from: 900))

        // Claude Code started in Cursor's terminal is still Claude Code, whatever it inherited.
        let terminal = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "claude"), (700, 600, "zsh"),
                              (600, 500, "Cursor Helper"), (500, 1, "Cursor")])
        #expect(!HookAdapter.isForeign(agent: "claude-code", environment: cursor, processes: terminal, from: 900))
        // Without Cursor's variable nothing changes.
        #expect(!HookAdapter.isForeign(agent: "claude-code", environment: [:], processes: ide, from: 900))
    }

    @Test func grokRunningCursorsHooksIsForeign() {
        #expect(HookAdapter.isForeign(agent: "cursor", environment: ["GROK_HOOK_EVENT": "Stop"]))
    }

    // MARK: - Process

    @Test func findsTheCursorApp() {
        let ide = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "Cursor Helper (Plugin)"), (700, 1, "Cursor")])
        #expect(AgentProcess.find(agent: "cursor", from: 900, in: ide)?.pid == 700)
    }

    @Test func findsTheCursorCLINotGrok() {
        let cli = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "cursor-agent"), (700, 1, "zsh")])
        #expect(AgentProcess.find(agent: "cursor", from: 900, in: cli)?.pid == 800)

        var node = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "node"), (700, 1, "zsh")])
        node[800]?.script = "/Users/me/.local/share/cursor-agent/versions/2026.11.01-abc/index.js"
        #expect(AgentProcess.find(agent: "cursor", from: 900, in: node)?.pid == 800)

        // `agent` is Grok's name; a node running something else is not Cursor.
        let grok = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "agent"), (700, 1, "zsh")])
        #expect(AgentProcess.find(agent: "cursor", from: 900, in: grok) == nil)
        var other = node
        other[800]?.script = "/usr/local/lib/node_modules/@other/cli/index.js"
        #expect(AgentProcess.find(agent: "cursor", from: 900, in: other) == nil)
        // The CLI inside Cursor's terminal belongs to the CLI, not the app.
        let nested = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "cursor-agent"), (700, 600, "zsh"),
                            (600, 1, "Cursor")])
        #expect(AgentProcess.find(agent: "cursor", from: 900, in: nested)?.pid == 800)
    }
}
