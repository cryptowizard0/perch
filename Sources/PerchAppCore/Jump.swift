import Foundation
import PerchCore

/// Where clicking a session row goes.
public enum JumpTarget: Equatable, Sendable {
    /// Back to an agent's terminal.
    case terminal(TerminalLink)
    /// A URL or path for `NSWorkspace.open`.
    case open(URL)

    public init?(link: String?) {
        guard let link else { return nil }
        if let terminal = TerminalLink(string: link) {
            self = .terminal(terminal)
        } else if let url = Self.url(link) {
            self = .open(url)
        } else {
            return nil
        }
    }

    /// Something `NSWorkspace.open` can handle: a URL with a scheme, or an absolute / `~` path.
    /// Terminal references other than `perch-terminal://` (tmux, …) return nil.
    static func url(_ link: String) -> URL? {
        let link = link.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty else { return nil }
        if link.hasPrefix("/") { return URL(fileURLWithPath: link) }
        if link.hasPrefix("~/") { return URL(fileURLWithPath: NSString(string: link).expandingTildeInPath) }
        guard link.contains("://"), let url = URL(string: link), let scheme = url.scheme, scheme != TerminalLink.scheme else { return nil }
        return url
    }
}

public enum GhosttyScript {
    /// Focuses the terminal with the link's id; if it is gone, the first terminal in the link's directory;
    /// otherwise just brings Ghostty forward. Prints "terminal" or "app".
    public static func focus(_ link: TerminalLink) -> String {
        """
        tell application "Ghostty"
            set matches to {}
            if "\(escape(link.terminalID ?? ""))" is not "" then set matches to (every terminal whose id is "\(escape(link.terminalID ?? ""))")
            if (count of matches) = 0 and "\(escape(link.cwd ?? ""))" is not "" then set matches to (every terminal whose working directory is "\(escape(link.cwd ?? ""))")
            activate
            if (count of matches) = 0 then return "app"
            focus (item 1 of matches)
            return "terminal"
        end tell
        """
    }

    /// AppleScript string literal body.
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
