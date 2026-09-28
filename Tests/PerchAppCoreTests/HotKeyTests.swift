import Testing
@testable import PerchAppCore

@Suite struct HotKeyTests {
    @Test func defaultIsOptionShiftSpace() {
        #expect(HotKey.quickEntryDefault == HotKey(keyCode: 49, modifiers: HotKey.option | HotKey.shift))
        #expect(HotKey.quickEntryDefault.description == "⌥⇧Space")
    }

    @Test func queueShortcuts() {
        #expect(HotKey.approve == HotKey("⌥⇧A"))
        #expect(HotKey.deny == HotKey("⌥⇧D"))
        #expect(HotKey.jump == HotKey("⌥⇧O"))
    }

    @Test func parsesWordsAndSymbols() {
        #expect(HotKey("opt+shift+space") == .quickEntryDefault)
        #expect(HotKey("⌥⇧Space") == .quickEntryDefault)
        #expect(HotKey("alt-shift-SPACE") == .quickEntryDefault)
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
