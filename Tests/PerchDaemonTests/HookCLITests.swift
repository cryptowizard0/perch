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

        // Permission prompt: the session needs you, keeping its link. No item: the session is the only state.
        try hook(cli, event("Notification", #","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash""#))
        var latest = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(latest.status == .waiting && latest.detail == "Claude needs your permission to use Bash" && latest.link == session.link)
        #expect(try allItems(d) == [])

        // Idle prompts are ignored.
        try hook(cli, event("Notification", #","notification_type":"idle_prompt","message":"Claude is waiting for your input""#))
        #expect(try d.client.send(Request(op: .sessions)).sessions?.map(\.status) == [.waiting])

        // Stop: done, with the reply's first line; no notice.
        try hook(cli, event("Stop", #","stop_hook_active":false,"last_assistant_message":"All 12 tests pass.""#))
        latest = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(latest.status == .done && latest.lastMessage == "All 12 tests pass.")
        #expect(try allItems(d) == [])

        // Next prompt: a new turn in the same session.
        try hook(cli, event("UserPromptSubmit", #","prompt":"thanks""#))
        #expect(try d.client.send(Request(op: .sessions)).sessions?.map(\.status) == [.running])
        #expect(try allItems(d) == [])
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

/// Every item in perchd, closed ones too: Claude Code / Codex hooks leave none behind except allowlisted requests.
func allItems(_ d: TestDaemon) throws -> [Item] {
    try d.client.send(Request(op: .list, filter: .init(all: true))).items ?? []
}

/// The one session a test drives.
func onlySession(_ d: TestDaemon) throws -> Session {
    let sessions = try d.client.send(Request(op: .sessions)).sessions ?? []
    guard sessions.count == 1 else { throw CLIError("expected one session, got \(sessions.count)") }
    return sessions[0]
}

/// Waits (up to 3 s) for a hook running in the background to post its request to the notch.
func postedRequest(_ d: TestDaemon) throws -> Item {
    for _ in 0..<300 {
        if let request = try d.client.send(Request(op: .list, filter: .init(kind: .request))).items?.first { return request }
        Thread.sleep(forTimeInterval: 0.01)
    }
    throw CLIError("the hook never posted its request")
}

/// PermissionRequest through `perch hook claude-code`: the notch answers, or the terminal asks.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct PermissionHookTests {
    let env = ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"]

    func permission(_ command: String) -> String {
        #"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"\#(command)","description":"Run it"}}"#
    }

    /// Starts the hook in the background and returns once its request is in the notch.
    func ask(_ d: TestDaemon, _ command: String, wait: String = "20") throws -> (() throws -> CLI.Result, Item) {
        let finish = try CLI(home: d.home).start(["hook", "claude-code", "--wait", wait], stdin: permission(command), env: env)
        return (finish, try postedRequest(d))
    }

    @Test func allowFromTheNotch() throws {
        let d = try TestDaemon()
        let (finish, request) = try ask(d, "npm test")
        #expect(request.title == "npm test")
        #expect(request.meta?["description"] == "Run it")
        #expect(request.expiresAt != nil)
        _ = try d.client.send(Request(op: .respond, id: request.id, value: "allow"))
        let result = try finish()
        #expect(result.status == 0)
        #expect(result.stdout == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        // The request is the only item, answered; the session runs on.
        #expect(try allItems(d).map(\.id) == [request.id])
        #expect(try onlySession(d).status == .running)
    }

    @Test func denyFromTheNotch() throws {
        let d = try TestDaemon()
        let (finish, request) = try ask(d, "git log")
        _ = try d.client.send(Request(op: .respond, id: request.id, value: "deny"))
        let result = try finish()
        #expect(result.stdout.contains(#""behavior":"deny""#))
    }

    @Test func timeoutHandsOverToTheTerminal() throws {
        let d = try TestDaemon()
        let started = Date()
        let (finish, _) = try ask(d, "pytest", wait: "1")
        let result = try finish()
        #expect(result.status == 0 && result.stdout.isEmpty)
        #expect(Date().timeIntervalSince(started) < 4)
        // No "go to terminal" item: the session says where to answer.
        #expect(try allItems(d).map(\.kind) == [.request])
        let session = try onlySession(d)
        #expect(session.status == .waiting && session.detail == "pytest\nAnswer in the terminal")
    }

    @Test func notOnTheAllowlistGoesToTheTerminalAtOnce() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        let started = Date()
        let result = try cli.run(["hook", "claude-code"], stdin: permission("rm -rf build/"), env: env)
        #expect(result.status == 0 && result.stdout.isEmpty)
        #expect(Date().timeIntervalSince(started) < 1)
        let asked = "rm -rf build/\nAnswer in the terminal: `rm -rf` is not on the allowlist"
        #expect(try onlySession(d).detail == asked)
        #expect(try allItems(d) == [])

        // Six seconds later Claude Code's permission_prompt notification must not replace the command text.
        let notification = #"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}"#
        try cli.run(["hook", "claude-code"], stdin: notification, env: env)
        #expect(try onlySession(d).detail == asked)

        // Answered in the terminal: the tool ran, the orange goes away without waiting for Stop.
        let ran = #"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}"#
        try cli.run(["hook", "claude-code"], stdin: ran, env: env)
        #expect(try onlySession(d).status == .running)
        #expect(try allItems(d) == [])
    }

    @Test func aBrokenAllowlistApprovesNothing() throws {
        let d = try TestDaemon()
        try "{ broken".write(to: d.home.appendingPathComponent("allowlist.json"), atomically: true, encoding: .utf8)
        let result = try CLI(home: d.home).run(["hook", "claude-code"], stdin: permission("npm test"), env: env)
        #expect(result.stdout.isEmpty)
        #expect(try allItems(d) == [])
        #expect(try onlySession(d).detail?.hasPrefix("npm test\nAnswer in the terminal") == true)
        let log = try String(contentsOf: d.home.appendingPathComponent("hook.log"), encoding: .utf8)
        #expect(log.contains("nothing can be approved from the notch"))
    }
}

/// `perch hook codex` fed Codex's stdin JSON (extra fields, nulls, no Notification), against a real perchd.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct CodexHookTests {
    let env = ["TERM_PROGRAM": "ghostty-not-scripted", "__CFBundleIdentifier": "com.mitchellh.ghostty"]

    func event(_ name: String, _ extra: String = "") -> String {
        #"{"session_id":"019a","turn_id":"t1","transcript_path":null,"cwd":"/w/perch","permission_mode":"default","model":"gpt-6","hook_event_name":"\#(name)"\#(extra)}"#
    }

    @discardableResult
    func hook(_ cli: CLI, _ json: String, wait: String? = nil) throws -> CLI.Result {
        try cli.run(["hook", "codex"] + (wait.map { ["--wait", $0] } ?? []), stdin: json, env: env)
    }

    @Test func aTurnWithANotchApproval() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)

        let prompt = try hook(cli, event("UserPromptSubmit", #","prompt":"run the tests""#))
        #expect(prompt.status == 0 && prompt.stdout.isEmpty && prompt.stderr.isEmpty)
        let session = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(session.id == "019a" && session.source == "codex" && session.title == "perch")

        // Allowlisted: the notch answers and Codex gets the decision.
        let bash = event("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"cargo test","description":null}"#)
        let finish = try CLI(home: d.home).start(["hook", "codex", "--wait", "20"], stdin: bash, env: env)
        let asked = try postedRequest(d)
        #expect(asked.title == "cargo test" && asked.source == "codex")
        _ = try d.client.send(Request(op: .respond, id: asked.id, value: "allow"))
        let answered = try finish()
        #expect(answered.stdout == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)

        // A patch is never approvable from the notch: straight to the terminal, orange until the tool runs.
        let patch = event("PermissionRequest", #","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch"}"#)
        let terminal = try hook(cli, patch, wait: "20")
        #expect(terminal.status == 0 && terminal.stdout.isEmpty)
        #expect(try onlySession(d).detail?.hasPrefix("apply_patch *** Begin Patch\nAnswer in the terminal") == true)
        try hook(cli, event("PostToolUse", #","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch"},"tool_response":{},"tool_use_id":"u1""#))
        #expect(try onlySession(d).status == .running)
        // The answered request is the only item Codex ever left.
        #expect(try allItems(d).map(\.id) == [asked.id])

        // Esc: Codex sends Interrupt and no Stop; the session goes idle anyway.
        try hook(cli, event("Interrupt"))
        #expect(try d.client.send(Request(op: .sessions)).sessions?.map(\.status) == [.idle])

        // A finished turn is done, no notice; a null last message still decodes.
        try hook(cli, event("UserPromptSubmit", #","prompt":"again""#))
        try hook(cli, event("Stop", #","stop_hook_active":false,"last_assistant_message":null"#))
        #expect(try onlySession(d).status == .done)
        #expect(try allItems(d).map(\.id) == [asked.id])
    }
}

/// `perch hook hermes` fed Hermes shell-hook payloads, against a real perchd.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct HermesHookTests {
    let env = ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"]

    @discardableResult
    func hook(_ cli: CLI, _ event: String, session: String = "s1", _ extra: String) throws -> CLI.Result {
        let json = #"{"hook_event_name":"\#(event)","tool_name":null,"tool_input":null,"session_id":"\#(session)","cwd":"/w/perch","extra":\#(extra)}"#
        return try cli.run(["hook", "hermes"], stdin: json, env: env)
    }

    @Test func aTurnWithADangerousCommand() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)

        let start = try hook(cli, "pre_llm_call", #"{"user_message":"clean up","conversation_history":[],"is_first_turn":true,"platform":"cli"}"#)
        #expect(start.status == 0 && start.stdout.isEmpty && start.stderr.isEmpty)  // stdout would become LLM context
        let session = try #require(try d.client.send(Request(op: .sessions)).sessions?.first)
        #expect(session.id == "s1" && session.source == "hermes" && session.title == "perch")

        // Hermes asks before `rm -rf`: orange, full command, answered in the terminal.
        try hook(cli, "pre_approval_request", session: "",
                 #"{"command":"rm -rf build/","description":"recursive delete","pattern_key":"rm_rf","session_key":"default","surface":"cli"}"#)
        var items = try d.client.send(Request(op: .list)).items ?? []
        #expect(items.map(\.title) == ["perch · rm -rf build/"])
        #expect(items.first?.status == .waiting && items.first?.link == session.link)
        try hook(cli, "post_approval_response", session: "", #"{"command":"rm -rf build/","session_key":"default","surface":"cli","choice":"once"}"#)
        #expect(try d.client.send(Request(op: .list)).items == [])

        try hook(cli, "post_llm_call", #"{"assistant_response":"Removed build/.","platform":"cli"}"#)
        try hook(cli, "on_session_end", #"{"completed":true,"interrupted":false,"platform":"cli"}"#)
        #expect(try d.client.send(Request(op: .sessions)).sessions == [])
        items = try d.client.send(Request(op: .list)).items ?? []
        #expect(items.map(\.title) == ["perch · Removed build/."])
        #expect(items.first?.kind == .notice)
    }
}

extension HermesHookTests {
    /// Approval hooks carry no session id: they jump to the terminal of the Hermes turn running in that directory
    /// (whose Ghostty terminal id was captured when the prompt was typed).
    @Test func approvalsJumpToTheTurnsTerminal() throws {
        let d = try TestDaemon()
        let turn = "perch-terminal://ghostty?id=T1&cwd=/w/perch&bundle=com.mitchellh.ghostty"
        _ = try d.client.send(Request(op: .sessionStart, session: Session(id: "s1", source: "hermes", title: "perch", link: turn, startedAt: Date())))
        try hook(CLI(home: d.home), "pre_approval_request", session: "",
                 #"{"command":"rm -rf build/","description":"recursive delete","session_key":"default","surface":"cli","tool_call_id":"c9"}"#)
        let item = try #require(try d.client.send(Request(op: .list)).items?.first)
        #expect(item.link == turn)
        #expect(item.key == "hermes:default:c9")
    }
}
