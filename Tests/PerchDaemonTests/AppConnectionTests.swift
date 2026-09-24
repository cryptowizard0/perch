import Foundation
import PerchAppCore
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

/// The notch app's link to perchd (PerchAppCore.QueueConnection) against a real in-process daemon.
@Suite struct AppConnectionTests {
    /// Collects updates delivered on a private queue.
    final class Recorder: @unchecked Sendable {
        let queue = DispatchQueue(label: "recorder")
        private var updates: [QueueConnection.Update] = []
        private let lock = NSLock()

        func record(_ update: QueueConnection.Update) { lock.withLock { updates.append(update) } }

        /// Waits until `predicate` holds for the updates so far.
        func wait(timeout: TimeInterval = 5, _ predicate: ([QueueConnection.Update]) -> Bool) -> [QueueConnection.Update] {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let now = lock.withLock { updates }
                if predicate(now) { return now }
                Thread.sleep(forTimeInterval: 0.005)
            }
            return lock.withLock { updates }
        }
    }

    func connect(_ socketPath: String, _ recorder: Recorder) -> QueueConnection {
        let connection = QueueConnection(client: PerchClient(socketPath: socketPath), queue: recorder.queue) {
            recorder.record($0)
        }
        connection.start()
        return connection
    }

    @Test func snapshotThenEvents() throws {
        let d = try TestDaemon()
        _ = try d.client.send(Request(op: .add, item: Item(title: "already there")))
        let recorder = Recorder()
        let connection = connect(d.daemon.config.socketPath, recorder)
        defer { connection.stop() }

        let first = recorder.wait { !$0.isEmpty }
        guard case .snapshot(let items) = first.first else { Issue.record("expected a snapshot, got \(first)"); return }
        #expect(items.map(\.title) == ["already there"])

        _ = try d.client.send(Request(op: .add, item: Item(title: "pushed")))
        let all = recorder.wait { $0.count >= 2 }
        guard case .event(let event) = all.last else { Issue.record("expected an event, got \(all)"); return }
        #expect(event.type == .added && event.item.title == "pushed")
    }

    @Test func offlineUntilPerchdStartsThenSnapshots() throws {
        let home = TestDaemon.freshHome()
        let recorder = Recorder()
        let connection = connect(PerchPaths.socket(in: home).path, recorder)
        defer { connection.stop() }

        let offline = recorder.wait { !$0.isEmpty }
        guard case .offline(let why) = offline.first else { Issue.record("expected offline, got \(offline)"); return }
        #expect(why.hasPrefix("perchd is not running"))

        let d = try TestDaemon(home: home)
        _ = try d.client.send(Request(op: .add, item: Item(title: "after start")))
        let updates = recorder.wait { $0.contains { if case .snapshot = $0 { return true } else { return false } } }
        let snapshot = updates.compactMap { if case .snapshot(let items) = $0 { return items } else { return nil } }.first
        #expect(snapshot?.map(\.title) == ["after start"])
    }

    @Test func reportsOfflineWhenPerchdGoesAway() throws {
        let d = try TestDaemon()
        let recorder = Recorder()
        let connection = connect(d.daemon.config.socketPath, recorder)
        defer { connection.stop() }
        _ = recorder.wait { !$0.isEmpty }
        d.server.stop()
        let updates = recorder.wait { $0.contains { if case .offline = $0 { return true } else { return false } } }
        #expect(updates.contains { if case .offline("perchd stopped") = $0 { return true } else { return false } })
    }

    @Test func stopEndsTheConnection() throws {
        let d = try TestDaemon()
        let recorder = Recorder()
        let connection = connect(d.daemon.config.socketPath, recorder)
        _ = recorder.wait { !$0.isEmpty }
        #expect(d.daemon.subscriberCount == 1)
        connection.stop()
        for _ in 0..<200 where d.daemon.subscriberCount > 0 { Thread.sleep(forTimeInterval: 0.01) }
        #expect(d.daemon.subscriberCount == 0)
    }
}
