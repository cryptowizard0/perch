import Darwin
import Foundation
import PerchCore

public enum ClientError: Error, CustomStringConvertible {
    case daemonNotRunning(socketPath: String)
    case timeout(TimeInterval)
    case disconnected
    case badResponse(String)
    case transport(String)

    public var description: String {
        switch self {
        case .daemonNotRunning(let path):
            return "perchd is not running (nothing listening on \(path)); start it with `perchd` or install it with `perchd install`"
        case .timeout(let seconds):
            return "perchd did not answer within \(Int(seconds))s"
        case .disconnected:
            return "perchd closed the connection"
        case .badResponse(let why):
            return "unreadable response from perchd: \(why)"
        case .transport(let why):
            return "cannot talk to perchd: \(why)"
        }
    }
}

/// Talks newline-delimited JSON to perchd over the Unix socket.
public struct PerchClient: Sendable {
    public var socketPath: String

    public init(socketPath: String = PerchPaths.socket.path) {
        self.socketPath = socketPath
    }

    /// One request, one response, then the connection is closed.
    public func send(_ request: Request, timeout: TimeInterval = 10) throws -> Response {
        let socket = try connect()
        defer { socket.close() }
        socket.setReadTimeout(timeout)
        do {
            try socket.writeLine(PerchJSON.encoder.encode(request))
            guard let line = try socket.readLine() else { throw ClientError.disconnected }
            return try Self.decodeResponse(line)
        } catch let error as SocketError {
            throw error.kind == .timeout ? ClientError.timeout(timeout) : ClientError.transport(error.description)
        }
    }

    func connect() throws -> BufferedSocket {
        do {
            return try BufferedSocket.connect(unixPath: socketPath)
        } catch let error as SocketError where [ENOENT, ECONNREFUSED].contains(error.code) {
            throw ClientError.daemonNotRunning(socketPath: socketPath)
        } catch let error as SocketError {
            throw ClientError.transport(error.description)
        }
    }

    static func decodeResponse(_ line: Data) throws -> Response {
        do {
            return try PerchJSON.decoder.decode(Response.self, from: line)
        } catch {
            throw ClientError.badResponse(String(describing: error))
        }
    }
}

extension PerchClient {
    /// Subscribes to perchd's events. Returns once perchd has acknowledged the subscription,
    /// so anything that happens after this call is guaranteed to arrive on the stream.
    public func watch() throws -> EventStream {
        let socket = try connect()
        do {
            socket.setReadTimeout(10)
            try socket.writeLine(PerchJSON.encoder.encode(Request(op: .watch)))
            guard let line = try socket.readLine() else { throw ClientError.disconnected }
            let ack = try Self.decodeResponse(line)
            guard ack.ok else { throw ClientError.badResponse(ack.error ?? "watch refused") }
            return EventStream(socket: socket)
        } catch {
            socket.close()
            if let error = error as? SocketError { throw ClientError.transport(error.description) }
            throw error
        }
    }
}

/// Events pushed by perchd, one per `next()`.
public final class EventStream {
    private let socket: BufferedSocket
    private var closed = false

    init(socket: BufferedSocket) {
        self.socket = socket
    }

    deinit {
        close()
    }

    /// The next event, or `nil` when perchd hangs up. `timeout: nil` waits forever;
    /// otherwise throws `ClientError.timeout` when nothing arrives in time.
    public func next(timeout: TimeInterval? = nil) throws -> Event? {
        socket.setReadTimeout(timeout)
        while true {
            let line: Data?
            do {
                line = try socket.readLine()
            } catch let error as SocketError {
                throw error.kind == .timeout ? ClientError.timeout(timeout ?? 0) : ClientError.transport(error.description)
            }
            guard let line else { return nil }
            let response = try PerchClient.decodeResponse(line)
            guard response.ok else { throw ClientError.badResponse(response.error ?? "error on watch stream") }
            if let event = response.event { return event }
        }
    }

    /// Makes a `next()` blocked on another thread return nil. Unlike `close()`, safe to call concurrently.
    public func interrupt() {
        socket.shutdown()
    }

    public func close() {
        guard !closed else { return }
        closed = true
        socket.close()
    }
}
