import Foundation

/// A Gregorian civil date, independent of the user's current calendar and time zone.
/// The explicit statistic time zone determines the date of a supplied instant.
public struct GoalDay: Codable, Equatable, Sendable, Comparable {
    public let key: Int

    public init(key: Int) throws {
        guard key >= 10_101, key <= 99_991_231 else { throw GoalHistoryError.invalidDay(key) }
        let year = key / 10_000
        let month = key / 100 % 100
        let day = key % 100
        guard (1...9_999).contains(year), (1...12).contains(month) else {
            throw GoalHistoryError.invalidDay(key)
        }
        let leapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day >= 1, day <= daysInMonth[month - 1] else { throw GoalHistoryError.invalidDay(key) }
        self.key = key
    }

    public init(containing date: Date, timeZoneIdentifier: String) throws {
        try DomainValidation.date(date, field: "date")
        let calendar = try Self.calendar(in: timeZoneIdentifier)
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard components.era == 1, let year = components.year, (1...9_999).contains(year),
              let month = components.month, let day = components.day else {
            throw DomainValidationError.invalidValue(field: "goalDay")
        }
        try self.init(key: year * 10_000 + month * 100 + day)
    }

    /// Captures the actual day boundary for audit, including zones whose day starts after 00:00.
    /// A skipped civil date fails rather than normalizing into another date.
    public func start(in timeZoneIdentifier: String) throws -> Date {
        let calendar = try Self.calendar(in: timeZoneIdentifier)
        let components = DateComponents(era: 1, year: key / 10_000, month: key / 100 % 100, day: key % 100, hour: 12)
        guard let noon = calendar.date(from: components),
              (try? GoalDay(containing: noon, timeZoneIdentifier: timeZoneIdentifier)) == self,
              let interval = calendar.dateInterval(of: .day, for: noon),
              interval.start.timeIntervalSinceReferenceDate.isFinite,
              (try? GoalDay(containing: interval.start, timeZoneIdentifier: timeZoneIdentifier)) == self else {
            throw GoalHistoryError.unavailableDay(key, timeZoneIdentifier)
        }
        return interval.start
    }

    /// Calendar addition uses local days, never a fixed 86400-second interval.
    public func addingDays(_ count: Int, timeZoneIdentifier: String) throws -> GoalDay {
        let calendar = try Self.calendar(in: timeZoneIdentifier)
        // No representable year 1...9999 date can require a larger day offset.
        guard (-3_660_000...3_660_000).contains(count) else {
            throw DomainValidationError.calculationOverflow(field: "goalDay")
        }
        guard let date = calendar.date(byAdding: .day, value: count, to: try start(in: timeZoneIdentifier)) else {
            throw DomainValidationError.calculationOverflow(field: "goalDay")
        }
        return try GoalDay(containing: date, timeZoneIdentifier: timeZoneIdentifier)
    }

    public static func < (lhs: GoalDay, rhs: GoalDay) -> Bool { lhs.key < rhs.key }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(key: container.decode(Int.self, forKey: .key))
    }

    private static func calendar(in identifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw GoalHistoryError.invalidTimeZoneIdentifier(identifier)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}
