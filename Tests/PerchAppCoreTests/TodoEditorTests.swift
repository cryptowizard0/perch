import Foundation
import PerchAppCore
import PerchCore
import Testing

/// The entry popup's state (#43), on its own.
@Suite struct TodoEditorTests {
    @Test func addStartsEmptyOnNormal() {
        let editor = TodoEditor.add(fromPanel: false)
        #expect(editor.mode == .add && editor.title.isEmpty && editor.priority == .normal)
        #expect(!editor.canSubmit && !editor.fromPanel)
    }

    @Test func editStartsFromTheTodo() {
        let item = Item(id: "t7k2", title: "Call Lin", priority: .high)
        let editor = TodoEditor.edit(item)
        #expect(editor.mode == .edit(id: "t7k2") && editor.title == "Call Lin" && editor.priority == .high)
        #expect(editor.canSubmit && editor.fromPanel)
    }

    @Test func blankTitlesCannotBeSubmitted() {
        var editor = TodoEditor.add(fromPanel: true)
        for blank in ["", " ", "  \t ", "\n"] {
            editor.title = blank
            #expect(!editor.canSubmit && editor.submittedTitle == nil)
        }
        editor.title = "  Call Lin @15:00 !h \n"
        #expect(editor.submittedTitle == "Call Lin @15:00 !h")
    }

    @Test func tabCyclesThePriorityBothWays() {
        var editor = TodoEditor.add(fromPanel: false)
        editor.cyclePriority(forward: true)
        #expect(editor.priority == .low)
        editor.cyclePriority(forward: true)
        #expect(editor.priority == .high)
        editor.cyclePriority(forward: true)
        #expect(editor.priority == .normal)
        editor.cyclePriority(forward: false)
        #expect(editor.priority == .high)
        editor.cyclePriority(forward: false)
        #expect(editor.priority == .low)
    }

    // MARK: The larger editor (#53)

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    /// Friday 2026-10-16 10:20 in Shanghai.
    var now: Date { at(16, 10, 20) }

    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func editLoadsNotesDateTimeAndURL() {
        var item = Item(id: "t7k2", title: "Call Lin", priority: .low, dueAt: at(20, 15, 30), link: "https://x.example")
        item.notes = "ask about Friday"
        let editor = TodoEditor.edit(item, now: now, calendar: calendar)
        #expect(editor.notes == "ask about Friday" && editor.url == "https://x.example")
        #expect(editor.hasDate && editor.hasTime && editor.date == at(20, 15, 30))
        #expect(editor.isLarge)

        let dayOnly = TodoEditor.edit(Item(title: "x", dueAt: at(20), dueDateOnly: true), now: now, calendar: calendar)
        #expect(dayOnly.hasDate && !dayOnly.hasTime && dayOnly.date == at(20))
        let none = TodoEditor.edit(Item(title: "x"), now: now, calendar: calendar)
        #expect(!none.hasDate && !none.hasTime && none.notes.isEmpty && none.url.isEmpty)
        #expect(!TodoEditor.add(fromPanel: true).isLarge)
    }

    /// Like Reminders: a date starts today; a time starts at the next hour today, 09:00 on another day; no date, no time.
    @Test func togglingDateAndTime() {
        var editor = TodoEditor.edit(Item(title: "x"), now: now, calendar: calendar)
        editor.setHasTime(true, now: now, calendar: calendar)
        #expect(editor.hasDate && editor.hasTime && editor.date == at(16, 11))
        editor.setHasDate(false, now: now, calendar: calendar)
        #expect(!editor.hasDate && !editor.hasTime)
        editor.setHasDate(true, now: now, calendar: calendar)
        #expect(editor.hasDate && !editor.hasTime && editor.date == at(16))

        var later = TodoEditor.edit(Item(title: "x", dueAt: at(20), dueDateOnly: true), now: now, calendar: calendar)
        later.setHasTime(true, now: now, calendar: calendar)
        #expect(later.date == at(20, 9))
        later.setHasTime(false, now: now, calendar: calendar)
        #expect(later.hasDate && !later.hasTime && later.date == at(20))
    }

    @Test func savingProducesTheEditedTodo() {
        let item = Item(id: "t7k2", title: "Call Lin", priority: .low, dueAt: at(20), dueDateOnly: true)
        var editor = TodoEditor.edit(item, now: now, calendar: calendar)
        editor.title = "  Call Lin back "
        editor.notes = "about Friday"
        editor.setHasTime(true, now: now, calendar: calendar)
        editor.url = " https://x.example "
        editor.priority = .high
        let edited = try! #require(editor.edited(item, calendar: calendar))
        #expect(edited.title == "Call Lin back" && edited.priority == .high && edited.notes == "about Friday")
        #expect(edited.dueAt == at(20, 9) && !edited.dueDateOnly && edited.link == "https://x.example")
        #expect(edited.id == item.id && edited.createdAt == item.createdAt)

        // Cleared fields go away; a blank title saves nothing.
        var clearing = TodoEditor.edit(edited, now: now, calendar: calendar)
        clearing.notes = "  "
        clearing.url = ""
        clearing.setHasDate(false, now: now, calendar: calendar)
        let cleared = try! #require(clearing.edited(edited, calendar: calendar))
        #expect(cleared.notes == nil && cleared.link == nil && cleared.dueAt == nil && !cleared.dueDateOnly)
        clearing.title = " "
        #expect(clearing.edited(edited, calendar: calendar) == nil)
    }
}
