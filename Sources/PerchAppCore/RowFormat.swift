import Foundation
import PerchCore

/// How one item reads in the expanded notch.
public enum RowFormat {
    /// Due items: "in 25m" / "5m overdue" when close, the clock time otherwise.
    /// Everything else: how long it has been there ("4m ago"); waiting items and requests count
    /// from their last update (when they started waiting again).
    public static func time(_ item: Item, now: Date, calendar: Calendar = .current) -> String {
        if let due = item.dueAt {
            let delta = due.timeIntervalSince(now)
            if delta < 0 { return "\(RelativeTime.duration(-delta)) overdue" }
            if delta < 3 * 3600 { return "in \(RelativeTime.duration(delta))" }
            return clock(due, now: now, calendar: calendar)
        }
        let since = item.kind == .request || item.status == .waiting ? item.updatedAt : item.createdAt
        return "\(RelativeTime.duration(now.timeIntervalSince(since))) ago"
    }

    /// SF Symbol for a source. Unknown agents get a generic chip; no code change needed to add one.
    public static func symbol(source: String) -> String {
        switch source {
        case "human": return "person.fill"
        case "claude-code", "claude": return "sparkle"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "hermes": return "paperplane.fill"
        default: return "cpu"
        }
    }

    /// Something `NSWorkspace.open` can handle: a URL with a scheme, or an absolute / `~` path.
    /// Terminal session references (tmux, …) return nil until M3 decides how to jump to them.
    public static func linkURL(_ link: String?) -> URL? {
        guard let link = link?.trimmingCharacters(in: .whitespaces), !link.isEmpty else { return nil }
        if link.hasPrefix("/") { return URL(fileURLWithPath: link) }
        if link.hasPrefix("~/") { return URL(fileURLWithPath: NSString(string: link).expandingTildeInPath) }
        guard link.contains("://"), let url = URL(string: link), url.scheme != nil else { return nil }
        return url
    }

    private static func clock(_ date: Date, now: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "MMM d HH:mm"
        return f.string(from: date)
    }
}
