import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

@Suite struct FilesTests {
    func eventually(_ timeout: TimeInterval = 3, _ condition: () throws -> Bool) rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return try condition()
    }

    func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    @Test func mirrorFollowsEveryChangeAndIsReadOnly() throws {
        let d = try TestDaemon()
        let path = d.daemon.config.mirrorPath
        #expect(read(path).contains("Nothing waiting."))
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "review PR #42"))).item)
        #expect(read(path).contains("- [ ] review PR #42 — human · `\(item.id)`"))
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o444)
        _ = try d.client.send(Request(op: .done, id: item.id))
        #expect(!read(path).contains("review PR #42"))
    }

    @Test func inboxLinesBecomeTasksAndAreCleared() throws {
        let d = try TestDaemon()
        let inbox = d.daemon.config.inboxPath
        #expect(FileManager.default.fileExists(atPath: inbox))
        let handle = try #require(FileHandle(forWritingAtPath: inbox))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("# keep me\n- [ ] buy milk\n- [ ] call mom +2h\n".utf8))
        try handle.close()

        #expect(try eventually { (try d.client.send(Request(op: .list)).items?.count ?? 0) == 2 })
        let items = try d.client.send(Request(op: .list)).items ?? []
        #expect(Set(items.map(\.title)) == ["buy milk", "call mom"])
        #expect(items.first { $0.title == "call mom" }?.dueAt != nil)
        #expect(items.allSatisfy { $0.source == "human" })
        #expect(eventually { read(inbox) == "# keep me\n" })
        #expect(eventually { read(d.daemon.config.mirrorPath).contains("buy milk") })
    }

    /// #6: a line still being written (no newline yet) is not absorbed half-done.
    @Test func aHalfWrittenInboxLineWaitsForTheRest() throws {
        let d = try TestDaemon()
        let inbox = d.daemon.config.inboxPath
        let handle = try #require(FileHandle(forWritingAtPath: inbox))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("- [ ] buy oat".utf8))
        Thread.sleep(forTimeInterval: 0.4)  // well inside the settle time
        #expect(try d.client.send(Request(op: .list)).items == [])
        #expect(read(inbox) == "- [ ] buy oat")
        try handle.write(contentsOf: Data(" milk\n".utf8))
        try handle.close()
        #expect(try eventually { try d.client.send(Request(op: .list)).items?.map(\.title) == ["buy oat milk"] })
        #expect(eventually { read(inbox) == "" })
    }

    /// Editors that save without a final newline still get their last line in, once the file settles.
    @Test func aLastLineWithoutNewlineGoesInOnceTheFileSettles() throws {
        let d = try TestDaemon()
        let inbox = d.daemon.config.inboxPath
        try Data("- [ ] first\n- [ ] no newline".utf8).write(to: URL(fileURLWithPath: inbox), options: .atomic)
        #expect(try eventually { try d.client.send(Request(op: .list)).items?.map(\.title) == ["first"] })
        #expect(try eventually { Set(try d.client.send(Request(op: .list)).items?.map(\.title) ?? []) == ["first", "no newline"] })
        #expect(eventually { read(inbox) == "" })
    }

    @Test func inboxWrittenByShellAppendAndAtomicSave() throws {
        let d = try TestDaemon()
        let inbox = d.daemon.config.inboxPath
        // `echo … >> inbox.md`
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "echo '- [ ] from the shell' >> '\(inbox)'"]
        try shell.run()
        shell.waitUntilExit()
        #expect(try eventually { try d.client.send(Request(op: .list)).items?.map(\.title) == ["from the shell"] })

        // An editor replacing the file (new inode).
        try Data("- [ ] from an editor\n".utf8).write(to: URL(fileURLWithPath: inbox), options: .atomic)
        #expect(try eventually { (try d.client.send(Request(op: .list)).items?.count ?? 0) == 2 })

        // And again after the replacement, to prove the watcher re-armed on the new file.
        let handle = try #require(FileHandle(forWritingAtPath: inbox))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("- [ ] after the swap\n".utf8))
        try handle.close()
        #expect(try eventually { (try d.client.send(Request(op: .list)).items?.count ?? 0) == 3 })
    }

    @Test func inboxAlreadyFullAtStartupIsIngested() throws {
        let home = URL(fileURLWithPath: "/tmp/perch-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "- [ ] left over\n".write(to: PerchPaths.inbox(in: home), atomically: true, encoding: .utf8)
        let daemon = try Daemon(config: DaemonConfig(home: home))
        #expect(daemon.perform(Request(op: .list)).items?.map(\.title) == ["left over"])
        #expect(read(PerchPaths.inbox(in: home).path) == "")
    }
}
