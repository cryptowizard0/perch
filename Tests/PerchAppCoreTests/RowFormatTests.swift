import Foundation
import PerchCore
import Testing
@testable import PerchAppCore

@Suite struct RowFormatTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func time(_ item: Item) -> String { RowFormat.time(item, now: now, calendar: calendar) }

    @Test func ageForItemsWithoutDue() {
        #expect(time(Item(title: "t", createdAt: now.addingTimeInterval(-12))) == "12s ago")
        #expect(time(Item(title: "t", createdAt: now.addingTimeInterval(-4 * 60))) == "4m ago")
        // Waiting items and requests count from when they (re)started waiting.
        let waiting = Item(title: "w", status: .waiting, createdAt: now.addingTimeInterval(-86_400),
                           updatedAt: now.addingTimeInterval(-30))
        #expect(time(waiting) == "30s ago")
    }

    @Test func dueTimes() {
        #expect(time(Item(title: "t", dueAt: now.addingTimeInterval(25 * 60))) == "in 25m")
        #expect(time(Item(title: "t", dueAt: now.addingTimeInterval(-5 * 60))) == "5m overdue")
        // Beyond a few hours, the clock time reads better: 1_800_000_000 is 2027-01-15 08:00 UTC.
        #expect(time(Item(title: "t", dueAt: now.addingTimeInterval(7 * 3600))) == "15:00")
        #expect(time(Item(title: "t", dueAt: now.addingTimeInterval(3 * 86_400))) == "Jan 18 08:00")
    }

    @Test func sourceSymbols() {
        #expect(RowFormat.symbol(source: "human") == "person.fill")
        #expect(RowFormat.symbol(source: "claude-code") == "sparkle")
        #expect(RowFormat.symbol(source: "codex") == "chevron.left.forwardslash.chevron.right")
        #expect(RowFormat.symbol(source: "hermes") == "paperplane.fill")
        #expect(RowFormat.symbol(source: "some-new-agent") == "cpu")
    }

    @Test func linkTargets() {
        #expect(RowFormat.linkURL("https://github.com/x/pull/42")?.absoluteString == "https://github.com/x/pull/42")
        #expect(RowFormat.linkURL("zed://file/tmp/a.swift")?.scheme == "zed")
        #expect(RowFormat.linkURL("/Users/me/project")?.isFileURL == true)
        #expect(RowFormat.linkURL("~/project")?.path == NSHomeDirectory() + "/project")
        #expect(RowFormat.linkURL("tmux:main:2") == nil)  // not openable yet; how to jump to terminals is M3
        #expect(RowFormat.linkURL("  ") == nil)
        #expect(RowFormat.linkURL(nil) == nil)
    }
}
