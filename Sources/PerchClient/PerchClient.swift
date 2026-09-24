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
public struct PerchClient {
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
