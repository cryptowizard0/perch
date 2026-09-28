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

    @Test func promptStartsTheTurnAndClearsWhatWasWaiting() {
        let r = requests(HookInput(sessionID: "abc", event: "UserPromptSubmit", cwd: "/Users/me/work/perch"))
        #expect(r.map(\.op) == [.sessionStart, .done, .done])
        #expect(r[0].session == Session(id: "abc", source: "claude-code", title: "perch", link: link, startedAt: now))
        #expect(r[1].key == "claude-code:abc")
        #expect(r[2].key == "claude-code:abc:done")
    }

    @Test func permissionPromptBecomesWaiting() throws {
        let r = requests(HookInput(sessionID: "abc", event: "Notification", cwd: "/w/perch",
                                   notificationType: "permission_prompt", message: "Claude needs your permission to use Bash"))
        let item = try #require(r.first?.item)
        #expect(r.map(\.op) == [.add])
        #expect(item.title == "perch · Claude needs your permission to use Bash")
        #expect(item.kind == .task && item.status == .waiting)
        #expect(item.source == "claude-code")
        #expect(item.key == "claude-code:abc")
        #expect(item.link == link)
        #expect(item.meta == ["session_id": "abc", "cwd": "/w/perch", "notification_type": "permission_prompt"])
    }

    @Test func otherNotificationsAreIgnored() {
        for type in ["idle_prompt", "auth_success", "agent_completed"] {
            #expect(requests(HookInput(sessionID: "abc", event: "Notification", notificationType: type, message: "x")).isEmpty)
        }
        #expect(!requests(HookInput(sessionID: "abc", event: "Notification", notificationType: "elicitation_dialog")).isEmpty)
        #expect(!requests(HookInput(sessionID: "abc", event: "Notification", notificationType: "agent_needs_input")).isEmpty)
    }

    @Test func stopEndsTheTurnAndLeavesANotice() throws {
        let message = "## Done\n\n**All 12 tests pass** and the PR is pushed.\nMore detail…"
        let r = requests(HookInput(sessionID: "abc", event: "Stop", cwd: "/w/perch", lastAssistantMessage: message))
        #expect(r.map(\.op) == [.sessionEnd, .done, .add])
        #expect(r[0].id == "abc" && r[0].at == now)
        #expect(r[1].key == "claude-code:abc")
        let notice = try #require(r[2].item)
        #expect(notice.kind == .notice)
        #expect(notice.title == "perch · Done")
        #expect(notice.key == "claude-code:abc:done")
        #expect(notice.expiresAt == now.addingTimeInterval(600))
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
        for event in ["StopFailure", "SessionEnd", "Interrupt"] {
            #expect(requests(HookInput(sessionID: "abc", event: event)).map(\.op) == [.sessionEnd, .done])
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
        guard case .terminal(let item) = plan("Bash", ["command": .string("rm -rf build/")]) else { Issue.record("expected terminal"); return }
        #expect(item.title == "perch · rm -rf build/")
        #expect(item.kind == .task && item.status == .waiting)
        #expect(item.key == "claude-code:s1")
        #expect(item.meta?["terminal_reason"] == "`rm -rf` is not on the allowlist")
        guard case .terminal = plan("Read", ["file_path": .string("/Users/me/.ssh/id_rsa")]) else { Issue.record("ssh"); return }
        guard case .terminal = plan("Write", ["file_path": .string("/w/perch/a.swift")]) else { Issue.record("write"); return }
    }

    @Test func timedOutRequestBecomesGoToTerminal() {
        guard case .ask(let request) = plan("Bash", ["command": .string("pytest")]) else { Issue.record("ask"); return }
        let item = HookAdapter.goToTerminal(after: request, agent: "claude-code", session: "s1")
        #expect(item.title == "perch · pytest")
        #expect(item.status == .waiting && item.kind == .task)
        #expect(item.key == "claude-code:s1")
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
        guard case .terminal(let item) = HookAdapter.permission(for: input, agent: "codex", link: nil, allowlist: .defaults,
                                                                 now: now, home: "/Users/me") else { Issue.record("terminal"); return }
        #expect(item.title == "perch · apply_patch \(patch)")
        #expect(item.key == "codex:019a")
    }

    @Test func latePermissionNotificationKeepsTheCommandText() {
        let notification = HookInput(sessionID: "s1", event: "Notification", notificationType: "permission_prompt", message: "needs permission")
        #expect(HookAdapter.requests(for: notification, agent: "claude-code", link: nil, now: now, alreadyWaiting: true).isEmpty)
        #expect(!HookAdapter.requests(for: notification, agent: "claude-code", link: nil, now: now, alreadyWaiting: false).isEmpty)
        let elicitation = HookInput(sessionID: "s1", event: "Notification", notificationType: "elicitation_dialog", message: "pick one")
        #expect(!HookAdapter.requests(for: elicitation, agent: "claude-code", link: nil, now: now, alreadyWaiting: true).isEmpty)
    }

    @Test func toolRunResolvesTheWaitingItem() {
        for event in ["PostToolUse", "PostToolUseFailure"] {
            let r = HookAdapter.requests(for: HookInput(sessionID: "s1", event: event, toolName: "Bash"), agent: "claude-code", link: nil, now: now)
            #expect(r.map(\.op) == [.done] && r.first?.key == "claude-code:s1")
        }
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
                                                 sessionKey: "default", surface: "cli"))
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
        #expect(r[0].session?.title == "telegram")
        #expect(r[0].session?.link == nil)
        let post = requests(try input(#"{"hook_event_name":"post_llm_call","session_id":"s2","cwd":"/","extra":{"platform":"telegram","assistant_response":"done"}}"#))
        #expect(post.first?.item?.title == "telegram · done")
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
        let r = requests(try input(#"{"hook_event_name":"pre_approval_request","session_id":"","cwd":"/w/perch","extra":{"command":"rm -rf build/","description":"recursive delete","session_key":"default","surface":"cli"}}"#))
        let item = try #require(r.first?.item)
        #expect(r.map(\.op) == [.add])
        #expect(item.title == "perch · rm -rf build/")
        #expect(item.kind == .task && item.status == .waiting && item.source == "hermes")
        #expect(item.key == "hermes:default")
        #expect(item.link == "L")
        #expect(item.meta == ["tool": "terminal", "terminal_reason": "recursive delete", "session_key": "default", "cwd": "/w/perch"])
    }

    /// Gateway approvals are answered in the chat app; there is no terminal to jump to.
    @Test func anApprovalFromTheGatewayWaitsInTheChat() throws {
        let r = requests(try input(#"{"hook_event_name":"pre_approval_request","session_id":"","cwd":"/","extra":{"command":"sudo reboot","description":"sudo","session_key":"agent:main:telegram:dm:42","surface":"gateway"}}"#))
        let item = try #require(r.first?.item)
        #expect(item.title == "telegram · sudo reboot")
        #expect(item.key == "hermes:agent:main:telegram:dm:42")
        #expect(item.meta?["answer_in"] == "Telegram")
        #expect(item.link == nil)
    }

    @Test func theResponseClearsIt() throws {
        for choice in ["once", "deny", "timeout"] {
            let r = requests(try input(#"{"hook_event_name":"post_approval_response","session_id":"","cwd":"/","extra":{"command":"rm -rf build/","session_key":"default","surface":"cli","choice":"\#(choice)"}}"#))
            #expect(r.map(\.op) == [.done] && r.first?.key == "hermes:default")
        }
    }

    @Test func otherHermesEventsAreIgnored() throws {
        for event in ["pre_tool_call", "post_tool_call", "on_session_start", "transform_llm_output"] {
            #expect(requests(try input(#"{"hook_event_name":"\#(event)","session_id":"s1","cwd":"/"}"#)).isEmpty)
        }
    }
}
