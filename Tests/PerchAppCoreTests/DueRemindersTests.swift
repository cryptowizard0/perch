import Foundation
import PerchCore
import Testing
@testable import PerchAppCore

@Suite struct DueRemindersTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func firesOnceWhenTheTimeComes() {
        var reminders = DueReminders(armedAt: start)
        let item = Item(id: "a", title: "reply to X", dueAt: start.addingTimeInterval(600))
        #expect(reminders.take(from: [item], now: start.addingTimeInterval(599)).isEmpty)
        #expect(reminders.take(from: [item], now: start.addingTimeInterval(600)).map(\.id) == ["a"])
        #expect(reminders.take(from: [item], now: start.addingTimeInterval(900)).isEmpty)
    }

    @Test func oldOverdueItemsAreNotAnnouncedAtLaunch() {
        var reminders = DueReminders(armedAt: start)
        let yesterday = Item(id: "old", title: "old", dueAt: start.addingTimeInterval(-86_400))
        let justNow = Item(id: "new", title: "new", dueAt: start.addingTimeInterval(-30))
        #expect(reminders.take(from: [yesterday, justNow], now: start).map(\.id) == ["new"])
    }

    @Test func snoozingAnnouncesAgain() {
        var reminders = DueReminders(armedAt: start)
        var item = Item(id: "a", title: "t", dueAt: start.addingTimeInterval(60))
        #expect(reminders.take(from: [item], now: start.addingTimeInterval(60)).count == 1)
        item.dueAt = start.addingTimeInterval(60 + 1800)
        #expect(reminders.take(from: [item], now: start.addingTimeInterval(120)).isEmpty)
        #expect(reminders.take(from: [item], now: start.addingTimeInterval(1860)).count == 1)
    }

    @Test func onlyActionableItems() {
        var reminders = DueReminders(armedAt: start)
        let at = start.addingTimeInterval(10)
        let items = [
            Item(id: "n", title: "notice", kind: .notice, dueAt: at),
            Item(id: "d", title: "done", status: .done, dueAt: at),
            Item(id: "t", title: "task", dueAt: at),
            Item(id: "w", title: "waiting", status: .waiting, dueAt: at.addingTimeInterval(-5)),
        ]
        #expect(reminders.take(from: items, now: at).map(\.id) == ["w", "t"])
    }
}
