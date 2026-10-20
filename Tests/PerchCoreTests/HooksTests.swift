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
                                   notificationType: "permission_prompt", message: "Claude needs your permission to use Bash",
                                   transcriptPath: "/x.jsonl"))
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

    @Test func grokCallingAnotherAgentsHookIsForeign() {
        let grok = ["GROK_HOOK_EVENT": "stop"]
        #expect(HookAdapter.isForeign(agent: "claude-code", environment: grok))
        #expect(HookAdapter.isForeign(agent: "codex", environment: grok))
        #expect(!HookAdapter.isForeign(agent: "grok", environment: grok))
        #expect(!HookAdapter.isForeign(agent: "claude-code", environment: ["GROK_SESSION_ID": "x"]))
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

    /// Claude Code's reports carry the transcript (perchd reads its end for interruptions no hook reports, #8).
    /// Codex has its own Interrupt hook and another log format, so its reports do not.
    @Test func claudeCodeReportsCarryTheTranscript() throws {
        let json = #"{"session_id":"abc","transcript_path":"/Users/me/.claude/projects/p/abc.jsonl","cwd":"/w/perch","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#
        let input = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        #expect(input.transcriptPath == "/Users/me/.claude/projects/p/abc.jsonl")
        #expect(requests(input).first?.report?.transcriptPath == "/Users/me/.claude/projects/p/abc.jsonl")
        let codex = HookAdapter.requests(for: input, agent: "codex", link: nil, now: now)
        #expect(codex.first?.report?.transcriptPath == nil)
        // Codex sends null.
        let null = try JSONDecoder().decode(HookInput.self, from: Data(#"{"session_id":"x","hook_event_name":"Stop","transcript_path":null}"#.utf8))
        #expect(null.transcriptPath == nil)
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

    /// The focused Ghostty terminal belongs to the agent when their directories are one tree, symlinks resolved: dsh
    /// reports the realpath (`/private/tmp/…`) where Ghostty's shell says `/tmp/…`.
    @Test func sameTreeResolvesSymlinks() {
        #expect(TerminalLink.sameTree("/Users/me/p", "/Users/me/p"))
        #expect(TerminalLink.sameTree("/Users/me/p/sub", "/Users/me/p"))
        #expect(TerminalLink.sameTree("/Users/me/p", "/Users/me/p/sub"))
        #expect(!TerminalLink.sameTree("/Users/me/p", "/Users/me/other"))
        #expect(!TerminalLink.sameTree("/Users/me/p", "/Users/me/p2"))
        // Symlinks resolve only for paths that exist (a live shell's directory always does): make one under /tmp.
        let dir = "/tmp/perch-same-tree-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: dir + "/x", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(TerminalLink.sameTree("/private" + dir, dir))
        #expect(TerminalLink.sameTree(dir + "/x", "/private" + dir))
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

    /// What Claude Code 2.1 injects when a background command finishes (#32): no line, so the human's prompt stays.
    static let taskNotification = """
        <task-notification>
        <task-id>bz7bon2oc</task-id>
        <tool-use-id>toolu_01AbC</tool-use-id>
        <output-file>/private/tmp/claude-501/-Users-me-work-perch/tasks/bz7bon2oc.output</output-file>
        <status>completed</status>
        <summary>Background command "swift test" completed (exit code 0)</summary>
        </task-notification>
        """

    @Test func backgroundTaskNotificationsHaveNoLine() throws {
        #expect(HookAdapter.promptLine(Self.taskNotification) == nil)
        #expect(HookAdapter.promptLine("\n" + Self.taskNotification) == nil)
        // Mentioning the tag is still a prompt.
        #expect(HookAdapter.promptLine("Why does <task-notification> show up?") == "Why does <task-notification> show up?")

        let payload = try JSONSerialization.data(withJSONObject: [
            "session_id": "s1", "cwd": "/w/perch", "hook_event_name": "UserPromptSubmit", "prompt": Self.taskNotification,
        ])
        let input = try JSONDecoder().decode(HookInput.self, from: payload)
        let report = try #require(HookAdapter.requests(for: input, agent: "claude-code", link: nil, now: Date()).first?.report)
        #expect(report.kind == .prompt && report.prompt == nil && report.keepPrompt == true)
        // Nobody typed: the terminal in focus right now is not this session's.
        #expect(!HookAdapter.startsTurn(input))
        let typed = try JSONDecoder().decode(HookInput.self, from: Data(#"{"session_id":"s1","hook_event_name":"UserPromptSubmit","prompt":"go"}"#.utf8))
        #expect(HookAdapter.startsTurn(typed))
        #expect(HookAdapter.requests(for: typed, agent: "claude-code", link: nil, now: Date()).first?.report?.keepPrompt == nil)
    }
}

/// Grok Build's hook stdin, as grok 1.0.50 sent it (captured 2026-10-12, trimmed to what Perch reads plus a little).
@Suite struct GrokAdapterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let link = "perch-terminal://ghostty?id=T1"

    func decode(_ event: String, _ fields: String) throws -> HookInput {
        let json = #"{"hookEventName":"x","sessionId":"01a1","session_id":"01a1","hook_event_name":"\#(event)","cwd":"/w/perch","workspaceRoot":"/w/perch","timestamp":"2026-10-12T08:09:41.979803+00:00","permissionMode":"default","permission_mode":"default"\#(fields)}"#
        return try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
    }

    func reports(_ event: String, _ fields: String = "") throws -> [SessionReport] {
        let requests = HookAdapter.requests(for: try decode(event, fields), agent: "grok", link: link, now: now)
        #expect(requests.allSatisfy { $0.op == .sessionReport })
        return requests.compactMap(\.report)
    }

    @Test func decodesCamelCaseFields() throws {
        let stop = try decode("Stop", #","transcriptPath":"/g/updates.jsonl","transcript_path":"/g/updates.jsonl","promptId":"p1","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"done","backgroundTasks":[],"sessionCrons":[]"#)
        #expect(stop.sessionID == "01a1" && stop.event == "Stop" && stop.promptID == "p1" && stop.reason == "end_turn")
        #expect(stop.lastAssistantMessage == "done" && stop.transcriptPath == "/g/updates.jsonl")
        let note = try decode("Notification", #","notificationType":"permission_prompt","message":"Tool permission requested","level":"info""#)
        #expect(note.notificationType == "permission_prompt" && note.message == "Tool permission requested")
        let tool = try decode("PostToolUse", #","toolName":"run_terminal_command","toolInput":{"command":"ls"},"toolResult":{"type":"Bash","exit_code":0}"#)
        #expect(tool.toolName == "run_terminal_command" && tool.toolStrings == ["command": "ls"])
        // camelCase alone is enough.
        let bare = try JSONDecoder().decode(HookInput.self, from: Data(#"{"sessionId":"s","hook_event_name":"SessionEnd","reason":"shutdown"}"#.utf8))
        #expect(bare.sessionID == "s" && bare.reason == "shutdown")
        // A non-string `reason` from some other agent does not break decoding.
        let odd = try JSONDecoder().decode(HookInput.self, from: Data(#"{"session_id":"s","hook_event_name":"Stop","reason":{"x":1}}"#.utf8))
        #expect(odd.reason == nil)
    }

    @Test func aTurn() throws {
        let prompt = try reports("UserPromptSubmit", #","promptId":"p1","prompt":"Run the shell command `echo hi`\nthen reply done.""#)
        #expect(prompt == [SessionReport(id: "01a1", kind: .prompt, at: now, source: "grok", title: "perch", cwd: "/w/perch",
                                         link: link, prompt: "Run the shell command echo hi", turn: "p1")])

        let waiting = try reports("Notification", #","notificationType":"permission_prompt","message":"Tool permission requested","level":"info""#)
        #expect(waiting.map(\.kind) == [.waiting])
        #expect(waiting.first?.detail == "Tool permission requested\nAnswer in the terminal" && waiting.first?.keepDetail == nil)

        for event in ["PostToolUse", "PostToolUseFailure"] {
            #expect(try reports(event, #","toolName":"run_terminal_command","toolInput":{"command":"ls"}"#).map(\.kind) == [.resume])
        }

        let stop = try reports("Stop", ###","promptId":"p1","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"## Done\nAll good""###)
        #expect(stop.map(\.kind) == [.stop] && stop.first?.lastMessage == "Done" && stop.first?.turn == "p1")
    }

    @Test func theSessionEndStopIsIgnored() throws {
        #expect(try reports("Stop", #","reason":"shutdown","stopHookActive":false"#).isEmpty)
        #expect(try reports("Stop", #","reason":"channel_closed","stopHookActive":false"#).isEmpty)
        #expect(try reports("SessionEnd", #","reason":"shutdown""#).map(\.kind) == [.end])
    }

    @Test func cancelledTurns() throws {
        for reason in ["user_interrupt", "permission_rejected", "permission_cancelled"] {
            let r = try reports("StopCancelled", #","promptId":"p1","reason":"\#(reason)","cancelledBy":"user""#)
            #expect(r.map(\.kind) == [.interrupt] && r.first?.turn == "p1")
        }
        #expect(try reports("StopCancelled", #","promptId":"p1","reason":"unknown","cancelledBy":"unknown""#).map(\.kind) == [.interrupt])
        for reason in ["max_turns", "no_progress"] {
            let r = try reports("StopCancelled", #","promptId":"p1","reason":"\#(reason)","cancelledBy":"runtime""#)
            #expect(r.map(\.kind) == [.failure] && r.first?.error == reason)
        }
        let failure = try reports("StopFailure", #","promptId":"p1","error":"rate_limit","errorDetails":"429","lastAssistantMessage":"Rate limited""#)
        #expect(failure.map(\.kind) == [.failure] && failure.first?.error == "rate_limit" && failure.first?.turn == "p1")
    }

    @Test func idlePromptSettles() throws {
        let r = try reports("Notification", #","notificationType":"idle_prompt","message":"Waiting for your next prompt","level":"info""#)
        #expect(r.map(\.kind) == [.settle] && r.first?.turn == nil)
        #expect(try reports("Notification", #","notificationType":"task_complete","message":"x""#).isEmpty)
    }

    @Test func subagentsAreIgnored() throws {
        #expect(try reports("Stop", #","reason":"end_turn","lastAssistantMessage":"x","subagentType":"explore""#).isEmpty)
        #expect(try reports("SessionEnd", #","reason":"shutdown","subagentType":"explore""#).isEmpty)
        #expect(try reports("StopCancelled", #","reason":"max_turns","cancelledBy":"runtime","subagentType":"explore""#).isEmpty)
    }

    @Test func unhandledEvents() throws {
        for event in ["SessionStart", "PreToolUse", "PermissionDenied", "SubagentStart", "PreCompact"] {
            #expect(try reports(event).isEmpty)
        }
    }
}

/// What Perch's dsh plugin sends `perch hook dsh`: already-normalised events (#74), built from the dsh 0.2.0-rc.2
/// probe run in #73 (2026-10-19).
@Suite struct DshAdapterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let link = "perch-terminal://ghostty?id=T1"
    /// dsh's event time, epoch ms.
    let at = 1_792_398_869_889.0

    func decode(_ event: String, _ fields: String = "", turn: String = #""4""#) throws -> HookInput {
        let json = #"{"hook_event_name":"\#(event)","session_id":"b7627ec2-685c-4f15-84f0-a5188bdc8d7c","cwd":"/private/tmp/perch-dsh-ws","at":1792398869889,"pid":60402,"turn":\#(turn)\#(fields)}"#
        return try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
    }

    func reports(_ event: String, _ fields: String = "") throws -> [SessionReport] {
        let requests = HookAdapter.requests(for: try decode(event, fields), agent: "dsh", link: link, now: now)
        // Never a request or any other item: the notch never approves dsh.
        #expect(requests.allSatisfy { $0.op == .sessionReport })
        return requests.compactMap(\.report)
    }

    @Test func decodesThePayload() throws {
        let prompt = try decode("Prompt", #","prompt":"PROBE_BASH please approve""#)
        #expect(prompt.sessionID == "b7627ec2-685c-4f15-84f0-a5188bdc8d7c" && prompt.event == "Prompt")
        #expect(prompt.cwd == "/private/tmp/perch-dsh-ws" && prompt.prompt == "PROBE_BASH please approve")
        #expect(prompt.at == Date(timeIntervalSince1970: at / 1000) && prompt.pid == 60402 && prompt.turn == "4")
        #expect(prompt.keepPrompt == nil)
        // A numeric turn reads the same.
        #expect(try decode("Prompt", turn: "4").turn == "4")
        #expect(try decode("Prompt", #","keep_prompt":true"#).keepPrompt == true)

        let questions = try decode("QuestionAsked", #","questions":[{"id":"colour","question":"Which colour should the button be?","header":"Colour","options":[{"label":"Orange"}],"multiSelect":false}]"#)
        #expect(questions.questions == [.init(question: "Which colour should the button be?", header: "Colour")])

        let end = try decode("TurnEnd", #","reason":"error","error":"mock: scripted failure","last_assistant_message":null"#)
        #expect(end.reason == "error" && end.error == .string("mock: scripted failure"))

        // The plugin may hand over `tool/call`'s arguments as the JSON string dsh keeps them in.
        let parsed = try decode("ApprovalAsked", #","tool_name":"bash","tool_input":{"command":"ls"}"#)
        let raw = try decode("ApprovalAsked", #","tool_name":"bash","tool_input":"{\"command\":\"ls\"}""#)
        #expect(parsed.toolInput == ["command": .string("ls")] && raw.toolInput == parsed.toolInput)

        // Odd shapes never break decoding.
        let odd = try JSONDecoder().decode(HookInput.self, from: Data(#"{"hook_event_name":"Prompt","session_id":"s","at":"soon","pid":"x","turn":[1],"keep_prompt":"yes","questions":{"a":1},"tool_input":"not json"}"#.utf8))
        #expect(odd.at == nil && odd.pid == nil && odd.turn == nil && odd.keepPrompt == nil && odd.questions == nil && odd.toolInput == nil)
    }

    @Test func aTurn() throws {
        let time = Date(timeIntervalSince1970: at / 1000)
        let prompt = try reports("Prompt", #","prompt":"PROBE_BASH please approve\nthen stop""#)
        #expect(prompt == [SessionReport(id: "b7627ec2-685c-4f15-84f0-a5188bdc8d7c", kind: .prompt, at: time, source: "dsh",
                                         title: "perch-dsh-ws", cwd: "/private/tmp/perch-dsh-ws", link: link,
                                         prompt: "PROBE_BASH please approve", turn: "4")])

        let done = try reports("TurnEnd", ###","reason":"completed","last_assistant_message":"## Finished after the tool.\nMore""###)
        #expect(done.map(\.kind) == [.stop] && done.first?.lastMessage == "Finished after the tool.")
        #expect(done.first?.turn == "4" && done.first?.at == time)

        #expect(try reports("SessionEnd").map(\.kind) == [.end])
    }

    @Test func theEventTimeIsTheReportTime() throws {
        let input = try JSONDecoder().decode(HookInput.self, from: Data(#"{"hook_event_name":"Answered","session_id":"s"}"#.utf8))
        #expect(HookAdapter.requests(for: input, agent: "dsh", link: nil, now: now).first?.report?.at == now)
    }

    @Test func anApprovalIsAnsweredInTheTerminal() throws {
        let bash = try reports("ApprovalAsked", #","tool_name":"bash","tool_input":{"command":"curl -s https://example.com -o /tmp/perch-dsh-outside.html","description":"Fetch example.com outside the workspace","sandbox_permissions":"danger-full-access","justification":"Probe: needs network"},"reason":"Probe: needs network and a path outside the workspace""#)
        #expect(bash.map(\.kind) == [.waiting])
        #expect(bash.first?.detail == "curl -s https://example.com -o /tmp/perch-dsh-outside.html\nAnswer in the terminal: Probe: needs network and a path outside the workspace")
        #expect(bash.first?.turn == "4")

        // Any other tool: its name and every argument, in full.
        let write = try reports("ApprovalAsked", #","tool_name":"write_file","tool_input":{"path":"/etc/hosts","content":"127.0.0.1 x","append":false}"#)
        #expect(write.first?.detail == "write_file append=false content=127.0.0.1 x path=/etc/hosts\nAnswer in the terminal")
        #expect(try reports("ApprovalAsked", #","tool_name":"bash""#).first?.detail == "bash\nAnswer in the terminal")
        #expect(try reports("ApprovalAsked").first?.detail == "tool\nAnswer in the terminal")

        // Allowed, denied, Esc or Ctrl+C on the prompt: dsh carries on.
        #expect(try reports("Answered").map(\.kind) == [.resume])
    }

    @Test func aQuestionIsAnsweredInTheTerminal() throws {
        let one = try reports("QuestionAsked", #","questions":[{"question":"Which colour should the button be?","header":"Colour"}]"#)
        #expect(one.map(\.kind) == [.waiting] && one.first?.detail == "Which colour should the button be?\nAnswer in the terminal")
        let three = try reports("QuestionAsked", #","questions":[{"question":"Which colour?"},{"question":"Which size?"},{"question":"Ship it?"}]"#)
        #expect(three.first?.detail == "Which colour? (and 2 more)\nAnswer in the terminal")
        let header = try reports("QuestionAsked", #","questions":[{"question":"","header":"Colour"}]"#)
        #expect(header.first?.detail == "Colour\nAnswer in the terminal")
        #expect(try reports("QuestionAsked").first?.detail == "Waiting for your answer\nAnswer in the terminal")
    }

    /// A `dsh web` session (#80): answered in the browser, linked to dsh web's address and never to a terminal.
    @Test func webSessions() throws {
        let web = #","surface":"web","url":"http://127.0.0.1:3080/""#
        let ask = try reports("ApprovalAsked", web + #","tool_name":"bash","tool_input":{"command":"touch ~/x"},"reason":"escalate""#)
        #expect(ask.first?.detail == "touch ~/x\nAnswer in dsh web: escalate")
        let question = try reports("QuestionAsked", web + #","questions":[{"question":"Orange or blue?"}]"#)
        #expect(question.first?.detail == "Orange or blue?\nAnswer in dsh web")
        #expect(HookAdapter.dshWebLink(try decode("Prompt", web)) == "http://127.0.0.1:3080/")
        #expect(HookAdapter.dshWebLink(try decode("Prompt", #","surface":"web","url":"https://dsh.example/ui/""#)) == "https://dsh.example/ui/")
        // No usable address: no link at all, never a terminal.
        #expect(HookAdapter.dshWebLink(try decode("Prompt", #","surface":"web""#)) == nil)
        #expect(HookAdapter.dshWebLink(try decode("Prompt", #","surface":"web","url":"file:///etc/passwd""#)) == nil)
        // The terminal UI is unchanged.
        let tui = try reports("ApprovalAsked", #","tool_name":"bash","tool_input":{"command":"ls"}"#)
        #expect(tui.first?.detail == "ls\nAnswer in the terminal")
        #expect(try decode("Prompt").surface == nil)
    }

    @Test func howATurnEnds() throws {
        for reason in ["completed", "max-tokens", "something-new"] {
            let r = try reports("TurnEnd", #","reason":"\#(reason)","last_assistant_message":"Done: hi""#)
            #expect(r.map(\.kind) == [.stop] && r.first?.lastMessage == "Done: hi" && r.first?.turn == "4")
        }
        #expect(try reports("TurnEnd").map(\.kind) == [.stop])
        // dsh-tui's narration line (⏵) is not the reply (seen on the real model, 2026-10-19).
        let narrated = try reports("TurnEnd", #","reason":"completed","last_assistant_message":"⏵ Replying briefly as requested\nok, nothing to build.""#)
        #expect(narrated.first?.lastMessage == "ok, nothing to build.")
        let onlyNarration = try reports("TurnEnd", #","reason":"completed","last_assistant_message":"⏵ Waiting on the actual project brief""#)
        #expect(onlyNarration.first?.lastMessage == "Waiting on the actual project brief")
        let error = try reports("TurnEnd", #","reason":"error","error":"400 mock: scripted failure""#)
        #expect(error.map(\.kind) == [.failure] && error.first?.error == "400 mock: scripted failure" && error.first?.turn == "4")
        // dsh's own shape, should the plugin pass it through.
        let object = try reports("TurnEnd", #","reason":"error","error":{"message":"mock: scripted failure","code":"invalid_request_error","status":400}"#)
        #expect(object.first?.error == "mock: scripted failure")
        #expect(try reports("TurnEnd", #","reason":"error""#).first?.error == "unknown")
        for reason in ["aborted", "blocked"] {
            let r = try reports("TurnEnd", #","reason":"\#(reason)""#)
            #expect(r.map(\.kind) == [.interrupt] && r.first?.turn == "4")
        }
    }

    @Test func aTurnNobodyTyped() throws {
        // The goal driver, a schedule or a background job woke dsh: the row keeps the human's prompt.
        let input = try decode("Prompt", #","keep_prompt":true,"prompt":"[scheduled] check the build""#)
        let report = try #require(HookAdapter.requests(for: input, agent: "dsh", link: nil, now: now).first?.report)
        #expect(report.kind == .prompt && report.prompt == nil && report.keepPrompt == true && report.turn == "4")
        // Focus may be anywhere: no terminal is recorded for it.
        #expect(!HookAdapter.startsTurn(input))
        #expect(HookAdapter.startsTurn(try decode("Prompt", #","prompt":"hi""#)))
        #expect(try reports("Prompt", #","prompt":"hi""#).first?.keepPrompt == nil)
    }

    @Test func dshsHooksBridgeCallingAnotherAgentsHookIsForeign() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // perch ← sh ← node dsh (its Claude Code / Codex hooks bridge running ~/.claude/settings.json).
        let bridge: [Int32: ProcessEntry] = [
            900: ProcessEntry(pid: 900, ppid: 800, name: "perch", startedAt: t0),
            800: ProcessEntry(pid: 800, ppid: 700, name: "sh", startedAt: t0),
            700: ProcessEntry(pid: 700, ppid: 1, name: "node", startedAt: t0, script: "/n/bin/dsh"),
        ]
        #expect(HookAdapter.isForeign(agent: "claude-code", environment: [:], processes: bridge, from: 900))
        #expect(HookAdapter.isForeign(agent: "codex", environment: [:], processes: bridge, from: 900))
        // dsh's own plugin, and agents dsh has no bridge for.
        #expect(!HookAdapter.isForeign(agent: "dsh", environment: [:], processes: bridge, from: 900))
        #expect(!HookAdapter.isForeign(agent: "grok", environment: [:], processes: bridge, from: 900))
        #expect(!HookAdapter.isForeign(agent: "claude-code", environment: [:], processes: [:], from: 900))
    }

    @Test func unhandledEvents() throws {
        // Including other agents' names: dsh never sends them, and PermissionRequest must never reach the notch.
        for event in ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "Notification", "tool/call"] {
            #expect(try reports(event).isEmpty)
        }
    }
}
