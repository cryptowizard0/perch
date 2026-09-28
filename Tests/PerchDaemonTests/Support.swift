import Foundation
import PerchClient
import PerchCore
@testable import PerchDaemon

/// A perchd running in-process against a throwaway home under /tmp
/// (short path: Unix socket paths are capped at 103 bytes).
final class TestDaemon {
    let home: URL
    let daemon: Daemon
    let server: Server
    var client: PerchClient { PerchClient(socketPath: daemon.config.socketPath) }
    var httpPort: UInt16 { server.httpPort! }
    /// False to keep the home for a second perchd (restart tests).
    let removeHome: Bool

    init(home: URL = TestDaemon.freshHome(), removeHome: Bool = true, now: @escaping () -> Date = Date.init,
         probe: @escaping ProcessProbe = SystemProcesses.startTime(of:),
         livenessInterval: TimeInterval = SessionRegistry.livenessInterval) throws {
        self.home = home
        self.removeHome = removeHome
        daemon = try Daemon(config: DaemonConfig(home: home), now: now, probe: probe, livenessInterval: livenessInterval)
        server = Server(daemon: daemon)
        try server.listenUnix(path: daemon.config.socketPath)
        try server.listenHTTP(port: 0)
    }

    static func freshHome() -> URL {
        URL(fileURLWithPath: "/tmp/perch-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    deinit {
        server.stop()
        if removeHome { try? FileManager.default.removeItem(at: home) }
    }

    /// Raw HTTP/1.1 exchange over a TCP socket; returns (status, body).
    func http(_ raw: String) throws -> (Int, String) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = httpPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        precondition(rc == 0, "connect failed")
        let socket = BufferedSocket(fd: fd)
        defer { socket.close() }
        socket.setReadTimeout(5)
        try socket.write(Data(raw.utf8))
        let head = String(decoding: try socket.read(until: Array("\r\n\r\n".utf8)) ?? [], as: UTF8.self)
        let status = Int(head.split(separator: " ")[1])!
        let body = String(decoding: try socket.read(until: [0x0A]) ?? [], as: UTF8.self)
        return (status, body)
    }

    func post(_ json: String, headers: String = "") throws -> (Int, String) {
        try http("POST /rpc HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n\(headers)Content-Length: \(json.utf8.count)\r\n\r\n\(json)")
    }
}
