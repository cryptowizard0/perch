import Testing
@testable import PerchAppCore

@Suite struct HotKeyTests {
    @Test func queueShortcuts() {
        #expect(HotKey.approve == HotKey("⌥⇧A"))
        #expect(HotKey.deny == HotKey("⌥⇧D"))
        #expect(HotKey.jump == HotKey("⌥⇧O"))
        #expect(HotKey.jump.description == "⌥⇧O")
    }

    @Test func parsesWordsAndSymbols() {
        let space = HotKey(keyCode: 49, modifiers: HotKey.option | HotKey.shift)
        #expect(HotKey("opt+shift+space") == space)
        #expect(HotKey("⌥⇧Space") == space)
        #expect(HotKey("alt-shift-SPACE") == space)
        #expect(HotKey("ctrl+cmd+n") == HotKey(keyCode: 45, modifiers: HotKey.control | HotKey.command))
        #expect(HotKey("⌥⇧A") == HotKey(keyCode: 0, modifiers: HotKey.option | HotKey.shift))
    }

    @Test func rejectsNonsense() {
        #expect(HotKey("space") == nil)  // no modifier
        #expect(HotKey("opt+shift") == nil)  // no key
        #expect(HotKey("opt+banana") == nil)
        #expect(HotKey("opt+a+b") == nil)
        #expect(HotKey("") == nil)
    }
}
