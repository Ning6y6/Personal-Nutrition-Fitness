import FoodDecisionCore
import Foundation

/// A value snapshot of date-only display preferences, separate from number parsing and business dates.
struct AppDateDisplayContext: Equatable, Sendable {
    let interfaceLanguage: String
    let locale: Locale
    let calendar: Calendar
    let timeZone: TimeZone

    init(
        interfaceLanguage: String = "zh-Hans",
        regionalLocale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        var components = Locale.Components(identifier: regionalLocale.identifier)
        let language = Locale.Language.Components(identifier: interfaceLanguage)
        components.languageComponents.languageCode = language.languageCode
        components.languageComponents.script = language.script
        // Constructing a language locale alone would lose the phone's 12/24-hour preference.
        components.hourCycle = regionalLocale.hourCycle
        let displayLocale = Locale(components: components)
        let capturedTimeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
        var displayCalendar = Calendar(identifier: calendar.identifier)
        displayCalendar.locale = displayLocale
        displayCalendar.timeZone = capturedTimeZone
        displayCalendar.firstWeekday = calendar.firstWeekday
        displayCalendar.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        self.interfaceLanguage = interfaceLanguage
        locale = displayLocale
        self.calendar = displayCalendar
        self.timeZone = capturedTimeZone
    }

    func fullDate(_ date: Date) -> String {
        formatted(date, using: style.year().month(.wide).day(), unavailable: "日期暂不可用")
    }

    func time(_ date: Date) -> String {
        formatted(date, using: style.hour().minute())
    }

    func dateTime(_ date: Date) -> String {
        formatted(date, using: style.year().month(.wide).day().hour().minute())
    }

    func dateTimeWithSeconds(_ date: Date) -> String {
        formatted(date, using: style.year().month(.wide).day().hour().minute().second())
    }

    func historyDateTime(_ date: Date, referenceDate: Date = .now) -> String {
        guard Self.isFinite(date) else { return "时间不可用" }
        var historyStyle = style.month(.abbreviated).day().hour().minute()
        if !Self.isFinite(referenceDate)
            || calendar.component(.year, from: date) != calendar.component(.year, from: referenceDate) {
            historyStyle = historyStyle.year()
        }
        return formatted(date, using: historyStyle)
    }

    /// GoalDay is a Gregorian civil key, never an instant in the phone's time zone.
    /// Chinese text can preserve even civil dates skipped by a particular time zone or calendar.
    /// Other languages format an independent UTC Gregorian noon for display only. This synthetic
    /// instant must never be stored, used for goal selection, or substituted for effectiveFrom.
    func civilDate(for day: GoalDay, referenceDay: GoalDay?) -> String {
        let year = day.key / 10_000
        let month = day.key / 100 % 100
        let dayOfMonth = day.key % 100
        let includesYear = referenceDay.map { $0.key / 10_000 != year } ?? true
        if locale.language.languageCode?.identifier == "zh" {
            let monthAndDay = "\(month)月\(dayOfMonth)日"
            return includesYear ? "\(year)年\(monthAndDay)" : monthAndDay
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = locale
        gregorian.timeZone = .gmt
        let components = DateComponents(era: 1, year: year, month: month, day: dayOfMonth, hour: 12)
        guard let displayInstant = gregorian.date(from: components) else {
            return numericCivilDate(year: year, month: month, day: dayOfMonth, includesYear: includesYear)
        }
        let represented = gregorian.dateComponents([.era, .year, .month, .day], from: displayInstant)
        guard represented.era == 1, represented.year == year, represented.month == month, represented.day == dayOfMonth else {
            // A calendar cutover may normalize a valid proleptic Gregorian key. Retain its fields.
            return numericCivilDate(year: year, month: month, day: dayOfMonth, includesYear: includesYear)
        }
        var civilStyle = Date.FormatStyle(locale: locale, calendar: gregorian, timeZone: .gmt)
            .month(.abbreviated).day()
        if includesYear { civilStyle = civilStyle.year() }
        return civilStyle.format(displayInstant)
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
    }

    private func formatted(_ date: Date, using style: Date.FormatStyle, unavailable: String = "时间不可用") -> String {
        guard Self.isFinite(date) else { return unavailable }
        let result = style.format(date)
        return result.isEmpty ? unavailable : result
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private func numericCivilDate(year: Int, month: Int, day: Int, includesYear: Bool) -> String {
        includesYear ? "\(year)-\(month)-\(day)" : "\(month)-\(day)"
    }
}
