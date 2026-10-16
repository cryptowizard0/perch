import Foundation
import Testing
@testable import PerchCore

@Suite struct DueParserTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    /// 2026-09-24 10:20:30 in Shanghai.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10, minute: 20, second: 30))! }

    func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func parse(_ s: String) throws -> Date {
        try DueParser.parse(s, now: now, calendar: calendar)
    }

    @Test func clockTimeLaterTodayIsToday() throws {
        #expect(try parse("@15:00") == at(24, 15, 0))
        #expect(try parse("@10:21") == at(24, 10, 21))
        #expect(try parse("@23") == at(24, 23, 0))
        #expect(try parse("@9:05") == at(25, 9, 5))
    }

    @Test func clockTimeAlreadyPassedIsTomorrow() throws {
        #expect(try parse("@10:20") == at(25, 10, 20))
        #expect(try parse("@9") == at(25, 9, 0))
        #expect(try parse("@0:00") == at(25, 0, 0))
    }

    @Test func relative() throws {
        #expect(try parse("+30m") == now.addingTimeInterval(1800))
        #expect(try parse("+2h") == now.addingTimeInterval(7200))
        #expect(try parse("+1d") == now.addingTimeInterval(86_400))
        #expect(try parse("+1h30m") == now.addingTimeInterval(5400))
    }

    @Test func iso8601() throws {
        #expect(try parse("2026-09-24T15:00:00+08:00") == at(24, 15, 0))
        #expect(try parse("2026-09-24T07:00:00Z") == at(24, 15, 0))
    }

    /// A bare date is a day with no time (a date-only reminder, #52): midnight on the wire, flagged as date-only.
    @Test func dateOnly() throws {
        let day = try DueParser.parseDue("2026-10-20", now: now, calendar: calendar)
        #expect(day == DueParser.Due(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!, dateOnly: true))
        #expect(try parse("2026-10-20") == day.date)
        #expect(try DueParser.parseDue("@15:00", now: now, calendar: calendar) == DueParser.Due(date: at(24, 15, 0), dateOnly: false))
        #expect(try DueParser.parseDue("2026-09-24T07:00:00Z", now: now, calendar: calendar).dateOnly == false)
    }

    @Test(arguments: ["2026-13-01", "2026-02-30", "2026-1-5", "20261020"])
    func rejectsBadDates(_ input: String) {
        #expect(throws: DueParser.ParseError.self) { try parse(input) }
    }

    @Test(arguments: ["", "15:00", "@", "@24:00", "@12:60", "@1:5", "@ab", "@12:00:00", "+", "+30", "+m", "+0m", "+30s", "+-5m", "tomorrow"])
    func rejects(_ input: String) {
        #expect(throws: DueParser.ParseError.self) { try parse(input) }
    }

    @Test func errorMessageExplainsSyntax() {
        #expect(throws: DueParser.ParseError(description: "invalid due 'soon': use @15:00, +30m, a date (2026-10-20) or an ISO-8601 time")) {
            try parse("soon")
        }
    }
}
