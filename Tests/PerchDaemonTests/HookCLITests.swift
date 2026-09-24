import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// `perch hook claude-code` fed Claude Code's stdin JSON, against a real perchd.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct HookCLITests {
    /// A plain terminal (no Ghostty probing), like hooks in CI.
    let env = ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"]

    func hook(_ cli: CLI, _ json: String) throws -> CLI.Result {
        try cli.run(["hook", "claude-code"], stdin: json, env: env)
    }

    func event(_ name: String, _ extra: String = "") -> String {
        #"{"session_id":"s1","transcript_path":"/t.jsonl","cwd":"/Users/me/work/perch","hook_event_name":"\#(name)"\#(extra)}"#
    }

    @Test func aTurnWithAPermissionPrompt() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)

        // Prompt submitted: the turn is running.
        let prompt = try hook(cli, event("UserPromptSubmit", #","prompt":"run the tests""#))
        #expect(prompt.status == 0 && prompt.stdout.isEmpty && prompt.stderr.isEmpty)
        let session = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(session.id == "s1" && session.title == "perch" && session.source == "claude-code")
        let link = try #require(session.link.flatMap(TerminalLink.init(string:)))
        #expect(link == TerminalLink(app: "apple_terminal", cwd: "/Users/me/work/perch", bundleID: "com.apple.Terminal"))

        // Permission prompt: waiting, orange, with the session's link.
        try hook(cli, event("Notification", #","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash""#))
        var items = try d.client.send(Request(op: .list)).items ?? []
        #expect(items.map(\.title) == ["perch · Claude needs your permission to use Bash"])
        #expect(items.first?.status == .waiting)
        #expect(items.first?.link == session.link)

        // Idle prompts are ignored.
        try hook(cli, event("Notification", #","notification_type":"idle_prompt","message":"Claude is waiting for your input""#))
        #expect(try d.client.send(Request(op: .list)).items?.count == 1)

        // Stop: turn over, waiting resolved, a notice that fades.
        try hook(cli, event("Stop", #","stop_hook_active":false,"last_assistant_message":"All 12 tests pass.""#))
        #expect(try d.client.send(Request(op: .sessions)).sessions == [])
        items = try d.client.send(Request(op: .list)).items ?? []
        #expect(items.map(\.title) == ["perch · All 12 tests pass."])
        #expect(items.first?.kind == .notice)
        #expect(items.first?.expiresAt != nil)

        // Next prompt: the old notice goes away, a new turn starts.
        try hook(cli, event("UserPromptSubmit", #","prompt":"thanks""#))
        #expect(try d.client.send(Request(op: .list)).items == [])
        #expect(try d.client.send(Request(op: .sessions)).sessions?.count == 1)
    }

    @Test func silentAndZeroWhenThingsGoWrong() throws {
        let home = URL(fileURLWithPath: "/tmp/perch-test-hook-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home)  // no perchd here
        for input in [event("Stop"), "not json", ""] {
            let result = try hook(cli, input)
            #expect(result.status == 0 && result.stdout.isEmpty && result.stderr.isEmpty)
        }
        let log = try String(contentsOf: home.appendingPathComponent("hook.log"), encoding: .utf8)
        #expect(log.contains("perchd is not running"))
        #expect(log.contains("unreadable claude-code hook input"))
    }
}
