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
        subcommands: [Run.self, Install.self, Uninstall.self],
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

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install perchd as a launchd agent (starts at login, restarts on crash).",
        discussion: "Writes ~/Library/LaunchAgents/\(LaunchAgent.label).plist pointing at this perchd binary and loads it."
    )

    @Option(help: "Localhost HTTP port for the agent.") var httpPort: UInt16 = UInt16(PerchPaths.defaultHTTPPort)
    @Flag(help: "Do not listen on HTTP.") var noHTTP = false
    @Flag(help: "Print the plist instead of installing it.") var dryRun = false

    func run() throws {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
            throw Fatal("cannot tell where this perchd binary lives")
        }
        let home = PerchPaths.home
        var arguments = ["run"]
        arguments += noHTTP ? ["--no-http"] : ["--http-port", String(httpPort)]
        let plist = try LaunchAgent.plist(executable: executable, arguments: arguments, home: home)
        if dryRun {
            FileHandle.standardOutput.write(plist)
            return
        }

        let client = PerchClient(socketPath: PerchPaths.socket(in: home).path)
        let loaded = FileManager.default.fileExists(atPath: LaunchAgent.plistURL.path)
        if !loaded, (try? client.send(Request(op: .ping), timeout: 2))?.ok == true {
            throw Fatal("a perchd is already running outside launchd; stop it first, then install")
        }
        if executable.contains("/.build/") {
            log("note: installing \(executable) from a build directory; `swift package clean` will break the agent. "
                + "Copy perchd somewhere stable (e.g. ~/.local/bin) and run install from there for daily use.")
        }
        try LaunchAgent.install(plist: plist, home: home)

        for _ in 0..<30 {
            if (try? client.send(Request(op: .ping), timeout: 1))?.ok == true {
                print("installed \(LaunchAgent.plistURL.path)")
                print("perchd is running; log: \(LaunchAgent.logURL(home: home).path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw Fatal("installed \(LaunchAgent.plistURL.path), but perchd is not answering; see \(LaunchAgent.logURL(home: home).path)")
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the launchd agent and remove its plist.")

    func run() throws {
        if try LaunchAgent.uninstall() {
            print("removed \(LaunchAgent.plistURL.path); perchd stopped")
        } else {
            print("perchd was not installed")
        }
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
