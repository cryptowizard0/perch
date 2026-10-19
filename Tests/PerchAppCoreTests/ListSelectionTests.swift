import Foundation
import PerchAppCore
import PerchCore
import Testing

/// Which Reminders lists Perch shows, and in what order (#69), against a throwaway defaults domain.
@MainActor
@Suite struct ListSelectionTests {
    let perch = ReminderList(id: "p", title: "Perch", isICloud: true)
    let work = ReminderList(id: "w", title: "Work", isICloud: true)
    let home = ReminderList(id: "h", title: "Home", isICloud: false)

    func defaults() -> UserDefaults {
        let name = "perch-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func upgradingChecksOnlyPerch() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        #expect(selection.resolve(lists: [work, perch, home], perch: perch) == [perch])
        // Every list is known now, in the order Reminders gave them; only "Perch" is checked.
        #expect(selection.order == ["w", "p", "h"])
        #expect(selection.checked == ["p"])
    }

    @Test func perchIsAlwaysCheckedWhereverItIs() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.order = ["w", "h", "p"]
        selection.checked = ["w"]
        #expect(selection.resolve(lists: [perch, work, home], perch: perch) == [work, perch])
        // Unchecking it doesn't stick.
        selection.setChecked("p", false)
        #expect(selection.resolve(lists: [perch, work, home], perch: perch) == [work, perch])
        #expect(Set(selection.checked) == ["w", "p"])
    }

    @Test func newListsGoAtTheEndUnchecked() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.resolve(lists: [perch, work], perch: perch)
        selection.setChecked("w", true)
        let errands = ReminderList(id: "e", title: "Errands", isICloud: true)
        #expect(selection.resolve(lists: [errands, perch, work], perch: perch) == [perch, work])
        #expect(selection.order == ["p", "w", "e"])
    }

    @Test func aMissingListIsLeftOutButNotForgotten() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.order = ["w", "p", "h"]
        selection.checked = ["w", "h", "p"]
        // Gone (deleted, or EventKit didn't list it this time): not shown…
        #expect(selection.resolve(lists: [perch, home], perch: perch) == [perch, home])
        // …but still remembered, so a list that comes back is checked again, in its old place.
        #expect(selection.order == ["w", "p", "h"] && Set(selection.checked) == ["w", "h", "p"])
        #expect(selection.resolve(lists: [perch, home, work], perch: perch) == [work, perch, home])
    }

    @Test func noListsAtAllLeaveTheSelectionAlone() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.order = ["w", "p"]
        selection.checked = ["w", "p"]
        #expect(selection.resolve(lists: [], perch: nil).isEmpty)
        #expect(selection.order == ["w", "p"] && selection.checked == ["w", "p"])
        #expect(selection.resolve(lists: [perch, work], perch: perch) == [work, perch])
    }

    @Test func aRenamedListStaysCheckedInItsPlace() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.order = ["w", "p"]
        selection.checked = ["w", "p"]
        let renamed = ReminderList(id: "w", title: "Office", isICloud: true)
        #expect(selection.resolve(lists: [perch, renamed], perch: perch) == [renamed, perch])
    }

    @Test func reorderingIsKept() {
        let store = defaults()
        let selection = ListSelection(defaults: store, listName: "Perch")
        selection.resolve(lists: [perch, work, home], perch: perch)
        selection.setChecked("h", true)
        selection.order = ["h", "w", "p"]
        // Read back later (the next launch).
        #expect(ListSelection(defaults: store, listName: "Perch").resolve(lists: [perch, work, home], perch: perch) == [home, perch])
        #expect(store.stringArray(forKey: "RemindersOrder.Perch") == ["h", "w", "p"])
        #expect(Set(store.stringArray(forKey: "RemindersChecked.Perch") ?? []) == ["h", "p"])
    }

    @Test func isolatedRunsKeepTheirOwnSelection() {
        let store = defaults()
        let real = ListSelection(defaults: store, listName: "Perch")
        real.resolve(lists: [perch, work], perch: perch)
        real.setChecked("w", true)
        let dev = ReminderList(id: "d", title: "Perch Dev", isICloud: true)
        let isolated = ListSelection(defaults: store, listName: "Perch Dev")
        #expect(isolated.resolve(lists: [perch, work, dev], perch: dev) == [dev])
        #expect(ListSelection.checkedKey(listName: "Perch Dev") == "RemindersChecked.Perch Dev")
        #expect(real.resolve(lists: [perch, work, dev], perch: perch) == [perch, work])
    }

    @Test func withoutPerchTheOtherCheckedListsRemain() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.order = ["p", "w"]
        selection.checked = ["p", "w"]
        #expect(selection.resolve(lists: [work], perch: nil) == [work])
    }

    @Test func draggingReordersAndIsKept() {
        let store = defaults()
        let selection = ListSelection(defaults: store, listName: "Perch")
        selection.resolve(lists: [perch, work, home], perch: perch)
        selection.setChecked("w", true)
        // The Lists… window shows every list in the stored order, then hands back its rows in their new order.
        #expect(selection.ordered([home, work, perch]) == [perch, work, home])
        selection.reorder(["h", "p", "w"])
        let later = ListSelection(defaults: store, listName: "Perch")
        #expect(later.resolve(lists: [perch, work, home], perch: perch) == [perch, work])
        #expect(later.ordered([perch, work, home]) == [home, perch, work])
        #expect(store.stringArray(forKey: "RemindersOrder.Perch") == ["h", "p", "w"])
    }

    @Test func draggingLeavesListsNotShownInTheirPlaces() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        // "x" is missing for now (EventKit didn't list it); the window shows only the other three.
        selection.order = ["p", "x", "w", "h"]
        selection.reorder(["h", "w", "p"])
        #expect(selection.order == ["h", "x", "w", "p"])
        // A list the order doesn't know yet takes a place among the shown ones, or the last.
        selection.reorder(["w", "n", "h", "p"])
        #expect(selection.order == ["w", "x", "n", "h", "p"])
    }

    @Test func checkingAndUncheckingIsKept() {
        let store = defaults()
        let selection = ListSelection(defaults: store, listName: "Perch")
        selection.resolve(lists: [perch, work, home], perch: perch)
        selection.setChecked("h", true)
        selection.setChecked("w", true)
        selection.setChecked("w", false)
        #expect(ListSelection(defaults: store, listName: "Perch").resolve(lists: [perch, work, home], perch: perch) == [perch, home])
        #expect(ListSelection(defaults: store, listName: "Perch Dev").checked.isEmpty)
    }
}
