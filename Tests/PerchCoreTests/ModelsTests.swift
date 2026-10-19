import Foundation
import Testing
@testable import PerchCore

@Suite struct ModelsTests {
    @Test func itemRoundTripsThroughJSONWithSnakeCaseKeys() throws {
        let item = Item(
            id: "t7k2",
            title: "review PR #42",
            kind: .request,
            status: .waiting,
            source: "claude-code",
            dueAt: Date(timeIntervalSince1970: 1_800_000_000),
            link: "tmux://main:2",
            meta: ["cwd": "/tmp/repo"],
            key: "session-abc",
            options: ["allow", "deny"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try PerchJSON.encoder.encode(item)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"due_at\""))
        #expect(json.contains("\"created_at\""))
        #expect(!json.contains("dueAt"))

        let back = try PerchJSON.decoder.decode(Item.self, from: data)
        #expect(back == item)
    }

    /// A todo carries its list's name as `list` (#69, from `meta`), for `perch ls --json`; it round-trips through meta.
    @Test func aTodoCarriesItsListOnTheWire() throws {
        let todo = Item(id: "t7k2", title: "send the invoice", source: "reminders",
                        meta: [Item.reminderMetaKey: "r1", Item.listIDMetaKey: "w", Item.listNameMetaKey: "Work"],
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let json = String(decoding: try PerchJSON.encoder.encode(todo), as: UTF8.self)
        #expect(json.contains(#""list":"Work""#))
        #expect(try PerchJSON.decoder.decode(Item.self, from: Data(json.utf8)) == todo)
        #expect(!String(decoding: try PerchJSON.encoder.encode(Item(title: "x")), as: UTF8.self).contains(#""list""#))
        // The lists themselves: identifier, name, iCloud.
        let list = String(decoding: try PerchJSON.encoder.encode(ReminderList(id: "w", title: "Work", isICloud: false)), as: UTF8.self)
        #expect(list == #"{"icloud":false,"id":"w","title":"Work"}"#)
    }

    @Test func expiryIsRoundedUpOnTheWire() throws {
        // The wire carries whole-second ISO-8601; truncating would shorten the window an agent asked for.
        let asked = Item(title: "r", kind: .request, expiresAt: Date(timeIntervalSince1970: 1_800_000_000.2))
        let json = String(decoding: try PerchJSON.encoder.encode(asked), as: UTF8.self)
        #expect(json.contains("\"expires_at\":\"2027-01-15T08:00:01Z\""))
        let back = try PerchJSON.decoder.decode(Item.self, from: Data(json.utf8))
        #expect(back.expiresAt == Date(timeIntervalSince1970: 1_800_000_001))

        let whole = Item(title: "r", kind: .request, expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try PerchJSON.decoder.decode(Item.self, from: PerchJSON.encoder.encode(whole)).expiresAt == whole.expiresAt)
    }

    @Test func newIDIsFourCharsFromSafeAlphabet() {
        let alphabet = Set("abcdefghjkmnpqrstuvwxyz23456789")
        for _ in 0..<100 {
            let id = Item.newID()
            #expect(id.count == 4)
            #expect(id.allSatisfy { alphabet.contains($0) })
        }
    }

    @Test func actionable() {
        #expect(Item(title: "a", kind: .task, status: .open).isActionable)
        #expect(Item(title: "a", kind: .request, status: .waiting).isActionable)
        #expect(!Item(title: "a", kind: .notice, status: .open).isActionable)
        #expect(!Item(title: "a", kind: .task, status: .done).isActionable)
    }

    @Test func requestAndResponseEncode() throws {
        let req = Request(op: .add, item: Item(title: "x"))
        let data = try PerchJSON.encoder.encode(req)
        #expect(String(decoding: data, as: UTF8.self).contains("\"op\":\"add\""))
        let res = Response.failure("nope")
        #expect(!res.ok)
        #expect(res.error == "nope")
    }
}

@Suite struct ItemDecodingTests {
    @Test func onlyTitleIsRequired() throws {
        let item = try PerchJSON.decoder.decode(Item.self, from: Data(#"{"title":"hi"}"#.utf8))
        #expect(item.title == "hi")
        #expect(item.priority == .normal)
        #expect(item.kind == .task)
        #expect(item.status == .open)
        #expect(item.source == "human")
        #expect(item.id.count == 4)
    }

    @Test func priorityRoundTripsAndAPatchCarriesIt() throws {
        let item = try PerchJSON.decoder.decode(Item.self, from: Data(#"{"title":"hi","priority":"low"}"#.utf8))
        #expect(item.priority == .low)
        #expect(String(decoding: try PerchJSON.encoder.encode(item), as: UTF8.self).contains(#""priority":"low""#))
        let patch = try PerchJSON.decoder.decode(Request.Patch.self, from: Data(#"{"priority":"high"}"#.utf8))
        #expect(patch.priority == .high && !patch.isEmpty)
        #expect(throws: DecodingError.self) {
            try PerchJSON.decoder.decode(Item.self, from: Data(#"{"title":"hi","priority":"urgent"}"#.utf8))
        }
    }

    @Test func missingTitleIsAnError() {
        #expect(throws: DecodingError.self) { try PerchJSON.decoder.decode(Item.self, from: Data("{}".utf8)) }
    }
}

@Suite struct QueueOrderTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func fixedOrder() {
        let t = { (s: TimeInterval) in self.now.addingTimeInterval(s) }
        let items = [
            Item(id: "dism", title: "", status: .dismissed, updatedAt: t(-1)),
            Item(id: "done", title: "", status: .done, updatedAt: t(-2)),
            Item(id: "note", title: "", kind: .notice),
            Item(id: "late", title: "", dueAt: t(86_400 * 3), createdAt: t(-40)),
            Item(id: "open", title: "", createdAt: t(-30)),
            Item(id: "tday", title: "", dueAt: t(3600), createdAt: t(-20)),
            Item(id: "over", title: "", dueAt: t(-60), createdAt: t(-10)),
            Item(id: "wait", title: "", status: .waiting),
            Item(id: "req2", title: "", kind: .request, status: .waiting, createdAt: t(10)),
            Item(id: "req1", title: "", kind: .request, status: .waiting, createdAt: t(0)),
        ]
        // Open tasks (todos) go oldest first: due dates never reorder them (#69).
        #expect(items.queueOrdered(now: now, calendar: calendar).map(\.id)
                == ["req1", "req2", "wait", "late", "open", "tday", "over", "note", "done", "dism"])
    }

    /// Open tasks go by Reminders list in the selection's order (#69), then priority, then age.
    @Test func openTasksGoByListFirst() {
        func todo(_ id: String, _ list: String?, _ priority: ItemPriority = .normal, _ age: TimeInterval = 0) -> Item {
            Item(id: id, title: "", priority: priority, meta: list.map { [Item.listIDMetaKey: $0] }, createdAt: now.addingTimeInterval(-age))
        }
        let items = [todo("p-hi", "p", .high), todo("w-lo", "w", .low), todo("w-n", "w"), todo("x", "gone"),
                     Item(id: "wait", title: "", status: .waiting), todo("p-old", "p", .normal, 60)]
        #expect(items.queueOrdered(now: now, calendar: calendar, lists: ["w", "p"]).map(\.id)
                == ["wait", "w-n", "w-lo", "p-hi", "p-old", "x"])
    }

    /// Open tasks go High, Normal, Low (#41), each oldest first; requests, waiting items and notices don't move.
    @Test func openTasksGoByPriorityFirst() {
        let t = { (s: TimeInterval) in self.now.addingTimeInterval(s) }
        let items = [
            Item(id: "lowo", title: "", priority: .low, dueAt: t(-60), createdAt: t(-20)),
            Item(id: "low1", title: "", priority: .low, createdAt: t(-10)),
            Item(id: "norm", title: "", dueAt: t(3600), createdAt: t(-5)),
            Item(id: "nrm2", title: "", createdAt: t(-4)),
            Item(id: "hig2", title: "", priority: .high, createdAt: t(5)),
            Item(id: "hig1", title: "", priority: .high, createdAt: t(0)),
            Item(id: "note", title: "", kind: .notice, priority: .high),
            Item(id: "wait", title: "", status: .waiting, priority: .low),
            Item(id: "reqq", title: "", kind: .request, status: .waiting, priority: .low),
            Item(id: "done", title: "", status: .done, priority: .high),
        ]
        #expect(items.queueOrdered(now: now, calendar: calendar).map(\.id)
                == ["reqq", "wait", "hig1", "hig2", "norm", "nrm2", "lowo", "low1", "note", "done"])
    }
}

/// Picking a checked list by name (#70): exact, case-sensitive, and an error that names the checked lists.
@Suite struct ListNameTests {
    let lists = [
        ReminderList(id: "p", title: "Perch", isICloud: true, account: "icloud"),
        ReminderList(id: "w", title: "Work", isICloud: true, account: "icloud"),
        ReminderList(id: "e1", title: "Errands", isICloud: true, account: "icloud"),
        ReminderList(id: "e2", title: "Errands", isICloud: false, account: "local"),
    ]

    func refusal(_ name: String) -> String? {
        do {
            _ = try ReminderList.checked(named: name, in: lists)
            return nil
        } catch {
            return String(describing: error)
        }
    }

    @Test func exactNamesOnly() throws {
        #expect(try ReminderList.checked(named: "Work", in: lists).id == "w")
        #expect(refusal("work") == "no checked Reminders list is called 'work' (names match exactly); checked lists: Perch, Work, Errands, Errands")
        #expect(refusal(" Work")?.hasPrefix("no checked Reminders list is called ' Work'") == true)
        #expect(refusal("Errands") == "2 checked Reminders lists are called 'Errands' (rename one in Reminders); checked lists: Perch, Work, Errands, Errands")
        #expect(throws: RemindersListError.self) { try ReminderList.checked(named: "Perch", in: []) }
    }

    @Test func movesStayWithinAnAccount() {
        #expect(lists[0].moveRefusal(to: lists[1]) == nil)
        #expect(lists[0].moveRefusal(to: lists[3])?.contains("different Reminders accounts") == true)
        // A bridge older than #70 doesn't say: no refusal.
        #expect(ReminderList(id: "x", title: "X", isICloud: true).moveRefusal(to: lists[3]) == nil)
    }
}

/// What Perch changes on a reminder (#52 / #53): the diff from one todo to another, and the alarm a time brings.
@Suite struct ReminderChangeTests {
    let t = Date(timeIntervalSince1970: 1_900_000_000)

    @Test func theDiffHasOnlyWhatChanged() {
        var old = Item(id: "a", title: "x", priority: .low, dueAt: t, dueDateOnly: true, link: "https://a")
        old.notes = "n"
        #expect(ReminderChange(from: old, to: old).isEmpty)
        var new = old
        new.title = "y"
        new.priority = .high
        new.notes = nil
        new.link = nil
        new.dueAt = t.addingTimeInterval(3600)
        new.dueDateOnly = false
        new.status = .done
        #expect(ReminderChange(from: old, to: new) == ReminderChange(
            title: "y", priority: 1, completed: true, dueAt: t.addingTimeInterval(3600), dueDateOnly: false,
            notes: "", clearURL: true))
        var undated = old
        undated.dueAt = nil
        undated.dueDateOnly = false
        #expect(ReminderChange(from: old, to: undated) == ReminderChange(clearDue: true))
    }

    /// Like the Reminders app: a time comes with an alarm at that time, which follows the time; other alarms stay.
    @Test func aTimeBringsItsAlarm() {
        let other = t.addingTimeInterval(-86_400)
        let timed = ReminderChange(dueAt: t, dueDateOnly: false)
        #expect(timed.alarms([], oldDue: nil, oldDueDateOnly: false) == [t])
        #expect(timed.alarms([other], oldDue: nil, oldDueDateOnly: false) == [other, t])
        // Moved: the alarm at the old time moves with it.
        let moved = ReminderChange(dueAt: t.addingTimeInterval(600), dueDateOnly: false)
        #expect(moved.alarms([t, other], oldDue: t, oldDueDateOnly: false) == [other, t.addingTimeInterval(600)])
        // A whole day, or no due date: the time's alarm goes; others stay.
        #expect(ReminderChange(dueAt: t, dueDateOnly: true).alarms([t, other], oldDue: t, oldDueDateOnly: false) == [other])
        #expect(ReminderChange(clearDue: true).alarms([t, other], oldDue: t, oldDueDateOnly: false) == [other])
        // Nothing about the due date: alarms untouched.
        #expect(ReminderChange(title: "y").alarms([t, other], oldDue: t, oldDueDateOnly: false) == [t, other])
        // Already there: not twice.
        #expect(timed.alarms([t], oldDue: t, oldDueDateOnly: false) == [t])
    }
}
