import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The entry popup through QueueModel against a real perchd (#43): add, edit, delete, the highlight.
@MainActor
@Suite struct TodoEditorModelTests {
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

    func all(_ d: TestDaemon) throws -> [Item] {
        try d.client.send(Request(op: .list, filter: Request.Filter(all: true))).items ?? []
    }

    @Test func returnAddsAndTheEditorStaysOpenEmptyOnNormal() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.openAdd(fromPanel: false)
        #expect(model.editor == .add(fromPanel: false))

        model.editor?.title = "Renew the domain"
        model.cycleEditorPriority(forward: false)  // Normal → High
        #expect(model.submitEditor())
        #expect(model.editor == .add(fromPanel: false))
        model.editor?.title = "Book flights"
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 2 }
        let items = try all(d)
        #expect(Set(items.map(\.title)) == ["Renew the domain", "Book flights"])
        #expect(items.first { $0.title == "Renew the domain" }?.priority == .high)
        #expect(items.first { $0.title == "Book flights" }?.priority == .normal)
        #expect(items.allSatisfy { $0.source == "human" && $0.kind == .task })
    }

    @Test func whatYouTypeIsTheTitleExactly() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.openAdd(fromPanel: false)
        model.editor?.title = "  Call Lin @15:00 !h  "
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 1 }
        let item = try #require(try all(d).first)
        #expect(item.title == "Call Lin @15:00 !h" && item.priority == .normal && item.dueAt == nil)
    }

    @Test func blankInputAddsNothing() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.openAdd(fromPanel: true)
        model.editor?.title = "   "
        #expect(!model.submitEditor())
        #expect(model.editor?.title == "   ")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(try all(d).isEmpty)
    }

    @Test func escapeClosesWithoutAChange() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "x"))).item)
        try await until { model.todos.openCount == 1 }
        model.openEdit(try #require(model.state.items[item.id]))
        model.editor?.title = "changed"
        model.cycleEditorPriority(forward: true)
        model.closeEditor()
        #expect(model.editor == nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        let stored = try #require(try d.client.send(Request(op: .get, id: item.id)).item)
        #expect(stored.title == "x" && stored.priority == .normal)
    }

    @Test func returnInEditSavesTitleAndPriorityAndCloses() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "Call Lin", priority: .low))).item)
        try await until { model.todos.openCount == 1 }
        model.openEdit(try #require(model.state.items[item.id]))
        #expect(model.editor == .edit(item))
        model.editor?.title = " Call Lin back "
        model.cycleEditorPriority(forward: true)  // Low → High
        #expect(model.submitEditor())
        #expect(model.editor == nil)
        try await until { model.state.items[item.id]?.title == "Call Lin back" }
        #expect(model.todos.groups.first?.priority == .high)
        #expect(try d.client.send(Request(op: .get, id: item.id)).item?.priority == .high)
    }

    @Test func anEditedTodoThatGoesAwayClosesTheEditor() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "x"))).item)
        try await until { model.todos.openCount == 1 }
        model.openEdit(try #require(model.state.items[item.id]))
        _ = try d.client.send(Request(op: .done, id: item.id))
        try await until { model.editor == nil }
    }

    @Test func deleteRemovesTheTodoAtOnce() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "x"))).item)
        try await until { model.todos.openCount == 1 }
        model.delete(try #require(model.state.items[item.id]))
        try await until { model.todos.openCount == 0 }
        #expect(try all(d).isEmpty)
    }

    @Test func aTodoAddedWhileThePanelIsOpenHighlightsBriefly() async throws {
        let d = try TestDaemon()
        let model = try await connected(d)
        defer { model.disconnect() }
        model.highlightDuration = 0.3
        // Collapsed: no highlight.
        let quiet = try #require(try d.client.send(Request(op: .add, item: Item(title: "quiet"))).item)
        try await until { model.todos.openCount == 1 }
        #expect(model.highlighted.isEmpty)

        model.expanded = true
        model.openAdd(fromPanel: true)
        model.editor?.title = "new"
        #expect(model.submitEditor())
        try await until { model.todos.openCount == 2 }
        let new = try #require(model.todos.items.first { $0.id != quiet.id })
        #expect(model.highlighted == [new.id])
        // Edits, re-ranks and notices don't highlight.
        model.setPriority(try #require(model.state.items[quiet.id]), .high)
        _ = try d.client.send(Request(op: .add, item: Item(title: "fyi", kind: .notice)))
        try await until { model.todos.groups.first?.priority == .high && model.state.items.count == 3 }
        #expect(model.highlighted == [new.id])
        try await until { model.highlighted.isEmpty }
    }
}
