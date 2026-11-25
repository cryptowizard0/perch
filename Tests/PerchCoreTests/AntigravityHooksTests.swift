import Foundation
import PerchCore
import Testing

/// What Google Antigravity sends ~/.gemini/config/hooks.json commands (Desktop App, IDE, and `agy` CLI).
@Suite struct AntigravityHooksTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let link = "perch-terminal://antigravity?cwd=/w/perch&bundle=com.google.antigravity"

    func decode(_ event: String, _ fields: String = "") throws -> HookInput {
        let json = #"{"conversationId":"ag-1","workspacePaths":["/w/perch"],"transcriptPath":"/tmp/transcript.jsonl","artifactDirectoryPath":"/tmp/artifacts","modelName":"auto","lastUserInput":"Fix the failing unit test","hookEventName":"\#(event)","cwd":"/w/perch"\#(fields)}"#
        return try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
    }

    func reports(_ event: String, _ fields: String = "") throws -> [SessionReport] {
        HookAdapter.requests(for: try decode(event, fields), agent: "antigravity", link: link, now: now).compactMap(\.report)
    }

    @Test func decodesCamelCasePayload() throws {
        let input = try decode("PreInvocation", #","invocationNum":3,"initialNumSteps":10"#)
        #expect(input.sessionID == "ag-1")
        #expect(input.event == "PreInvocation")
        #expect(input.cwd == "/w/perch")
        #expect(input.transcriptPath == "/tmp/transcript.jsonl")
        #expect(input.lastUserInput == "Fix the failing unit test")
        #expect(input.invocationNum == 3)
        #expect(HookAdapter.startsTurn(input))

        // Falls back to workspacePaths[0] when cwd is missing.
        let noCwd = try JSONDecoder().decode(HookInput.self, from: Data(
            #"{"conversationId":"ag-2","workspacePaths":["/w/fallback"],"hookEventName":"Stop","terminationReason":"NO_TOOL_CALL","fullyIdle":true}"#.utf8
        ))
        #expect(noCwd.cwd == "/w/fallback")
        #expect(noCwd.terminationReason == "NO_TOOL_CALL")
        #expect(noCwd.fullyIdle == true)
    }

    @Test func preInvocationAndStopNormalTurn() throws {
        let prompt = try reports("PreInvocation", #","invocationNum":1"#)
        #expect(prompt.map(\.kind) == [.prompt])
        #expect(prompt.first?.source == "antigravity")
        #expect(prompt.first?.title == "perch")
        #expect(prompt.first?.cwd == "/w/perch")
        #expect(prompt.first?.link == link)
        #expect(prompt.first?.prompt == "Fix the failing unit test")
        #expect(prompt.first?.continueTurn == true)

        // Wrapped <USER_REQUEST> prompts are unwrapped cleanly.
        let wrapped = try JSONDecoder().decode(HookInput.self, from: Data(
            #"{"conversationId":"ag-1","hookEventName":"PreInvocation","cwd":"/w/perch","lastUserInput":"<USER_REQUEST>\n**Add** Antigravity support\nmore lines\n</USER_REQUEST>\n<ADDITIONAL_METADATA>time</ADDITIONAL_METADATA>"}"#.utf8
        ))
        let wrappedReport = HookAdapter.requests(for: wrapped, agent: "antigravity", link: link, now: now).compactMap(\.report)
        #expect(wrappedReport.first?.prompt == "Add Antigravity support")

        // Normal Stop with reply populated from transcript.
        var stopInput = try decode("Stop", #","executionNum":1,"terminationReason":"NO_TOOL_CALL","error":"","fullyIdle":true"#)
        stopInput.lastAssistantMessage = "## Done\nAll tests pass."
        let stop = HookAdapter.requests(for: stopInput, agent: "antigravity", link: link, now: now).compactMap(\.report)
        #expect(stop.map(\.kind) == [.stop])
        #expect(stop.first?.lastMessage == "Done")

        // Other normal completion reasons.
        for reason in ["TERMINAL_STEP_TYPE", "INJECTED_RESPONSE", "model_stop"] {
            #expect(try reports("Stop", #","terminationReason":"\#(reason)","error":"" "#).map(\.kind) == [.stop], "\(reason)")
        }
    }

    @Test func canceledAndFailedStops() throws {
        for reason in ["USER_CANCELED", "USER_CANCELLED", "aborted", "TERMINAL_CUSTOM_HOOK"] {
            #expect(try reports("Stop", #","terminationReason":"\#(reason)","error":"" "#).map(\.kind) == [.interrupt], "\(reason)")
        }

        let err = try reports("Stop", #","terminationReason":"ERROR","error":"429 rate limit""#)
        #expect(err.map(\.kind) == [.failure] && err.first?.error == "429 rate limit")

        let maxInv = try reports("Stop", #","terminationReason":"MAX_INVOCATIONS","error":"" "#)
        #expect(maxInv.map(\.kind) == [.failure] && maxInv.first?.error == "max_invocations")

        let budget = try reports("Stop", #","terminationReason":"MAX_TOKEN_BUDGET_EXCEEDED","error":"" "#)
        #expect(budget.map(\.kind) == [.failure] && budget.first?.error == "max_token_budget_exceeded")

        // A custom hook termination with an error message is a failure.
        let blockedErr = try reports("Stop", #","terminationReason":"TERMINAL_CUSTOM_HOOK","error":"blocked by policy""#)
        #expect(blockedErr.map(\.kind) == [.failure] && blockedErr.first?.error == "blocked by policy")
    }

    @Test func unhandledEventsAndStdoutContract() throws {
        for event in ["SessionStart", "PreToolUse", "PostToolUse", "PostInvocation"] {
            #expect(try reports(event).isEmpty, "\(event)")
        }
        #expect(HookAdapter.antigravityOutput(for: "Stop") == #"{"decision":"stop"}"#)
        #expect(HookAdapter.antigravityOutput(for: "PreInvocation") == "{}")
        #expect(HookAdapter.antigravityOutput(for: nil) == "{}")
    }

    @Test func transcriptLastReplyReadsCurrentTurnOnly() {
        let log = """
        {"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"first question"}
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","content":"first answer"}
        {"step_index":2,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"second question"}
        {"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","thinking":"hmm","tool_calls":[{"name":"read_file"}]}
        {"step_index":4,"source":"MODEL","type":"GENERIC","content":"tool output"}
        {"step_index":5,"source":"MODEL","type":"PLANNER_RESPONSE","content":"## Fixed\\nAll tests pass."}
        """
        #expect(AntigravityTranscript.lastReply(tail: log) == "## Fixed\nAll tests pass.")

        // Truncated first line in tail slice is skipped safely.
        let truncated = """
        truncated-json-prefix"}
        {"step_index":5,"source":"MODEL","type":"PLANNER_RESPONSE","content":"Recovered reply"}
        """
        #expect(AntigravityTranscript.lastReply(tail: truncated) == "Recovered reply")

        // Stops at USER_INPUT so an earlier turn's reply is never reused.
        let noReplyYet = """
        {"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","content":"old reply"}
        {"step_index":2,"source":"USER_EXPLICIT","type":"USER_INPUT","content":"new question"}
        {"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","thinking":"thinking","tool_calls":[]}
        """
        #expect(AntigravityTranscript.lastReply(tail: noReplyYet) == nil)
    }

    // MARK: - Process and foreign hooks

    func table(_ entries: [(Int32, Int32, String)]) -> [Int32: ProcessEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.0, ProcessEntry(pid: $0.0, ppid: $0.1, name: $0.2, startedAt: now)) })
    }

    @Test func findsCLIAppOrLanguageServerFallback() {
        // agy CLI in a terminal.
        let cli = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "agy"), (700, 1, "zsh")])
        #expect(AgentProcess.find(agent: "antigravity", from: 900, in: cli)?.pid == 800)

        // Antigravity Desktop App: prefers Antigravity over intermediate language_server.
        let app = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "language_server"), (700, 1, "Antigravity")])
        #expect(AgentProcess.find(agent: "antigravity", from: 900, in: app)?.pid == 700)

        // Detached language_server (reparented to launchd): falls back to language_server.
        let detached = table([(900, 899, "perch"), (899, 800, "sh"), (800, 1, "language_server")])
        #expect(AgentProcess.find(agent: "antigravity", from: 900, in: detached)?.pid == 800)

        // agy started inside Antigravity's terminal binds to agy, not the app.
        let nested = table([(900, 899, "perch"), (899, 800, "sh"), (800, 700, "agy"), (700, 600, "zsh"), (600, 1, "Antigravity")])
        #expect(AgentProcess.find(agent: "antigravity", from: 900, in: nested)?.pid == 800)
    }

    @Test func grokRunningAntigravityHooksIsForeign() {
        #expect(HookAdapter.isForeign(agent: "antigravity", environment: ["GROK_HOOK_EVENT": "Stop"]))
        #expect(!HookAdapter.isForeign(agent: "antigravity", environment: ["ANTIGRAVITY_AGENT": "1"]))
    }
}
