import Foundation
import PerchCore
import Testing
@testable import PerchAppCore

@Suite struct ClickTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let task = Item(id: "t7k2", title: "write docs")
    let waiting = Item(id: "w", title: "claude needs input", status: .waiting)
    let notice = Item(id: "n", title: "codex finished", kind: .notice, expiresAt: Date(timeIntervalSince1970: 1_800_000_300))
    let request = Item(id: "r", title: "npm test", kind: .request, status: .waiting)

    @Test func clickCompletesTasks() {
        #expect(Click.on(task, option: false) == .complete)
        #expect(Click.on(waiting, option: false) == .complete)
        let request = Click.complete.request(for: task)
        #expect(request?.op == .done && request?.id == "t7k2")
    }

    @Test func optionClickSnoozesThirtyMinutesFromNow() {
        #expect(Click.on(task, option: true) == .snooze)
        let request = Click.snooze.request(for: task, now: now)
        #expect(request?.op == .update)
        #expect(request?.patch == .init(dueAt: now.addingTimeInterval(1800)))
    }

    @Test func clickKeepsANoticeAsATask() {
        #expect(Click.on(notice, option: false) == .keep)
        #expect(Click.on(notice, option: true) == .keep)
        #expect(Click.keep.request(for: notice)?.patch == .init(kind: .task))
    }

    @Test func requestsIgnoreClicks() {
        #expect(Click.on(request, option: false) == Click.none)
        #expect(Click.on(request, option: true) == Click.none)
        #expect(Click.none.request(for: request) == nil)
    }
}
