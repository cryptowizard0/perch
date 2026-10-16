import Foundation
import PerchCore

/// The todo popup's state (#43): adding or editing, the title as typed, the chosen priority. `QueueModel` holds it;
/// the popup only draws it and forwards keys. No parsing: the trimmed text is the title exactly. Editing (#53) is the
/// larger editor, modeled on Reminders' detail view: also notes, a date with an optional time, and a URL.
public struct TodoEditor: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case add
        case edit(id: String)
    }

    public var mode: Mode
    public var title: String
    public var priority: ItemPriority
    /// Opened from the expanded panel ("+ Add a todo", Edit…), which stays open meanwhile and has the
    /// popup just below it; otherwise (⌥⇧Space) the popup sits just below the folded notch.
    public var fromPanel: Bool
    /// The larger editor's fields (unused while adding).
    public var notes = ""
    public var hasDate = false
    /// With `hasDate`: whether there is a time too.
    public var hasTime = false
    /// The day (midnight) without a time, else the day and the time. Meaningless while `hasDate` is off.
    public var date = Date(timeIntervalSinceReferenceDate: 0)
    public var url = ""

    public init(mode: Mode, title: String, priority: ItemPriority, fromPanel: Bool) {
        self.mode = mode
        self.title = title
        self.priority = priority
        self.fromPanel = fromPanel
    }

    /// Editing shows the larger editor; adding stays the small popup.
    public var isLarge: Bool { mode != .add }

    /// A new todo: empty, Normal.
    public static func add(fromPanel: Bool) -> TodoEditor {
        TodoEditor(mode: .add, title: "", priority: .normal, fromPanel: fromPanel)
    }

    /// An existing todo, prefilled; always from the panel.
    public static func edit(_ item: Item, now: Date = Date(), calendar: Calendar = .current) -> TodoEditor {
        var editor = TodoEditor(mode: .edit(id: item.id), title: item.title, priority: item.priority, fromPanel: true)
        editor.notes = item.notes ?? ""
        editor.url = item.link ?? ""
        editor.hasDate = item.dueAt != nil
        editor.hasTime = item.dueAt != nil && !item.dueDateOnly
        editor.date = item.dueAt ?? calendar.startOfDay(for: now)
        return editor
    }

    /// The date switch. On: today (or the day it had); off: no date, and so no time.
    public mutating func setHasDate(_ on: Bool, now: Date, calendar: Calendar = .current) {
        if on && !hasDate { date = calendar.startOfDay(for: now) }
        hasDate = on
        if !on { hasTime = false }
    }

    /// The time switch, like Reminders: on starts at the next hour when the day is today, 09:00 on another day (and
    /// turns the date on); off keeps the day.
    public mutating func setHasTime(_ on: Bool, now: Date, calendar: Calendar = .current) {
        guard on != hasTime else { return }
        if on {
            if !hasDate { setHasDate(true, now: now, calendar: calendar) }
            let day = calendar.startOfDay(for: date)
            if calendar.isDate(day, inSameDayAs: now) {
                date = calendar.dateInterval(of: .hour, for: now)!.end
            } else {
                date = calendar.date(byAdding: .hour, value: 9, to: day)!
            }
        } else {
            date = calendar.startOfDay(for: date)
        }
        hasTime = on
    }

    /// `item` as saving would leave it: title, priority, notes, due date and URL from the editor, everything else as
    /// it was. Nil while the title is blank.
    public func edited(_ item: Item, calendar: Calendar = .current) -> Item? {
        guard let title = submittedTitle else { return nil }
        var edited = item
        edited.title = title
        edited.priority = priority
        edited.notes = notes
        edited.dueAt = hasDate ? (hasTime ? date : calendar.startOfDay(for: date)) : nil
        edited.dueDateOnly = hasDate && !hasTime
        let link = url.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.link = link.isEmpty ? nil : link
        return edited
    }

    /// The title Return would store; nil while blank.
    public var submittedTitle: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var canSubmit: Bool { submittedTitle != nil }

    /// Tab: the next button (High → Normal → Low → High); Shift-Tab: the previous one.
    public mutating func cyclePriority(forward: Bool) {
        let all = ItemPriority.allCases
        let index = all.firstIndex(of: priority)!
        priority = all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }
}
