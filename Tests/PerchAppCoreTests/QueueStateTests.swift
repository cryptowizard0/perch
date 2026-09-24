import Foundation
import PerchCore
import Testing
@testable import PerchAppCore

@Suite struct QueueStateTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func event(_ type: EventType, _ item: Item) -> Event { Event(type: type, item: item, at: now) }

    @Test func snapshotKeepsOnlyActiveItems() {
        let state = QueueState(items: [
            Item(id: "a", title: "open"), Item(id: "b", title: "done", status: .done),
            Item(id: "c", title: "gone", status: .dismissed), Item(id: "d", title: "w", status: .waiting),
        ])
        #expect(Set(state.items.keys) == ["a", "d"])
    }

    @Test func eventsInsertReplaceAndDrop() {
        var state = QueueState()
        state.apply(event(.added, Item(id: "a", title: "one")))
        state.apply(event(.updated, Item(id: "a", title: "one, renamed")))
        #expect(state.items["a"]?.title == "one, renamed")
        state.apply(event(.updated, Item(id: "a", title: "one", status: .done)))
        #expect(state.items.isEmpty)
        state.apply(event(.added, Item(id: "b", title: "two")))
        state.apply(event(.removed, Item(id: "b", title: "two")))
        #expect(state.items.isEmpty)
        // A closed item reopened by `add --key` comes back.
        state.apply(event(.updated, Item(id: "a", title: "again", status: .waiting)))
        #expect(state.items["a"]?.status == .waiting)
    }

    @Test func orderedUsesTheQueueOrder() {
        let state = QueueState(items: [
            Item(id: "n", title: "notice", kind: .notice),
            Item(id: "t", title: "task"),
            Item(id: "r", title: "request", kind: .request, status: .waiting),
            Item(id: "o", title: "overdue", dueAt: now.addingTimeInterval(-60)),
        ])
        #expect(state.ordered(now: now).map(\.id) == ["r", "o", "t", "n"])
    }

    @Test func signalPriority() {
        func signal(_ items: [Item]) -> Signal { QueueState(items: items).summary(now: now).signal }
        let task = Item(id: "t", title: "task")
        let waiting = Item(id: "w", title: "claude needs input", status: .waiting)
        let request = Item(id: "r", title: "npm test", kind: .request, status: .waiting)
        let overdue = Item(id: "o", title: "late", dueAt: now.addingTimeInterval(-1))
        let notice = Item(id: "n", title: "codex finished", kind: .notice)

        #expect(signal([]) == .idle)
        #expect(signal([notice]) == .idle)
        #expect(signal([task, notice]) == .todo)
        #expect(signal([task, waiting]) == .waiting)
        #expect(signal([task, request]) == .waiting)
        #expect(signal([request, overdue]) == .overdue)
        // A notice with a past due date is not a todo, so it cannot turn the dot red.
        #expect(signal([Item(id: "x", title: "n", kind: .notice, dueAt: now.addingTimeInterval(-60))]) == .idle)
    }

    @Test func countExcludesNotices() {
        let state = QueueState(items: [
            Item(id: "t", title: "task"), Item(id: "r", title: "r", kind: .request, status: .waiting),
            Item(id: "n", title: "notice", kind: .notice),
        ])
        #expect(state.summary(now: now).count == 2)
    }

    @Test func pulsesWhenAnAgentStartsWaiting() {
        var state = QueueState()
        func pulses(_ e: Event) -> Bool { state.apply(e) }
        #expect(pulses(event(.added, Item(id: "r", title: "npm test", kind: .request, status: .waiting))))
        #expect(!pulses(event(.updated, Item(id: "r", title: "npm test (again)", kind: .request, status: .waiting))))
        #expect(!pulses(event(.added, Item(id: "t", title: "a task"))))
        #expect(pulses(event(.updated, Item(id: "t", title: "a task", status: .waiting))))
        #expect(!pulses(event(.added, Item(id: "n", title: "notice", kind: .notice))))
        #expect(!pulses(event(.updated, Item(id: "r", title: "npm test", kind: .request, status: .done))))
    }

    @Test func nextDue() {
        let state = QueueState(items: [
            Item(id: "a", title: "past", dueAt: now.addingTimeInterval(-10)),
            Item(id: "b", title: "soon", dueAt: now.addingTimeInterval(60)),
            Item(id: "c", title: "later", dueAt: now.addingTimeInterval(600)),
            Item(id: "n", title: "notice", kind: .notice, dueAt: now.addingTimeInterval(5)),
        ])
        #expect(state.nextDue(after: now) == now.addingTimeInterval(60))
    }
}
