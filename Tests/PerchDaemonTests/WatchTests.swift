import Foundation
import PerchClient
import PerchCore
import Testing
@testable import PerchDaemon

@Suite struct WatchTests {
    @Test func watcherReceivesAddedUpdatedRemoved() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()

        let item = try #require(try d.client.send(Request(op: .add, item: Item(title: "watch me", status: .waiting))).item)
        _ = try d.client.send(Request(op: .done, id: item.id))
        _ = try d.client.send(Request(op: .remove, id: item.id))

        let events = try (0..<3).map { _ in try #require(try stream.next(timeout: 5)) }
        #expect(events.map(\.type) == [.added, .updated, .removed])
        #expect(events.allSatisfy { $0.item.id == item.id })
        #expect(events[1].item.status == .done)
    }

    @Test func everyWatcherGetsEveryEvent() throws {
        let d = try TestDaemon()
        let a = try d.client.watch()
        let b = try d.client.watch()
        _ = try d.client.send(Request(op: .add, item: Item(title: "fan out", kind: .notice)))
        #expect(try a.next(timeout: 5)?.item.title == "fan out")
        #expect(try b.next(timeout: 5)?.item.title == "fan out")
    }

    @Test func failedOpsEmitNothing() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        _ = try d.client.send(Request(op: .done, id: "nope"))
        #expect(throws: ClientError.self) { try stream.next(timeout: 0.2) }
    }

    @Test func eventArrivesWellUnder200ms() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        let start = Date()
        _ = try d.client.send(Request(op: .add, item: Item(title: "fast", kind: .notice)))
        _ = try stream.next(timeout: 1)
        #expect(Date().timeIntervalSince(start) < 0.2)
    }

    @Test func disconnectedWatcherIsDropped() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        #expect(d.daemon.subscriberCount == 1)
        stream.close()
        for _ in 0..<50 where d.daemon.subscriberCount > 0 { Thread.sleep(forTimeInterval: 0.01) }
        #expect(d.daemon.subscriberCount == 0)
        #expect(try d.client.send(Request(op: .add, item: Item(title: "nobody listening", kind: .notice))).ok)
    }

    /// One Reminders bridge at a time (#51); every watcher hears when it comes and goes, and the next one can take over.
    @Test func watchersHearWhenTheBridgeComesAndGoes() throws {
        let d = try TestDaemon()
        let other = try d.client.watch()
        let bridge = try d.client.watch()
        #expect(other.watcher != nil && other.watcher != bridge.watcher)
        #expect(try d.client.send(Request(op: .bridgeRegister, watcher: bridge.watcher)).bridge == true)
        #expect(try d.client.send(Request(op: .bridgeRegister, watcher: other.watcher)).bridge == false)
        // Asking again as the bridge is harmless.
        #expect(try d.client.send(Request(op: .bridgeRegister, watcher: bridge.watcher)).bridge == true)
        guard case .bridge(true)? = try other.nextPush(timeout: 5) else { Issue.record("expected the bridge to arrive"); return }
        #expect(d.daemon.hasBridge)

        bridge.close()
        guard case .bridge(false)? = try other.nextPush(timeout: 5) else { Issue.record("expected the bridge to leave"); return }
        #expect(!d.daemon.hasBridge)
        #expect(try d.client.send(Request(op: .bridgeRegister, watcher: other.watcher)).bridge == true)
        // `next()` (items only) never sees bridge pushes.
        let items = try d.client.watch()
        other.close()
        _ = try d.client.send(Request(op: .add, item: Item(title: "after", kind: .notice)))
        #expect(try items.next(timeout: 5)?.item.title == "after")
    }

    /// The bridge is the notch app over the Unix socket; nothing on the HTTP port can take its place.
    @Test func httpCannotBeTheBridge() throws {
        let d = try TestDaemon()
        let stream = try d.client.watch()
        for op in ["bridge_register", "todo_snapshot"] {
            let (status, body) = try d.post(#"{"op":"\#(op)","watcher":"\#(stream.watcher!)","reminders":[]}"#)
            #expect(status == 200 && body.contains(#""ok":false"#) && body.contains("Unix socket"))
        }
        #expect(!d.daemon.hasBridge)
    }

    @Test func watchOverHTTPStreamsNDJSON() throws {
        let d = try TestDaemon()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = d.httpPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        let http = BufferedSocket(fd: fd)
        defer { http.close() }
        http.setReadTimeout(5)
        let body = #"{"op":"watch"}"#
        try http.write(Data("POST /rpc HTTP/1.1\r\nHost: host.docker.internal:7331\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8))
        let head = String(decoding: try http.read(until: Array("\r\n\r\n".utf8)) ?? [], as: UTF8.self)
        #expect(head.hasPrefix("HTTP/1.1 200"))
        #expect(head.contains("application/x-ndjson"))
        let ack = try PerchJSON.decoder.decode(Response.self, from: try #require(try http.readLine()))
        #expect(ack.ok)

        _ = try d.client.send(Request(op: .add, item: Item(title: "to hermes", status: .waiting)))
        let pushed = try PerchJSON.decoder.decode(Response.self, from: try #require(try http.readLine()))
        #expect(pushed.event?.type == .added)
        #expect(pushed.event?.item.title == "to hermes")
    }
}
