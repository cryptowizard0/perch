import Darwin
import Foundation
import PerchClient
import PerchCore

/// Owns perchd's listeners (Unix socket, localhost HTTP) and the open connections.
/// Each connection gets its own thread: there are only ever a handful (CLI calls, the notch app, `--wait`s).
public final class Server {
    public let daemon: Daemon
    public private(set) var httpPort: UInt16?
    private var listeners: [Listener] = []
    private let acceptQueue = DispatchQueue(label: "dev.perch.perchd.accept")
    private let lock = NSLock()
    private var connections: Set<Int32> = []

    public init(daemon: Daemon) {
        self.daemon = daemon
    }

    /// Binds the Unix socket (mode 0600). Fails if `path` exists: the caller decides whether it is stale.
    public func listenUnix(path: String) throws {
        let fd = try Listener.bindUnix(path: path)
        listeners.append(Listener(fd: fd, queue: acceptQueue) { [weak self] in self?.spawn($0, LineConnection.serve) })
    }

    /// Binds `127.0.0.1:port` (0 = any free port; see `httpPort`).
    public func listenHTTP(port: UInt16) throws {
        let (fd, bound) = try Listener.bindLoopback(port: port)
        httpPort = bound
        listeners.append(Listener(fd: fd, queue: acceptQueue) { [weak self] in self?.spawn($0, HTTPConnection.serve) })
    }

    /// Stops accepting and hangs up on every open connection.
    public func stop() {
        listeners.forEach { $0.stop() }
        listeners.removeAll()
        lock.lock()
        connections.forEach { _ = shutdown($0, SHUT_RDWR) }
        lock.unlock()
    }

    private func spawn(_ fd: Int32, _ serve: @escaping (Int32, Daemon) -> Void) {
        lock.lock()
        connections.insert(fd)
        lock.unlock()
        let daemon = daemon
        let thread = Thread { [weak self] in
            serve(fd, daemon)
            self?.lock.lock()
            self?.connections.remove(fd)
            self?.lock.unlock()
            Darwin.close(fd)
        }
        thread.name = "perchd.connection"
        thread.start()
    }
}

/// A non-blocking listening socket drained by a dispatch source.
final class Listener {
    private let source: DispatchSourceRead

    init(fd: Int32, queue: DispatchQueue, onAccept: @escaping (Int32) -> Void) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                // Accepted sockets inherit O_NONBLOCK on BSD; connection threads want blocking I/O.
                _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
                onAccept(client)
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    func stop() {
        source.cancel()
    }

    static func bindUnix(path: String) throws -> Int32 {
        var addr = try BufferedSocket.unixAddress(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { return try fail(fd, "bind \(path)") }
        chmod(path, 0o600)
        guard listen(fd, 64) == 0 else { return try fail(fd, "listen \(path)") }
        return fd
    }

    static func bindLoopback(port: UInt16) throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let rc = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { p -> Int32 in
                guard bind(fd, p, len) == 0 else { return -1 }
                return getsockname(fd, p, &len)
            }
        }
        guard rc == 0 else { return (try fail(fd, "bind 127.0.0.1:\(port)"), 0) }
        guard listen(fd, 64) == 0 else { return (try fail(fd, "listen 127.0.0.1:\(port)"), 0) }
        return (fd, UInt16(bigEndian: addr.sin_port))
    }

    private static func fail(_ fd: Int32, _ what: String) throws -> Int32 {
        let error = SocketError.system(what)
        Darwin.close(fd)
        throw error
    }
}

/// Serializes writes to one connection off the daemon queue, so a slow watcher never blocks perchd.
final class ConnectionWriter {
    private let fd: Int32
    private let queue = DispatchQueue(label: "dev.perch.perchd.write")
    private var broken = false

    init(fd: Int32) {
        self.fd = fd
    }

    func send(_ data: Data) {
        queue.async { [self] in
            guard !broken else { return }
            do { try BufferedSocket.writeAll(fd, data) } catch { broken = true }
        }
    }

    func sendLine(_ response: Response) {
        guard var data = try? PerchJSON.encoder.encode(response) else { return }
        data.append(0x0A)
        send(data)
    }

    /// Blocks until everything queued so far is written.
    func drain() {
        queue.sync {}
    }
}

/// Unix socket protocol: one JSON `Request` per line, one `Response` per line.
/// `watch` turns the connection into an event stream until the client hangs up.
enum LineConnection {
    static func serve(_ fd: Int32, _ daemon: Daemon) {
        let socket = BufferedSocket(fd: fd)
        let writer = ConnectionWriter(fd: fd)
        defer { writer.drain() }
        while let line = try? socket.readLine() {
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            let request: Request
            do {
                request = try PerchJSON.decoder.decode(Request.self, from: line)
            } catch {
                writer.sendLine(.failure("invalid request: \(describe(error))"))
                continue
            }
            if request.op == .watch {
                let id = daemon.subscribe { writer.sendLine($0) }
                while (try? socket.readLine()) != nil {}
                daemon.unsubscribe(id)
                return
            }
            writer.sendLine(daemon.perform(request))
        }
    }
}

/// Human-readable decoding errors, so an agent sending bad JSON learns what to fix.
func describe(_ error: Error) -> String {
    guard let error = error as? DecodingError else { return String(describing: error) }
    func path(_ context: DecodingError.Context) -> String {
        let p = context.codingPath.map(\.stringValue).joined(separator: ".")
        return p.isEmpty ? "" : " at '\(p)'"
    }
    switch error {
    case .keyNotFound(let key, let context):
        return "missing '\(key.stringValue)'\(path(context))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
        return "\(context.debugDescription)\(path(context))"
    case .dataCorrupted(let context):
        return "\(context.debugDescription)\(path(context))"
    @unknown default:
        return String(describing: error)
    }
}
