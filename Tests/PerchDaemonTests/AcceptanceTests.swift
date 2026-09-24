import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// M1 acceptance (docs/MILESTONES.md): two terminals add and watch each other through the real
/// `perch` binary; events arrive with no perceptible delay; repeated --key never duplicates.
@Suite(.enabled(if: CLI.binary != nil, "perch binary not built"))
struct AcceptanceTests {
    @Test func twoTerminalsAddAndWatch() throws {
        let d = try TestDaemon()
        let cli = CLI(home: d.home)

        // Terminal A and B each run `perch watch --json` (a CLI process, not the in-process client).
        let watchA = try cli.start(["watch", "--json"])
        let watchB = try cli.start(["watch", "--json"])
        for _ in 0..<200 where d.daemon.subscriberCount < 2 { Thread.sleep(forTimeInterval: 0.01) }
        #expect(d.daemon.subscriberCount == 2)

        // Each terminal adds; then an agent re-adds the same key four times.
        let idA = try cli.run("add", "from terminal A").stdout
        let idB = try cli.run("add", "from terminal B").stdout
        for n in [1, 2, 3, 3] {
            try cli.run("add", "claude needs input (\(n))", "--status", "waiting", "--source", "claude-code", "--key", "session-42")
        }
        #expect(try cli.run("ls", "--json").json.items?.count == 3)

        // Stop the watchers and check both saw every change, in order.
        Thread.sleep(forTimeInterval: 0.2)
        d.server.stop()  // hanging up ends both `perch watch` processes
        for output in [try watchA(), try watchB()] {
            var lines = output.stdout.split(separator: "\n").map { Data($0.utf8) }
            // With --json the watcher's exit is itself reported as JSON on stdout.
            let last = lines.popLast() ?? Data()
            #expect(try PerchJSON.decoder.decode(Response.self, from: last).error == "perchd stopped")
            #expect(output.status == 1)
            let events = try lines.map { try PerchJSON.decoder.decode(Event.self, from: $0) }
            #expect(events.map(\.type) == [.added, .added, .added, .updated, .updated])
            #expect(events.prefix(2).map(\.item.id) == [idA, idB])
            #expect(Set(events.dropFirst(2).map(\.item.id)).count == 1)
            #expect(events.last?.item.title == "claude needs input (3)")
        }
    }

    @Test func cliToWatcherLatencyIsImperceptible() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        let started = Date()
        try CLI(home: d.home).run("add", "latency probe")
        _ = try stream.next(timeout: 1)
        // Includes launching the perch process; the M2 budget is 200 ms end to end.
        #expect(Date().timeIntervalSince(started) < 0.2)
    }
}
