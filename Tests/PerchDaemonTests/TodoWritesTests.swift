import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// Todo writes from the CLI, inbox.md and plain apps go through perchd to the Reminders bridge (#52). A real perchd,
/// the notch app's model as the bridge over a fake Reminders database, and the real `perch` binary. Checked from
/// outside: what `perch` prints, the fake store's contents, todo.md and inbox.md.
@MainActor
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct TodoWritesTests {
    let support = RemindersBridgeTests()
    let refused = "Todo needs Perch.app running with Reminders access"

    /// Runs `perch` off the main actor, so the bridge (which lives on it) can answer meanwhile.
    func perch(_ d: TestDaemon, _ args: String...) async throws -> CLI.Result {
        let cli = CLI(home: d.home)
        return try await Task.detached { try cli.run(args) }.value
    }

    func listed(_ d: TestDaemon, _ args: String...) async throws -> [Item] {
        let cli = CLI(home: d.home)
        return try await Task.detached { try cli.run(["ls", "--json"] + args).json.items ?? [] }.value
    }

    func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func append(_ text: String, to path: String) throws {
        let handle = try #require(FileHandle(forWritingAtPath: path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    @Test func cliWritesGoThroughTheBridgeAndLsSeesThemAtOnce() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }

        let added = try await perch(d, "add", "Book flights", "-p", "high")
        #expect(added.status == 0)
        let id = added.stdout
        let afterAdd = try await listed(d)
        #expect(afterAdd.map(\.id) == [id])
        #expect(afterAdd.first?.title == "Book flights" && afterAdd.first?.priority == .high)
        let entry = try #require(store.entry(titled: "Book flights"))
        #expect(entry.reminder.priority == 1 && !entry.reminder.completed)
        let external = entry.reminder.externalID

        let updated = try await perch(d, "update", id, "--title", "Book flights to Lisbon", "-p", "low")
        #expect(updated.stdout == "updated \(id)  Book flights to Lisbon")
        #expect(try await listed(d).map(\.title) == ["Book flights to Lisbon"])
        #expect(store.entry(external)?.reminder.title == "Book flights to Lisbon")
        #expect(store.entry(external)?.reminder.priority == 9)

        #expect(try await perch(d, "done", id).stdout == "done \(id)  Book flights to Lisbon")
        #expect(try await listed(d).isEmpty)
        #expect(try await listed(d, "--status", "done").map(\.id) == [id])
        #expect(store.entry(external)?.reminder.completed == true)

        #expect(try await perch(d, "update", id, "--status", "open").status == 0)
        #expect(try await listed(d).map(\.id) == [id])
        #expect(store.entry(external)?.reminder.completed == false)

        #expect(try await perch(d, "rm", id).stdout == "removed \(id)  Book flights to Lisbon")
        #expect(try await listed(d, "--all").isEmpty)
        #expect(store.entries.isEmpty)

        // `update --status dismissed` deletes too.
        let other = try await perch(d, "add", "Throwaway").stdout
        #expect(try await perch(d, "update", other, "--status", "dismissed").status == 0)
        #expect(store.entries.isEmpty)
        #expect(try await listed(d, "--all").isEmpty)
    }

    @Test func withoutABridgeTodoWritesFailAndNothingIsQueued() async throws {
        let d = try TestDaemon()
        // A cached todo, from a bridge that has since gone.
        let gone = try d.bridge([Reminder(externalID: "r1", title: "Buy milk")])
        gone.close()
        try await support.until { !d.daemon.hasBridge }
        let todo = try #require(try await listed(d).first)

        for args in [["add", "Book flights"], ["add", "x", "--status", "done"], ["done", todo.id],
                     ["update", todo.id, "-p", "low"], ["update", todo.id, "--status", "dismissed"], ["rm", todo.id]] {
            let cli = CLI(home: d.home)
            let plain = try await Task.detached { try cli.run(args) }.value
            #expect(plain.status == 1 && plain.stdout.isEmpty)
            #expect(plain.stderr == "perch: \(refused)")
            let json = try await Task.detached { try cli.run(args + ["--json"]) }.value
            #expect(json.status == 1)
            #expect(json.stdout == #"{"error":"\#(refused)","ok":false}"#)
        }

        // A bridge arriving later has nothing to catch up on.
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(store.entries.isEmpty)
    }

    @Test func aLateAckStillRecordsTheKeySoARetryDoesNotDuplicate() async throws {
        let d = try TestDaemon(bridgeTimeout: 0.3)
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }

        store.readDelay = 0.8
        let first = try await perch(d, "add", "Renew passport", "--key", "passport", "--json")
        #expect(first.status == 1)
        #expect(first.json.error?.contains("didn't confirm") == true)
        #expect(store.entries.map(\.reminder.title) == ["Renew passport"])

        store.readDelay = 0
        try await support.until(timeout: 3) { model.todos.openCount == 1 }
        let retry = try await perch(d, "add", "Renew passport", "--key", "passport", "-p", "high")
        #expect(retry.status == 0)
        #expect(store.entries.count == 1 && store.entries.first?.reminder.priority == 1)
        #expect(try await listed(d).map(\.id) == [retry.stdout])
    }

    /// The bridge made the reminder but couldn't read the list afterwards: the writer hears why at once (no waiting for
    /// a snapshot that won't come), and the key is remembered all the same.
    @Test func aWriteMadeButNotShownFailsAtOnceAndKeepsItsKey() async throws {
        let d = try TestDaemon(bridgeTimeout: 5)
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }

        store.readFails = true
        let started = Date()
        let first = try await perch(d, "add", "Call the bank", "--key", "bank")
        #expect(first.status == 1 && Date().timeIntervalSince(started) < 4)
        #expect(first.stderr == "perch: Perch.app made the change but couldn't read Reminders: the database is busy")
        #expect(store.entries.map(\.reminder.title) == ["Call the bank"])

        store.readFails = false
        #expect(try await perch(d, "add", "Call the bank", "--key", "bank", "-p", "high").status == 0)
        #expect(store.entries.count == 1 && store.entries.first?.reminder.priority == 1)

        // Deleted on the phone: the same key makes it anew rather than failing for good.
        store.phoneDelete(try #require(store.entries.first).reminder.externalID)
        try await support.until { model.todos.openCount == 0 }
        let again = try await perch(d, "add", "Call the bank", "--key", "bank", "--json")
        #expect(again.status == 0 && again.json.item?.key == "bank")
        #expect(store.entries.map(\.reminder.title) == ["Call the bank"])
    }

    @Test func dueLinkAndPriorityMapAndReAddingAKeyUpdates() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }

        let added = try await perch(d, "add", "Dentist", "--due", "2030-11-03", "--link", "https://dentist.example",
                                    "-p", "low", "--key", "dentist", "--source", "claude-code", "--meta", "cwd=/tmp",
                                    "--expires", "60", "--json")
        let item = try #require(added.json.item)
        let midnight = try #require(Calendar.current.date(from: DateComponents(year: 2030, month: 11, day: 3)))
        #expect(item.dueAt == midnight && item.dueDateOnly && item.link == "https://dentist.example")
        #expect(item.priority == .low && item.key == "dentist")
        // Not stored for todos: they come from Reminders.
        #expect(item.source == "reminders" && item.meta?["cwd"] == nil && item.expiresAt == nil)
        let entry = try #require(store.entry(titled: "Dentist"))
        #expect(entry.reminder.dueAt == midnight && entry.reminder.dueDateOnly)
        #expect(entry.reminder.url == "https://dentist.example" && entry.reminder.priority == 9)

        // Same key: the same reminder takes the new fields (with a time now, and no link).
        let timed = try #require(ISO8601DateFormatter().date(from: "2030-11-03T09:30:00Z"))
        let again = try await perch(d, "add", "Dentist at 9:30", "--due", "2030-11-03T09:30:00Z", "--key", "dentist",
                                    "-p", "high", "--json")
        #expect(again.json.item?.id == item.id)
        #expect(store.entries.count == 1)
        let after = try #require(store.entry(entry.reminder.externalID))
        #expect(after.reminder.title == "Dentist at 9:30" && after.reminder.priority == 1)
        #expect(after.reminder.dueAt == timed && !after.reminder.dueDateOnly && after.reminder.url == nil)
        #expect(after.reminder.notes == entry.reminder.notes)

        // An identical re-add changes nothing.
        let same = try await perch(d, "add", "Dentist at 9:30", "--due", "2030-11-03T09:30:00Z", "--key", "dentist",
                                   "-p", "high", "--json")
        #expect(same.json.item == again.json.item)

        // Normal is "no priority".
        #expect(try await perch(d, "update", item.id, "-p", "normal").status == 0)
        #expect(store.entry(entry.reminder.externalID)?.reminder.priority == 0)

        // `update --due` and `--no-due`.
        #expect(try await perch(d, "update", item.id, "--due", "2030-12-24").status == 0)
        #expect(store.entry(entry.reminder.externalID)?.reminder.dueDateOnly == true)
        #expect(try await perch(d, "update", item.id, "--no-due").status == 0)
        #expect(store.entry(entry.reminder.externalID)?.reminder.dueAt == nil)
        #expect(try await listed(d).first?.dueAt == nil)
    }

    @Test func aWaitingTaskPromotedToOpenMovesIntoReminders() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }

        let waiting = try await perch(d, "add", "Approve the deploy", "--status", "waiting", "--source", "hermes",
                                      "--key", "deploy", "-p", "high").stdout
        #expect(store.entries.isEmpty)
        let promoted = try await perch(d, "update", waiting, "--status", "open", "--json")
        #expect(promoted.json.item?.id == waiting && promoted.json.item?.status == .open)
        #expect(store.entry(titled: "Approve the deploy")?.reminder.priority == 1)
        let all = try await listed(d, "--all")
        #expect(all.map(\.id) == [waiting] && all.first?.source == "reminders" && all.first?.key == "deploy")

        // The key still reaches it.
        #expect(try await perch(d, "done", "--key", "deploy").status == 0)
        #expect(store.entry(titled: "Approve the deploy")?.reminder.completed == true)

        // A notice kept as a task moves too.
        let notice = try await perch(d, "add", "codex finished", "--kind", "notice", "--source", "codex").stdout
        #expect(try await perch(d, "update", notice, "--kind", "task").status == 0)
        #expect(store.entry(titled: "codex finished") != nil)
        #expect(try await listed(d).map(\.title) == ["codex finished"])
    }

    @Test func todosDoneThisWeekListAndReopen() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let taxes = store.phoneAdd("Filed taxes", completedAt: Date().addingTimeInterval(-2 * 86_400))
        store.phoneAdd("Old news", completedAt: Date().addingTimeInterval(-8 * 86_400))
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        try await support.until { (try? support.cached(d, status: .done))?.count == 1 }

        let done = try await listed(d, "--status", "done")
        #expect(done.map(\.title) == ["Filed taxes"])
        #expect(try await perch(d, "update", try #require(done.first?.id), "--status", "open").status == 0)
        #expect(store.entry(taxes)?.reminder.completed == false)
        #expect(try await listed(d).map(\.title) == ["Filed taxes"])
        #expect(model.todos.openCount == 1)
    }

    @Test func inboxLinesWaitForABridgeThenBecomeReminders() async throws {
        let d = try TestDaemon()
        let inbox = d.daemon.config.inboxPath
        let lines = "# keep me\n- [ ] buy milk\n- [ ] call mom +2h\n"
        try append(lines, to: inbox)
        try await Task.sleep(nanoseconds: UInt64((Daemon.inboxSettle + 0.3) * 1e9))
        #expect(read(inbox) == lines)
        #expect(try await listed(d).isEmpty)

        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        try await support.until { store.entries.count == 2 }
        #expect(Set(store.entries.map(\.reminder.title)) == ["buy milk", "call mom"])
        #expect(store.entry(titled: "call mom")?.reminder.dueAt != nil)
        try await support.until { read(inbox) == "# keep me\n" }
        try await support.until { model.todos.openCount == 2 }
        #expect(read(d.daemon.config.mirrorPath).contains("buy milk"))

        // With the bridge there, a new line goes straight in, from a shell append or an editor's atomic save.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "echo '- [ ] from the shell' >> '\(inbox)'"]
        try shell.run()
        shell.waitUntilExit()
        try await support.until { store.entry(titled: "from the shell") != nil }
        try Data("# keep me\n- [ ] from an editor\n".utf8).write(to: URL(fileURLWithPath: inbox), options: .atomic)
        try await support.until { store.entry(titled: "from an editor") != nil }
        try append("- [ ] after the swap\n", to: inbox)
        try await support.until { store.entry(titled: "after the swap") != nil }
        try await support.until { read(inbox) == "# keep me\n" }
        #expect(store.entries.count == 5)
    }

    /// #6: a line still being written is not absorbed half-done; one without a final newline goes in once it settles.
    @Test func unfinishedInboxLinesWaitForTheRest() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        let inbox = d.daemon.config.inboxPath

        let written = Date()
        try append("- [ ] buy oat", to: inbox)
        try await Task.sleep(nanoseconds: 400_000_000)  // well inside the settle time
        // Only meaningful if this look really came before the settle time (a busy main actor can delay it past that).
        if Date().timeIntervalSince(written) < Daemon.inboxSettle * 0.8 {
            #expect(store.entries.isEmpty && read(inbox) == "- [ ] buy oat")
            try append(" milk\n", to: inbox)
            try await support.until { store.entries.map(\.reminder.title) == ["buy oat milk"] }
            try await support.until { read(inbox) == "" }
        } else {
            try await support.until { read(inbox) == "" }
        }

        try Data("- [ ] first\n- [ ] no newline".utf8).write(to: URL(fileURLWithPath: inbox), options: .atomic)
        try await support.until { store.entry(titled: "first") != nil }
        try await support.until { store.entry(titled: "no newline") != nil }
        try await support.until { read(inbox) == "" }
    }

    /// A line the bridge can't take (the list is gone) stays in the file.
    @Test func inboxLinesTheBridgeRefusesStayInTheFile() async throws {
        let d = try TestDaemon()
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        store.deleteList("Perch")
        try await support.until { model.reminders == .createList }

        let inbox = d.daemon.config.inboxPath
        try append("- [ ] nowhere to go\n", to: inbox)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(read(inbox) == "- [ ] nowhere to go\n")
        let add = try await perch(d, "add", "x")
        #expect(add.status == 1 && add.stderr == "perch: Perch list not found")

        // "Create Perch list": the line goes in, with nothing else touching the file.
        model.createRemindersList()
        try await support.until { store.entry(titled: "nowhere to go") != nil }
        try await support.until { read(inbox) == "" }
    }

    /// An inbox line the bridge makes after perchd stopped waiting leaves the file then, and is never sent twice.
    @Test func anInboxLineMadeLateLeavesTheFileOnce() async throws {
        let d = try TestDaemon(bridgeTimeout: 0.3)
        let store = FakeRemindersStore()
        let model = try await support.bridge(d, store)
        defer { model.disconnect() }
        store.readDelay = 0.8
        let inbox = d.daemon.config.inboxPath
        try append("- [ ] slow one\n", to: inbox)
        try await support.until { store.entry(titled: "slow one") != nil }
        try await Task.sleep(nanoseconds: 500_000_000)  // perchd has given up by now; touch the file meanwhile
        try append("# note\n", to: inbox)
        try await support.until(timeout: 5) { read(inbox) == "# note\n" }
        store.readDelay = 0
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(store.entries.map(\.reminder.title) == ["slow one"])
    }

    @Test func staleTodosSayHowOldTheyAreOnlyWhileNoBridgeIsConnected() async throws {
        let d = try TestDaemon()
        // No todos cached: nothing to say.
        let empty = try await perch(d, "ls")
        #expect(empty.stderr == "nothing here")
        #expect(!(try await perch(d, "ls", "--json")).stdout.contains("todos_as_of"))

        let store = FakeRemindersStore()
        store.phoneAdd("Buy milk")
        var model = try await support.bridge(d, store)
        try await support.until { model.todos.openCount == 1 }
        let live = try await perch(d, "ls")
        #expect(live.stderr.isEmpty && live.stdout.contains("Buy milk"))
        #expect(!(try await perch(d, "ls", "--json")).stdout.contains("todos_as_of"))
        #expect(!read(d.daemon.config.mirrorPath).contains("As of"))

        model.disconnect()
        try await support.until { !d.daemon.hasBridge }
        let stale = try await perch(d, "ls")
        #expect(stale.stdout == live.stdout)
        let json = try await perch(d, "ls", "--json")
        let asOf = try #require(json.json.todosAsOf)
        let hhmm = DateFormatter()
        hhmm.locale = Locale(identifier: "en_US_POSIX")
        hhmm.dateFormat = "HH:mm"
        #expect(stale.stderr == "Todos as of \(hhmm.string(from: asOf)) — Perch.app isn't connected")
        // todo.md is read later, so it carries the day too.
        hhmm.dateFormat = "yyyy-MM-dd HH:mm"
        let mirror = read(d.daemon.config.mirrorPath)
        #expect(mirror.contains("## To do\n\n_As of \(hhmm.string(from: asOf)) — Perch.app isn't connected_\n\n### Perch\n\n- [ ] Buy milk"))
        // Lists without todos stay quiet.
        let requests = try await perch(d, "ls", "--kind", "request")
        #expect(requests.stderr == "nothing here")

        model = try await support.bridge(d, store)
        defer { model.disconnect() }
        #expect(try await perch(d, "ls").stderr.isEmpty)
        #expect(!(try await perch(d, "ls", "--json")).stdout.contains("todos_as_of"))
        try await support.until { !read(d.daemon.config.mirrorPath).contains("As of") }
    }
}
