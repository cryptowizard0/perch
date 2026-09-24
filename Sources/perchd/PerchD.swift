import ArgumentParser
import Darwin
import Foundation
import PerchClient
import PerchCore
import PerchDaemon

// perchd — the Perch daemon. Single source of truth.
// Owns the SQLite store, listens on the Unix socket (+ localhost HTTP),
// pushes events to every `watch` client, renders ~/.perch/todo.md, ingests ~/.perch/inbox.md.

@main
struct PerchD: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "perchd",
        abstract: "The Perch daemon: SQLite store, Unix socket, localhost HTTP, event push.",
        version: PerchVersion.string,
        subcommands: [Run.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the daemon in the foreground (default).")

    @Option(help: "Localhost HTTP port (0 = pick a free one).") var httpPort: UInt16 = UInt16(PerchPaths.defaultHTTPPort)
    @Flag(help: "Do not listen on HTTP.") var noHTTP = false

    func run() throws {
        signal(SIGPIPE, SIG_IGN)
        let config = DaemonConfig()
        try claimSocket(config.socketPath)

        let daemon = try Daemon(config: config)
        let server = Server(daemon: daemon)
        do {
            try server.listenUnix(path: config.socketPath)
        } catch let error as SocketError where error.code == EADDRINUSE {
            throw Fatal("perchd is already running (\(config.socketPath))")  // lost a startup race
        }
        if !noHTTP {
            do {
                try server.listenHTTP(port: httpPort)
            } catch {
                unlink(config.socketPath)
                throw Fatal("cannot listen on 127.0.0.1:\(httpPort) (\(error)); use --http-port or --no-http")
            }
        }

        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                server.stop()
                unlink(config.socketPath)
                Darwin.exit(0)
            }
            source.resume()
            sources.append(source)
        }

        let http = server.httpPort.map { "http://127.0.0.1:\($0)/rpc" } ?? "off"
        log("perchd \(PerchVersion.string) — socket \(config.socketPath), http \(http), db \(config.databasePath)")
        withExtendedLifetime((server, sources)) { dispatchMain() }
    }

    /// Refuses to start if another perchd answers on the socket; removes a stale socket file otherwise.
    private func claimSocket(_ path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        if let pong = try? PerchClient(socketPath: path).send(Request(op: .ping), timeout: 2), pong.ok {
            throw Fatal("perchd is already running (\(path))")
        }
        unlink(path)
    }
}

/// A startup failure: one readable line on stderr, exit 1, no usage dump.
struct Fatal: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
