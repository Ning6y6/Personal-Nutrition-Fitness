import Foundation

/// A local calendar day's immutable, half-open interval used to group saved meal timestamps.
/// Refresh the window from an explicitly supplied clock/calendar; the model does not observe time.
public struct MealDayWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String

    // Calendar equality includes its identifier, locale, time zone and week configuration.
    // Keeping that context distinguishes calendar changes even when their day bounds match.
    private let calendar: Calendar

    public var calendarIdentifier: Calendar.Identifier {
        calendar.identifier
    }

    public init(containing date: Date, calendar: Calendar) throws {
        try DomainValidation.date(date, field: "date")
        // A let-bound autoupdating Calendar/Locale/TimeZone is still dynamically backed by system
        // preferences. Materialize their identifiers into ordinary values before storing them.
        let sourceTimeZone = calendar.timeZone
        guard let timeZone = TimeZone(identifier: sourceTimeZone.identifier),
              timeZone.secondsFromGMT(for: date) == sourceTimeZone.secondsFromGMT(for: date) else {
            // An identifier that cannot reconstruct the supplied zone must not silently become
            // an autoupdating value or a guessed fixed offset with different day boundaries.
            throw DomainValidationError.invalidValue(field: "timeZoneIdentifier")
        }
        var snapshot = Calendar(identifier: calendar.identifier)
        snapshot.locale = calendar.locale.map { Locale(identifier: $0.identifier) }
        snapshot.timeZone = timeZone
        snapshot.firstWeekday = calendar.firstWeekday
        snapshot.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        guard let interval = snapshot.dateInterval(of: .day, for: date),
              interval.start.timeIntervalSinceReferenceDate.isFinite,
              interval.end.timeIntervalSinceReferenceDate.isFinite,
              interval.start < interval.end,
              interval.start <= date, date < interval.end else {
            throw DomainValidationError.invalidValue(field: "dayInterval")
        }
        // Calendar arithmetic handles DST and other local day-boundary changes. Never add 86400.
        start = interval.start
        end = interval.end
        timeZoneIdentifier = timeZone.identifier
        self.calendar = snapshot
    }

    public func contains(_ date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
        return start <= date && date < end
    }
}
