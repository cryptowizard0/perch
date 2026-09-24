import Foundation

/// A global shortcut as Carbon wants it (`RegisterEventHotKey`: virtual key code + modifier mask),
/// parsed from text like "opt+shift+space" or "⌥⇧Space" so it can live in a config value.
public struct HotKey: Equatable, Sendable, CustomStringConvertible {
    public var keyCode: UInt32
    /// Carbon modifier bits: cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000.
    public var modifiers: UInt32

    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    /// Quick entry. ⌥⇧ is the Perch family: ⌥⇧A / ⌥⇧D / ⌥⇧O answer and jump (M4).
    public static let quickEntryDefault = HotKey(keyCode: 49, modifiers: option | shift)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// nil when the text names no key, an unknown key, or no modifier (a bare key would hijack typing).
    public init?(_ text: String) {
        var modifiers: UInt32 = 0
        var key: UInt32?
        var rest = Substring(text.lowercased())
        let symbols: [Character: UInt32] = ["⌘": Self.command, "⇧": Self.shift, "⌥": Self.option, "⌃": Self.control]
        while let first = rest.first, let bit = symbols[first] {
            modifiers |= bit
            rest = rest.dropFirst()
        }
        for part in rest.split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " }) where !part.isEmpty {
            switch part {
            case "cmd", "command": modifiers |= Self.command
            case "shift": modifiers |= Self.shift
            case "opt", "option", "alt": modifiers |= Self.option
            case "ctrl", "control": modifiers |= Self.control
            default:
                guard key == nil, let code = Self.keyCodes[String(part)] else { return nil }
                key = code
            }
        }
        guard let key, modifiers != 0 else { return nil }
        self.init(keyCode: key, modifiers: modifiers)
    }

    public var description: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        let name = Self.keyCodes.first { $0.value == keyCode }?.key ?? "#\(keyCode)"
        return s + (name.count == 1 ? name.uppercased() : name.capitalized)
    }

    /// ANSI virtual key codes (Carbon `kVK_*`).
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "space": 49, "return": 36, "tab": 48, "escape": 53,
    ]
}
