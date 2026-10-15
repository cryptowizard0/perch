import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// A clock a second further on at every reading: perchd stamps `created_at` in whole seconds, so todos added in a
/// burst would otherwise tie (and fall back to id order).
final class SteppingClock: @unchecked Sendable {
    private var time = Date()
    private let lock = NSLock()
    func next() -> Date { lock.withLock { time = time.addingTimeInterval(1); return time } }
}

/// The Todo tab's model (#42): QueueModel driven by a real perchd.
@MainActor
@Suite struct TodoModelTests {
    func until(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { Issue.record("timed out"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func connected(_ d: TestDaemon) async throws -> QueueModel {
        let model = QueueModel()
        model.connect(client: d.client)
        try await until { model.online }
        return model
    }

    @discardableResult
    func add(_ d: TestDaemon, _ title: String, _ priority: ItemPriority = .normal, kind: ItemKind = .task) throws -> Item {
        try #require(try d.client.send(Request(op: .add, item: Item(title: title, kind: kind, priority: priority))).item)
    }

    func report(_ d: TestDaemon, _ id: String, _ kind: SessionReport.Kind) throws {
        let r = try d.client.send(Request(op: .sessionReport, report: SessionReport(
            id: id, kind: kind, at: Date(), source: "claude-code", title: id, prompt: kind == .prompt ? "go" : nil,
            detail: kind == .waiting ? "rm -rf build/" : nil)))
        #expect(r.ok)
    }

    @Test func openTasksAreGroupedByPriorityOldestFirst() async throws {
        let clock = SteppingClock()
        let d = try TestDaemon(now: clock.next)
        let model = try await connected(d)
        defer { model.disconnect() }
        #expect(model.todos.summary == "Nothing to do yet." && model.todos.groups.isEmpty)

        let low = try add(d, "read the doc", .low)
        let first = try add(d, "reply to Sam")
        let high = try add(d, "renew the domain", .high)
        let second = try add(d, "book flights")
        try add(d, "codex finished", kind: .notice)
        try add(d, "npm test", kind: .request)
        try await until { model.todos.openCount == 4 }
        #expect(model.todos.groups.map(\.title) == ["High", "Normal", "Low"])
        #expect(model.todos.items.map(\.id) == [high.id, first.id, second.id, low.id])
        #expect(model.todos.summary == "4 open · 1 high")

        for item in [low, first, high, second] { _ = try d.client.send(Request(op: .done, id: item.id)) }
        try await until { model.todos.openCount == 0 }
        #expect(model.todos.summary == "All clear")

        // A fresh connection learns from the done tasks that there have been todos.
        let relaunched = try await connected(d)
        defer { relaunched.disconnect() }
        #expect(relaunched.todos.summary == "All clear")
    }

    @Test func reRankingMovesATodoToItsNewGroup() async throws {
        let clock = SteppingClock()
        let d = try TestDaemon(now: clock.next)
        let model = try await connected(d)
        defer { model.disconnect() }
        let older = try add(d, "older")
        let item = try add(d, "x")
        try add(d, "newest", .high)
        try await until { model.todos.openCount == 3 }

        // From the CLI's side (an `update`).
        _ = try d.client.send(Request(op: .update, id: item.id, patch: Request.Patch(priority: .low)))
        try await until { model.todos.groups.last?.priority == .low }
        #expect(model.todos.groups.last?.items.map(\.id) == [item.id])

        // From the right-click menu: back to High, before the newer High todo (it is older).
        model.setPriority(try #require(model.state.items[item.id]), .high)
        try await until { model.todos.groups.first?.items.count == 2 }
        #expect(model.todos.groups.first?.items.first?.id == item.id)
        #expect(model.todos.groups.map(\.items).last?.map(\.id) == [older.id])
        #expect(try d.client.send(Request(op: .get, id: item.id)).item?.priority == .high)
    }

    @Test func undoWithinTheDelayLeavesTheTodoOpen() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.completionDelay = 0.3
        let item = try add(d, "x")
        try await until { model.todos.openCount == 1 }
        let stream = try d.client.watch()

        model.toggleCompletion(item)
        #expect(model.completing == [item.id])
        model.undoCompletion(item.id)
        #expect(model.completing.isEmpty)
        // Clicking the circle again cancels too.
        model.toggleCompletion(item)
        model.toggleCompletion(item)
        #expect(model.completing.isEmpty)

        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(model.todos.items.map(\.id) == [item.id])
        #expect(try d.client.send(Request(op: .get, id: item.id)).item?.status == .open)
        // No `done` went out: nothing changed at all.
        #expect(throws: ClientError.self) { try stream.next(timeout: 0.1) }
    }

    @Test func aCompletionCommitsAfterTheDelayEvenCollapsed() async throws {
        let clock = SteppingClock()
        let d = try TestDaemon(now: clock.next)
        let model = try await connected(d)
        defer { model.disconnect() }
        model.completionDelay = 0.3
        model.expanded = true
        let item = try add(d, "x")
        let other = try add(d, "y")
        try await until { model.todos.openCount == 2 }

        model.toggleCompletion(item)
        model.expanded = false
        // Still crossed out (and listed) until the delay passes.
        #expect(model.todos.items.map(\.id) == [item.id, other.id] && model.completing == [item.id])
        try await until { model.todos.openCount == 1 }
        #expect(model.completing.isEmpty)
        #expect(try d.client.send(Request(op: .get, id: item.id)).item?.status == .done)
        #expect(model.todos.items.map(\.id) == [other.id])
        // Too late to undo once it is done.
        model.undoCompletion(item.id)
        #expect(try d.client.send(Request(op: .get, id: item.id)).item?.status == .done)
    }

    @Test func aTodoDoneElsewhereStopsItsPendingCompletion() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.completionDelay = 5
        let item = try add(d, "x")
        try await until { model.todos.openCount == 1 }
        model.toggleCompletion(item)
        _ = try d.client.send(Request(op: .remove, id: item.id))
        try await until { model.completing.isEmpty }
        #expect(model.todos.openCount == 0)
    }

    @Test func thePanelOpensOnAgentsWhileOneNeedsYouOrFailed() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.expanded = true
        #expect(model.tab == .agents)
        model.pick(.todo)
        #expect(model.tab == .todo)
        model.expanded = false
        model.expanded = true
        #expect(model.tab == .todo)

        // Open on Todo: a session needing you dots the Agents icon orange and does not switch tabs.
        try report(d, "a", .waiting)
        try await until { model.panel.attention == .waiting }
        #expect(model.tab == .todo)
        model.expanded = false
        model.expanded = true
        #expect(model.tab == .agents)

        // Failed: a red dot, and still Agents first.
        try report(d, "a", .failure)
        try await until { model.panel.attention == .failed }
        model.expanded = false
        model.expanded = true
        #expect(model.tab == .agents)

        // Nothing urgent: back to the tab last picked.
        try report(d, "a", .prompt)
        try await until { model.panel.attention == nil }
        model.expanded = false
        model.expanded = true
        #expect(model.tab == .todo)

        // A relaunch starts on Agents.
        let relaunched = try await connected(d)
        defer { relaunched.disconnect() }
        relaunched.expanded = true
        #expect(relaunched.tab == .agents)
    }

    @Test func todosNeverTouchTheFoldedNotch() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        var chimes: [ChimeSound] = []
        model.onChime = { chimes.append($0) }
        model.completionDelay = 0.05
        let item = try add(d, "x", .high)
        try add(d, "y")
        try await until { model.todos.openCount == 2 }
        model.setPriority(item, .low)
        try await until { model.todos.groups.last?.items.first?.id == item.id }
        model.toggleCompletion(item)
        try await until { model.todos.openCount == 1 }
        #expect(model.pulse == 0 && model.banner == nil && chimes.isEmpty)
        #expect(model.panel.signal == nil && model.panel.runningCount == 0)
    }
}
