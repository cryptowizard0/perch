import Foundation
import Testing
@testable import PerchCore

@Suite struct MirrorTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

    @Test func rendersSectionsInQueueOrder() {
        let items = [
            Item(id: "note", title: "codex finished", kind: .notice, source: "codex"),
            Item(id: "task", title: "reply to X", dueAt: now.addingTimeInterval(7 * 3600)),
            Item(id: "wait", title: "needs input", status: .waiting, source: "claude-code", link: "tmux://main:2"),
            Item(id: "reqq", title: "npm test", kind: .request, status: .waiting, source: "claude-code"),
            Item(id: "gone", title: "closed", status: .done),
        ]
        #expect(MirrorRenderer.render(items, now: now, calendar: calendar) == """
        \(MirrorRenderer.header)

        # Perch

        ## Waiting on you

        - [ ] npm test — request · claude-code · `reqq`
        - [ ] needs input — claude-code · tmux://main:2 · `wait`

        ## To do

        - [ ] reply to X — due 2027-01-15 15:00 · human · `task`

        ## Notices

        - codex finished — codex · `note`

        """)
    }

    @Test func emptyQueue() {
        #expect(MirrorRenderer.render([], now: now).hasSuffix("# Perch\n\nNothing waiting.\n"))
    }
}

@Suite struct InboxTests {
    @Test func absorbsOpenCheckboxesAndKeepsEverythingElse() {
        let parsed = Inbox.parse("""
        # my inbox
        - [ ] buy milk
          * [ ] call mom @18:00
        - [x] already done
        -[ ] not a checkbox
        - [ ]
        some note
        """)
        #expect(parsed.entries == ["buy milk", "call mom @18:00"])
        #expect(parsed.remainder == "# my inbox\n- [x] already done\n-[ ] not a checkbox\nsome note")
    }

    @Test func onlyEntriesLeavesAnEmptyFile() {
        #expect(Inbox.parse("- [ ] a\n- [ ] b\n\n") == Inbox.Parsed(entries: ["a", "b"], remainder: ""))
    }

    /// A last line without its newline may still be being written (#6): it stays, and `pending` says so.
    @Test func anUnterminatedLastEntryWaits() {
        let parsed = Inbox.parse("# notes\n- [ ] done typing\n- [ ] still typ")
        #expect(parsed.entries == ["done typing"])
        #expect(parsed.remainder == "# notes\n- [ ] still typ")
        #expect(parsed.pending)
        // Once the file has stopped changing, it goes in after all.
        let settled = Inbox.parse("# notes\n- [ ] done typing\n- [ ] still typ", absorbUnterminated: true)
        #expect(settled.entries == ["done typing", "still typ"] && settled.remainder == "# notes" && !settled.pending)
        // Terminated, or not an entry: nothing to wait for.
        #expect(!Inbox.parse("- [ ] a\n").pending)
        #expect(!Inbox.parse("- [ ] a\nsome note").pending)
        #expect(Inbox.parse("- [ ] only").entries.isEmpty)
    }
}

@Suite struct QuickEntryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func trailingDueToken() throws {
        let (title, due) = QuickEntry.parse("回复 X 的邮件 +30m", now: now)
        #expect(title == "回复 X 的邮件")
        #expect(due == now.addingTimeInterval(1800))
        #expect(QuickEntry.parse("call mom @18:00", now: now).due != nil)
    }

    @Test func noValidTokenKeepsWholeTitle() {
        #expect(QuickEntry.parse("email @alice", now: now) == ("email @alice", nil))
        #expect(QuickEntry.parse("+30m", now: now) == ("+30m", nil))
        #expect(QuickEntry.parse("plain", now: now) == ("plain", nil))
    }
}
