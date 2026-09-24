import Foundation

/// A link back to the terminal an agent runs in: `perch-terminal://ghostty?id=…&cwd=…&bundle=…`.
/// Hook adapters build it; the notch app resolves it (Ghostty: focus that exact terminal via AppleScript;
/// anything else: bring the app with `bundle` id to the front).
public struct TerminalLink: Equatable, Sendable {
    public static let scheme = "perch-terminal"

    /// Terminal program, lowercased `TERM_PROGRAM` ("ghostty", "iterm.app", …).
    public var app: String
    /// The terminal's own id for its tab / split, when it can be asked (Ghostty's AppleScript `terminal id`).
    public var terminalID: String?
    /// The agent's working directory; also used to find the terminal when the id is gone.
    public var cwd: String?
    /// Bundle id of the app that launched the shell (`__CFBundleIdentifier`), to activate as a last resort.
    public var bundleID: String?

    public init(app: String, terminalID: String? = nil, cwd: String? = nil, bundleID: String? = nil) {
        self.app = app
        self.terminalID = terminalID
        self.cwd = cwd
        self.bundleID = bundleID
    }

    public init?(string: String) {
        guard let c = URLComponents(string: string), c.scheme == Self.scheme, let host = c.host, !host.isEmpty else { return nil }
        func value(_ name: String) -> String? {
            c.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        self.init(app: host, terminalID: value("id"), cwd: value("cwd"), bundleID: value("bundle"))
    }

    public var string: String {
        var c = URLComponents()
        c.scheme = Self.scheme
        c.host = app
        let items = [("id", terminalID), ("cwd", cwd), ("bundle", bundleID)].compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        c.queryItems = items.isEmpty ? nil : items
        return c.string ?? "\(Self.scheme)://\(app)"
    }
}
