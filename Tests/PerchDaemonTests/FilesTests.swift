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
        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "review PR #42", status: .waiting))).item)
        #expect(read(path).contains("- [ ] review PR #42 — human · `\(item.id)`"))
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o444)
        _ = try d.client.send(Request(op: .done, id: item.id))
        #expect(!read(path).contains("review PR #42"))
    }

    /// Inbox lines become reminders through the bridge (#52); with no bridge connected they wait in the file. The rest
    /// of the inbox's behaviour is in `TodoWritesTests`.
    @Test func inboxLinesWaitInTheFileWithoutABridge() throws {
        let d = try TestDaemon()
        let inbox = d.daemon.config.inboxPath
        let lines = "# keep me\n- [ ] buy milk\n- [ ] call mom +2h\n"
        try Data(lines.utf8).write(to: URL(fileURLWithPath: inbox), options: .atomic)
        Thread.sleep(forTimeInterval: Daemon.inboxSettle + 0.3)
        #expect(read(inbox) == lines)
        #expect(try d.client.send(Request(op: .list)).items == [])
    }
}
