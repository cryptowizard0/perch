import Foundation
import Testing
@testable import PerchCore

@Suite struct HookAdapterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let link = "perch-terminal://ghostty?id=T1"

    func requests(_ input: HookInput) -> [Request] {
        HookAdapter.requests(for: input, agent: "claude-code", link: link, now: now)
    }

    @Test func decodesClaudeCodeStdin() throws {
        let json = #"""
        {"session_id":"abc","transcript_path":"/x.jsonl","cwd":"/Users/me/work/perch","permission_mode":"default",
         "hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}
        """#
        let input = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        #expect(input == HookInput(sessionID: "abc", event: "Notification", cwd: "/Users/me/work/perch",
                                   notificationType: "permission_prompt", message: "Claude needs your permission to use Bash"))
    }

    @Test func promptStartsTheTurn() {
        let r = requests(HookInput(sessionID: "abc", event: "UserPromptSubmit", cwd: "/Users/me/work/perch",
                                   prompt: "\n  Fix the **flaky** test\nin CI"))
        #expect(r.map(\.op) == [.sessionReport])
        #expect(r[0].report == SessionReport(id: "abc", kind: .prompt, at: now, source: "claude-code", title: "perch",
                                             cwd: "/Users/me/work/perch", link: link, prompt: "Fix the flaky test"))
    }

    @Test func permissionPromptBecomesWaiting() throws {
        let r = requests(HookInput(sessionID: "abc", event: "Notification", cwd: "/w/perch",
                                   notificationType: "permission_prompt", message: "Claude needs your permission to use Bash"))
        #expect(r.map(\.op) == [.sessionReport])
        let report = try #require(r[0].report)
        #expect(report.kind == .waiting && report.detail == "Claude needs your permission to use Bash" && report.keepDetail == true)
        #expect(report.source == "claude-code" && report.title == "perch" && report.link == link)
    }

    @Test func otherNotificationsAreIgnored() {
        for type in ["idle_prompt", "auth_success", "agent_completed"] {
            #expect(requests(HookInput(sessionID: "abc", event: "Notification", notificationType: type, message: "x")).isEmpty)
        }
        #expect(!requests(HookInput(sessionID: "abc", event: "Notification", notificationType: "elicitation_dialog")).isEmpty)
        #expect(!requests(HookInput(sessionID: "abc", event: "Notification", notificationType: "agent_needs_input")).isEmpty)
    }

    @Test func stopFinishesTheTurn() throws {
        let message = "## Done\n\n**All 12 tests pass** and the PR is pushed.\nMore detail…"
        let r = requests(HookInput(sessionID: "abc", event: "Stop", cwd: "/w/perch", lastAssistantMessage: message))
        #expect(r.map(\.op) == [.sessionReport])
        #expect(r[0].report?.kind == .stop && r[0].report?.lastMessage == "Done" && r[0].report?.at == now)
    }

    @Test func summaries() {
        #expect(HookAdapter.summary(nil) == "finished")
        #expect(HookAdapter.summary("\n\n  ") == "finished")
        #expect(HookAdapter.summary("- `swift test` passes") == "swift test passes")
        let long = String(repeating: "x", count: 200)
        #expect(HookAdapter.summary(long).count == 140)
        #expect(HookAdapter.summary(long).hasSuffix("…"))
    }

    @Test func endingEvents() {
        // Interrupt: Codex, Esc on a running turn (no Stop follows).
        let kinds: [String: SessionReport.Kind] = ["StopFailure": .failure, "SessionEnd": .end, "Interrupt": .interrupt]
        for (event, kind) in kinds {
            let r = requests(HookInput(sessionID: "abc", event: event))
            #expect(r.map(\.op) == [.sessionReport])
            #expect(r[0].report?.kind == kind)
        }
        #expect(requests(HookInput(sessionID: "abc", event: "PreToolUse")).isEmpty)
    }

    @Test func projectNames() {
        #expect(HookAdapter.projectName("/Users/me/work/perch/") == "perch")
        #expect(HookAdapter.projectName(nil) == "agent")
        #expect(HookAdapter.projectName("/") == "/")
    }
}

@Suite struct TerminalLinkTests {
    @Test func roundTrip() throws {
        let link = TerminalLink(app: "ghostty", terminalID: "ABC-123", cwd: "/Users/me/my project", bundleID: "com.mitchellh.ghostty")
        #expect(link.string == "perch-terminal://ghostty?id=ABC-123&cwd=/Users/me/my%20project&bundle=com.mitchellh.ghostty")
        #expect(TerminalLink(string: link.string) == link)
        #expect(TerminalLink(string: "perch-terminal://ghostty") == TerminalLink(app: "ghostty"))
        #expect(TerminalLink(string: "https://example.com") == nil)
        #expect(TerminalLink(string: "/tmp") == nil)
    }

    /// Codex's desktop app runs its agent inside ChatGPT.app and passes hooks no terminal or bundle variables:
    /// the outermost app in the agent's path is what to bring forward.
    @Test func hostAppFromTheAgentsPath() {
        #expect(TerminalLink.hostApp(executable: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
                == "/Applications/ChatGPT.app")
        #expect(TerminalLink.hostApp(executable: "/Users/me/Applications/Foo Bar.app/Contents/MacOS/agent") == "/Users/me/Applications/Foo Bar.app")
        #expect(TerminalLink.hostApp(executable: "/Users/me/.local/share/claude/versions/2.1.258") == nil)
        #expect(TerminalLink.hostApp(executable: "/opt/apps/notreally.application/bin/x") == nil)
        #expect(TerminalLink.hostApp(executable: "codex") == nil)
    }
}

@Suite struct PermissionAdapterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func input(_ tool: String, _ fields: [String: JSONValue]) -> HookInput {
        HookInput(sessionID: "s1", event: "PermissionRequest", cwd: "/w/perch", toolName: tool, toolInput: fields)
    }

    func plan(_ tool: String, _ fields: [String: JSONValue]) -> HookAdapter.PermissionPlan {
        HookAdapter.permission(for: input(tool, fields), agent: "claude-code", link: "L", allowlist: .defaults, now: now, home: "/Users/me")
    }

    @Test func decodesToolInput() throws {
        let json = #"{"session_id":"s1","hook_event_name":"PermissionRequest","cwd":"/w","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests","timeout":120000,"run_in_background":false},"permission_suggestions":[{"type":"addRules"}]}"#
        let decoded = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        #expect(decoded.toolName == "Bash")
        #expect(decoded.toolStrings == ["command": "npm test", "description": "Run tests"])
        #expect(decoded.toolInput?["timeout"] == .number(120000))
    }

    @Test func allowlistedAsksTheNotch() throws {
        guard case .ask(let request) = plan("Bash", ["command": .string("npm test"), "description": .string("Run tests")]) else {
            Issue.record("expected ask"); return
        }
        #expect(request.title == "npm test")
        #expect(request.kind == .request && request.status == .waiting)
        #expect(request.options == ["allow", "deny"])
        #expect(request.expiresAt == now.addingTimeInterval(20))
        #expect(request.key == nil)
        #expect(request.link == "L")
        #expect(request.meta == ["session_id": "s1", "tool": "Bash", "project": "perch", "cwd": "/w/perch", "description": "Run tests"])
    }

    @Test func everythingElseGoesStraightToTheTerminal() throws {
        guard case .terminal(let reason) = plan("Bash", ["command": .string("rm -rf build/")]) else { Issue.record("expected terminal"); return }
        #expect(reason == "`rm -rf` is not on the allowlist")
        guard case .terminal = plan("Read", ["file_path": .string("/Users/me/.ssh/id_rsa")]) else { Issue.record("ssh"); return }
        guard case .terminal = plan("Write", ["file_path": .string("/w/perch/a.swift")]) else { Issue.record("write"); return }
    }

    @Test func aTimedOutRequestSaysAnswerInTheTerminal() {
        let pytest = input("Bash", ["command": .string("pytest")])
        guard case .ask(let request) = plan("Bash", ["command": .string("pytest")]) else { Issue.record("ask"); return }
        let report = HookAdapter.terminalReport(after: request, input: pytest, agent: "claude-code", link: "L", now: now)
        #expect(report.kind == .waiting && report.detail == "pytest\nAnswer in the terminal" && report.id == "s1")
    }

    @Test func decisionJSONForClaudeCode() {
        #expect(HookAdapter.decision(agent: "claude-code", answer: "allow")
                == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        #expect(HookAdapter.decision(agent: "claude-code", answer: "deny")
                == #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Denied by the user from the Perch notch."},"hookEventName":"PermissionRequest"}}"#)
        #expect(HookAdapter.decision(agent: "claude-code", answer: "maybe") == nil)
    }

    /// Codex documents the same `hookSpecificOutput.decision.behavior` shape (message optional, deny only here).
    @Test func decisionJSONForCodex() {
        for answer in ["allow", "deny", "maybe"] {
            #expect(HookAdapter.decision(agent: "codex", answer: answer) == HookAdapter.decision(agent: "claude-code", answer: answer))
        }
    }

    @Test func decodesCodexStdin() throws {
        let json = #"{"session_id":"019a","turn_id":"t3","hook_event_name":"PermissionRequest","cwd":"/w/perch","transcript_path":null,"permission_mode":"default","model":"gpt-6","tool_name":"Bash","tool_input":{"command":"cargo test","description":null}}"#
        let decoded = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        #expect(decoded.sessionID == "019a" && decoded.event == "PermissionRequest")
        #expect(decoded.toolStrings == ["command": "cargo test"])
        let plan = HookAdapter.permission(for: decoded, agent: "codex", link: nil, allowlist: .defaults, now: now, home: "/Users/me")
        guard case .ask(let request) = plan else { Issue.record("expected ask"); return }
        #expect(request.title == "cargo test" && request.source == "codex")
        #expect(request.meta?["description"] == nil)
    }

    /// Codex's own tools are not on the allowlist: a patch or an MCP call always goes to the terminal, shown in full.
    @Test func codexPatchGoesToTheTerminal() {
        let patch = "*** Begin Patch\n*** Update File: a.swift\n+x\n*** End Patch"
        let input = HookInput(sessionID: "019a", event: "PermissionRequest", cwd: "/w/perch", toolName: "apply_patch",
                              toolInput: ["command": .string(patch)])
        let plan = HookAdapter.permission(for: input, agent: "codex", link: nil, allowlist: .defaults, now: now, home: "/Users/me")
        guard case .terminal = plan else { Issue.record("terminal"); return }
        #expect(HookAdapter.permissionReport(for: input, plan: plan, agent: "codex", link: nil, now: now).detail
                == "apply_patch \(patch)\nAnswer in the terminal: apply_patch is not on the allowlist")
    }

    @Test func latePermissionNotificationKeepsTheCommandText() {
        let notification = HookInput(sessionID: "s1", event: "Notification", notificationType: "permission_prompt", message: "needs permission")
        // The session report keeps a recorded command (keep_detail); a question replaces it.
        let late = HookAdapter.requests(for: notification, agent: "claude-code", link: nil, now: now)
        #expect(late.map(\.op) == [.sessionReport] && late[0].report?.keepDetail == true)
        let elicitation = HookInput(sessionID: "s1", event: "Notification", notificationType: "elicitation_dialog", message: "pick one")
        let question = HookAdapter.requests(for: elicitation, agent: "claude-code", link: nil, now: now)
        #expect(question.map(\.op) == [.sessionReport] && question[0].report?.keepDetail == false)
    }

    @Test func toolRunResumesTheSession() {
        for event in ["PostToolUse", "PostToolUseFailure"] {
            let r = HookAdapter.requests(for: HookInput(sessionID: "s1", event: event, toolName: "Bash"), agent: "claude-code", link: nil, now: now)
            #expect(r.map(\.op) == [.sessionReport] && r[0].report?.kind == .resume)
        }
    }

    @Test func stopFailureRecordsTheErrorType() throws {
        let json = #"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"StopFailure","error":"rate_limit","error_details":"429 Too Many Requests","last_assistant_message":"API Error: Rate limit reached"}"#
        let input = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        let r = HookAdapter.requests(for: input, agent: "claude-code", link: nil, now: now)
        #expect(r[0].report?.kind == .failure && r[0].report?.error == "rate_limit")
        // An error that is not a string still decodes.
        let odd = try JSONDecoder().decode(HookInput.self, from: Data(#"{"session_id":"s1","hook_event_name":"StopFailure","error":{"x":1}}"#.utf8))
        #expect(odd.errorType == "unknown")
    }

    @Test func permissionReportsTheCommandAndWhereToAnswer() {
        let npm = input("Bash", ["command": .string("npm test")])
        let asked = HookAdapter.permission(for: npm, agent: "claude-code", link: "L", allowlist: .defaults, now: now, home: "/Users/me")
        let ask = HookAdapter.permissionReport(for: npm, plan: asked, agent: "claude-code", link: "L", now: now)
        #expect(ask.kind == .waiting && ask.detail == "npm test" && ask.link == "L" && ask.title == "perch")

        let rm = input("Bash", ["command": .string("rm -rf build/")])
        let terminal = HookAdapter.permission(for: rm, agent: "claude-code", link: "L", allowlist: .defaults, now: now, home: "/Users/me")
        #expect(HookAdapter.permissionReport(for: rm, plan: terminal, agent: "claude-code", link: "L", now: now).detail
                == "rm -rf build/\nAnswer in the terminal: `rm -rf` is not on the allowlist")
    }
}

/// Hermes Agent shell hooks: the same adapter, Hermes's own event names and payload (`extra` carries the details).
@Suite struct HermesAdapterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func input(_ json: String) throws -> HookInput {
        try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
    }

    func requests(_ input: HookInput, link: String? = "L") -> [Request] {
        HookAdapter.requests(for: input, agent: "hermes", link: link, now: now)
    }

    @Test func decodesHermesStdin() throws {
        let decoded = try input(#"""
        {"hook_event_name":"pre_approval_request","tool_name":null,"tool_input":null,"session_id":"","cwd":"/w/perch",
         "extra":{"command":"rm -rf build/","description":"recursive delete","pattern_key":"rm_rf","pattern_keys":["rm_rf"],
                  "session_key":"default","surface":"cli","turn_id":"t1","tool_call_id":"c1"}}
        """#)
        #expect(decoded.event == "pre_approval_request" && decoded.sessionID == "")
        #expect(decoded.extra == HookInput.Extra(command: "rm -rf build/", description: "recursive delete",
                                                 sessionKey: "default", surface: "cli", toolCallID: "c1"))
    }

    @Test func aTurnStartsAndClearsTheLastNotice() throws {
        let r = requests(try input(#"{"hook_event_name":"pre_llm_call","session_id":"s1","cwd":"/w/perch","extra":{"user_message":"hi","conversation_history":[{"role":"user","content":"hi"}],"is_first_turn":true,"platform":"cli"}}"#))
        #expect(r.map(\.op) == [.sessionStart, .done])
        #expect(r[0].session == Session(id: "s1", source: "hermes", title: "perch", link: "L", startedAt: now))
        #expect(r[1].key == "hermes:s1:done")
    }

    /// Gateway turns happen in a chat app: named after it, and never linked to whatever terminal started the gateway.
    @Test func gatewayTurnsAreNamedAfterThePlatform() throws {
        let r = requests(try input(#"{"hook_event_name":"pre_llm_call","session_id":"s2","cwd":"/","extra":{"platform":"telegram"}}"#))
        #expect(r[0].session?.title == "Telegram")
        #expect(r[0].session?.link == nil)
        let post = requests(try input(#"{"hook_event_name":"post_llm_call","session_id":"s2","cwd":"/","extra":{"platform":"telegram","assistant_response":"done"}}"#))
        #expect(post.first?.item?.title == "Telegram · done")
        #expect(post.first?.item?.link == nil)
    }

    @Test func aFinishedTurnLeavesANoticeAndEndsTheSession() throws {
        let post = requests(try input(#"{"hook_event_name":"post_llm_call","session_id":"s1","cwd":"/w/perch","extra":{"assistant_response":"**Deployed** v2 to staging.\nDetails…","platform":"cli"}}"#))
        #expect(post.map(\.op) == [.add])
        let notice = try #require(post.first?.item)
        #expect(notice.title == "perch · Deployed v2 to staging.")
        #expect(notice.kind == .notice && notice.source == "hermes" && notice.key == "hermes:s1:done")
        #expect(notice.expiresAt == now.addingTimeInterval(600))

        let end = requests(try input(#"{"hook_event_name":"on_session_end","session_id":"s1","cwd":"/w/perch","extra":{"completed":true,"interrupted":false}}"#))
        #expect(end.map(\.op) == [.sessionEnd])
        #expect(end[0].id == "s1" && end[0].at == now)
    }

    @Test func anApprovalInTheCLIWaitsInTheTerminal() throws {
        let r = requests(try input(#"{"hook_event_name":"pre_approval_request","session_id":"","cwd":"/w/perch","extra":{"command":"rm -rf build/","description":"recursive delete","session_key":"default","surface":"cli","tool_call_id":"c1"}}"#))
        let item = try #require(r.first?.item)
        #expect(r.map(\.op) == [.add])
        #expect(item.title == "perch · rm -rf build/")
        #expect(item.kind == .task && item.status == .waiting && item.source == "hermes")
        #expect(item.key == "hermes:default:c1")
        // If Hermes dies mid-approval no response comes: fade well after Hermes's own timeouts (60 s CLI, 300 s gateway).
        #expect(item.expiresAt == now.addingTimeInterval(15 * 60))
        #expect(item.link == "L")
        #expect(item.meta == ["tool": "terminal", "terminal_reason": "recursive delete", "session_key": "default", "cwd": "/w/perch"])
    }

    /// Gateway approvals are answered in the chat app; there is no terminal to jump to.
    @Test func anApprovalFromTheGatewayWaitsInTheChat() throws {
        let r = requests(try input(#"{"hook_event_name":"pre_approval_request","session_id":"","cwd":"/","extra":{"command":"sudo reboot","description":"sudo","session_key":"agent:main:telegram:dm:42","surface":"gateway"}}"#))
        let item = try #require(r.first?.item)
        #expect(item.title == "Telegram · sudo reboot")
        #expect(item.key == "hermes:agent:main:telegram:dm:42")  // no tool_call_id: one per chat
        #expect(item.meta?["answer_in"] == "Telegram")
        #expect(item.link == nil)
    }

    @Test func theResponseClearsIt() throws {
        for choice in ["once", "deny", "timeout"] {
            let r = requests(try input(#"{"hook_event_name":"post_approval_response","session_id":"","cwd":"/","extra":{"command":"rm -rf build/","session_key":"default","surface":"cli","choice":"\#(choice)","tool_call_id":"c1"}}"#))
            #expect(r.map(\.op) == [.done] && r.first?.key == "hermes:default:c1")
        }
    }

    /// Delegated children run whole turns of their own: they are Hermes working, not Hermes waiting for you.
    @Test func subagentsAreIgnored() throws {
        for event in ["pre_llm_call", "post_llm_call", "on_session_end"] {
            #expect(requests(try input(#"{"hook_event_name":"\#(event)","session_id":"child","cwd":"/w","extra":{"platform":"subagent","assistant_response":"x"}}"#)).isEmpty)
        }
    }

    /// The background skill / memory review is a fork that shares the parent's session id: it must not replace
    /// the real turn's notice or start a Live Activity.
    @Test func theBackgroundReviewIsIgnored() throws {
        let prompt = "Review the conversation above…\n\nYou can only call memory and skill management tools. Other tools will be denied at runtime — do not attempt them."
        let encoded = String(decoding: try JSONEncoder().encode(prompt), as: UTF8.self)
        for event in ["pre_llm_call", "post_llm_call"] {
            #expect(requests(try input(#"{"hook_event_name":"\#(event)","session_id":"s1","cwd":"/w","extra":{"platform":"cli","user_message":\#(encoded),"assistant_response":"Saved a skill."}}"#)).isEmpty)
        }
    }

    @Test func otherHermesEventsAreIgnored() throws {
        for event in ["pre_tool_call", "post_tool_call", "on_session_start", "transform_llm_output"] {
            #expect(requests(try input(#"{"hook_event_name":"\#(event)","session_id":"s1","cwd":"/"}"#)).isEmpty)
        }
    }
}

/// The Running row shows the prompt's first line: Claude Code wraps shell-mode (`!cmd`) and slash-command prompts
/// in tags, which read as the command itself.
@Suite struct PromptLineTests {
    @Test func shellModeReadsAsTheCommand() {
        #expect(HookAdapter.promptLine("<bash-input>scripts/install.sh</bash-input><bash-stdout>[1/1] Planning build\nok</bash-stdout><bash-stderr></bash-stderr>")
                == "$ scripts/install.sh")
        #expect(HookAdapter.promptLine("<bash-input>git status\ngit log</bash-input>") == "$ git status")
        #expect(HookAdapter.promptLine("<bash-input>ls `pwd`/**</bash-input>") == "$ ls `pwd`/**")
        let long = HookAdapter.promptLine("<bash-input>" + String(repeating: "x", count: 300) + "</bash-input>")
        #expect(long?.count == HookAdapter.summaryLength && long?.hasSuffix("…") == true)
    }

    @Test func slashCommandsReadAsTyped() {
        #expect(HookAdapter.promptLine("<command-message>implement</command-message>\n<command-name>/implement</command-name>\n<command-args>#17</command-args>")
                == "/implement #17")
        #expect(HookAdapter.promptLine("<command-name>/clear</command-name>\n<command-message>clear</command-message>\n<command-args></command-args>")
                == "/clear")
        #expect(HookAdapter.promptLine("<command-name>review</command-name><command-args>  since main </command-args>") == "/review since main")
    }

    @Test func plainPromptsAreUnchanged() {
        #expect(HookAdapter.promptLine("\n  Fix the **flaky** test\nin CI") == "Fix the flaky test")
        #expect(HookAdapter.promptLine("Why does <div> collapse?") == "Why does <div> collapse?")
        #expect(HookAdapter.promptLine("  \n ") == nil)
    }
}
