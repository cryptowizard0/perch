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
}
