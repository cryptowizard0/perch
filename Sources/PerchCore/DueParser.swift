import Foundation

/// Due-time syntax shared by `perch add --due`, the inbox and (M2) quick entry.
///
/// - `@15:00`, `@9:30`, `@9` — the next time the clock shows that time: today, or tomorrow if it has passed.
/// - `+30m`, `+2h`, `+1d`, `+1h30m` — relative to now.
/// - ISO-8601 (`2026-09-24T15:00:00+08:00`) — for agents that already have an absolute time.
public enum DueParser {
    public struct ParseError: Error, CustomStringConvertible, Equatable {
        public let description: String
    }

    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) throws -> Date {
        let s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") { return try clockTime(String(s.dropFirst()), original: s, now: now, calendar: calendar) }
        if s.hasPrefix("+") { return try relative(String(s.dropFirst()), original: s, now: now) }
        if let date = iso.date(from: s) ?? isoFractional.date(from: s) { return date }
        throw invalid(s)
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
        ParseError(description: "invalid due '\(text)': use @15:00, +30m or an ISO-8601 time")
    }

    private static let iso = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
