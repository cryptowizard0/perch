import Foundation

/// Everything lives under `~/.perch` (override with `PERCH_HOME`).
public enum PerchPaths {
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["PERCH_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".perch", isDirectory: true)
    }
    /// Unix socket the CLI and the notch app talk to.
    public static var socket: URL { socket(in: home) }
    /// SQLite store. Only perchd opens it.
    public static var database: URL { database(in: home) }
    /// Read-only markdown mirror rendered by perchd. Agents may `cat` it; never edit it.
    public static var mirror: URL { mirror(in: home) }
    /// Append-only inbox. Any `- [ ] …` line dropped here is ingested and cleared by perchd.
    public static var inbox: URL { inbox(in: home) }
    /// What may be approved from the notch (see `Allowlist`). Missing = defaults.
    public static var allowlist: URL { home.appendingPathComponent("allowlist.json") }
    /// Where `perch hook` records failures (hooks must not print).
    public static var hookLog: URL { home.appendingPathComponent("hook.log") }
    /// Localhost HTTP port for clients that cannot reach the socket (e.g. Hermes in Docker).
    public static let defaultHTTPPort = 7331

    public static func socket(in home: URL) -> URL { home.appendingPathComponent("perchd.sock") }
    public static func database(in home: URL) -> URL { home.appendingPathComponent("perch.sqlite") }
    public static func mirror(in home: URL) -> URL { home.appendingPathComponent("todo.md") }
    public static func inbox(in home: URL) -> URL { home.appendingPathComponent("inbox.md") }
}
