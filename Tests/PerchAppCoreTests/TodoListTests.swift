import Foundation
import PerchAppCore
import PerchCore
import Testing

/// The Todo tab for a set of items (#42): groups, order, summary.
@Suite struct TodoListTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func todo(_ id: String, _ priority: ItemPriority = .normal, age: TimeInterval = 0, kind: ItemKind = .task,
              status: ItemStatus = .open) -> Item {
        Item(id: id, title: id, kind: kind, status: status, priority: priority, createdAt: t0.addingTimeInterval(-age))
    }

    @Test func groupsGoHighNormalLowAndSkipEmptyOnes() {
        let list = TodoList(items: [todo("l", .low), todo("h", .high), todo("n1"), todo("n2")])
        #expect(list.groups.map(\.title) == ["High", "Normal", "Low"])
        #expect(list.groups.map(\.items.count) == [1, 2, 1])
        let noHigh = TodoList(items: [todo("l", .low), todo("n")])
        #expect(noHigh.groups.map(\.priority) == [.normal, .low])
        #expect(TodoList(items: [todo("l", .low)]).groups.map(\.title) == ["Low"])
    }

    @Test func theOldestComesFirstInEachGroup() {
        let list = TodoList(items: [todo("new", age: 10), todo("old", age: 300), todo("mid", age: 60),
                                    todo("tie-b", .high, age: 5), todo("tie-a", .high, age: 5)])
        #expect(list.groups[0].items.map(\.id) == ["tie-a", "tie-b"])
        #expect(list.groups[1].items.map(\.id) == ["old", "mid", "new"])
        // Re-ranked: it keeps its place by creation time in its new group.
        var moved = todo("mid", .high, age: 60)
        moved.updatedAt = t0
        let reranked = TodoList(items: [todo("a", .high, age: 120), moved, todo("b", .high, age: 1)])
        #expect(reranked.items.map(\.id) == ["a", "mid", "b"])
    }

    @Test func onlyOpenTasksAreListed() {
        let list = TodoList(items: [
            todo("task"), todo("note", kind: .notice), todo("req", kind: .request, status: .waiting),
            todo("wait", status: .waiting), todo("done", status: .done), todo("gone", status: .dismissed),
        ])
        #expect(list.items.map(\.id) == ["task"])
        #expect(list.openCount == 1)
    }

    @Test func theSummaryLine() {
        let six = (0..<6).map { todo("t\($0)", $0 < 2 ? .high : .normal) }
        #expect(TodoList(items: six).summary == "6 open · 2 high")
        #expect(TodoList(items: [todo("a"), todo("b", .low)]).summary == "2 open")
        #expect(TodoList(items: []).summary == "All clear")
        // One empty state (#51): whether there ever were todos doesn't matter.
        #expect(TodoList(items: [todo("n", kind: .notice), todo("d", status: .done)]).summary == "All clear")
    }

    @Test func heightFollowsTheGroupsAndScrollsPastTheCap() {
        let empty = PanelLayout.todoHeight(TodoList(items: []))
        // The title, and "+ Add a todo" fixed at the bottom.
        #expect(empty == PanelLayout.titleHeight + PanelLayout.addRowHeight)
        let one = PanelLayout.todoHeight(TodoList(items: [todo("a")]))
        #expect(one == empty + PanelLayout.headerHeight + PanelLayout.todoRowHeight)
        let two = PanelLayout.todoHeight(TodoList(items: [todo("a"), todo("b", .high)]))
        #expect(two == one + PanelLayout.headerHeight + PanelLayout.todoRowHeight)
        let many = TodoList(items: (0..<60).map { todo("t\($0)") })
        #expect(PanelLayout.todoHeight(many) == PanelLayout.maxListHeight)
        #expect(PanelLayout.todoHeight(many, online: false) == PanelLayout.titleHeight + PanelLayout.messageHeight)
        // Without the list (Connect Reminders and the like), the message and its button, whatever perchd caches.
        for state in [RemindersState.connect, .openSettings, .createList] {
            #expect(PanelLayout.todoHeight(many, reminders: state) == PanelLayout.titleHeight + PanelLayout.remindersHeight)
        }
        #expect(PanelLayout.todoHeight(many, reminders: .ready(iCloud: false)) == PanelLayout.maxListHeight)
        #expect(PanelLayout.maxListHeight > PanelLayout.titleHeight + PanelLayout.addRowHeight + PanelLayout.todoRowHeight * 10)
        // Each tab is sized for itself.
        let panel = Panel(sessions: [])
        #expect(PanelLayout.listHeight(.todo, panel: panel, todos: many) == PanelLayout.maxListHeight)
        #expect(PanelLayout.listHeight(.agents, panel: panel, todos: many) == PanelLayout.messageHeight)
    }
}

/// Which tab the panel opens on, and the dot on the Agents icon.
@Suite struct PanelTabTests {
    func session(_ id: String, _ status: SessionStatus, source: String = "claude-code") -> Session {
        var s = Session(id: id, source: source, title: id)
        s.status = status
        return s
    }

    @Test func theAgentsDotIsOrangeThenRed() {
        #expect(Panel(sessions: []).attention == nil)
        #expect(Panel(sessions: [session("a", .running), session("b", .done), session("c", .idle)]).attention == nil)
        #expect(Panel(sessions: [session("a", .failed), session("b", .running)]).attention == .failed)
        #expect(Panel(sessions: [session("a", .failed), session("b", .waiting)]).attention == .waiting)
        // Hermes stays out of the panel, and of the dot.
        #expect(Panel(sessions: [session("h", .waiting, source: "hermes")]).attention == nil)
    }

    @Test func agentsWinWhileOneNeedsYouOrFailed() {
        for status in SessionStatus.allCases {
            let panel = Panel(sessions: [session("a", status)])
            let urgent = status == .waiting || status == .failed
            #expect(PanelTab.opening(picked: .todo, panel: panel) == (urgent ? .agents : .todo))
            #expect(PanelTab.opening(picked: .agents, panel: panel) == .agents)
        }
        #expect(PanelTab.opening(picked: .todo, panel: Panel(sessions: [])) == .todo)
    }
}

/// The Todo tab's due dates (#53): a fixed now and calendar, English labels.
@Suite struct DueLabelTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    /// Friday 2026-10-16 10:20 in Shanghai.
    var now: Date { day(16, 10, 20) }

    func day(_ d: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: d, hour: hour, minute: minute))!
    }

    func label(_ due: Date?, dateOnly: Bool = true) -> TodoList.DueLabel? {
        TodoList.dueLabel(Item(title: "x", dueAt: due, dueDateOnly: dateOnly), now: now, calendar: calendar)
    }

    @Test func daysReadTodayTomorrowWeekdayThenDate() {
        #expect(label(nil) == nil)
        #expect(label(day(16))?.text == "Today")
        #expect(label(day(17))?.text == "Tomorrow")
        #expect(label(day(18))?.text == "Sunday")
        #expect(label(day(22))?.text == "Thursday")
        #expect(label(day(23))?.text == "Oct 23")
        #expect(label(day(3, month: 12))?.text == "Dec 3")
        #expect(label(day(5, month: 1, year: 2027))?.text == "Jan 5, 2027")
        #expect(label(day(14))?.text == "Oct 14")
        #expect(label(day(20, month: 6, year: 2025))?.text == "Jun 20, 2025")
    }

    @Test func aTimeIsShownWhenTheReminderHasOne() {
        #expect(label(day(16, 15), dateOnly: false)?.text == "Today 15:00")
        #expect(label(day(17, 9, 5), dateOnly: false)?.text == "Tomorrow 09:05")
        #expect(label(day(23, 18, 30), dateOnly: false)?.text == "Oct 23 18:30")
        #expect(label(day(16, 15), dateOnly: false)?.full == "Friday, October 16, 2026 at 15:00")
        #expect(label(day(16))?.full == "Friday, October 16, 2026")
    }

    /// A whole day is overdue once it is over; a time once it has passed.
    @Test func overdue() {
        #expect(label(day(16))?.overdue == false)
        #expect(label(day(15))?.overdue == true)
        #expect(label(day(16, 9), dateOnly: false)?.overdue == true)
        #expect(label(day(16, 11), dateOnly: false)?.overdue == false)
    }

    /// Dates don't change the order: priority groups, oldest first.
    @Test func datesDontReorder() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let list = TodoList(items: [
            Item(id: "old", title: "old", dueAt: day(30), createdAt: t0),
            Item(id: "new", title: "new", dueAt: day(1), createdAt: t0.addingTimeInterval(60)),
        ])
        #expect(list.items.map(\.id) == ["old", "new"])
    }
}
