import Darwin
import Foundation

public struct SocketError: Error, CustomStringConvertible {
    public enum Kind: Sendable { case timeout, tooLarge, closed, system }
    public let kind: Kind
    /// `errno` for `.system`, 0 otherwise.
    public let code: Int32
    public let description: String

    public static func system(_ what: String, _ code: Int32 = errno) -> SocketError {
        SocketError(kind: .system, code: code, description: "\(what): \(String(cString: strerror(code)))")
    }
    static let timeout = SocketError(kind: .timeout, code: 0, description: "timed out")
    static let closed = SocketError(kind: .closed, code: 0, description: "connection closed")
}

/// A blocking stream socket with a read buffer, for newline-delimited JSON and minimal HTTP.
public final class BufferedSocket {
    /// Upper bound for one line / one HTTP head. Protects perchd from a peer that never sends `\n`.
    public static let maxMessage = 1 << 20

    public let fd: Int32
    private var buffer: [UInt8] = []

    public init(fd: Int32) {
        self.fd = fd
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    public static func connect(unixPath: String) throws -> BufferedSocket {
        var addr = try unixAddress(unixPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system("socket") }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let error = SocketError.system("connect \(unixPath)")
            Darwin.close(fd)
            throw error
        }
        return BufferedSocket(fd: fd)
    }

    /// `nil` blocks forever. Non-positive values time out almost immediately.
    public func setReadTimeout(_ seconds: TimeInterval?) {
        var tv = timeval()
        if let seconds {
            let s = max(seconds, 0.001)
            tv.tv_sec = Int(s)
            tv.tv_usec = Int32((s - Double(Int(s))) * 1_000_000)
        }
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// One line without the trailing `\n`; `nil` on EOF.
    public func readLine() throws -> Data? {
        try read(until: [0x0A]).map { Data($0) }
    }

    /// Bytes up to (not including) `delimiter`, which is consumed. `nil` on EOF with nothing buffered;
    /// on EOF with a partial message, returns what is left.
    public func read(until delimiter: [UInt8]) throws -> [UInt8]? {
        var searchFrom = 0
        while true {
            if let end = find(delimiter, from: searchFrom) {
                let out = Array(buffer[..<end])
                buffer.removeFirst(end + delimiter.count)
                return out
            }
            searchFrom = max(0, buffer.count - delimiter.count + 1)
            guard buffer.count <= Self.maxMessage else {
                throw SocketError(kind: .tooLarge, code: 0, description: "message larger than \(Self.maxMessage) bytes")
            }
            if try fill() == 0 {
                if buffer.isEmpty { return nil }
                defer { buffer.removeAll() }
                return buffer
            }
        }
    }

    public func read(exactly count: Int) throws -> [UInt8] {
        while buffer.count < count {
            if try fill() == 0 { throw SocketError.closed }
        }
        let out = Array(buffer[..<count])
        buffer.removeFirst(count)
        return out
    }

    public func writeLine(_ data: Data) throws {
        var line = data
        line.append(0x0A)
        try write(line)
    }

    public func write(_ data: Data) throws {
        try Self.writeAll(fd, data)
    }

    public func close() {
        Darwin.close(fd)
    }

    /// Wakes a thread blocked in `read` on this socket (it sees EOF). Safe to call from another thread;
    /// the owner still calls `close()`.
    public func shutdown() {
        Darwin.shutdown(fd, SHUT_RDWR)
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.system("write")
                }
                p += n
                left -= n
            }
        }
    }

    public static func unixAddress(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else {
            throw SocketError(kind: .system, code: ENAMETOOLONG,
                              description: "socket path is \(bytes.count) bytes, max \(capacity - 1): \(path)")
        }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    private func fill() throws -> Int {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                buffer.append(contentsOf: chunk[..<n])
                return n
            }
            if n == 0 { return 0 }
            switch errno {
            case EINTR: continue
            case EAGAIN: throw SocketError.timeout
            case ECONNRESET: return 0
            default: throw SocketError.system("read")
            }
        }
    }

    private func find(_ needle: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, buffer.count >= needle.count else { return nil }
        var i = start
        while i <= buffer.count - needle.count {
            if buffer[i] == needle[0], buffer[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }
}
