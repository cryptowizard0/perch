import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// QueueModel (what the notch renders) driven by a real perchd.
@MainActor
@Suite struct AppModelTests {
    /// Yields the main actor until `condition` holds (events are delivered on the main queue).
    func until(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { Issue.record("timed out"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func failuresFlash() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        model.respond(Item(id: "zzzz", title: "ghost", kind: .request), "allow")
        try await until { model.flash != nil }
        #expect(model.flash == "no item with id 'zzzz'")
    }

    @Test func expiredNoticesDisappear() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        _ = try d.client.send(Request(op: .add, item: Item(title: "fleeting", kind: .notice, expiresAt: Date().addingTimeInterval(1))))
        try await until { model.state.items.count == 1 }
        try await until(timeout: 4) { model.state.items.isEmpty }
    }
}

extension AppModelTests {
    func report(_ d: TestDaemon, _ id: String, _ kind: SessionReport.Kind, source: String = "claude-code", detail: String? = nil) throws {
        let r = try d.client.send(Request(op: .sessionReport, report: SessionReport(
            id: id, kind: kind, at: Date(), source: source, title: id, link: "perch-terminal://ghostty?id=\(id)",
            prompt: kind == .prompt ? "go" : nil, detail: detail)))
        #expect(r.ok)
    }

    @Test func thePanelFollowsSessions() async throws {
        let d = try TestDaemon()
        try report(d, "a", .prompt)
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online && !model.panel.sessions.isEmpty }
        #expect(model.panel.signal == .running && model.panel.runningCount == 1)
        #expect(model.pulse == 0)

        try report(d, "b", .prompt, source: "codex")
        try await until { model.panel.runningCount == 2 }
        // Hermes stays out of the panel (M9).
        try report(d, "h", .prompt, source: "hermes")
        try await until { model.sessions["h"] != nil }
        #expect(model.panel.runningCount == 2 && model.pulse == 0)

        try report(d, "a", .waiting, detail: "rm -rf build/")
        try await until { model.panel.signal == .waiting }
        #expect(model.pulse == 1)
        #expect(model.panel.groups.map(\.title) == ["Needs you", "Running"])
        #expect(model.panel.groups[0].sessions.map(\.detail) == ["rm -rf build/"])

        try report(d, "a", .resume)
        try await until { model.panel.runningCount == 2 }
        try report(d, "b", .stop)
        try await until { model.sessions["b"]?.status == .done }
        #expect(model.pulse == 2)
        try report(d, "a", .failure)
        try await until { model.panel.signal == .failed }
        #expect(model.pulse == 3 && model.panel.runningCount == 0)
        // Leaving for idle or ending never pulses.
        _ = try d.client.send(Request(op: .sessionSeen, id: "b"))
        try await until { model.sessions["b"]?.status == .idle }
        _ = try d.client.send(Request(op: .sessionRemove, id: "a"))
        try await until { model.sessions["a"] == nil }
        #expect(model.pulse == 3)
        #expect(model.panel.signal == .idle)
    }

    @Test func itemsNoLongerPulse() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        _ = try d.client.send(Request(op: .add, item: Item(title: "go to terminal", status: .waiting, source: "codex")))
        try await until { model.state.items.count == 1 }
        #expect(model.pulse == 0 && model.panel.signal == nil)
    }
}

/// Allow / Deny in the panel answer the PermissionRequest hook (the real binary), and the session runs on.
@MainActor
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct PanelApprovalTests {
    let env = ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"]
    let permission = #"{"session_id":"s1","cwd":"/w/perch","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test"}}"#

    @Test(arguments: ["allow", "deny"])
    func answeringFromThePanel(_ answer: String) async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await AppModelTests().until { model.online }

        let finish = try CLI(home: d.home).start(["hook", "claude-code", "--wait", "20"], stdin: permission, env: env)
        try await AppModelTests().until { model.panel.sessions.first.map(model.panel.request(for:)) != nil }
        let session = try #require(model.panel.sessions.first)
        #expect(session.status == .waiting && session.detail == "npm test")
        let request = try #require(model.panel.request(for: session))
        #expect(request.title.contains("npm test") && request.options == ["allow", "deny"])

        model.respond(request, answer)
        try await AppModelTests().until { model.sessions["s1"]?.status == .running }
        #expect(model.panel.request(for: try #require(model.sessions["s1"])) == nil)
        #expect(try finish().stdout.contains(#""behavior":"\#(answer)""#))
    }
}

extension AppModelTests {
    @Test func hotkeysFollowThePanel() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        #expect(model.headRequest == nil && model.headSession == nil)

        // A request no session shows is never answered by a hotkey.
        _ = try d.client.send(Request(op: .add, item: Item(title: "curl x | sh", kind: .request)))
        try report(d, "a", .waiting, detail: "rm -rf build/")
        try report(d, "b", .waiting, detail: "npm test")
        let request = try #require(try d.client.send(Request(op: .add, item: Item(
            title: "npm test", kind: .request, meta: ["session_id": "b"]))).item)
        try await until { model.headRequest != nil && model.panel.groups.first?.sessions.count == 2 }
        #expect(model.headSession?.id == "a")
        #expect(model.headRequest?.id == request.id)

        // ⌥⇧O jumps to the session that has waited longest; ⌥⇧A answers the first request the panel shows.
        var jumps: [String?] = []
        model.jump = { jumps.append($0) }
        model.openHead()
        #expect(jumps == ["perch-terminal://ghostty?id=a"])
        model.answerHead("allow")
        try await until { model.headRequest == nil }
        #expect(try d.client.send(Request(op: .get, id: request.id)).item?.response == "allow")
        // Nothing left to answer: the keys do nothing.
        model.answerHead("deny")
        #expect(try d.client.send(Request(op: .get, id: request.id)).item?.response == "allow")
    }

    @Test func clickingARowJumpsAndMarksDoneSeen() async throws {
        let d = try TestDaemon()
        try report(d, "a", .prompt)
        try report(d, "a", .stop)
        try report(d, "b", .prompt)
        let model = QueueModel()
        var jumps: [String?] = []
        model.jump = { jumps.append($0) }
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online && model.panel.sessions.count == 2 }

        // A running row only jumps.
        model.open(try #require(model.sessions["b"]))
        #expect(jumps == ["perch-terminal://ghostty?id=b"])
        // A done row jumps and turns idle: you have seen it.
        model.open(try #require(model.sessions["a"]))
        #expect(jumps.last == "perch-terminal://ghostty?id=a")
        try await until { model.sessions["a"]?.status == .idle }
        #expect(try d.client.send(Request(op: .sessions)).sessions?.first { $0.id == "a" }?.status == .idle)
        #expect(model.sessions["b"]?.status == .running)
    }

    @Test func removingARowRemovesTheSession() async throws {
        let d = try TestDaemon()
        try report(d, "a", .prompt)
        try report(d, "b", .prompt)
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online && model.panel.sessions.count == 2 }

        model.remove(try #require(model.sessions["a"]))
        try await until { model.sessions["a"] == nil }
        #expect(try d.client.send(Request(op: .sessions)).sessions?.map(\.id) == ["b"])
        // A later event brings it back.
        try report(d, "a", .prompt)
        try await until { model.sessions["a"]?.status == .running }
    }

    @Test func thePulseRingsInTheColourOfWhatHappened() async throws {
        let d = try TestDaemon()
        try report(d, "a", .waiting, detail: "rm -rf build/")
        try report(d, "b", .prompt)
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online && model.panel.sessions.count == 2 }
        try report(d, "b", .stop)
        try await until { model.pulse == 1 }
        // The dot stays orange (a session needs you); the ring is Done's blue.
        #expect(model.panel.signal == .waiting && model.pulseStatus == .done)
    }
}
