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
