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

    @Test func deletedListsAreDroppedSilently() {
        let selection = ListSelection(defaults: defaults(), listName: "Perch")
        selection.order = ["w", "p", "h"]
        selection.checked = ["w", "h", "p"]
        #expect(selection.resolve(lists: [perch, home], perch: perch) == [perch, home])
        #expect(selection.order == ["p", "h"] && Set(selection.checked) == ["h", "p"])
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
}
