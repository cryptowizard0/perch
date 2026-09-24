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
        for event in ["StopFailure", "SessionEnd"] {
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
