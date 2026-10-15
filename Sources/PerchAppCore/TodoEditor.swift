import Foundation
import PerchCore

/// The todo popup's state (#43): adding or editing, the title as typed, the chosen priority. `QueueModel` holds it;
/// the popup only draws it and forwards keys. No parsing: the trimmed text is the title exactly.
public struct TodoEditor: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case add
        case edit(id: String)
    }

    public var mode: Mode
    public var title: String
    public var priority: ItemPriority
    /// Opened from the expanded panel ("+ Add a todo", a double-click, Edit…), which stays open meanwhile and has the
    /// popup just below it; otherwise (⌥⇧Space) the popup sits just below the folded notch.
    public var fromPanel: Bool

    public init(mode: Mode, title: String, priority: ItemPriority, fromPanel: Bool) {
        self.mode = mode
        self.title = title
        self.priority = priority
        self.fromPanel = fromPanel
    }

    /// A new todo: empty, Normal.
    public static func add(fromPanel: Bool) -> TodoEditor {
        TodoEditor(mode: .add, title: "", priority: .normal, fromPanel: fromPanel)
    }

    /// An existing todo, prefilled; always from the panel.
    public static func edit(_ item: Item) -> TodoEditor {
        TodoEditor(mode: .edit(id: item.id), title: item.title, priority: item.priority, fromPanel: true)
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
