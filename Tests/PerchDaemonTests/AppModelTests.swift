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

    @Test func clicksReachPerchdAndComeBackAsEvents() async throws {
        let d = try TestDaemon()
        let task = try #require(try d.client.send(Request(op: .add, item: Item(title: "write docs"))).item)
        let notice = try #require(try d.client.send(Request(op: .add, item: Item(
            title: "codex finished", kind: .notice, source: "codex", expiresAt: Date().addingTimeInterval(300)))).item)
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online && model.state.items.count == 2 }

        let before = Date()
        model.click(task, option: true)
        try await until { model.state.items[task.id]?.dueAt != nil }
        let due = try #require(model.state.items[task.id]?.dueAt)
        #expect(abs(due.timeIntervalSince(before) - 1800) < 5)

        model.click(notice, option: false)
        try await until { model.state.items[notice.id]?.kind == .task }
        #expect(model.state.items[notice.id]?.expiresAt == nil)

        model.click(task, option: false)
        try await until { model.state.items[task.id] == nil }
        #expect(try d.client.send(Request(op: .get, id: task.id)).item?.status == .done)
    }

    @Test func failuresFlash() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        model.click(Item(id: "zzzz", title: "ghost"), option: false)
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
    @Test func quickAddParsesTheDueTime() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        #expect(!model.quickAdd("   "))
        #expect(model.quickAdd("回复 X 的邮件 @15:00"))
        try await until { model.state.items.count == 1 }
        let item = try #require(model.state.items.values.first)
        #expect(item.title == "回复 X 的邮件")
        #expect(item.source == "human")
        #expect(Calendar.current.component(.hour, from: try #require(item.dueAt)) == 15)
    }
}

extension AppModelTests {
    @Test func dueTimeFiresReminderAndPulse() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        var reminded: [String] = []
        model.onDue = { reminded.append($0.title) }
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        let pulses = model.pulse
        // perchd stores whole seconds; +1.5 s lands 1–2 s from now.
        _ = try d.client.send(Request(op: .add, item: Item(title: "stand up", dueAt: Date().addingTimeInterval(1.5))))
        try await until { model.state.items.count == 1 }
        #expect(reminded.isEmpty)
        #expect(model.summary.signal == .todo)
        try await until(timeout: 4) { !reminded.isEmpty }
        #expect(reminded == ["stand up"])
        #expect(model.pulse == pulses + 1)
        #expect(model.summary.signal == .overdue)
    }
}

extension AppModelTests {
    func report(_ d: TestDaemon, _ id: String, _ kind: SessionReport.Kind, source: String = "claude-code", detail: String? = nil) throws {
        let r = try d.client.send(Request(op: .sessionReport, report: SessionReport(
            id: id, kind: kind, at: Date(), source: source, title: id, prompt: kind == .prompt ? "go" : nil, detail: detail)))
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
    @Test func headRequestAndRespond() async throws {
        let d = try TestDaemon()
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        #expect(model.headRequest == nil)
        _ = try d.client.send(Request(op: .add, item: Item(title: "a task")))
        let a = try #require(try d.client.send(Request(op: .add, item: Item(title: "npm test", kind: .request))).item)
        let b = try #require(try d.client.send(Request(op: .add, item: Item(title: "pytest", kind: .request))).item)
        try await until { model.state.items.count == 3 }
        // Same second: queue order breaks the tie, and the head follows it.
        let ordered = [a, b].queueOrdered()
        #expect(model.headRequest?.id == ordered[0].id)

        model.respond(ordered[0], "allow")
        try await until { model.state.items[ordered[0].id] == nil }
        #expect(try d.client.send(Request(op: .get, id: ordered[0].id)).item?.response == "allow")
        #expect(model.headRequest?.id == ordered[1].id)
    }
}
