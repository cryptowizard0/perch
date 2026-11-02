import Testing
@testable import PerchAppCore

@Suite struct EditCommandTests {
    @Test func commandKeysMapToEditActions() {
        #expect(EditCommand(key: "x", command: true) == .cut)
        #expect(EditCommand(key: "c", command: true) == .copy)
        #expect(EditCommand(key: "v", command: true) == .paste)
        #expect(EditCommand(key: "a", command: true) == .selectAll)
        #expect(EditCommand(key: "z", command: true) == .undo)
        #expect(EditCommand(key: "z", command: true, shift: true) == .redo)
        #expect(EditCommand(key: "Z", command: true, shift: true) == .redo)
    }

    @Test func selectorsAreTheEditMenus() {
        #expect(EditCommand.cut.selector == "cut:")
        #expect(EditCommand.copy.selector == "copy:")
        #expect(EditCommand.paste.selector == "paste:")
        #expect(EditCommand.selectAll.selector == "selectAll:")
        #expect(EditCommand.undo.selector == "undo:")
        #expect(EditCommand.redo.selector == "redo:")
    }

    @Test func otherKeysAndModifiersAreLeftAlone() {
        #expect(EditCommand(key: "v", command: false) == nil)  // typing a v
        #expect(EditCommand(key: "q", command: true) == nil)
        #expect(EditCommand(key: "v", command: true, shift: true) == nil)  // ⌘⇧V isn't paste
        #expect(EditCommand(key: "v", command: true, option: true) == nil)
        #expect(EditCommand(key: "c", command: true, control: true) == nil)
        #expect(EditCommand(key: "", command: true) == nil)
    }
}
