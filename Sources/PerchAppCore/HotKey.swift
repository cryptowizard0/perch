import Foundation

/// A global shortcut as Carbon wants it (`RegisterEventHotKey`: virtual key code + modifier mask).
public struct HotKey: Equatable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier bits: cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000.
    public var modifiers: UInt32

    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    /// ⌥⇧ is the Perch family. Allow / deny the first request the panel shows; registered only while there is one.
    public static let approve = HotKey(keyCode: 0, modifiers: option | shift)  // kVK_ANSI_A
    public static let deny = HotKey(keyCode: 2, modifiers: option | shift)  // kVK_ANSI_D
    /// Jump to the first Needs-you session; registered only while a session needs you.
    public static let jump = HotKey(keyCode: 31, modifiers: option | shift)  // kVK_ANSI_O

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
