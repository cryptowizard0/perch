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
    public static var socket: URL { home.appendingPathComponent("perchd.sock") }
    /// SQLite store. Only perchd opens it.
    public static var database: URL { home.appendingPathComponent("perch.sqlite") }
    /// Read-only markdown mirror rendered by perchd. Agents may `cat` it; never edit it.
    public static var mirror: URL { home.appendingPathComponent("todo.md") }
    /// Append-only inbox. Any `- [ ] …` line dropped here is ingested and cleared by perchd.
    public static var inbox: URL { home.appendingPathComponent("inbox.md") }
    /// Localhost HTTP port for clients that cannot reach the socket (e.g. Hermes in Docker).
    public static let defaultHTTPPort = 7331
}
