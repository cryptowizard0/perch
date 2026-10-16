import Foundation

/// Due-time syntax shared by `perch add --due`, the inbox and (M2) quick entry.
///
/// - `@15:00`, `@9:30`, `@9` — the next time the clock shows that time: today, or tomorrow if it has passed.
/// - `+30m`, `+2h`, `+1d`, `+1h30m` — relative to now.
/// - ISO-8601 (`2026-09-24T15:00:00+08:00`) — for agents that already have an absolute time.
/// - A date alone (`2026-10-20`) — a day with no time (#52): a date-only reminder; midnight on the wire.
public enum DueParser {
    public struct ParseError: Error, CustomStringConvertible, Equatable {
        public let description: String
    }

    /// When something is due, and whether that is a whole day rather than a moment.
    public struct Due: Equatable, Sendable {
        public var date: Date
        public var dateOnly: Bool
        public init(date: Date, dateOnly: Bool) {
            self.date = date
            self.dateOnly = dateOnly
        }
    }

    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) throws -> Date {
        try parseDue(text, now: now, calendar: calendar).date
    }

    public static func parseDue(_ text: String, now: Date, calendar: Calendar = .current) throws -> Due {
        let s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") { return Due(date: try clockTime(String(s.dropFirst()), original: s, now: now, calendar: calendar), dateOnly: false) }
        if s.hasPrefix("+") { return Due(date: try relative(String(s.dropFirst()), original: s, now: now), dateOnly: false) }
        if let date = iso.date(from: s) ?? isoFractional.date(from: s) { return Due(date: date, dateOnly: false) }
        if let day = day(s, calendar: calendar) { return Due(date: day, dateOnly: true) }
        throw invalid(s)
    }

    /// `YYYY-MM-DD`, a real day: its start in `calendar`'s time zone.
    private static func day(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, zip(parts, [4, 2, 2]).allSatisfy({ $0.count == $1 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return date
    }

    private static func clockTime(_ body: String, original: String, now: Date, calendar: Calendar) throws -> Date {
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]), (0...23).contains(hour),
              let minute = parts.count == 2 ? Int(parts[1]) : 0, (0...59).contains(minute),
              parts.count == 1 || parts[1].count == 2
        else { throw invalid(original) }
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { throw invalid(original) }
        if today > now { return today }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let next = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow)
        else { throw invalid(original) }
        return next
    }

    private static func relative(_ body: String, original: String, now: Date) throws -> Date {
        var total: TimeInterval = 0
        var digits = ""
        for ch in body {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
                continue
            }
            guard let n = Int(digits), let unit: TimeInterval = ["m": 60, "h": 3600, "d": 86_400][ch] else { throw invalid(original) }
            total += TimeInterval(n) * unit
            digits = ""
        }
        guard digits.isEmpty, total > 0 else { throw invalid(original) }
        return now.addingTimeInterval(total)
    }

    private static func invalid(_ text: String) -> ParseError {
        ParseError(description: "invalid due '\(text)': use @15:00, +30m, a date (2026-10-20) or an ISO-8601 time")
    }

    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
