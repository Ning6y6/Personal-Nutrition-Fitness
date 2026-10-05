import Foundation
import Testing
@testable import FoodDecisionCore

struct MealDayWindowTests {
    @Test("London day length follows the calendar across daylight saving transitions", arguments: [
        ("2026-03-29T12:00:00Z", 23.0),
        ("2026-10-25T12:00:00Z", 25.0),
        ("2026-10-05T12:00:00Z", 24.0),
    ])
    func londonDayLength(text: String, hours: Double) throws {
        let calendar = try calendar(timeZone: "Europe/London")
        let instant = try date(text)
        let window = try MealDayWindow(containing: instant, calendar: calendar)

        #expect(window.end.timeIntervalSince(window.start) == hours * 60 * 60)
        #expect(window.timeZoneIdentifier == "Europe/London")
        #expect(window.calendarIdentifier == .gregorian)
        #expect(window.contains(instant))
        #expect(calendar.component(.hour, from: window.start) == 0)
        #expect(calendar.component(.hour, from: window.end) == 0)
    }

    @Test("A day includes its start and excludes the next day's start", arguments: [
        "2026-03-29T12:00:00Z", "2026-10-25T12:00:00Z",
    ])
    func halfOpenBoundaries(text: String) throws {
        let window = try MealDayWindow(containing: date(text), calendar: calendar(timeZone: "Europe/London"))

        #expect(window.contains(window.start))
        #expect(window.contains(window.end) == false)
        #expect(window.contains(window.start.addingTimeInterval(-0.001)) == false)
        #expect(window.contains(window.end.addingTimeInterval(-0.001)))
    }

    @Test("Crossing local midnight creates a new window without rewriting historical timestamps")
    func localMidnight() throws {
        let calendar = try calendar(timeZone: "Europe/London")
        let beforeMidnight = try date("2026-10-04T22:59:59Z")
        let midnight = try date("2026-10-04T23:00:00Z")
        let yesterday = try MealDayWindow(containing: beforeMidnight, calendar: calendar)
        let today = try MealDayWindow(containing: midnight, calendar: calendar)

        #expect(yesterday != today)
        #expect(yesterday.end == today.start)
        #expect(yesterday.contains(beforeMidnight))
        #expect(today.contains(beforeMidnight) == false)
        #expect(yesterday.contains(midnight) == false)
        #expect(today.contains(midnight))
        #expect(calendar.component(.day, from: yesterday.start) == 4)
        #expect(calendar.component(.day, from: today.start) == 5)
    }

    @Test("The same instant can belong to different local days after a time-zone change")
    func sameInstantDifferentTimeZones() throws {
        let instant = try date("2026-10-05T00:30:00Z")
        let londonCalendar = try calendar(timeZone: "Europe/London")
        let losAngelesCalendar = try calendar(timeZone: "America/Los_Angeles")
        let london = try MealDayWindow(containing: instant, calendar: londonCalendar)
        let losAngeles = try MealDayWindow(containing: instant, calendar: losAngelesCalendar)

        #expect(london != losAngeles)
        #expect(london.start != losAngeles.start)
        #expect(london.timeZoneIdentifier == "Europe/London")
        #expect(losAngeles.timeZoneIdentifier == "America/Los_Angeles")
        #expect(londonCalendar.component(.day, from: instant) == 5)
        #expect(losAngelesCalendar.component(.day, from: instant) == 4)
        #expect(london.contains(instant))
        #expect(losAngeles.contains(instant))
    }

    @Test("Calendar semantics participate in equality even when day boundaries match", arguments: CalendarChange.allCases)
    func calendarSemanticsInEquality(change: CalendarChange) throws {
        let instant = try date("2026-10-05T12:00:00Z")
        let originalCalendar = try calendar(timeZone: "UTC")
        var changedCalendar = originalCalendar
        switch change {
        case .identifier:
            changedCalendar = Calendar(identifier: .buddhist)
            changedCalendar.timeZone = originalCalendar.timeZone
            changedCalendar.locale = originalCalendar.locale
        case .locale:
            changedCalendar.locale = Locale(identifier: "en_US")
        case .weekConfiguration:
            changedCalendar.firstWeekday = 7
            changedCalendar.minimumDaysInFirstWeek = 1
        }
        let original = try MealDayWindow(containing: instant, calendar: originalCalendar)
        let changed = try MealDayWindow(containing: instant, calendar: changedCalendar)

        #expect(original.start == changed.start)
        #expect(original.end == changed.end)
        #expect(original != changed)
        #expect(original == (try MealDayWindow(containing: instant.addingTimeInterval(1), calendar: originalCalendar)))
    }

    @Test("Forward and backward wall-clock corrections recalculate the containing day", arguments: [
        "2026-10-04T12:00:00Z", "2026-10-06T12:00:00Z",
    ])
    func wallClockCorrection(text: String) throws {
        let calendar = try calendar(timeZone: "Europe/London")
        let originalInstant = try date("2026-10-05T12:00:00Z")
        let correctedInstant = try date(text)
        let original = try MealDayWindow(containing: originalInstant, calendar: calendar)
        let corrected = try MealDayWindow(containing: correctedInstant, calendar: calendar)

        #expect(original != corrected)
        #expect(original.contains(originalInstant))
        #expect(corrected.contains(correctedInstant))
        #expect(original.contains(correctedInstant) == false)
        #expect(corrected.contains(originalInstant) == false)
    }

    @Test("Non-finite construction dates fail before invoking calendar arithmetic", arguments: [Double.nan, .infinity, -.infinity])
    func invalidConstructionDate(value: Double) throws {
        let calendar = try calendar(timeZone: "Europe/London")

        #expect(throws: DomainValidationError.nonFiniteValue(field: "date")) {
            try MealDayWindow(containing: Date(timeIntervalSinceReferenceDate: value), calendar: calendar)
        }
    }

    @Test("A non-finite candidate is never contained in a valid day", arguments: [Double.nan, .infinity, -.infinity])
    func invalidContainmentDate(value: Double) throws {
        let window = try MealDayWindow(containing: date("2026-10-05T12:00:00Z"), calendar: calendar(timeZone: "Europe/London"))

        #expect(window.contains(Date(timeIntervalSinceReferenceDate: value)) == false)
    }

    @Test("A window is an immutable calendar snapshot, independent of subsequent caller changes")
    func calendarSnapshot() throws {
        let instant = try date("2026-10-05T12:00:00Z")
        var sourceCalendar = try calendar(timeZone: "Europe/London")
        let window = try MealDayWindow(containing: instant, calendar: sourceCalendar)
        let expected = window
        sourceCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        sourceCalendar.locale = Locale(identifier: "en_US")
        let changed = try MealDayWindow(containing: instant, calendar: sourceCalendar)

        #expect(window == expected)
        #expect(window.timeZoneIdentifier == "Europe/London")
        #expect(window.calendarIdentifier == .gregorian)
        #expect(window != changed)
        #expect(window.contains(instant))
    }

    @Test("An autoupdating calendar is materialized into the same immutable window as an explicit snapshot")
    func autoupdatingCalendarSnapshot() throws {
        let instant = try date("2026-10-05T12:00:00Z")
        let autoupdating = Calendar.autoupdatingCurrent
        var explicit = Calendar(identifier: autoupdating.identifier)
        explicit.locale = autoupdating.locale.map { Locale(identifier: $0.identifier) }
        explicit.timeZone = try #require(TimeZone(identifier: autoupdating.timeZone.identifier))
        explicit.firstWeekday = autoupdating.firstWeekday
        explicit.minimumDaysInFirstWeek = autoupdating.minimumDaysInFirstWeek

        let materialized = try MealDayWindow(containing: instant, calendar: autoupdating)
        let expected = try MealDayWindow(containing: instant, calendar: explicit)

        #expect(materialized == expected)
        #expect(materialized.start == expected.start)
        #expect(materialized.end == expected.end)
        #expect(materialized.timeZoneIdentifier == expected.timeZoneIdentifier)
        #expect(materialized.calendarIdentifier == explicit.identifier)
        #expect(materialized.contains(instant))
    }

    @Test("GMT and positive or negative half-hour fixed zones retain their day boundaries", arguments: [0, 19_800, -12_600])
    func fixedTimeZoneSnapshots(seconds: Int) throws {
        let instant = try date("2026-10-05T12:00:00Z")
        var source = Calendar(identifier: .gregorian)
        let zone = try #require(TimeZone(secondsFromGMT: seconds))
        source.timeZone = zone
        let expectedInterval = try #require(source.dateInterval(of: .day, for: instant))
        let window = try MealDayWindow(containing: instant, calendar: source)
        let reconstructedZone = try #require(TimeZone(identifier: window.timeZoneIdentifier))

        #expect(window.start == expectedInterval.start)
        #expect(window.end == expectedInterval.end)
        #expect(window.end.timeIntervalSince(window.start) == 24 * 60 * 60)
        #expect(reconstructedZone.secondsFromGMT(for: instant) == seconds)
        #expect(window.contains(instant))
        #expect(window.contains(window.end) == false)
    }

    enum CalendarChange: CaseIterable, Sendable {
        case identifier, locale, weekConfiguration
    }

    private func calendar(timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }
}
