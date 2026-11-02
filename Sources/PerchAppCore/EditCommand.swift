import Foundation

/// The Edit menu's shortcuts (⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⌘⇧Z). Perch is an agent app with no main menu, so nothing
/// turns these keys into actions; the popup's panel does it itself, so its text fields can cut, copy and paste.
public enum EditCommand: Equatable, Sendable {
    case cut, copy, paste, selectAll, undo, redo

    /// `key` is the key's character ignoring modifiers (layout-aware, like menu key equivalents).
    public init?(key: String, command: Bool, shift: Bool = false, option: Bool = false, control: Bool = false) {
        guard command, !option, !control else { return nil }
        switch (key.lowercased(), shift) {
        case ("x", false): self = .cut
        case ("c", false): self = .copy
        case ("v", false): self = .paste
        case ("a", false): self = .selectAll
        case ("z", false): self = .undo
        case ("z", true): self = .redo
        default: return nil
        }
    }

    /// The first-responder action the Edit menu item would send.
    public var selector: String {
        switch self {
        case .cut: "cut:"
        case .copy: "copy:"
        case .paste: "paste:"
        case .selectAll: "selectAll:"
        case .undo: "undo:"
        case .redo: "redo:"
        }
    }
}
