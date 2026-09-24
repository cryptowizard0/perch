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
    @Test func liveActivityFollowsSessions() async throws {
        let d = try TestDaemon()
        _ = try d.client.send(Request(op: .sessionStart, session: Session(id: "a", source: "claude-code", title: "perch",
                                                                          startedAt: Date().addingTimeInterval(-245))))
        let model = QueueModel()
        model.connect(client: d.client)
        defer { model.disconnect() }
        try await until { model.online }
        #expect(model.liveActivity?.text(now: Date()) == "1 agent · 4m")

        _ = try d.client.send(Request(op: .sessionStart, session: Session(id: "b", source: "codex", title: "x")))
        try await until { model.sessions.count == 2 }
        #expect(model.liveActivity?.text(now: Date()) == "2 agents · 4m")

        _ = try d.client.send(Request(op: .sessionEnd, id: "a"))
        _ = try d.client.send(Request(op: .sessionEnd, id: "b"))
        try await until { model.sessions.isEmpty }
        #expect(model.liveActivity == nil)
    }
}
