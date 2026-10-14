import FoodDecisionCore
import Foundation
import Testing
@testable import FoodDecisionAssistant

struct AppDateDisplayContextTests {
    struct ClockExample: Sendable {
        let regionalIdentifier: String
        let expectedTime: String
        let expectedRegion: String
        let expectedCycle: Locale.HourCycle
    }

    @Test("Chinese language preserves UK/US regions and explicit 12/24-hour preferences", arguments: [
        ClockExample(regionalIdentifier: "en_GB@hours=h12", expectedTime: "下午2:30", expectedRegion: "GB", expectedCycle: .oneToTwelve),
        ClockExample(regionalIdentifier: "en_GB@hours=h23", expectedTime: "14:30", expectedRegion: "GB", expectedCycle: .zeroToTwentyThree),
        ClockExample(regionalIdentifier: "en_US@hours=h12", expectedTime: "下午2:30", expectedRegion: "US", expectedCycle: .oneToTwelve),
        ClockExample(regionalIdentifier: "en_US@hours=h23", expectedTime: "14:30", expectedRegion: "US", expectedCycle: .zeroToTwentyThree)
    ])
    func chineseClockPreferences(example: ClockExample) throws {
        let display = context(regionalIdentifier: example.regionalIdentifier)
        let date = try instant(2026, 10, 14, hour: 14, minute: 30)
        #expect(display.locale.language.languageCode?.identifier == "zh")
        #expect(display.locale.language.script?.identifier == "Hans")
        #expect(display.locale.region?.identifier == example.expectedRegion)
        #expect(display.locale.hourCycle == example.expectedCycle)
        #expect(display.fullDate(date) == "2026年10月14日")
        #expect(normalized(display.time(date)) == example.expectedTime)
    }

    @Test("Future English format support is explicit and does not require an English App UI", arguments: [
        ("en_GB@hours=h23", "14 October 2026", "14:30"),
        ("en_US@hours=h12", "October 14, 2026", "2:30 PM")
    ])
    func explicitEnglishFormatting(example: (String, String, String)) throws {
        let display = context(language: "en", regionalIdentifier: example.0)
        let date = try instant(2026, 10, 14, hour: 14, minute: 30)
        #expect(display.locale.language.languageCode?.identifier == "en")
        #expect(normalized(display.fullDate(date)) == example.1)
        #expect(normalized(display.time(date)) == example.2)
    }

    @Test("Confirmation detail retains seconds while ordinary date/time retains minute precision", arguments: [
        "en_GB@hours=h12", "en_GB@hours=h23", "en_US@hours=h12", "en_US@hours=h23"
    ])
    func confirmationPrecision(identifier: String) throws {
        let display = context(regionalIdentifier: identifier)
        let date = try instant(2026, 10, 14, hour: 14, minute: 30, second: 9)
        let minuteText = display.dateTime(date)
        let secondsText = display.dateTimeWithSeconds(date)
        #expect(minuteText.contains("2026年10月14日"))
        #expect(minuteText.contains(":30"))
        #expect(minuteText.contains(":09") == false)
        #expect(secondsText.contains("2026年10月14日"))
        #expect(secondsText.contains(":30:09"))
    }

    @Test("History keeps the year across the supplied calendar's year boundary", arguments: ["sameYear", "previousYear", "buddhist"])
    func historyUsesContextCalendar(kind: String) throws {
        let calendar = Calendar(identifier: kind == "buddhist" ? .buddhist : .gregorian)
        let display = AppDateDisplayContext(regionalLocale: Locale(identifier: "en_GB@hours=h23"), calendar: calendar, timeZone: .gmt)
        let date = try instant(kind == "sameYear" ? 2026 : 2025, 10, 14, hour: 14, minute: 30)
        let reference = try instant(2026, 10, 15)
        let text = display.historyDateTime(date, referenceDate: reference)
        if kind == "sameYear" {
            #expect(text.contains("2026") == false)
        } else {
            #expect(text.contains(kind == "buddhist" ? "2568" : "2025"))
        }
        #expect(text.contains("10月14日"))
        #expect(text.contains("14:30"))
        #expect(display.calendar.identifier == calendar.identifier)
    }

    @Test("The phone time zone determines an instant's displayed date and history year")
    func yearBoundaryUsesPhoneTimeZone() throws {
        let date = try instant(2027, 1, 1, hour: 0, minute: 30)
        let reference = try instant(2026, 12, 31, hour: 12)
        let losAngeles = try context(in: "America/Los_Angeles")
        let tokyo = try context(in: "Asia/Tokyo")
        #expect(losAngeles.fullDate(date) == "2026年12月31日")
        #expect(tokyo.fullDate(date) == "2027年1月1日")
        #expect(losAngeles.historyDateTime(date, referenceDate: reference).contains("2026") == false)
        #expect(tokyo.historyDateTime(date, referenceDate: reference).contains("2027"))
    }

    @Test("Phone DST changes the displayed clock without shifting a saved instant")
    func daylightSavingDisplay() throws {
        let display = try context(in: "Europe/London")
        let before = try instant(2026, 3, 29, hour: 0, minute: 30)
        let after = before.addingTimeInterval(3_600)
        #expect(display.time(before) == "00:30")
        #expect(display.time(after) == "02:30")
        #expect(display.fullDate(before) == "2026年3月29日")
        #expect(display.fullDate(after) == "2026年3月29日")
        #expect(after.timeIntervalSince(before) == 3_600)
    }

    struct CivilExample: Sendable {
        let key: Int
        let referenceKey: Int?
        let expected: String
    }

    @Test("Gregorian civil keys remain exact across zones, skipped days, leap days and cutovers", arguments: [
        CivilExample(key: 20111230, referenceKey: nil, expected: "2011年12月30日"),
        CivilExample(key: 20240229, referenceKey: 20240101, expected: "2月29日"),
        CivilExample(key: 20270101, referenceKey: 20261231, expected: "2027年1月1日"),
        CivilExample(key: 15821010, referenceKey: nil, expected: "1582年10月10日"),
        CivilExample(key: 20261014, referenceKey: 20260101, expected: "10月14日")
    ], ["Pacific/Apia", "America/Los_Angeles", "Asia/Tokyo"])
    func civilDatesNeverFollowPhoneTimeZone(example: CivilExample, zone: String) throws {
        let display = try context(in: zone)
        let day = try GoalDay(key: example.key)
        let reference = try example.referenceKey.map { try GoalDay(key: $0) }
        #expect(display.civilDate(for: day, referenceDay: reference) == example.expected)
        #expect(GoalDatePresentation.text(for: day, referenceDay: reference, display: display) == example.expected)
        if zone == "Pacific/Apia", example.key == 20111230 {
            #expect(throws: GoalHistoryError.unavailableDay(20111230, zone)) { try day.start(in: zone) }
        }
    }

    @Test("Future English civil dates use a separate UTC Gregorian display calendar", arguments: [
        "Pacific/Apia", "America/Los_Angeles", "Asia/Tokyo"
    ])
    func englishCivilDatesNeverUsePhoneCalendar(zone: String) throws {
        let timeZone = try #require(TimeZone(identifier: zone))
        let display = AppDateDisplayContext(interfaceLanguage: "en", regionalLocale: Locale(identifier: "en_GB@hours=h23"),
            calendar: Calendar(identifier: .buddhist), timeZone: timeZone)
        #expect(display.civilDate(for: try GoalDay(key: 20111230), referenceDay: nil) == "30 Dec 2011")
        #expect(display.civilDate(for: try GoalDay(key: 20270101), referenceDay: try GoalDay(key: 20260101)) == "1 Jan 2027")
    }

    @Test("Non-finite legacy instants display unavailable rather than a fabricated date", arguments: [Double.nan, .infinity, -.infinity])
    func invalidDateHasNeutralFallback(rawValue: Double) {
        let display = context()
        let date = Date(timeIntervalSinceReferenceDate: rawValue)
        #expect(display.fullDate(date) == "日期暂不可用")
        #expect(display.time(date) == "时间不可用")
        #expect(display.dateTime(date) == "时间不可用")
        #expect(display.dateTimeWithSeconds(date) == "时间不可用")
        #expect(display.historyDateTime(date) == "时间不可用")
    }

    @Test("An unavailable reference retains a valid history date's year")
    func invalidReferenceCannotHideHistoryYear() throws {
        let display = context()
        let date = try instant(2026, 10, 14)
        let reference = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(display.historyDateTime(date, referenceDate: reference).contains("2026"))
    }

    private func context(language: String = "zh-Hans", regionalIdentifier: String = "en_GB@hours=h23") -> AppDateDisplayContext {
        AppDateDisplayContext(interfaceLanguage: language, regionalLocale: Locale(identifier: regionalIdentifier),
            calendar: Calendar(identifier: .gregorian), timeZone: .gmt)
    }

    private func context(in zone: String) throws -> AppDateDisplayContext {
        AppDateDisplayContext(regionalLocale: Locale(identifier: "en_GB@hours=h23"), calendar: Calendar(identifier: .gregorian),
            timeZone: try #require(TimeZone(identifier: zone)))
    }

    private func instant(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)))
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
