import Foundation
import PerchAppCore
import Testing

@Suite struct DisplayTests {
    // In `NSScreen.screens` order: the first is the main (menu-bar) display.
    let external = DisplayScreen(id: "EXT", name: "U2701B", hasNotch: false)
    let builtIn = DisplayScreen(id: "BUILTIN", name: "Built-in Retina Display", hasNotch: true)

    @Test func automaticPrefersTheNotchElseTheMainDisplay() {
        #expect(DisplayChoice.automatic.screen(in: [external, builtIn]) == 1)
        #expect(DisplayChoice.automatic.screen(in: [external]) == 0)
        #expect(DisplayChoice.automatic.screen(in: []) == nil)
    }

    @Test func mainIsTheFirstScreen() {
        #expect(DisplayChoice.main.screen(in: [external, builtIn]) == 0)
        #expect(DisplayChoice.main.screen(in: [builtIn, external]) == 0)
        #expect(DisplayChoice.main.screen(in: []) == nil)
    }

    @Test func aPinnedDisplayWinsWhileConnectedThenFallsBackToAutomatic() {
        let pinned = DisplayChoice.display(id: "EXT", name: "U2701B")
        #expect(pinned.screen(in: [builtIn, external]) == 1)
        #expect(pinned.screen(in: [external, builtIn]) == 0)
        let gone = DisplayChoice.display(id: "OTHER", name: "Studio Display")
        #expect(gone.screen(in: [external, builtIn]) == 1)
        #expect(gone.screen(in: [external]) == 0)
    }

    @Test func choiceRoundTripsThroughUserDefaults() throws {
        let suite = "perch-display-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DisplayChoice(defaults: defaults) == .automatic)

        for choice in [DisplayChoice.main, .display(id: "EXT", name: "U2701B"), .automatic] {
            choice.save(to: defaults)
            #expect(DisplayChoice(defaults: defaults) == choice)
        }
        #expect(defaults.string(forKey: "Display") == "automatic")
        #expect(defaults.string(forKey: "DisplayName") == nil)

        DisplayChoice.display(id: "EXT", name: "U2701B").save(to: defaults)
        #expect(defaults.string(forKey: "Display") == "EXT")
        #expect(defaults.string(forKey: "DisplayName") == "U2701B")

        // `defaults write … Display main` by hand; a UUID written without a name still pins.
        defaults.set("main", forKey: "Display")
        #expect(DisplayChoice(defaults: defaults) == .main)
        defaults.removeObject(forKey: "DisplayName")
        defaults.set("EXT", forKey: "Display")
        #expect(DisplayChoice(defaults: defaults) == .display(id: "EXT", name: "Display"))
        defaults.set("", forKey: "Display")
        #expect(DisplayChoice(defaults: defaults) == .automatic)
        defaults.set(3, forKey: "Display")
        #expect(DisplayChoice(defaults: defaults) == .automatic)
    }

    @Test func menuListsConnectedDisplaysAndChecksThePinnedOne() {
        let items = DisplayMenu.displays(choice: .display(id: "BUILTIN", name: "Built-in Retina Display"),
                                         screens: [external, builtIn])
        #expect(items == [
            DisplayMenuItem(title: "U2701B", choice: .display(id: "EXT", name: "U2701B"), checked: false, enabled: true),
            DisplayMenuItem(title: "Built-in Retina Display", choice: .display(id: "BUILTIN", name: "Built-in Retina Display"),
                            checked: true, enabled: true),
        ])
        #expect(DisplayMenu.displays(choice: .automatic, screens: [external, builtIn]).allSatisfy { !$0.checked })
        #expect(DisplayMenu.displays(choice: .main, screens: [external, builtIn]).allSatisfy { !$0.checked })
    }

    @Test func menuNumbersDisplaysWithTheSameName() {
        let twin = DisplayScreen(id: "EXT2", name: "U2701B", hasNotch: false)
        let titles = DisplayMenu.displays(choice: .automatic, screens: [external, twin, builtIn]).map(\.title)
        #expect(titles == ["U2701B", "U2701B (2)", "Built-in Retina Display"])
    }

    @Test func menuKeepsAPinnedDisplayThatIsNotConnected() {
        let items = DisplayMenu.displays(choice: .display(id: "OTHER", name: "Studio Display"), screens: [builtIn])
        #expect(items.map(\.title) == ["Built-in Retina Display", "Studio Display (not connected)"])
        #expect(items.last?.checked == true)
        #expect(items.last?.enabled == false)
        #expect(items.first?.checked == false)
    }
}
