import Foundation
import PerchClient
import PerchCore

/// `POST /rpc` on 127.0.0.1 — the same JSON as the Unix socket, for clients that cannot reach it
/// (Hermes in Docker via `host.docker.internal`). One request per connection.
///
/// A browser must never be able to drive this port (a web page approving a permission request would be
/// a hole), so requests carrying `Origin`, a non-JSON `Content-Type` or an unexpected `Host` are refused.
enum HTTPConnection {
    static let allowedHosts: Set<String> = ["127.0.0.1", "localhost", "[::1]", "host.docker.internal"]

    static func serve(_ fd: Int32, _ daemon: Daemon) {
        let socket = BufferedSocket(fd: fd)
        let writer = ConnectionWriter(fd: fd)
        defer { writer.drain() }
        socket.setReadTimeout(10)

        guard let headBytes = try? socket.read(until: Array("\r\n\r\n".utf8)),
              let head = String(bytes: headBytes, encoding: .utf8) else { return }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return reply(writer, 400, "malformed request line") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        if headers["origin"] != nil { return reply(writer, 403, "browser requests are not allowed") }
        if let host = headers["host"], !allowedHosts.contains(stripPort(host).lowercased()) {
            return reply(writer, 403, "unexpected Host header '\(host)'")
        }
        guard requestLine[1] == "/rpc" else { return reply(writer, 404, "not found; use POST /rpc") }
        guard requestLine[0] == "POST" else { return reply(writer, 405, "method not allowed; use POST /rpc") }
        guard headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            return reply(writer, 415, "Content-Type must be application/json")
        }
        guard let lengthText = headers["content-length"], let length = Int(lengthText), length >= 0 else {
            return reply(writer, 411, "Content-Length required")
        }
        guard length <= BufferedSocket.maxMessage else { return reply(writer, 413, "body too large") }
        guard let body = try? socket.read(exactly: length) else { return }

        let request: Request
        do {
            request = try PerchJSON.decoder.decode(Request.self, from: Data(body))
        } catch {
            return reply(writer, 400, "invalid request: \(describe(error))")
        }

        if request.op == .watch {
            // Newline-delimited JSON until the client disconnects; body length is delimited by close.
            writer.send(Data("HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n".utf8))
            socket.setReadTimeout(nil)
            let id = daemon.subscribe { writer.sendLine($0) }
            while (try? socket.readLine()) != nil {}
            daemon.unsubscribe(id)
            return
        }
        reply(writer, 200, daemon.perform(request))
    }

    private static func reply(_ writer: ConnectionWriter, _ status: Int, _ error: String) {
        reply(writer, status, .failure(error))
    }

    private static func reply(_ writer: ConnectionWriter, _ status: Int, _ response: Response) {
        var body = (try? PerchJSON.encoder.encode(response)) ?? Data()
        body.append(0x0A)
        let head = "HTTP/1.1 \(status) \(reason(status))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        writer.send(Data(head.utf8) + body)
    }

    private static func stripPort(_ host: String) -> String {
        if host.hasPrefix("["), let end = host.firstIndex(of: "]") { return String(host[...end]) }
        return String(host.split(separator: ":", maxSplits: 1).first ?? "")
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        default: return "Error"
        }
    }
}
