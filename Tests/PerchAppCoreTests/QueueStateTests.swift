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
}
