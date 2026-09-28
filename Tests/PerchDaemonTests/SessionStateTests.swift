import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The session state machine, driven by `perch hook <agent>` (the real binary) against a real perchd.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct SessionStateTests {
    let env = ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"]

    func claude(_ name: String, _ extra: String = "", session: String = "s1") -> String {
        #"{"session_id":"\#(session)","transcript_path":"/t.jsonl","cwd":"/Users/me/work/perch","hook_event_name":"\#(name)"\#(extra)}"#
    }

    func codex(_ name: String, _ extra: String = "") -> String {
        #"{"session_id":"019a","turn_id":"t1","transcript_path":null,"cwd":"/w/perch","model":"gpt-6","hook_event_name":"\#(name)"\#(extra)}"#
    }

    /// Runs the hook and checks the contract: nothing on stdout or stderr, exit 0.
    func hook(_ cli: CLI, _ agent: String, _ json: String, wait: String? = nil) throws {
        let result = try cli.run(["hook", agent] + (wait.map { ["--wait", $0] } ?? []), stdin: json, env: env)
        #expect(result.status == 0 && result.stdout.isEmpty && result.stderr.isEmpty)
    }

    func session(_ d: TestDaemon, _ id: String) throws -> Session? {
        try d.client.send(Request(op: .sessions)).sessions?.first { $0.id == id }
    }

    @Test func claudeCodeWalksThroughEveryState() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)

        try hook(cli, "claude-code", claude("UserPromptSubmit", #","prompt":"Refactor the state machine\nand add tests""#))
        var s = try #require(try session(d, "s1"))
        #expect(s.status == .running && s.source == "claude-code" && s.title == "perch" && s.cwd == "/Users/me/work/perch")
        #expect(s.prompt == "Refactor the state machine")
        #expect(s.link.flatMap(TerminalLink.init(string:))?.app == "apple_terminal")

        try hook(cli, "claude-code", claude("Notification", #","notification_type":"elicitation_dialog","message":"Which database?""#))
        s = try #require(try session(d, "s1"))
        #expect(s.status == .waiting && s.detail == "Which database?")
        // idle_prompt is not "needs you".
        try hook(cli, "claude-code", claude("Notification", #","notification_type":"idle_prompt","message":"Claude is waiting""#))
        #expect(try session(d, "s1")?.detail == "Which database?")

        try hook(cli, "claude-code", claude("PostToolUse", #","tool_name":"AskUserQuestion","tool_input":{}"#))
        s = try #require(try session(d, "s1"))
        #expect(s.status == .running && s.detail == nil && s.prompt == "Refactor the state machine")

        try hook(cli, "claude-code", claude("Stop", ###","stop_hook_active":false,"last_assistant_message":"## Done\nAll 12 tests pass.""###))
        s = try #require(try session(d, "s1"))
        #expect(s.status == .done && s.lastMessage == "Done")

        #expect(try cli.run("session", "seen", "s1").status == 0)
        #expect(try session(d, "s1")?.status == .idle)

        try hook(cli, "claude-code", claude("UserPromptSubmit", #","prompt":"again""#))
        #expect(try session(d, "s1")?.status == .running)
        try hook(cli, "claude-code", claude("StopFailure", #","error":"rate_limit","error_details":"429","last_assistant_message":"API Error: Rate limit reached""#))
        s = try #require(try session(d, "s1"))
        #expect(s.status == .failed && s.error == "rate_limit")

        // The next prompt clears the failure.
        try hook(cli, "claude-code", claude("UserPromptSubmit", #","prompt":"retry""#))
        s = try #require(try session(d, "s1"))
        #expect(s.status == .running && s.error == nil && s.prompt == "retry")

        try hook(cli, "claude-code", claude("SessionEnd", #","reason":"prompt_input_exit""#))
        #expect(try session(d, "s1") == nil)
    }

    @Test func codexWalksThroughEveryState() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)

        try hook(cli, "codex", codex("UserPromptSubmit", #","prompt":"clean up""#))
        #expect(try session(d, "019a")?.status == .running)

        // Not on the allowlist: needs you, answer in the terminal; no request for the notch.
        try hook(cli, "codex", codex("PermissionRequest", #","tool_name":"Bash","tool_input":{"command":"rm -rf build/","description":null}"#), wait: "20")
        var s = try #require(try session(d, "019a"))
        #expect(s.status == .waiting)
        #expect(s.detail?.hasPrefix("rm -rf build/\nAnswer in the terminal") == true)
        #expect(try d.client.send(Request(op: .list, filter: .init(kind: .request))).items == [])

        try hook(cli, "codex", codex("PostToolUse", #","tool_name":"Bash","tool_input":{"command":"rm -rf build/"},"tool_response":{}"#))
        #expect(try session(d, "019a")?.status == .running)

        try hook(cli, "codex", codex("Stop", #","stop_hook_active":false,"last_assistant_message":null"#))
        s = try #require(try session(d, "019a"))
        #expect(s.status == .done && s.lastMessage == nil)

        try hook(cli, "codex", codex("UserPromptSubmit", #","prompt":"more""#))
        try hook(cli, "codex", codex("Interrupt"))
        #expect(try session(d, "019a")?.status == .idle)

        try hook(cli, "codex", codex("SessionEnd"))
        #expect(try session(d, "019a") == nil)
    }

    @Test func anEventForAnUnknownSessionCreatesIt() throws {
        let d = try TestDaemon()
        try hook(CLI(home: d.home), "claude-code", claude("Stop", #","last_assistant_message":"ok""#, session: "late"))
        let s = try #require(try session(d, "late"))
        #expect(s.status == .done && s.title == "perch" && s.lastMessage == "ok")
    }

    @Test func doneBecomesIdleAfterTenMinutes() throws {
        let clock = Clock(Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
        let d = try TestDaemon(now: clock.read)
        try hook(CLI(home: d.home), "claude-code", claude("Stop", #","last_assistant_message":"ok""#))
        let stream = try d.client.watch()
        clock.advance(SessionRegistry.doneLifetime - 1)
        _ = try d.client.send(Request(op: .ping))
        #expect(try session(d, "s1")?.status == .done)
        clock.advance(1)
        _ = try d.client.send(Request(op: .ping))  // re-arms the timer against the moved clock
        guard case .session(let event) = try stream.nextPush(timeout: 3) else { Issue.record("expected a session event"); return }
        #expect(event.type == .updated && event.session.status == .idle)
        #expect(try session(d, "s1")?.status == .idle)
    }

    @Test func sessionsSurviveARestart() throws {
        let home = TestDaemon.freshHome()
        defer { try? FileManager.default.removeItem(at: home) }
        do {
            let d = try TestDaemon(home: home, removeHome: false)
            try hook(CLI(home: home), "claude-code", claude("UserPromptSubmit", #","prompt":"keep me""#))
            try hook(CLI(home: home), "claude-code", claude("Notification", #","notification_type":"permission_prompt","message":"needs permission""#))
            try? FileManager.default.removeItem(atPath: d.daemon.config.socketPath)  // perchd's startup does this
        }
        let reopened = try TestDaemon(home: home, removeHome: false)
        let s = try #require(try session(reopened, "s1"))
        #expect(s.status == .waiting && s.prompt == "keep me" && s.detail == "needs permission")
    }

    @Test func cliListsAndRemovesSessions() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)
        try hook(cli, "claude-code", claude("UserPromptSubmit", #","prompt":"write the docs""#))
        let listed = try cli.run("session", "ls", "--json").json.sessions ?? []
        #expect(listed.map(\.status) == [.running])
        #expect(listed.first?.prompt == "write the docs")
        let text = try cli.run("session", "ls").stdout
        #expect(text.contains("s1") && text.contains("running") && text.contains("perch") && text.contains("write the docs"))

        let removed = try cli.run("session", "rm", "s1").stdout
        #expect(removed == "removed s1  perch")
        #expect(try session(d, "s1") == nil)
        let missing = try cli.run("session", "rm", "s1", "--json")
        #expect(missing.status != 0 && missing.json.error == "no session with id 's1'")

        // The next event brings it back.
        try hook(cli, "claude-code", claude("Notification", #","notification_type":"agent_needs_input","message":"Pick one""#))
        #expect(try session(d, "s1")?.status == .waiting)
    }

    @Test func watchersSeeSessionUpdated() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        try hook(CLI(home: d.home), "claude-code", claude("Stop", #","last_assistant_message":"ok""#))
        var types: [SessionEventType] = []
        while types.count < 1 {
            if case .session(let event) = try stream.nextPush(timeout: 3) {
                types.append(event.type)
                #expect(event.session.status == .done)
            }
        }
        #expect(types == [.updated])
    }
}

/// Allowlisted PermissionRequests post a request linked to the session; the session resolves it.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct SessionRequestTests {
    let env = ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"]

    func event(_ name: String, _ extra: String = "") -> String {
        #"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"\#(name)"\#(extra)}"#
    }

    let permission = #","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run the tests"}"#

    /// Starts an allowlisted PermissionRequest hook and returns once its request is in the notch.
    func ask(_ d: TestDaemon) throws -> (() throws -> CLI.Result, Item) {
        let finish = try CLI(home: d.home).start(["hook", "claude-code", "--wait", "20"], stdin: event("PermissionRequest", permission), env: env)
        return (finish, try postedRequest(d))
    }

    func session(_ d: TestDaemon) throws -> Session? {
        try d.client.send(Request(op: .sessions)).sessions?.first { $0.id == "s1" }
    }

    @Test func answeringResolvesItAndTheSessionRunsOn() throws {
        let d = try TestDaemon()
        let (finish, request) = try ask(d)
        #expect(request.meta?["session_id"] == "s1")
        let waiting = try #require(try session(d))
        #expect(waiting.status == .waiting && waiting.detail == "npm test")
        _ = try d.client.send(Request(op: .respond, id: request.id, value: "allow"))
        #expect(try finish().stdout.contains(#""behavior":"allow""#))
        #expect(try session(d)?.status == .running)
    }

    @Test(arguments: ["PostToolUse", "Stop", "SessionEnd"])
    func theSessionResolvesIt(_ name: String) throws {
        let d = try TestDaemon()
        let (finish, request) = try ask(d)
        let extra = name == "PostToolUse" ? permission : ""
        let result = try CLI(home: d.home).run(["hook", "claude-code"], stdin: event(name, extra), env: env)
        #expect(result.status == 0 && result.stdout.isEmpty)
        let resolved = try #require(try d.client.send(Request(op: .get, id: request.id)).item)
        #expect(resolved.status == .done && resolved.response == nil)
        // No answer, no decision: the terminal asks (with parallel tools, another tool's PostToolUse can close it).
        let answered = try finish()
        #expect(answered.status == 0 && answered.stdout.isEmpty)
        if name == "PostToolUse" {
            #expect(try session(d)?.detail == "npm test\nAnswer in the terminal")
        }
    }

    @Test func timingOutLeavesItToTheTerminal() throws {
        let d = try TestDaemon()
        let finish = try CLI(home: d.home).start(["hook", "claude-code", "--wait", "1"], stdin: event("PermissionRequest", permission), env: env)
        #expect(try finish().stdout.isEmpty)
        let s = try #require(try session(d))
        #expect(s.status == .waiting && s.detail == "npm test\nAnswer in the terminal")
    }
}

/// Async hooks can arrive out of order: an older report never overrides a newer one.
@Suite struct SessionOrderTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func report(_ d: TestDaemon, _ kind: SessionReport.Kind, at offset: TimeInterval, detail: String? = nil) throws -> Response {
        try d.client.send(Request(op: .sessionReport, report: SessionReport(id: "s1", kind: kind, at: t0.addingTimeInterval(offset),
                                                                          source: "claude-code", title: "perch", detail: detail)))
    }

    @Test func olderReportsAreIgnored() throws {
        let d = try TestDaemon(now: { Date(timeIntervalSince1970: 1_800_000_100) })
        _ = try report(d, .prompt, at: 0)
        _ = try report(d, .stop, at: 10)
        let late = try report(d, .waiting, at: 5, detail: "needs permission")
        #expect(late.ok && late.sessions == [])
        #expect(try d.client.send(Request(op: .sessions)).sessions?.first?.status == .done)

        // Removed at 20: a straggler from before that does not bring it back; a newer event does.
        _ = try report(d, .end, at: 20)
        _ = try report(d, .stop, at: 15)
        #expect(try d.client.send(Request(op: .sessions)).sessions == [])
        _ = try report(d, .prompt, at: 25)
        #expect(try d.client.send(Request(op: .sessions)).sessions?.first?.status == .running)
    }

    @Test func aPermissionPromptKeepsTheCommand() throws {
        let d = try TestDaemon(now: { Date(timeIntervalSince1970: 1_800_000_100) })
        _ = try report(d, .waiting, at: 0, detail: "rm -rf build/")
        _ = try d.client.send(Request(op: .sessionReport, report: SessionReport(
            id: "s1", kind: .waiting, at: t0.addingTimeInterval(6), detail: "Claude needs your permission", keepDetail: true)))
        #expect(try d.client.send(Request(op: .sessions)).sessions?.first?.detail == "rm -rf build/")
    }
}

/// A clock tests can move.
final class Clock: @unchecked Sendable {
    private var now: Date
    private let lock = NSLock()
    init(_ start: Date) { now = start }
    func read() -> Date { lock.withLock { now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { now = now.addingTimeInterval(seconds) } }
}
