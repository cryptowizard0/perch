import Foundation
import PerchCore

/// Human-readable output. Agents should use `--json`; this format may change.
enum Format {
    static func row(_ item: Item, sourceWidth: Int, now: Date = Date()) -> String {
        var line = "\(item.id)  \(pad(state(item), 9))  \(pad(item.source, sourceWidth))  \(oneLine(item.title))"
        if let due = item.dueAt {
            let overdue = due < now && (item.status == .open || item.status == .waiting)
            line += "  · \(overdue ? "overdue" : "due") \(shortDate(due, now: now))"
        }
        if let response = item.response { line += "  → \(response)" }
        return line
    }

    static func details(_ item: Item) -> String {
        var fields: [(String, String?)] = [
            ("id", item.id), ("title", item.title), ("kind", item.kind.rawValue), ("status", item.status.rawValue),
            ("source", item.source), ("due", item.dueAt.map(longDate)), ("link", item.link), ("key", item.key),
            ("options", item.options?.joined(separator: ", ")), ("response", item.response),
            ("expires", item.expiresAt.map(longDate)),
        ]
        if let meta = item.meta, !meta.isEmpty {
            fields.append(("meta", meta.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))
        }
        fields += [("created", longDate(item.createdAt)), ("updated", longDate(item.updatedAt))]
        return fields.compactMap { name, value in value.map { "\(pad(name + ":", 9)) \($0)" } }.joined(separator: "\n")
    }

    static func event(_ event: Event) -> String {
        let type = event.type.rawValue.replacingOccurrences(of: "item.", with: "")
        return "\(time.string(from: event.at))  \(pad(type, 7))  \(row(event.item, sourceWidth: 0))"
    }

    /// `<id>  <status>  <source>  <title>  · 4m  <what it is about>`. Running counts from the turn's start,
    /// the rest from when the session entered its status.
    static func session(_ session: Session, now: Date = Date()) -> String {
        let since = session.status == .running ? session.turnStartedAt : session.statusAt
        let minutes = max(0, Int(now.timeIntervalSince(since) / 60))
        var line = "\(session.id)  \(pad(session.status.rawValue, 7))  \(session.source)  \(session.title)  · \(minutes)m"
        let about: String?
        switch session.status {
        case .running: about = session.prompt
        case .waiting: about = session.detail
        case .failed: about = session.error
        case .done, .idle: about = session.lastMessage
        }
        if let about, !about.isEmpty { line += "  " + about.split(whereSeparator: \.isNewline).joined(separator: " · ") }
        return line
    }

    static func sessionEvent(_ event: SessionEvent) -> String {
        let type = event.type.rawValue.replacingOccurrences(of: "session.", with: "session ")
        return "\(time.string(from: event.at))  \(type)  \(session(event.session, now: event.at))"
    }

    /// request / notice show their kind; tasks show their status.
    static func state(_ item: Item) -> String {
        switch (item.kind, item.status) {
        case (_, .done), (_, .dismissed), (.task, _): return item.status.rawValue
        case (.request, _), (.notice, _): return item.kind.rawValue
        }
    }

    static func shortDate(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? hourMinute.string(from: date) : monthDay.string(from: date)
    }

    static func longDate(_ date: Date) -> String {
        full.string(from: date)
    }

    private static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
    }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private static let time = formatter("HH:mm:ss")
    private static let hourMinute = formatter("HH:mm")
    private static let monthDay = formatter("MM-dd HH:mm")
    private static let full = formatter("yyyy-MM-dd HH:mm:ss")
}
