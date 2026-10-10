import Foundation
import Testing
@testable import FoodDecisionCore

struct GoalDayTests {
    @Test("Gregorian day keys validate actual dates", arguments: [20261010, 20240229, 20000229, 10101, 99991231])
    func validKeys(key: Int) throws {
        #expect(try GoalDay(key: key).key == key)
    }

    @Test("Malformed, non-leap and out-of-range day keys are rejected", arguments: [0, -20261010, 20261301, 20261000, 20260431, 20260229, 19000229, 100000101, Int.max, Int.min])
    func invalidKeys(key: Int) {
        #expect(throws: GoalHistoryError.invalidDay(key)) { try GoalDay(key: key) }
    }

    @Test("Same instant uses the explicitly supplied local date", arguments: [
        ("Europe/London", 20261010), ("America/Los_Angeles", 20261009), ("Asia/Tokyo", 20261010),
    ])
    func explicitTimeZone(zone: String, expected: Int) throws {
        let instant = try date("2026-10-10T00:30:00Z")
        #expect(try GoalDay(containing: instant, timeZoneIdentifier: zone).key == expected)
    }

    @Test("Keys remain Gregorian when a statistic window comes from a Buddhist calendar")
    func gregorianProjectionOfStatisticWindow() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        let window = try MealDayWindow(containing: date("2026-10-10T12:00:00Z"), calendar: calendar)
        #expect(calendar.component(.year, from: window.start) == 2569)
        #expect(try GoalDay(containing: window.start, timeZoneIdentifier: window.timeZoneIdentifier).key == 20261010)
    }

    @Test("Local date boundaries follow London daylight saving instead of fixed seconds", arguments: [
        (20260329, 23.0), (20261025, 25.0),
    ])
    func daylightSaving(dayKey: Int, expectedHours: Double) throws {
        let day = try GoalDay(key: dayKey)
        let next = try day.addingDays(1, timeZoneIdentifier: "Europe/London")
        let start = try day.start(in: "Europe/London")
        let end = try next.start(in: "Europe/London")
        #expect(end.timeIntervalSince(start) == expectedHours * 3_600)
        #expect(try GoalDay(containing: start, timeZoneIdentifier: "Europe/London") == day)
        #expect(try GoalDay(containing: end.addingTimeInterval(-0.001), timeZoneIdentifier: "Europe/London") == day)
        #expect(try GoalDay(containing: end, timeZoneIdentifier: "Europe/London") == next)
    }

    @Test("Adding calendar days handles year and leap-day boundaries", arguments: [
        (20261231, 1, 20270101), (20240301, -1, 20240229), (20260228, 1, 20260301), (20261010, 0, 20261010),
    ])
    func addingDays(key: Int, amount: Int, expected: Int) throws {
        #expect(try GoalDay(key: key).addingDays(amount, timeZoneIdentifier: "UTC").key == expected)
    }

    @Test("A skipped civil day cannot silently normalize to a different day")
    func skippedCivilDay() throws {
        let skipped = try GoalDay(key: 20111230)
        #expect(throws: GoalHistoryError.unavailableDay(20111230, "Pacific/Apia")) {
            try skipped.start(in: "Pacific/Apia")
        }
        #expect(try GoalDay(key: 20111229).addingDays(1, timeZoneIdentifier: "Pacific/Apia").key == 20111231)
    }

    @Test("Invalid time zones are rejected at every calendar entry point", arguments: ["", "Unknown/Zone"])
    func invalidTimeZones(zone: String) throws {
        let day = try GoalDay(key: 20261010)
        #expect(throws: GoalHistoryError.invalidTimeZoneIdentifier(zone)) { try day.start(in: zone) }
        #expect(throws: GoalHistoryError.invalidTimeZoneIdentifier(zone)) { try day.addingDays(1, timeZoneIdentifier: zone) }
        #expect(throws: GoalHistoryError.invalidTimeZoneIdentifier(zone)) {
            try GoalDay(containing: Date(timeIntervalSince1970: 1_000), timeZoneIdentifier: zone)
        }
    }

    @Test("Calendar arithmetic rejects unrepresentable offsets", arguments: [Int.max, Int.min])
    func arithmeticOverflow(amount: Int) throws {
        #expect(throws: DomainValidationError.calculationOverflow(field: "goalDay")) {
            try GoalDay(key: 20261010).addingDays(amount, timeZoneIdentifier: "UTC")
        }
    }

    @Test("Non-finite clocks are rejected before calendar arithmetic", arguments: [Double.nan, .infinity, -.infinity])
    func invalidClock(value: Double) {
        #expect(throws: DomainValidationError.nonFiniteValue(field: "date")) {
            try GoalDay(containing: Date(timeIntervalSinceReferenceDate: value), timeZoneIdentifier: "UTC")
        }
    }

    @Test("Codable day construction applies the same validation")
    func codableValidation() throws {
        let value = try GoalDay(key: 20261010)
        #expect(try JSONDecoder().decode(GoalDay.self, from: JSONEncoder().encode(value)) == value)
        #expect(throws: GoalHistoryError.invalidDay(20260229)) {
            try JSONDecoder().decode(GoalDay.self, from: Data(#"{"key":20260229}"#.utf8))
        }
    }

    private func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }
}
