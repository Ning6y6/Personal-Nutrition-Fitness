import Foundation
import UIKit
import XCTest

/// Actual system-tab taps and existing form interactions, separate from PNG render tests.
/// Run only on the dedicated QA simulator, whose store contains fictitious inputs/public seeds.
/// No app reset, database inspection, test-only launch mode, network, export or restore is used.
@MainActor
final class NativeNavigationUITests: XCTestCase {
    // Only the simulator application launched by this test is included in failure evidence.
    // This reference is never used to mutate an app store or bypass a failed interaction.
    private var diagnosticApplication: XCUIApplication?

    /// Run on the fresh, dedicated synthetic QA simulator with no existing meals.
    /// Displayed kcal are integers; editing and readback must preserve the actual inputs.
    func testKcalDisplayIsConsistentAndPreservesExactInputs() throws {
        executionTimeAllowance = 600
        let app = try launchApp()
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let mealName = "[UI测试] 热量精度餐-\(token)"
        let sourceNote = "[UI测试] 热量精度目标-\(token)"
        let rice = "熟长粒白米饭（无盐）"
        try selectTab("今日", in: app)
        let today = try uniqueIdentifiedControl(identifier: "today.content", in: app)
        guard today.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).count == 0 else {
            XCTFail("This fixed-total acceptance requires the fresh synthetic QA simulator; existing meals must be preserved.")
            throw NavigationUIFailure.conditionNotMet
        }

        // The self-selected synthetic goal is confirmed through the real form.
        // Its source token identifies this append-only version without editing old versions.
        try saveFictitiousGoal(energy: "2000.25", saturatedFat: "15", fibre: "30", sourceNote: sourceNote, in: app)
        try openGoalFromSettings(in: app)
        let energyInput = goalField("热量预算 (kcal)", in: app)
        try reveal(energyInput, in: app)
        XCTAssertEqual(energyInput.value as? String, "2000.25", "Integer display must not round the saved goal input.")
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"])
        XCTAssertTrue(app.navigationBars["每日预算与目标"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["放弃修改"].exists, "Read-only goal inspection must not dirty the form.")
        try tap(app.buttons["settings.goalHistory"])
        try requireExists(app.navigationBars["目标历史"])
        let goalList = try uniqueIdentifiedControl(identifier: "goalHistory.list", in: app)
        let versions = goalList.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "goalHistory.row.", sourceNote
        ))
        try reveal(versions.firstMatch, in: app)
        guard versions.count == 1 else {
            XCTFail("This run's source token must identify exactly one saved synthetic goal version.")
            throw NavigationUIFailure.missingControl
        }
        try assertIntegerKcal(2000, in: versions.firstMatch.label, context: "Goal history row")
        try tap(versions.firstMatch)
        try requireExists(app.navigationBars["目标版本详情"])
        try assertIdentifiedKcal(2000, identifier: "goalHistory.detail.energy", containerID: "goalHistory.detail", in: app)
        attachScreen(app, name: "KcalPrecisionUI-goal-history-integer-display")
        let back = app.navigationBars["目标版本详情"].buttons.matching(NSPredicate(
            format: "label IN %@", ["目标历史", "返回", "Back"]
        ))
        guard back.count == 1 else {
            XCTFail("Goal detail must expose one real Back action.")
            throw NavigationUIFailure.missingControl
        }
        try tap(back.firstMatch)
        try tap(app.navigationBars["目标历史"].buttons["完成"])

        // Public seed: 131 kcal / 100 g. The raw 180 g calculation is 235.8 kcal.
        try openMealStart(in: app)
        try tap(app.buttons["空白记录"])
        try requireExists(app.textFields["meal.name"])
        try replaceText(in: app.textFields["meal.name"], with: mealName, app: app)
        try selectFoodAtCurrentTextSize(rice, prefix: "meal.food.", in: app)
        try replaceText(in: singleField(prefix: "meal.weight.", in: app), with: "180", app: app)
        try assertIdentifiedKcal(236, identifier: "meal.preview.energy", containerID: "meal.form", in: app)
        attachScreen(app, name: "KcalPrecisionUI-rice180-preview236")
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try requireExists(app.navigationBars["今日"])
        let todayRows = today.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row."))
        XCTAssertEqual(todayRows.count, 1, "Only this run's real saved meal may contribute to the fixed Today totals.")
        let todayRow = namedRecordButton(mealName, in: app)
        try reveal(todayRow, in: app)
        try assertIntegerKcal(236, in: todayRow.label, context: "Today meal row")
        try assertFixedKcalTodayRing(in: app)
        attachScreen(app, name: "KcalPrecisionUI-today236-budget2000-remaining1764")

        let mealID = try expandMeal(named: mealName, in: app)
        // A regular-size LabeledContent exposes its title and value as one AX row.
        // The exact pair distinguishes the expanded snapshot from the summary's 236.
        let expandedEnergy = today.staticTexts.matching(NSPredicate(
            format: "label IN %@", ["热量、236 kcal", "热量, 236 kcal"]
        ))
        try reveal(expandedEnergy.firstMatch, in: app)
        guard expandedEnergy.count == 1 else {
            XCTFail("The expanded synthetic meal must expose one exact 236 kcal snapshot row.")
            throw NavigationUIFailure.missingControl
        }
        try assertIntegerKcal(236, in: expandedEnergy.firstMatch.label, context: "Expanded meal snapshot")
        attachScreen(app, name: "KcalPrecisionUI-expanded-snapshot236")
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(180, rice: rice, in: app)
        try assertIdentifiedKcal(236, identifier: "meal.detail.energy", containerID: "meal.detail", in: app)
        attachScreen(app, name: "KcalPrecisionUI-saved-detail180g236")

        try tap(app.navigationBars["餐食详情"].buttons["编辑"])
        try requireExists(app.textFields["meal.name"])
        let editWeight = try singleField(prefix: "meal.weight.", in: app)
        try reveal(editWeight, in: app)
        XCTAssertEqual(Double(editWeight.value as? String ?? ""), 180)
        try assertIdentifiedKcal(236, identifier: "meal.preview.energy", containerID: "meal.form", in: app)
        // 181 g calculates 237.11 kcal. Cancel must discard this real draft change.
        try replaceText(in: editWeight, with: "181", app: app)
        try assertIdentifiedKcal(237, identifier: "meal.preview.energy", containerID: "meal.form", in: app)
        attachScreen(app, name: "KcalPrecisionUI-edit181g-preview237-before-discard")
        try tap(mealEntryBar(in: app).buttons["取消"])
        try requireExists(app.buttons["放弃修改"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try requireExists(app.navigationBars["餐食详情"])
        try verifyRiceWeight(180, rice: rice, in: app)
        try assertIdentifiedKcal(236, identifier: "meal.detail.energy", containerID: "meal.detail", in: app)
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])

        _ = try expandMeal(named: mealName, in: app)
        let reuse = today.buttons.matching(identifier: "meal.reuse.\(mealID)")
        try reveal(reuse.firstMatch, in: app)
        guard reuse.count == 1 else {
            XCTFail("Reuse must target this run's unique meal on the frontmost Today page.")
            throw NavigationUIFailure.missingControl
        }
        try tap(reuse.firstMatch)
        try requireExists(app.textFields["meal.name"])
        let reuseWeight = try singleField(prefix: "meal.weight.", in: app)
        try reveal(reuseWeight, in: app)
        XCTAssertEqual(Double(reuseWeight.value as? String ?? ""), 180)
        try assertIdentifiedKcal(236, identifier: "meal.preview.energy", containerID: "meal.form", in: app)
        attachScreen(app, name: "KcalPrecisionUI-reuse180g-preview236")
        try tap(mealEntryBar(in: app).buttons["取消"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["放弃修改"].exists, "An untouched reuse preview must remain cancellable.")
        XCTAssertEqual(todayRows.count, 1, "Cancelling reuse must not append a second meal.")
        try assertFixedKcalTodayRing(in: app)

        let history = app.buttons["查看全部历史"]
        try reveal(history, in: app)
        try tap(history)
        try requireExists(app.navigationBars["历史餐食"])
        let historyRow = namedRecordButton(mealName, in: app)
        try reveal(historyRow, in: app)
        try assertIntegerKcal(236, in: historyRow.label, context: "History meal row")
        attachScreen(app, name: "KcalPrecisionUI-history-row236")
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(180, rice: rice, in: app)
        try assertIdentifiedKcal(236, identifier: "meal.detail.energy", containerID: "meal.detail", in: app)
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])
        try tap(app.navigationBars["历史餐食"].buttons["完成"])

        try openMealStart(in: app)
        let start = try uniqueIdentifiedControl(identifier: "meal.start", in: app)
        let recent = start.buttons.containing(.staticText, identifier: mealName)
        try reveal(recent.firstMatch, in: app)
        guard recent.count == 1 else {
            XCTFail("Recently Eaten must identify this run's one exact synthetic meal.")
            throw NavigationUIFailure.missingControl
        }
        try assertIntegerKcal(236, in: recent.firstMatch.label, context: "Recently Eaten row")
        attachScreen(app, name: "KcalPrecisionUI-recently-eaten236")
        try tap(app.navigationBars["记录一餐"].buttons["取消"])

        // Only this verified, uniquely named synthetic meal is removed through its UI.
        // The confirmed synthetic goal version remains append-only; no reset is used.
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(180, rice: rice, in: app)
        try assertIdentifiedKcal(236, identifier: "meal.detail.energy", containerID: "meal.detail", in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
        XCTAssertTrue(namedRecordButton(mealName, in: app).waitForNonExistence(timeout: 5))
    }

    private func assertIdentifiedKcal(
        _ expected: Int, identifier: String, containerID: String, in app: XCUIApplication
    ) throws {
        let container = try uniqueIdentifiedControl(identifier: containerID, in: app)
        let controls = container.descendants(matching: .any).matching(identifier: identifier)
        try reveal(controls.firstMatch, in: app)
        guard controls.count == 1 else {
            XCTFail("The frontmost \(containerID) must expose one \(identifier) kcal row.")
            throw NavigationUIFailure.missingControl
        }
        let control = controls.firstMatch
        let text = [control.label, control.value as? String ?? ""].joined(separator: " ")
        try assertIntegerKcal(expected, in: text, context: identifier)
    }

    private func assertIntegerKcal(_ expected: Int, in text: String, context: String) throws {
        let expression = try NSRegularExpression(pattern: "([0-9][0-9,，.]*)\\s*kcal")
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else {
            XCTFail("\(context) must expose its actual kcal amount: \(text)")
            throw NavigationUIFailure.conditionNotMet
        }
        for match in matches {
            guard let range = Range(match.range(at: 1), in: text) else {
                XCTFail("\(context) must expose a complete kcal number.")
                throw NavigationUIFailure.conditionNotMet
            }
            let number = text[range].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            XCTAssertEqual(number, String(expected), "\(context) must show the expected integer kcal without a decimal fraction.")
        }
    }

    private func assertFixedKcalTodayRing(in app: XCUIApplication) throws {
        let today = try uniqueIdentifiedControl(identifier: "today.content", in: app)
        let rings = today.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "今日热量"))
        try reveal(rings.firstMatch, in: app)
        guard rings.count == 1 else {
            XCTFail("Today must expose one real energy ring for this fixed-total synthetic scenario.")
            throw NavigationUIFailure.missingControl
        }
        let value = rings.firstMatch.value as? String ?? ""
        let expression = try NSRegularExpression(
            pattern: "^已记录 ([0-9,，]+) 千卡，预算 ([0-9,，]+) 千卡，预算剩余 ([0-9,，]+) kcal$"
        )
        guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            XCTFail("The ring must expose integer current, budget and remaining kcal: \(value)")
            throw NavigationUIFailure.conditionNotMet
        }
        // Fixed expectations from raw 235.8 and 2000.25, never a rounded baseline plus raw kcal.
        for (capture, expected) in [(1, "236"), (2, "2000"), (3, "1764")] {
            guard let range = Range(match.range(at: capture), in: value) else {
                XCTFail("The ring must expose all three actual amounts.")
                throw NavigationUIFailure.conditionNotMet
            }
            let number = value[range].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            XCTAssertEqual(number, expected)
        }
    }

    /// Actual UI under English process language/region, with the UK regional 24-hour default.
    /// A region launch does not prove the separate system 24-Hour Time toggle was tested.
    func testChineseDatesUnderEnglishUKRegionalClock() throws {
        executionTimeAllowance = 600
        try verifyChineseDatesUnderEnglishRegion(language: "en-GB", region: "en_GB", uses12HourClock: false)
    }

    /// Actual UI under the US regional 12-hour default; no hour-cycle force key is passed.
    func testChineseDatesUnderEnglishUSRegionalClock() throws {
        executionTimeAllowance = 600
        try verifyChineseDatesUnderEnglishRegion(language: "en-US", region: "en_US", uses12HourClock: true)
    }

    private func verifyChineseDatesUnderEnglishRegion(
        language: String, region: String, uses12HourClock: Bool
    ) throws {
        let app = try launchApp(language: language, region: region)
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let mealName = "[UI测试] 中文日期餐-\(token)"
        let sourceNote = "[UI测试] 中文日期目标-\(token)"
        let rice = "熟长粒白米饭（无盐）"

        try selectTab("今日", in: app)
        let navigationText = app.navigationBars["今日"].staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        try assertChineseDate(in: navigationText, requiresYear: true)
        attachScreen(app, name: "ChineseDatesUI-\(region)-today-subtitle")

        // Establish this run's meal through the same real form as the user.
        // Capture its selected clock before saving, then compare all readbacks.
        try openMealStart(in: app)
        try tap(app.buttons["空白记录"])
        try requireExists(app.textFields["meal.name"])
        let pickerQuery = app.datePickers.matching(identifier: "meal.time")
        try reveal(pickerQuery.firstMatch, in: app)
        guard pickerQuery.count == 1 else {
            XCTFail("The real meal form must expose one date/time picker.")
            throw NavigationUIFailure.missingControl
        }
        let pickerText = displayedDatePickerText(pickerQuery.firstMatch)
        try assertChineseDate(in: pickerText, requiresYear: true)
        let selectedClock = try assertChineseClock(in: pickerText, uses12HourClock: uses12HourClock)
        attachScreen(app, name: "ChineseDatesUI-\(region)-native-meal-picker")
        try replaceText(in: app.textFields["meal.name"], with: mealName, app: app)
        try selectFoodAtCurrentTextSize(rice, prefix: "meal.food.", in: app)
        try replaceText(in: singleField(prefix: "meal.weight.", in: app), with: "100", app: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try requireExists(app.navigationBars["今日"])

        let todayRow = namedRecordButton(mealName, in: app)
        try reveal(todayRow, in: app)
        let todayClock = try assertChineseClock(in: todayRow.label, uses12HourClock: uses12HourClock)
        XCTAssertEqual(todayClock.hour, selectedClock.hour)
        XCTAssertEqual(todayClock.period, selectedClock.period, "Saving must preserve AM/PM as well as the numeric clock.")
        XCTAssertEqual(todayClock.minute, selectedClock.minute, "Saving must preserve the actual picker time.")
        try openMeal(named: mealName, in: app)
        let detailTime = try uniqueIdentifiedControl(identifier: "meal.detail.time", in: app)
        try reveal(detailTime, in: app)
        try assertChineseDate(in: detailTime.label, requiresYear: true)
        let detailClock = try assertChineseClock(in: detailTime.label, uses12HourClock: uses12HourClock)
        XCTAssertEqual(detailClock.hour, selectedClock.hour)
        XCTAssertEqual(detailClock.period, selectedClock.period, "Saving must preserve AM/PM as well as the numeric clock.")
        XCTAssertEqual(detailClock.minute, selectedClock.minute)
        try verifyRiceWeight(100, rice: rice, in: app)
        attachScreen(app, name: "ChineseDatesUI-\(region)-meal-detail")
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])

        let history = app.buttons["查看全部历史"]
        try reveal(history, in: app)
        try tap(history)
        try requireExists(app.navigationBars["历史餐食"])
        let historyRow = namedRecordButton(mealName, in: app)
        try reveal(historyRow, in: app)
        try assertChineseDate(in: historyRow.label, requiresYear: false)
        let historyClock = try assertChineseClock(in: historyRow.label, uses12HourClock: uses12HourClock)
        XCTAssertEqual(historyClock.hour, selectedClock.hour)
        XCTAssertEqual(historyClock.period, selectedClock.period, "Saving must preserve AM/PM as well as the numeric clock.")
        XCTAssertEqual(historyClock.minute, selectedClock.minute)
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(100, rice: rice, in: app)
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])
        attachScreen(app, name: "ChineseDatesUI-\(region)-meal-history")
        try tap(app.navigationBars["历史餐食"].buttons["完成"])

        // The unique source note identifies one append-only QA goal version.
        // The shared helper explicitly selects Self Selected before editing it.
        try saveFictitiousGoal(energy: "2450", saturatedFat: "15", fibre: "30", sourceNote: sourceNote, in: app)
        try tap(app.buttons["settings.goalHistory"])
        try requireExists(app.navigationBars["目标历史"])
        let versions = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "goalHistory.row.", sourceNote
        ))
        try reveal(versions.firstMatch, in: app)
        guard versions.count == 1 else {
            XCTFail("This run's unique source note must identify exactly one confirmed goal version.")
            throw NavigationUIFailure.missingControl
        }
        let version = versions.firstMatch
        try assertChineseDate(in: version.label, requiresYear: false)
        _ = try assertChineseClock(in: version.label, uses12HourClock: uses12HourClock)
        try tap(version)
        try requireExists(app.navigationBars["目标版本详情"])
        let confirmedAt = try uniqueIdentifiedControl(identifier: "goalHistory.detail.confirmedAt", in: app)
        try reveal(confirmedAt, in: app)
        try assertChineseDate(in: confirmedAt.label, requiresYear: true)
        _ = try assertChineseClock(in: confirmedAt.label, uses12HourClock: uses12HourClock)
        let confirmationText = confirmedAt.label
        let secondsExpression = try NSRegularExpression(pattern: "[0-9]{1,2}[:：][0-9]{2}[:：]([0-9]{2})")
        guard let secondsMatch = secondsExpression.firstMatch(
            in: confirmationText, range: NSRange(confirmationText.startIndex..., in: confirmationText)
        ), let secondsRange = Range(secondsMatch.range(at: 1), in: confirmationText),
           let seconds = Int(confirmationText[secondsRange]) else {
            XCTFail("The confirmed goal detail must retain its displayed seconds: \(confirmationText)")
            throw NavigationUIFailure.conditionNotMet
        }
        XCTAssertTrue((0...59).contains(seconds), "Confirmation seconds must be a valid 0...59 value.")
        attachScreen(app, name: "ChineseDatesUI-\(region)-goal-confirmation")
        let back = app.navigationBars["目标版本详情"].buttons.matching(NSPredicate(
            format: "label IN %@", ["目标历史", "返回", "Back"]
        ))
        guard back.count == 1 else {
            XCTFail("Goal detail must expose one real Back action.")
            throw NavigationUIFailure.missingControl
        }
        try tap(back.firstMatch)
        let unknownHistory = app.staticTexts["开始记录目标历史之前的目标未知。之后每次修改都会保留；同一天多次修改，使用最后确认的目标。"]
        try reveal(unknownHistory, in: app)
        XCTAssertTrue(unknownHistory.isHittable, "Chinese date formatting must keep the existing unknown-history explanation visible.")
        try tap(app.navigationBars["目标历史"].buttons["完成"])

        try openGoalFromSettings(in: app)
        try chooseChineseGoalCalendarDateTwoDaysAhead(in: app)
        let goalBar = app.navigationBars["每日预算与目标"]
        try tap(goalBar.buttons["取消"])
        try requireExists(app.buttons["继续编辑"])
        try tap(app.buttons["继续编辑"])
        try assertChineseDate(in: app.staticTexts["goal.effectiveSummary"].label, requiresYear: false)
        try tap(goalBar.buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(goalBar.waitForNonExistence(timeout: 5))

        // Only delete this run's uniquely named synthetic meal, after verifying it.
        // Confirmed QA goal versions remain append-only; no store reset is used.
        try selectTab("今日", in: app)
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(100, rice: rice, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    private func displayedDatePickerText(_ picker: XCUIElement) -> String {
        ([picker.label, picker.value as? String ?? ""]
            + picker.descendants(matching: .button).allElementsBoundByIndex.map(\.label))
            .joined(separator: " ")
    }

    private func uniqueIdentifiedControl(identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let controls = app.descendants(matching: .any).matching(identifier: identifier)
        try requireExists(controls.firstMatch)
        guard controls.count == 1 else {
            XCTFail("The displayed control must expose exactly one \(identifier) identifier.")
            throw NavigationUIFailure.missingControl
        }
        return controls.firstMatch
    }

    private func assertChineseDate(in text: String, requiresYear: Bool) throws {
        let pattern = requiresYear
            ? "[0-9]{4}\\s*年\\s*[0-9]{1,2}\\s*月\\s*[0-9]{1,2}\\s*日"
            : "[0-9]{1,2}\\s*月\\s*[0-9]{1,2}\\s*日"
        XCTAssertNotNil(text.range(of: pattern, options: .regularExpression), "The actual visible date must use Chinese year/month/day: \(text)")
        let englishDateWords = "\\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?|at)\\b"
        XCTAssertNil(text.range(of: englishDateWords, options: [.regularExpression, .caseInsensitive]), "An English phone must not leak English month/date words into Chinese App dates.")
    }

    @discardableResult
    private func assertChineseClock(in text: String, uses12HourClock: Bool) throws -> (hour: Int, minute: Int, period: String?) {
        let expression = try NSRegularExpression(pattern: "([0-9]{1,2})[:：]([0-9]{2})")
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]), let minute = Int(text[minuteRange]) else {
            XCTFail("The real displayed time must contain an hour and minute: \(text)")
            throw NavigationUIFailure.conditionNotMet
        }
        XCTAssertTrue((0...59).contains(minute))
        let period = text.range(of: "凌晨|上午|中午|下午|晚上|午夜|早上|早晨|夜里|夜间", options: .regularExpression)
        XCTAssertNil(text.range(of: "\\b(?:AM|PM)\\b", options: [.regularExpression, .caseInsensitive]), "Chinese time must not contain English AM/PM.")
        if uses12HourClock {
            XCTAssertTrue((1...12).contains(hour), "The displayed 12-hour preference must be respected.")
            XCTAssertNotNil(period, "A 12-hour Chinese time must include its Chinese day period.")
        } else {
            XCTAssertTrue((0...23).contains(hour))
            XCTAssertNil(period, "The displayed 24-hour preference must omit a day period.")
        }
        return (hour, minute, period.map { String(text[$0]) })
    }

    private func chooseChineseGoalCalendarDateTwoDaysAhead(in app: XCUIApplication) throws {
        let other = app.buttons["goal.effectiveOther"]
        try reveal(other, in: app)
        if other.value as? String != "已展开" { try tap(other) }
        let pickers = app.datePickers.matching(identifier: "goal.effectiveDate")
        try reveal(pickers.firstMatch, in: app)
        guard pickers.count == 1 else {
            XCTFail("The goal form must expose one real date picker.")
            throw NavigationUIFailure.missingControl
        }
        let dates = pickers.firstMatch.descendants(matching: .button)
        guard dates.count == 1 else {
            XCTFail("The compact goal date picker must expose one real calendar button.")
            throw NavigationUIFailure.missingControl
        }
        // The compact native button's name is "Date Picker"; its value is the visible date.
        let selectedDateText = [dates.firstMatch.label, dates.firstMatch.value as? String ?? ""].joined(separator: " ")
        try assertChineseDate(in: selectedDateText, requiresYear: true)
        try tap(dates.firstMatch)
        let headers = app.buttons.matching(identifier: "DatePicker.Show")
        try requireExists(headers.firstMatch)
        guard headers.count == 1 else {
            XCTFail("The open native calendar must expose one month header.")
            throw NavigationUIFailure.missingControl
        }
        let header = headers.firstMatch
        let monthText = [header.label, header.value as? String ?? ""].joined(separator: " ")
        XCTAssertNotNil(monthText.range(of: "[0-9]{4}\\s*年.*[0-9]{1,2}\\s*月", options: .regularExpression), "The real calendar month must be Chinese under the English phone locale.")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let selectedDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: .now)))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "yyyy年M月"
        let expectedMonth = formatter.string(from: selectedDate)
        for _ in 0..<3 {
            let displayed = try XCTUnwrap(header.value as? String)
            if displayed == expectedMonth { break }
            let displayedDate = try XCTUnwrap(formatter.date(from: displayed))
            try tap(app.buttons[selectedDate < displayedDate ? "DatePicker.PreviousMonth" : "DatePicker.NextMonth"])
        }
        XCTAssertEqual(header.value as? String, expectedMonth)
        formatter.dateFormat = "M月d日"
        let shortDate = formatter.string(from: selectedDate)
        // Native calendar accessibility names follow the process language even
        // when the visible month/date values use the DatePicker's Chinese locale.
        // Accept exact independently formatted English labels for the same civil day;
        // the Chinese header and resulting selected date remain strict assertions.
        let englishUK = Date.FormatStyle(locale: Locale(identifier: "en_GB"), calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide).format(selectedDate)
        let englishUS = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide).format(selectedDate)
        attachScreen(app, name: "ChineseDatesUI-native-goal-calendar-open")
        let days = app.buttons.matching(NSPredicate(
            format: "label IN %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
            [shortDate, englishUK, englishUS], "\(shortDate) ", "今天, \(shortDate) "
        ))
        try requireExists(days.firstMatch)
        guard days.count == 1 else {
            XCTFail("The expected native calendar day must be unambiguous.")
            throw NavigationUIFailure.missingControl
        }
        try tap(days.firstMatch)
        let dismissPopover = app.buttons["PopoverDismissRegion"]
        if dismissPopover.exists { try tap(dismissPopover) }
        let summary = app.staticTexts["goal.effectiveSummary"]
        try reveal(summary, in: app)
        let parts = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let year = try XCTUnwrap(parts.year)
        let month = try XCTUnwrap(parts.month)
        let day = try XCTUnwrap(parts.day)
        let yearPrefix = year == calendar.component(.year, from: .now) ? "" : "\(year)年"
        XCTAssertEqual(summary.label, "\(yearPrefix)\(month)月\(day)日生效", "Date selection must retain the actual selected civil day.")
        attachScreen(app, name: "ChineseDatesUI-native-goal-calendar")
    }

    func testFourTabsAndUnreleasedPages() throws {
        executionTimeAllowance = 120
        let app = try launchApp()
        defer { app.terminate() }

        try selectTab("今日", in: app)
        try requireExists(app.buttons["预算与目标"], "Today's existing budget shortcut must remain reachable.")
        try requireExists(app.buttons["today.recordMeal"], "The single meal entry must be reachable only on Today.")
        XCTAssertEqual(app.buttons.matching(identifier: "today.recordMeal").count, 1)

        try selectTab("扫描", in: app)
        try requireExists(app.staticTexts["扫描尚未开放"], "Scan must explicitly remain unavailable.")
        try requireExists(
            app.staticTexts["食品标签识别将在后续独立切片中开放。当前不会启动相机或上传照片。"],
            "The scan placeholder must explain its current boundary."
        )
        XCTAssertFalse(app.buttons["预算与目标"].exists, "Today's budget control must not leak into Scan.")
        XCTAssertFalse(app.buttons["today.recordMeal"].exists, "Meal entry must not leak into Scan.")
        attachScreen(app, name: "NativeNavigationUI-scan-placeholder")

        try selectTab("日历", in: app)
        try requireExists(app.staticTexts["日历尚未开放"], "Calendar must explicitly remain unavailable.")
        try requireExists(
            app.staticTexts["按日回顾将在日确认与历史目标等功能完成后开放。现在可在今日页查看全部历史餐食。"],
            "The calendar placeholder must not pretend that day-history logic is complete."
        )
        XCTAssertFalse(app.buttons["预算与目标"].exists)
        XCTAssertFalse(app.buttons["today.recordMeal"].exists, "Meal entry must not leak into Calendar.")
        attachScreen(app, name: "NativeNavigationUI-calendar-placeholder")

        try selectTab("设置", in: app)
        try requireExists(app.buttons["每日预算与目标"], "Settings must expose the existing goal form.")
        try requireExists(app.buttons["本地备份"], "Settings must expose the existing backup flow.")
        XCTAssertFalse(app.buttons["预算与目标"].exists)
        XCTAssertFalse(app.buttons["today.recordMeal"].exists, "Meal entry must not leak into Settings.")

        try selectTab("今日", in: app)
        try requireExists(app.buttons["预算与目标"], "Returning to Today must preserve its dedicated toolbar.")
        attachScreen(app, name: "NativeNavigationUI-today-return")
    }

    /// Run on the synthetic QA phone at regular and actual maximum system text size.
    func testTodayBottomControlsStayOutsideScrollingContent() throws {
        // AX adds real form-row scrolling and longer fixture input, not App delays.
        executionTimeAllowance = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory ? 480 : 360
        let app = try launchApp()
        defer { app.terminate() }
        try selectTab("今日", in: app)
        try verifyTodayEntrySeparation(in: app)
        attachScreen(app, name: "TodayBottomUI-initial-unobstructed-viewport")

        let name = "[UI测试] 底部遮挡-\(String(UUID().uuidString.prefix(6)))"
        try createRiceMeal(named: name, grams: 180, in: app)
        let row = namedRecordButton(name, in: app)
        let id = try positionCollapsedTodayMealNearBottom(row, in: app)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.row.")).count, 1,
                       "The original 180g acceptance must run with exactly one Today meal on synthetic QA.")
        attachScreen(app, name: "TodayBottomUI-rice180-before-expansion")
        // No reveal or drag after expansion until the complete action group is verified.
        try tap(row)
        attachScreen(app, name: "TodayBottomUI-rice180-immediately-after-expansion")
        try waitForAutoRevealedTodayMeal(id: id, in: app)
        attachScreen(app, name: "TodayBottomUI-rice180-actions-visible-without-another-swipe")
        for action in ["edit", "reuse", "details"] {
            try tap(app.buttons["meal.\(action).\(id)"])
            if action == "details" {
                try requireExists(app.navigationBars["餐食详情"])
                try verifyRiceWeight(180, rice: "熟长粒白米饭（无盐）", in: app)
                try tap(app.navigationBars["餐食详情"].buttons["关闭"])
            } else {
                try requireExists(app.textFields["meal.name"])
                // The complete Today action group has already passed. This
                // gesture belongs only to the opened form's virtualized AX row.
                let weights = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.weight."))
                try reveal(weights.firstMatch, in: app)
                XCTAssertEqual(Double(try singleField(prefix: "meal.weight.", in: app).value as? String ?? ""), 180)
                try tap(mealEntryBar(in: app).buttons["取消"])
                XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
                XCTAssertFalse(app.buttons["放弃修改"].exists, "Opening an untouched edit or reuse draft must remain cancellable.")
            }
            try requireExists(app.navigationBars["今日"])
            try waitForAutoRevealedTodayMeal(id: id, in: app)
        }
        let history = app.buttons["查看全部历史"]
        try reveal(history, in: app)
        let readable = try todayReadableFrame(in: app)
        XCTAssertGreaterThanOrEqual(history.frame.minY, readable.minY)
        XCTAssertLessThanOrEqual(history.frame.maxY, readable.maxY,
                                 "The complete last content button must be above the fixed entry, not just have a hittable sliver.")
        try verifyTodayEntrySeparation(in: app)
        attachScreen(app, name: "TodayBottomUI-complete-history-button-above-entry")
        try tap(history)
        try requireExists(app.navigationBars["历史餐食"])
        try tap(app.navigationBars["历史餐食"].buttons["完成"])
        try requireExists(app.navigationBars["今日"])

        try tap(app.buttons["today.recordMeal"])
        try requireExists(app.buttons["空白记录"])
        try tap(app.navigationBars["记录一餐"].buttons["取消"])
        try requireExists(app.navigationBars["今日"])
        try selectTab("设置", in: app)
        XCTAssertFalse(app.buttons["today.recordMeal"].exists)
        try selectTab("今日", in: app)
        try verifyTodayEntrySeparation(in: app)
        try reveal(history, in: app)
        XCTAssertLessThanOrEqual(history.frame.maxY, try todayReadableFrame(in: app).maxY)
        attachScreen(app, name: "TodayBottomUI-returned-tabs-remain-unobstructed")

        // Delete only this run's uniquely named synthetic meal through the existing UI.
        try openMeal(named: name, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    private func verifyTodayEntrySeparation(in app: XCUIApplication) throws {
        let content = app.descendants(matching: .any).matching(identifier: "today.content").firstMatch
        let entry = app.buttons["today.recordMeal"]
        let tabs = app.tabBars.firstMatch
        try requireExists(content)
        try requireExists(entry)
        try requireExists(tabs)
        let scrollFrame = content.frame
        let entryFrame = entry.frame
        let tabFrame = tabs.frame
        guard [scrollFrame.maxY, entryFrame.minY, entryFrame.maxY, tabFrame.minY].allSatisfy(\.isFinite) else {
            attachFailureEvidence(app: app, element: content, context: "Today requires finite native viewport, entry and tab boundaries.")
            XCTFail("Native Today boundaries must be finite.")
            throw NavigationUIFailure.conditionNotMet
        }
        if scrollFrame.maxY > entryFrame.minY || entryFrame.maxY > tabFrame.minY {
            attachFailureEvidence(app: app, element: content,
                                  context: "Scroll=\(scrollFrame), entry=\(entryFrame), tabs=\(tabFrame)")
        }
        XCTAssertLessThanOrEqual(scrollFrame.maxY, entryFrame.minY,
                                 "Visible scrolling content must end before the fixed entry, including at intermediate scroll positions.")
        XCTAssertLessThanOrEqual(entryFrame.maxY, tabFrame.minY,
                                 "The complete entry must be above the native tab bar.")
        XCTAssertGreaterThanOrEqual(entryFrame.height, 44)
        XCTAssertTrue(entry.isHittable)
    }

    func testSettingsSaveRefreshesPreviouslyDisplayedTodayBudget() throws {
        // This test isolates invalidation of Today's already displayed budget.
        // Optional zero/blank and positive-value round trips have independent
        // real-form tests below. Keep the App alive between both saves so a
        // relaunch cannot conceal a stale Today view. Do not disable UI synchronization.
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }

        // Establish an explicit baseline through the real form; works with or without an old goal.
        try saveFictitiousGoal(energy: "2150", saturatedFat: "15", fibre: "30", in: app)
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_150, in: app)

        // Today already held 2150. Changing another tab's form must invalidate that stale view state.
        try saveFictitiousGoal(energy: "2350", saturatedFat: "15", fibre: "30", in: app)
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_350, in: app)
        attachScreen(app, name: "NativeNavigationUI-settings-save-today-refresh")

        // The same persisted values must be visible through Today's pre-existing shortcut.
        try tap(app.buttons["预算与目标"])
        try requireExists(app.navigationBars["每日预算与目标"])
        XCTAssertEqual(goalField("热量预算 (kcal)", in: app).value as? String, "2350.0")
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"])
        XCTAssertTrue(app.navigationBars["每日预算与目标"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["放弃修改"].exists, "Opening without editing must not require discard confirmation.")
    }

    func testGoalOptionalExplicitZeroAndBlankRoundTripThroughRealForm() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }

        // Set all fields through the real form. No previous test's goal is a prerequisite.
        try saveFictitiousGoal(energy: "2425", saturatedFat: "0", fibre: "", in: app)
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_425, in: app)
        try openGoalFromSettings(in: app)
        let saturatedFat = goalField("饱和脂肪上限 (g)", in: app)
        let fibre = goalField("纤维目标 (g)", in: app)
        try reveal(saturatedFat, in: app)
        XCTAssertEqual(saturatedFat.value as? String, "0.0", "Explicit zero must remain a saved value, not become unset.")
        try reveal(fibre, in: app)
        XCTAssertEqual(fibre.value as? String, "", "A blank optional value must remain empty, not become zero.")
        XCTAssertEqual(fibre.placeholderValue, "未设置", "Unset text belongs to the placeholder, not the saved input.")
        attachScreen(app, name: "NativeNavigationUI-optional-zero-and-unset")
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"])
        XCTAssertTrue(app.navigationBars["每日预算与目标"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["放弃修改"].exists, "An untouched reopened form must not require discard confirmation.")
    }

    func testGoalOptionalPositiveValuesRoundTripThroughRealForm() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }

        try saveFictitiousGoal(energy: "2465", saturatedFat: "15", fibre: "30", in: app)
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_465, in: app)
        try openGoalFromSettings(in: app)
        let saturatedFat = goalField("饱和脂肪上限 (g)", in: app)
        let fibre = goalField("纤维目标 (g)", in: app)
        try reveal(saturatedFat, in: app)
        XCTAssertEqual(saturatedFat.value as? String, "15.0")
        try reveal(fibre, in: app)
        XCTAssertEqual(fibre.value as? String, "30.0")
        attachScreen(app, name: "NativeNavigationUI-optional-positive-values")
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"])
        XCTAssertTrue(app.navigationBars["每日预算与目标"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    func testCancelProtectsDraftWithoutChangingSavedTodayBudget() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }

        try saveFictitiousGoal(energy: "2350", saturatedFat: "15", fibre: "30", in: app)
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_350, in: app)
        try openGoalFromSettings(in: app)
        let formBar = app.navigationBars["每日预算与目标"]
        // First prove this gesture actually dismisses an untouched form. Otherwise a later
        // no-dismiss observation could merely mean the gesture never reached the sheet.
        dragSheetDown(from: formBar, in: app)
        XCTAssertTrue(formBar.waitForNonExistence(timeout: 5), "An untouched goal sheet must permit the same dismissal gesture.")
        try openGoalFromSettings(in: app)
        try replaceText(in: goalField("热量预算 (kcal)", in: app), with: "9999", app: app)
        dragSheetDown(from: formBar, in: app)
        try requireExists(formBar, "A modified goal must remain open after the proven dismissal gesture.")
        XCTAssertEqual(goalField("热量预算 (kcal)", in: app).value as? String, "9999")
        try tap(formBar.buttons["取消"])
        try tap(app.buttons["继续编辑"])
        try requireExists(formBar, "Continue editing must retain the real form.")
        XCTAssertEqual(goalField("热量预算 (kcal)", in: app).value as? String, "9999")
        XCTAssertTrue(formBar.buttons["保存"].isEnabled, "Valid edits can be saved directly; only the explicit Save action confirms a new version.")

        try tap(formBar.buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(formBar.waitForNonExistence(timeout: 5))
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_350, in: app)

        // Reopen the store-backed form, not just the pre-existing label, to verify no accidental save.
        try openGoalFromSettings(in: app)
        XCTAssertEqual(goalField("热量预算 (kcal)", in: app).value as? String, "2350.0")
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"])
        XCTAssertTrue(app.navigationBars["每日预算与目标"].waitForNonExistence(timeout: 5))
        attachScreen(app, name: "NativeNavigationUI-cancel-preserves-settings")
    }

    func testMealInvalidRawWeightProtectsDraftAndAllowsExplicitDiscard() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }

        try openMealStart(in: app)
        try tap(app.buttons["空白记录"])
        let name = app.textFields["meal.name"]
        try requireExists(name)
        dragSheetDown(from: mealEntryBar(in: app), in: app)
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "Untouched meal dismissal is the positive gesture control.")
        try requireExists(app.buttons["空白记录"])

        try tap(app.buttons["空白记录"])
        try requireExists(name)
        let initialName = name.value as? String
        let weight = try singleField(prefix: "meal.weight.", in: app)
        try replaceText(in: weight, with: ".", app: app)
        XCTAssertEqual(name.value as? String, initialName, "Only the invalid raw weight changed, not the name.")
        XCTAssertFalse(mealEntryBar(in: app).buttons["保存"].isEnabled)
        dragSheetDown(from: mealEntryBar(in: app), in: app)
        try requireExists(name, "Invalid intermediate input must be protected even without valid food/weight.")
        XCTAssertEqual(weight.value as? String, ".")
        try tap(mealEntryBar(in: app).buttons["取消"])
        try tap(app.buttons["继续编辑"])
        XCTAssertEqual(weight.value as? String, ".", "Continue must retain the raw text, not normalize it away.")
        attachScreen(app, name: "NativeMealEntryUI-invalid-meal-weight-protected")
        try tap(mealEntryBar(in: app).buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        try requireExists(app.buttons["空白记录"])
        try tap(app.navigationBars["记录一餐"].firstMatch.buttons["取消"])
        try requireExists(app.navigationBars["今日"])
    }

    func testTemplateInvalidRawWeightProtectsDraftAndAllowsExplicitDiscard() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }

        try openMealStart(in: app)
        try reveal(app.buttons["管理常用模板"], in: app)
        try tap(app.buttons["管理常用模板"])
        let managerBar = app.navigationBars["常用模板"]
        try requireExists(managerBar)
        try tap(managerBar.buttons["新建"])
        let editorBar = app.navigationBars["新建常用模板"]
        let name = app.textFields["template.name"]
        try requireExists(name)
        dragSheetDown(from: editorBar, in: app)
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5), "Untouched template dismissal is the positive gesture control.")
        try tap(managerBar.buttons["新建"])
        try requireExists(name)
        let originalName = name.value as? String
        let weight = try singleField(prefix: "template.weight.", in: app)
        try replaceText(in: weight, with: ".", app: app)
        XCTAssertEqual(name.value as? String, originalName, "Only the invalid raw default weight changed.")
        XCTAssertFalse(editorBar.buttons["保存"].isEnabled)
        dragSheetDown(from: editorBar, in: app)
        try requireExists(editorBar, "A changed template draft must not disappear on a proven down gesture.")
        XCTAssertEqual(weight.value as? String, ".")
        try tap(editorBar.buttons["取消"])
        try tap(app.buttons["继续编辑"])
        XCTAssertEqual(weight.value as? String, ".")
        attachScreen(app, name: "NativeMealEntryUI-invalid-template-weight-protected")
        try tap(editorBar.buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5))
        try tap(managerBar.buttons["完成"])
        try tap(app.navigationBars["记录一餐"].firstMatch.buttons["取消"])
        try requireExists(app.navigationBars["今日"])
    }

    func testChineseMealSaveAndTemplateReusePreserveOriginalWeights() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let suffix = String(UUID().uuidString.prefix(8))
        let mealName = "[UI测试] 中文午餐-\(suffix)"
        let templateName = "[UI测试] 米饭模板-\(suffix)"
        let reusedName = "[UI测试] 复用午餐-\(suffix)"
        let rice = "熟长粒白米饭（无盐）"

        try openMealStart(in: app)
        try tap(app.buttons["空白记录"])
        try requireExists(app.textFields["meal.name"])
        // replaceText requires the real Chinese text to be visible, then taps the real Done
        // keyboard action and waits for the keyboard to disappear. No forced resignation.
        try replaceText(in: app.textFields["meal.name"], with: mealName, app: app)
        try selectFood(rice, prefix: "meal.food.", in: app)
        try replaceText(in: singleField(prefix: "meal.weight.", in: app), with: "200", app: app)
        let entrySave = mealEntryBar(in: app).buttons["保存"]
        try waitFor(NSPredicate(format: "isEnabled == true"), on: entrySave, message: "Valid weighed public rice must be savable.")
        try tap(entrySave)
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try requireExists(app.navigationBars["今日"])
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(200, rice: rice, in: app)
        try reveal(app.buttons["保存为常用模板"], in: app)
        try tap(app.buttons["保存为常用模板"])
        let templateBar = app.navigationBars["新建常用模板"]
        try requireExists(templateBar)
        try replaceText(in: app.textFields["template.name"], with: templateName, app: app)
        try tap(templateBar.buttons["保存"])
        XCTAssertTrue(templateBar.waitForNonExistence(timeout: 5))
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])

        try openMealStart(in: app)
        let templateButton = namedRecordButton(templateName, in: app)
        try reveal(templateButton, in: app)
        try tap(templateButton)
        try requireExists(app.textFields["meal.name"])
        let reuseWeight = try singleField(prefix: "meal.weight.", in: app)
        XCTAssertEqual(Double(reuseWeight.value as? String ?? ""), 200)
        try replaceText(in: app.textFields["meal.name"], with: reusedName, app: app)
        try replaceText(in: reuseWeight, with: "150", app: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        try requireExists(app.navigationBars["今日"])
        try openMeal(named: reusedName, in: app)
        try verifyRiceWeight(150, rice: rice, in: app)
        attachScreen(app, name: "NativeMealEntryUI-template-reused-150g")
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])

        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(200, rice: rice, in: app)
        attachScreen(app, name: "NativeMealEntryUI-original-meal-still-200g")
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])
        try openMealStart(in: app)
        try reveal(app.buttons["管理常用模板"], in: app)
        try tap(app.buttons["管理常用模板"])
        try requireExists(app.navigationBars["常用模板"])
        let savedTemplate = namedRecordButton(templateName, in: app)
        try reveal(savedTemplate, in: app)
        let useCountLabel = savedTemplate.descendants(matching: .staticText)
            .matching(identifier: "1 项 · 已使用 1 次").firstMatch
        XCTAssertTrue(
            savedTemplate.label.contains("已使用 1 次") || useCountLabel.exists,
            "Only the successfully saved reuse increments the template count."
        )
        try tap(savedTemplate)
        try requireExists(app.navigationBars["编辑常用模板"])
        XCTAssertEqual(Double(try singleField(prefix: "template.weight.", in: app).value as? String ?? ""), 200)
        attachScreen(app, name: "NativeMealEntryUI-template-default-still-200g")
        try tap(app.navigationBars["编辑常用模板"].buttons["取消"])
        XCTAssertFalse(app.buttons["放弃修改"].exists, "Opening the unchanged template must not dirty it.")
    }

    /// Run normally, and repeat with the simulator's real system content size set to AX5.
    /// The test does not set font preferences or introduce a test-only app rendering mode.
    func testMealControlsReachableAtCurrentSystemTextSize() throws {
        executionTimeAllowance = 180
        let app = try launchApp(language: "en-GB", region: "en_GB")
        defer { app.terminate() }
        let rice = "熟长粒白米饭（无盐）"

        try selectTab("今日", in: app)
        let history = app.buttons["查看全部历史"]
        let bottomContent = history.exists ? history : app.staticTexts["今天还没有记录餐食。"]
        try reveal(bottomContent, in: app)
        XCTAssertTrue(bottomContent.isHittable, "Today's bottom history/empty content must be reachable above the entry and tab bar.")
        attachScreen(app, name: "NativeMealEntryUI-system-text-size-today-bottom")
        try tap(app.buttons["today.recordMeal"])
        try tap(app.buttons["空白记录"])
        try requireExists(app.textFields["meal.name"])
        let datePickers = app.datePickers.matching(identifier: "meal.time")
        try reveal(datePickers.firstMatch, in: app)
        XCTAssertEqual(datePickers.count, 1)
        let hierarchy = XCTAttachment(string: datePickers.firstMatch.debugDescription)
        hierarchy.name = "ChineseDatesUI-AX-native-date-picker-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreen(app, name: "ChineseDatesUI-AX-native-meal-picker")
        let wheels = datePickers.firstMatch.pickerWheels
        if wheels.count > 0 {
            // Native AX layout uses Today + hour + minute, with no displayed year.
            // The phone's UK regional 24-hour default has three real wheels.
            XCTAssertEqual(wheels.count, 3)
            XCTAssertEqual(wheels.element(boundBy: 0).value as? String, "今天")
            let hourText = try XCTUnwrap(wheels.element(boundBy: 1).value as? String)
            let minuteText = try XCTUnwrap(wheels.element(boundBy: 2).value as? String)
            // Visible wheels are Chinese Today/date + numeric hour/minute. Native AX
            // unit descriptors follow the process language, as the observed tree shows.
            XCTAssertNotNil(hourText.range(of: "^[0-9]{1,2}(?:点| o[’']clock)$", options: .regularExpression))
            XCTAssertNotNil(minuteText.range(of: "^[0-9]{1,2}(?:分钟| minutes?)$", options: .regularExpression))
            let hour = try XCTUnwrap(Int(hourText.prefix(while: { $0.isNumber })))
            let minute = try XCTUnwrap(Int(minuteText.prefix(while: { $0.isNumber })))
            XCTAssertTrue((0...23).contains(hour))
            XCTAssertTrue((0...59).contains(minute))
        } else {
            let pickerText = displayedDatePickerText(datePickers.firstMatch)
            try assertChineseDate(in: pickerText, requiresYear: true)
            _ = try assertChineseClock(in: pickerText, uses12HourClock: false)
        }
        attachScreen(app, name: "ChineseDatesUI-AX-native-meal-picker")
        try selectFoodAtCurrentTextSize(rice, prefix: "meal.food.", in: app)
        let weight = try singleField(prefix: "meal.weight.", in: app)
        try replaceText(in: weight, with: "200", app: app)
        XCTAssertEqual(weight.value as? String, "200")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The real meal Done action must close the keyboard at the current system text size.")
        attachScreen(app, name: "NativeMealEntryUI-system-text-size-meal-menu-and-weight")

        try tap(mealEntryBar(in: app).buttons["取消"])
        try tap(app.buttons["继续编辑"])
        XCTAssertEqual(weight.value as? String, "200", "Continue editing must preserve the actual raw input.")
        try tap(mealEntryBar(in: app).buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try requireExists(app.buttons["空白记录"])
        try tap(app.navigationBars["记录一餐"].firstMatch.buttons["取消"])
        try requireExists(app.navigationBars["今日"])
    }

    func testTemplateControlsReachableAtCurrentSystemTextSize() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }
        let rice = "熟长粒白米饭（无盐）"

        try openMealStart(in: app)
        try reveal(app.buttons["管理常用模板"], in: app)
        try tap(app.buttons["管理常用模板"])
        let managerBar = app.navigationBars["常用模板"]
        try requireExists(managerBar)
        try tap(managerBar.buttons["新建"])
        let editorBar = app.navigationBars["新建常用模板"]
        try requireExists(app.textFields["template.name"])
        try selectFoodAtCurrentTextSize(rice, prefix: "template.food.", in: app)
        let weight = try singleField(prefix: "template.weight.", in: app)
        try replaceText(in: weight, with: "150", app: app)
        XCTAssertEqual(weight.value as? String, "150")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The real template Done action must close the keyboard at the current system text size.")
        attachScreen(app, name: "NativeMealEntryUI-system-text-size-template-menu-and-weight")

        try tap(editorBar.buttons["取消"])
        try tap(app.buttons["继续编辑"])
        XCTAssertEqual(weight.value as? String, "150")
        try tap(editorBar.buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(editorBar.waitForNonExistence(timeout: 5))
        try tap(managerBar.buttons["完成"])
        try tap(app.navigationBars["记录一餐"].firstMatch.buttons["取消"])
        try requireExists(app.navigationBars["今日"])
    }

    func testGoalFooterReachableAtCurrentSystemTextSize() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }

        try openGoalFromSettings(in: app)
        let formBar = app.navigationBars["每日预算与目标"]
        let fibre = goalField("纤维目标 (g)", in: app)
        try reveal(fibre, in: app)
        let originalValue = fibre.value as? String
        let replacement = Double(originalValue ?? "") == 31 ? "32" : "31"
        try replaceText(in: fibre, with: replacement, app: app)
        XCTAssertEqual(fibre.value as? String, replacement)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The real goal Done action must close the keyboard at the current system text size.")

        let sourceDisclosure = app.buttons["goal.sourceDisclosure"]
        try reveal(sourceDisclosure, in: app)
        XCTAssertTrue(sourceDisclosure.isHittable, "The collapsed source control must remain reachable at the current system text size.")
        let effectiveSummary = app.staticTexts["goal.effectiveSummary"]
        try reveal(effectiveSummary, in: app)
        XCTAssertTrue(effectiveSummary.isHittable, "The actual selected civil date must remain readable at the current system text size.")
        XCTAssertFalse(app.switches["我已核对并确认预算、目标与上限"].exists, "Confirmation belongs to the explicit Save action, without an additional switch.")
        XCTAssertTrue(formBar.buttons["保存"].isHittable)
        attachScreen(app, name: "NativeMealEntryUI-system-text-size-goal-footer")

        // No Save action: editing and navigating the footer must not create a QA version.
        try tap(formBar.buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(formBar.waitForNonExistence(timeout: 5))
        try openGoalFromSettings(in: app)
        let reopenedFibre = goalField("纤维目标 (g)", in: app)
        try reveal(reopenedFibre, in: app)
        XCTAssertEqual(reopenedFibre.value as? String, originalValue, "Discard must retain the existing persisted fibre setting, including absence.")
        try tap(formBar.buttons["取消"])
        XCTAssertTrue(formBar.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["放弃修改"].exists, "Opening without changes must not require discard confirmation.")
    }

    func testSettingsBackupEntryOpensExistingFlowWithoutExporting() throws {
        executionTimeAllowance = 120
        let app = try launchApp()
        defer { app.terminate() }

        try selectTab("设置", in: app)
        try tap(app.buttons["本地备份"])
        let backupBar = app.navigationBars["本地备份"]
        try requireExists(backupBar, "The original backup sheet must be reachable from Settings.")
        try requireExists(app.buttons["导出全量备份"])
        try requireExists(app.buttons["验证备份恢复"])
        // Opening the management UI does not authorize exporting health data or switching stores.
        attachScreen(app, name: "NativeNavigationUI-backup-entry")
        try tap(backupBar.buttons["完成"])
        XCTAssertTrue(backupBar.waitForNonExistence(timeout: 5))
        try requireExists(app.navigationBars["设置"])
        XCTAssertTrue(app.tabBars.buttons["设置"].isSelected)
    }

    func testInlineMealExpandEditReuseDeleteRecalculatesToday() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let suffix = String(UUID().uuidString.prefix(6))
        let firstName = "[UI测试] 展开甲-\(suffix)"
        let secondName = "[UI测试] 展开乙-\(suffix)"
        let reuseName = "[UI测试] 展开复用-\(suffix)"
        try createRiceMeal(named: firstName, grams: 200, in: app)
        try createRiceMeal(named: secondName, grams: 100, in: app)
        let baseline = try recordedTodayEnergy(in: app)

        let firstID = try expandMeal(named: firstName, in: app)
        XCTAssertFalse(app.navigationBars["餐食详情"].exists, "Expansion must stay in the list, not open a modal.")
        try tap(app.buttons["meal.row.\(firstID)"])
        XCTAssertEqual(app.buttons["meal.row.\(firstID)"].value as? String, "已收起")
        try tap(app.buttons["meal.row.\(firstID)"])
        let secondID = try expandMeal(named: secondName, in: app)
        XCTAssertEqual(app.buttons["meal.row.\(firstID)"].value as? String, "已收起", "Only one row per list may remain expanded.")
        XCTAssertEqual(app.buttons["meal.row.\(secondID)"].value as? String, "已展开")
        try attachInlineScreen(app, name: "NativeInlineMealUI-switch-one-expanded-row", anchor: app.buttons["meal.details.\(secondID)"])

        _ = try expandMeal(named: firstName, in: app)
        let edit = app.buttons["meal.edit.\(firstID)"]
        try reveal(edit, in: app)
        try tap(edit)
        try requireExists(app.textFields["meal.name"])
        XCTAssertEqual(Double(try singleField(prefix: "meal.weight.", in: app).value as? String ?? ""), 200)
        try replaceText(in: singleField(prefix: "meal.weight.", in: app), with: "150", app: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(try recordedTodayEnergy(in: app), baseline - 65.5, accuracy: 1, "Editing must invalidate Today's aggregate from the new snapshot.")

        _ = try expandMeal(named: firstName, in: app)
        let reuse = app.buttons["meal.reuse.\(firstID)"]
        try reveal(reuse, in: app)
        try tap(reuse)
        try requireExists(app.textFields["meal.name"])
        XCTAssertEqual(Double(try singleField(prefix: "meal.weight.", in: app).value as? String ?? ""), 150)
        try replaceText(in: app.textFields["meal.name"], with: reuseName, app: app)
        try replaceText(in: singleField(prefix: "meal.weight.", in: app), with: "75", app: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(try recordedTodayEnergy(in: app), baseline - 65.5 + 98.25, accuracy: 1)
        try openMeal(named: firstName, in: app)
        try verifyRiceWeight(150, rice: "熟长粒白米饭（无盐）", in: app)
        try tap(app.navigationBars["餐食详情"].buttons["关闭"])
        try openMeal(named: reuseName, in: app)
        try verifyRiceWeight(75, rice: "熟长粒白米饭（无盐）", in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: true, in: app)
        XCTAssertFalse(namedRecordButton(reuseName, in: app).exists, "A deleted row must not remain as a ghost expansion.")
        XCTAssertEqual(try recordedTodayEnergy(in: app), baseline - 65.5, accuracy: 1)
        try attachInlineScreen(app, name: "NativeInlineMealUI-edit-reuse-delete-recomputed", anchor: app.buttons["meal.row.\(firstID)"])

        // Remove only the two run-specific fictitious meals via their existing confirmed UI.
        try openMeal(named: firstName, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
        try openMeal(named: secondName, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    func testInlineHistoryDateEditMovesMealOutOfTodayAndBack() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 日期-\(String(UUID().uuidString.prefix(6)))"
        let now = Date()
        let calendar = Calendar.current
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        try createRiceMeal(named: name, grams: 100, in: app)
        let baseline = try recordedTodayEnergy(in: app)
        let id = try expandMeal(named: name, in: app)
        try reveal(app.buttons["meal.edit.\(id)"], in: app)
        try tap(app.buttons["meal.edit.\(id)"])
        try changeMealDate(to: yesterday, in: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(namedRecordButton(name, in: app).exists, "The edited yesterday meal must leave Today's rows.")
        XCTAssertEqual(try recordedTodayEnergy(in: app), baseline - 131, accuracy: 1)
        let history = app.buttons["查看全部历史"]
        try reveal(history, in: app)
        try tap(history)
        try requireExists(app.navigationBars["历史餐食"])
        _ = try expandMeal(named: name, in: app)
        XCTAssertFalse(app.navigationBars["餐食详情"].exists)
        try attachInlineScreen(app, name: "NativeInlineMealUI-yesterday-expanded-in-history", anchor: app.buttons["meal.details.\(id)"])
        let edit = app.buttons["meal.edit.\(id)"]
        try reveal(edit, in: app)
        try tap(edit)
        try changeMealDate(to: now, in: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try tap(app.navigationBars["历史餐食"].buttons["完成"])
        XCTAssertEqual(try recordedTodayEnergy(in: app), baseline, accuracy: 1)
        try openMeal(named: name, in: app)
        try verifyRiceWeight(100, rice: "熟长粒白米饭（无盐）", in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    /// Repeat with the actual simulator system set to AX5; does not change App preferences.
    func testInlineActionsReachableAtCurrentSystemTextSize() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 大字号展开-\(String(UUID().uuidString.prefix(6)))"
        try createRiceMeal(named: name, grams: 100, in: app)
        let id = try expandMeal(named: name, in: app)
        for action in ["edit", "reuse", "details"] {
            let button = app.buttons["meal.\(action).\(id)"]
            try reveal(button, in: app)
            XCTAssertTrue(button.isHittable, "Each explicit inline action must be reachable at the real current text size.")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        try attachInlineScreen(app, name: "NativeInlineMealUI-system-text-size-visible-actions", anchor: app.buttons["meal.details.\(id)"])
        try tap(app.buttons["meal.details.\(id)"])
        try requireExists(app.navigationBars["餐食详情"])
        try verifyRiceWeight(100, rice: "熟长粒白米饭（无盐）", in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    func testTodayInlineExpansionAutomaticallyRevealsDetailsAboveEntryButton() throws {
        guard !UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory else {
            throw XCTSkip("The regular-size case also checks the summary; AX uses the full three-action acceptance case.")
        }
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 自动定位详情-\(String(UUID().uuidString.prefix(6)))"
        try createRiceMeal(named: name, grams: 100, in: app)
        let row = namedRecordButton(name, in: app)
        let id = try positionCollapsedTodayMealNearBottom(row, in: app)
        attachScreen(app, name: "NativeInlineAutoscrollUI-collapsed-at-bottom")

        // No reveal/swipe after this tap: such a helper would perform the missing
        // scroll itself and could make the unfixed implementation pass.
        try tap(row)
        try waitForAutoRevealedTodayMeal(id: id, in: app)
        XCTAssertFalse(app.navigationBars["餐食详情"].exists, "Automatic positioning must preserve inline detail, not open a sheet.")
        XCTAssertTrue(app.tabBars.buttons["今日"].isSelected)
        attachScreen(app, name: "NativeInlineAutoscrollUI-expanded-without-manual-scroll")

        // Only after the no-gesture assertions may ordinary helpers scroll for
        // cleanup. Delete this unique synthetic meal, never another saved row.
        try tap(app.buttons["meal.details.\(id)"])
        try requireExists(app.navigationBars["餐食详情"])
        try verifyRiceWeight(100, rice: "熟长粒白米饭（无盐）", in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    /// Run only on synthetic QA with an already effective goal. Never changes a goal
    /// to satisfy the precondition; both regular and AX runs must show the real rows.
    func testTodayNutritionSpacingKeepsInlineActionsVisible() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 营养行间距-\(String(UUID().uuidString.prefix(8)))"
        let rice = "熟长粒白米饭（无盐）"
        try createRiceMeal(named: name, grams: 100, in: app)
        let today = try uniqueIdentifiedControl(identifier: "today.content", in: app)
        let rings = today.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "今日热量"))
        try requireExists(rings.firstMatch, "This spacing acceptance requires an already effective QA goal and the real Today energy ring; no goal will be created or changed.")
        guard rings.count == 1 else {
            XCTFail("The current goal must produce exactly one real Today energy ring.")
            throw NavigationUIFailure.missingControl
        }
        try reveal(rings.firstMatch, in: app)
        XCTAssertTrue((rings.firstMatch.value as? String ?? "").contains("预算"))
        attachScreen(app, name: "TodayNutritionSpacingUI-current-goal-ring")

        for (title, evidenceName) in [
            ("蛋白质目标", "protein"), ("碳水预算", "carbohydrate"),
            ("脂肪预算", "fat"), ("饱和脂肪上限", "saturated-fat"),
        ] {
            // R1 matched both an aggregate AX label and its StaticText title.
            // Choose the concrete title representation and require exact uniqueness;
            // never hide those two different AX representations with firstMatch.
            let titles = today.staticTexts.matching(NSPredicate(format: "label == %@", title))
            let combinedRows = today.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", title))
            let allRepresentations = today.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title))
            let diagnostic = XCTAttachment(string: "Synthetic meal: \(name)\napp.frame: \(app.frame)\n\(title): exactStaticText=\(titles.count), combinedOther=\(combinedRows.count), allPrefix=\(allRepresentations.count)\n\(app.debugDescription)")
            diagnostic.name = "TodayNutritionSpacingUI-\(evidenceName)-actual-AX-before-assertion"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            try requireExists(titles.firstMatch, "The real Today \(title) title must exist before this test can prove the taller nutrition card was exercised.")
            guard titles.count == 1 else {
                XCTFail("The frontmost Today card must expose exactly one StaticText title equal to \(title).")
                throw NavigationUIFailure.missingControl
            }
            try reveal(titles.firstMatch, in: app)
            XCTAssertTrue(titles.firstMatch.isHittable, "The current nutrition title must actually be visible before recording evidence.")
            attachScreen(app, name: "TodayNutritionSpacingUI-\(evidenceName)-row")
        }

        let row = namedRecordButton(name, in: app)
        let id = try positionCollapsedTodayMealNearBottom(row, in: app)
        attachScreen(app, name: "TodayNutritionSpacingUI-collapsed-at-bottom")
        // No test scroll after expansion: the existing strict helper requires all
        // three complete 44 pt actions above the fixed entry, with stable frames.
        try tap(row)
        try waitForAutoRevealedTodayMeal(id: id, in: app)
        XCTAssertFalse(app.navigationBars["餐食详情"].exists)
        XCTAssertTrue(app.tabBars.buttons["今日"].isSelected)
        attachScreen(app, name: "TodayNutritionSpacingUI-actions-visible-without-another-swipe")

        // The strict no-gesture check has passed. Remove only this run's uniquely
        // named meal after its saved public food and weight have been verified.
        try tap(app.buttons["meal.details.\(id)"])
        try requireExists(app.navigationBars["餐食详情"])
        try verifyRiceWeight(100, rice: rice, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
        XCTAssertTrue(namedRecordButton(name, in: app).waitForNonExistence(timeout: 5))
    }

    /// Also run at actual system AX text size: every expansion must expose its
    /// complete action group without a subsequent test-driven scroll.
    func testTodayInlineAutoscrollSurvivesCollapseReopenAndMealSwitch() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let suffix = String(UUID().uuidString.prefix(6))
        let olderName = "[UI测试] 自动定位旧餐-\(suffix)"
        let newerName = "[UI测试] 自动定位新餐-\(suffix)"
        try createRiceMeal(named: olderName, grams: 100, in: app)
        try createRiceMeal(named: newerName, grams: 125, in: app)
        let newer = namedRecordButton(newerName, in: app)
        let newerID = try positionCollapsedTodayMealNearBottom(newer, in: app)

        try tap(newer)
        try waitForAutoRevealedTodayMeal(id: newerID, in: app)
        if UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory {
            // Locate a tall summary only after all three actions have passed visibility checks.
            try reveal(newer, in: app)
        }
        try tap(newer)
        try waitFor(NSPredicate(format: "value == %@", "已收起"), on: newer, message: "Tapping the header again must collapse its inline detail.")
        XCTAssertTrue(app.buttons["meal.edit.\(newerID)"].waitForNonExistence(timeout: 5))
        // Collapse does not issue a new scroll request. Reopening the same real
        // header must nevertheless obtain a fresh request and reveal it again.
        try tap(newer)
        try waitForAutoRevealedTodayMeal(id: newerID, in: app)
        attachScreen(app, name: "NativeInlineAutoscrollUI-collapse-reopen-without-manual-scroll")

        let older = namedRecordButton(olderName, in: app)
        let olderID: String
        if UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory {
            // The action-first AX assertion has passed. Locate the summary to
            // collapse before preparing another meal, never to help its expansion.
            try reveal(newer, in: app)
            try tap(newer)
            try waitFor(NSPredicate(format: "value == %@", "已收起"), on: newer, message: "The overlong detail must be collapsible from its visible header.")
            olderID = try positionCollapsedTodayMealNearBottom(older, in: app)
        } else {
            try requireExists(older)
            try waitFor(liveHittablePredicate(), on: older, message: "The next regular-size header must remain reachable while another row is expanded.")
            olderID = try inlineMealID(of: older, in: app)
        }
        // Again, no reveal/swipe until positioning is verified. The normal-size
        // path switches directly from one expanded meal to another.
        try tap(older)
        try waitForAutoRevealedTodayMeal(id: olderID, in: app)
        XCTAssertEqual(newer.value as? String, "已收起", "Switching meals must not leave the previous row expanded.")
        XCTAssertFalse(app.buttons["meal.edit.\(newerID)"].exists)
        XCTAssertFalse(app.navigationBars["餐食详情"].exists)
        attachScreen(app, name: "NativeInlineAutoscrollUI-second-meal-without-manual-scroll")

        try openMeal(named: newerName, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
        try openMeal(named: olderName, in: app)
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    private func inlineMealID(of row: XCUIElement, in app: XCUIApplication) throws -> String {
        let prefix = "meal.row."
        guard row.identifier.hasPrefix(prefix) else {
            attachFailureEvidence(app: app, element: row, context: "Auto-scroll acceptance requires the unique named inline meal header.")
            XCTFail("The intended synthetic meal must resolve to its real stable header identifier.")
            throw NavigationUIFailure.missingControl
        }
        return String(row.identifier.dropFirst(prefix.count))
    }

    private func todayReadableFrame(in app: XCUIApplication) throws -> CGRect {
        let container = app.descendants(matching: .any).matching(identifier: "today.content").firstMatch
        let navigation = app.navigationBars["今日"]
        let entry = app.buttons["today.recordMeal"]
        let tabs = app.tabBars.firstMatch
        try requireExists(container)
        try requireExists(navigation)
        try requireExists(entry)
        try requireExists(tabs)
        let frame = container.frame.intersection(app.frame)
        let top = max(frame.minY, navigation.frame.maxY)
        let bottom = min(frame.maxY, entry.frame.minY, tabs.frame.minY)
        guard frame.width.isFinite, top.isFinite, bottom.isFinite,
              frame.width > 44, bottom - top > 88 else {
            attachFailureEvidence(app: app, element: container, context: "Today must expose a finite reading region above the fixed meal-entry button and below navigation.")
            XCTFail("The real Today reading bounds must be usable before checking auto-scroll.")
            throw NavigationUIFailure.conditionNotMet
        }
        return CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
    }

    private func positionCollapsedTodayMealNearBottom(_ row: XCUIElement, in app: XCUIApplication) throws -> String {
        try reveal(row, in: app)
        let id = try inlineMealID(of: row, in: app)
        XCTAssertEqual(row.value as? String, "已收起", "The regression setup must begin with a collapsed meal.")
        let container = app.descendants(matching: .any).matching(identifier: "today.content").firstMatch
        // Check once more after the last permitted drag; otherwise a valid
        // final position is reported as a setup failure without observing it.
        for attempt in 0...8 {
            let visible = try todayReadableFrame(in: app)
            let header = row.frame
            let isAccessibilitySize = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
            let summaryFits = header.height <= visible.height - 8
            let visibleHeader = header.intersection(visible)
            // R8's actual AX5 small phone had a 576 pt summary in a 384.5 pt
            // reading region. A real visible, hittable portion is enough to
            // tap it; only the following expanded actions must all fit at once.
            let summaryIsPrepared = isAccessibilitySize && !summaryFits
                ? visibleHeader.width >= 44 && visibleHeader.height >= 44
                : header.minY >= visible.minY
            if row.isHittable, summaryIsPrepared,
               header.maxY >= visible.minY + visible.height * 0.75,
               header.maxY <= visible.maxY - 8 {
                return id
            }
            guard attempt < 8 else { break }
            // Aim for the middle of the allowed bottom-quarter band, not its
            // edge: a tiny corrective drag may remain below native pan slop.
            // Use only the real scroll container's unobstructed bounds.
            // The header must settle in the bottom quarter, leaving too little
            // room for the nutrition rows and actions. Do not require a 40 pt
            // placement band: native drag deceleration can overshoot it.
            // All gestures precede the expansion tap, never its assertion.
            let quarterStart = visible.minY + visible.height * 0.75
            let bandMiddle = (quarterStart + visible.maxY - 8) / 2
            let targetBottom = isAccessibilitySize && summaryFits
                ? min(visible.maxY - 8, max(bandMiddle, visible.minY + header.height))
                : bandMiddle
            let desiredDelta = targetBottom - header.maxY
            let maximumStep = visible.height * 0.35
            let delta = max(-maximumStep, min(maximumStep, desiredDelta))
            let bounds = container.frame
            let startY = visible.midY - delta / 2
            let endY = visible.midY + delta / 2
            let start = container.coordinate(withNormalizedOffset: CGVector(
                dx: 0.04, dy: (startY - bounds.minY) / bounds.height
            ))
            let end = container.coordinate(withNormalizedOffset: CGVector(
                dx: 0.04, dy: (endY - bounds.minY) / bounds.height
            ))
            // A slow drag held at its endpoint avoids an inertial fling during
            // setup, particularly when an AX header occupies half the viewport.
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        attachFailureEvidence(app: app, element: row, context: "The collapsed header could not be positioned in the bottom quarter of the actual reading region.")
        XCTFail("The auto-scroll regression must start near the bottom; an arbitrary visible header is insufficient.")
        throw NavigationUIFailure.conditionNotMet
    }

    private func waitForAutoRevealedTodayMeal(id: String, in app: XCUIApplication) throws {
        let row = app.buttons["meal.row.\(id)"]
        let visible = try todayReadableFrame(in: app)
        let requiresSummary = !UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        let actions = [app.buttons["meal.edit.\(id)"], app.buttons["meal.reuse.\(id)"], app.buttons["meal.details.\(id)"]]
        let controls = requiresSummary ? [row] + actions : actions
        var previousFrames: [CGRect]?
        var stableObservations = 0
        let positioned = NSPredicate { _, _ in
            guard row.value as? String == "已展开",
                  controls.allSatisfy({ control in
                      guard control.exists, control.isHittable else { return false }
                      let frame = control.frame
                      return frame.width.isFinite && frame.height.isFinite
                          && frame.width > 0 && frame.height > 0
                          && frame.minY >= visible.minY - 1 && frame.maxY <= visible.maxY + 1
                  }), actions.allSatisfy({ $0.frame.height + 0.001 >= 44 }) else { return false }
            // Accessibility CGRect subtraction can produce 43.99999999999994
            // for a 44 pt control at a fractional origin. This is below one pixel,
            // not permission to accept a visibly smaller tap target.
            let frames = controls.map(\.frame)
            stableObservations = previousFrames == frames ? stableObservations + 1 : 0
            previousFrames = frames
            return stableObservations >= 2
        }
        do {
            try waitFor(
                positioned, on: row, timeout: 10,
                message: requiresSummary
                    ? "Single-tap expansion must reveal the summary and complete action group above the fixed entry without a test scroll."
                    : "AX expansion must reveal all three complete actions above the fixed entry without a test scroll."
            )
        } catch {
            attachFailureEvidence(app: app, element: row, context: "Reading region: \(visible); action frames: \(actions.map(\.frame))")
            throw error
        }
        let dimensions = actions.map {
            "\($0.identifier): \($0.frame), height=\(String(format: "%.17g", Double($0.frame.height)))"
        }.joined(separator: "\n")
        let evidence = XCTAttachment(string: "Reading region: \(visible)\n\(dimensions)")
        evidence.name = "Today-actions-complete-native-bounds"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testMealWeightFirstFocusDeletesLastDigitAndSaves() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let mealName = "[UI测试] 光标餐食-\(UUID().uuidString.prefix(8))"
        try createRiceMeal(named: mealName, grams: 500, in: app)
        let id = try expandMeal(named: mealName, in: app)
        let edit = app.buttons["meal.edit.\(id)"]
        try reveal(edit, in: app)
        try tap(edit)

        try verifyWeightCaretAtEnd(
            in: singleField(prefix: "meal.weight.", in: app),
            doneIdentifier: "meal.keyboardDone", app: app
        )
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try openMeal(named: mealName, in: app)
        try verifyRiceWeight(50, rice: "熟长粒白米饭（无盐）", in: app)
        attachScreen(app, name: "WeightCaret-meal-saved-50g")
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    func testTemplateWeightFirstFocusDeletesLastDigitAndDiscardPreservesMeal() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let mealName = "[UI测试] 光标模板来源-\(UUID().uuidString.prefix(8))"
        try createRiceMeal(named: mealName, grams: 500, in: app)
        try openMeal(named: mealName, in: app)
        let templateAction = app.buttons["保存为常用模板"]
        try reveal(templateAction, in: app)
        try tap(templateAction)
        let bar = app.navigationBars["新建常用模板"]
        try requireExists(bar)
        try verifyWeightCaretAtEnd(
            in: singleField(prefix: "template.weight.", in: app),
            doneIdentifier: "template.keyboardDone", app: app
        )
        try tap(bar.buttons["取消"])
        try requireExists(app.buttons["继续编辑"])
        try tap(app.buttons["继续编辑"])
        XCTAssertEqual(try singleField(prefix: "template.weight.", in: app).value as? String, "50")
        try tap(bar.buttons["取消"])
        try tap(app.buttons["放弃修改"])
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        try verifyRiceWeight(500, rice: "熟长粒白米饭（无盐）", in: app)
        attachScreen(app, name: "WeightCaret-template-discard-source-still-500g")
        try deleteCurrentlyOpenedMeal(cancelFirst: false, in: app)
    }

    private func verifyWeightCaretAtEnd(
        in field: XCUIElement, doneIdentifier: String, app: XCUIApplication
    ) throws {
        XCTAssertEqual(field.value as? String, "500")
        try reveal(field, in: app)
        // A normal tap in the broad native field, not a corrective tap next to the digits.
        // Delete proves the actual insertion point; no Select All or forced resignation.
        try tap(field)
        try requireExists(app.keyboards.firstMatch)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "50", "First focus must place the caret after the last digit.")
        // Stay in the same focus session, then tap before the visible digits.
        // Initial end placement must not continually steal the user's insertion point.
        let bounds = field.frame
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            XCTFail("The live native weight field must have usable bounds.")
            throw NavigationUIFailure.conditionNotMet
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        field.typeText("1")
        XCTAssertEqual(field.value as? String, "150", "A subsequent tap must still allow insertion before the value.")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "50")
        attachScreen(app, name: "WeightCaret-\(doneIdentifier)-first-focus-at-end")
        try finishKeyboardEditing(identifier: doneIdentifier, in: app)

        // The value is now shorter than at the first focus. An old end index is invalid.
        try tap(field)
        try requireExists(app.keyboards.firstMatch)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "5", "Refocusing must use the shorter current value, not a stale index.")
        field.typeText("0")
        XCTAssertEqual(field.value as? String, "50")
        try finishKeyboardEditing(identifier: doneIdentifier, in: app)
    }

    private func launchApp(language: String = "zh-Hans", region: String = "zh_CN") throws -> XCUIApplication {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests are authorized only for a dedicated fictitious-data simulator, never a physical device.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.ning6y6.ShiHeng")
        diagnosticApplication = app
        // System-supported process-local locale settings, not an app-specific data/reset mode.
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", region]
        app.launch()
        guard app.wait(for: .runningForeground, timeout: 15) else {
            attachFailureEvidence(app: app, element: app, context: "Fresh launch did not reach runningForeground.")
            XCTFail("The launched QA app must reach runningForeground before querying its tab bar.")
            throw NavigationUIFailure.conditionNotMet
        }
        let todayTab = app.tabBars.buttons["今日"]
        guard todayTab.waitForExistence(timeout: 15) else {
            attachFailureEvidence(app: app, element: todayTab, context: "Fresh launch did not expose the native Today tab.")
            XCTFail("The native system TabView must actually appear.")
            throw NavigationUIFailure.missingControl
        }
        return app
        #endif
    }

    private func selectTab(_ title: String, in app: XCUIApplication) throws {
        let tab = app.tabBars.buttons[title]
        try tap(tab)
        try waitFor(NSPredicate(format: "isSelected == true"), on: tab, message: "The tapped \(title) tab must become selected.")
        try requireExists(app.navigationBars[title], "The selected tab must expose its own navigation title.")
    }

    private func openGoalFromSettings(in app: XCUIApplication) throws {
        try selectTab("设置", in: app)
        try tap(app.buttons["每日预算与目标"])
        try requireExists(app.navigationBars["每日预算与目标"])
        try requireExists(goalField("热量预算 (kcal)", in: app))
    }

    private func openMealStart(in app: XCUIApplication) throws {
        // A history fallback may still be presented after its detail was closed.
        if app.navigationBars["历史餐食"].exists {
            try tap(app.navigationBars["历史餐食"].buttons["完成"])
        }
        try selectTab("今日", in: app)
        try tap(app.buttons["today.recordMeal"])
        try requireExists(app.buttons["空白记录"])
    }

    private func mealEntryBar(in app: XCUIApplication) -> XCUIElement {
        // The start sheet and nested entry share a title. Only the entry owns Save.
        let bars = app.navigationBars.matching(NSPredicate(format: "identifier IN %@", ["记录一餐", "编辑餐食"]))
            .containing(.button, identifier: "保存")
        XCTAssertLessThanOrEqual(bars.count, 1, "The frontmost entry/editor must expose one real Save bar.")
        return bars.firstMatch
    }

    private func singleField(prefix: String, in app: XCUIApplication) throws -> XCUIElement {
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        try requireExists(fields.firstMatch, "The named component field must exist.")
        guard fields.count == 1 else {
            XCTFail("This one-component fixture must expose exactly one \(prefix) field.")
            throw NavigationUIFailure.missingControl
        }
        return fields.firstMatch
    }

    private func selectFood(_ name: String, prefix: String, in app: XCUIApplication) throws {
        let pickers = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        try requireExists(pickers.firstMatch)
        guard pickers.count == 1 else {
            XCTFail("The fixture must expose one identified native food picker.")
            throw NavigationUIFailure.missingControl
        }
        try reveal(pickers.firstMatch, in: app)
        try tap(pickers.firstMatch)
        try tap(app.buttons[name])
        XCTAssertTrue(pickers.firstMatch.label.contains(name), "The real picker must show the selected public food.")
    }

    private func selectFoodAtCurrentTextSize(_ name: String, prefix: String, in app: XCUIApplication) throws {
        let controls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        // Native Form virtualizes offscreen rows at AX sizes. Scroll until the
        // actual control exists and is reachable before requiring its uniqueness.
        try reveal(controls.firstMatch, in: app)
        guard controls.count == 1 else {
            attachFailureEvidence(app: app, element: controls.firstMatch, context: "The one-component fixture must expose one identified food control.")
            XCTFail("The named food menu must be unambiguous.")
            throw NavigationUIFailure.missingControl
        }
        let control = controls.firstMatch
        try tap(control)
        try tap(app.buttons[name])
        if control.label == "食物" {
            // The accessibility-size native Menu has a concise label and the complete
            // selection in its value; default-size Picker labels retain the selected name.
            XCTAssertEqual(control.value as? String, name, "The accessibility menu must expose the full selected food name without truncation.")
        } else {
            XCTAssertTrue(control.label.contains(name), "The default-size native picker must show the complete selected public food.")
        }
    }

    private func namedRecordButton(_ name: String, in app: XCUIApplication) -> XCUIElement {
        // Labels may combine a row's name, time and amount. The run-specific exact name
        // anchors its prefix; never search an arbitrary meal or template by position.
        // A template exists in both the underlying start sheet and the manager.
        // Scope to the actual manager's stable row identifiers, not an arbitrary
        // first match from the two presentations of the same saved template.
        let candidates: XCUIElementQuery
        if app.navigationBars["常用模板"].exists {
            candidates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "template.manage."))
        } else if app.navigationBars["历史餐食"].exists {
            // A native sheet can expose the underlying Today's accessibility
            // elements too. Only query the actual frontmost history list.
            candidates = app.descendants(matching: .any).matching(identifier: "meal.history").firstMatch.buttons
        } else {
            candidates = app.buttons
        }
        let buttons = candidates.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, "\(name)、"))
        if buttons.count == 1 { return buttons.firstMatch }
        let containingText = candidates.containing(.staticText, identifier: name)
        XCTAssertLessThanOrEqual(containingText.count, 1, "The run-specific record name must be unambiguous.")
        return containingText.firstMatch
    }

    private func openMeal(named name: String, in app: XCUIApplication) throws {
        let id = try expandMeal(named: name, in: app)
        // History can expose the underlying Today's identical action identifier.
        // Query the actual frontmost page, then require its single real action.
        let containerID = app.navigationBars["历史餐食"].exists ? "meal.history" : "today.content"
        let container = app.descendants(matching: .any).matching(identifier: containerID).firstMatch
        let actions = container.buttons.matching(identifier: "meal.details.\(id)")
        try requireExists(actions.firstMatch)
        XCTAssertEqual(actions.count, 1)
        let details = actions.firstMatch
        try reveal(details, in: app)
        try tap(details)
        try requireExists(app.navigationBars["餐食详情"])
    }

    @discardableResult
    private func expandMeal(named name: String, in app: XCUIApplication) throws -> String {
        var row = namedRecordButton(name, in: app)
        if !row.exists && !app.navigationBars["历史餐食"].exists {
            let history = app.buttons["查看全部历史"]
            try reveal(history, in: app)
            try tap(history)
            try requireExists(app.navigationBars["历史餐食"])
            row = namedRecordButton(name, in: app)
        }
        try reveal(row, in: app)
        let prefix = "meal.row."
        guard row.identifier.hasPrefix(prefix) else {
            attachFailureEvidence(app: app, element: row, context: "Meal expansion must use its stable actual header identifier.")
            XCTFail("The intended named meal must resolve to one inline header.")
            throw NavigationUIFailure.missingControl
        }
        let id = String(row.identifier.dropFirst(prefix.count))
        if row.value as? String != "已展开" { try tap(row) }
        XCTAssertEqual(row.value as? String, "已展开")
        return id
    }

    private func createRiceMeal(named name: String, grams: Int, in app: XCUIApplication) throws {
        try openMealStart(in: app)
        try tap(app.buttons["空白记录"])
        try requireExists(app.textFields["meal.name"])
        try replaceText(in: app.textFields["meal.name"], with: name, app: app)
        try selectFoodAtCurrentTextSize("熟长粒白米饭（无盐）", prefix: "meal.food.", in: app)
        try replaceText(in: singleField(prefix: "meal.weight.", in: app), with: String(grams), app: app)
        try tap(mealEntryBar(in: app).buttons["保存"])
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
        try requireExists(app.navigationBars["今日"])
    }

    private func attachInlineScreen(_ app: XCUIApplication, name: String, anchor: XCUIElement) throws {
        // An immediate post-toggle screenshot caught the actual default animation
        // mid-transition in R3. Reveal the intended expanded content, then require
        // its real frame to settle across observations; do not wait a guessed delay.
        try reveal(anchor, in: app)
        var previousFrame: CGRect?
        var stableObservations = 0
        let settled = NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement, element.exists, element.isHittable else { return false }
            let current = element.frame
            guard current.width.isFinite, current.height.isFinite, current.width > 0, current.height > 0 else { return false }
            stableObservations = previousFrame == current ? stableObservations + 1 : 0
            previousFrame = current
            return stableObservations >= 2
        }
        try waitFor(settled, on: anchor, timeout: 8, message: "Inline screenshot evidence requires visible settled content.")
        attachScreen(app, name: name)
    }

    private func recordedTodayEnergy(in app: XCUIApplication) throws -> Double {
        // A measured displayed baseline avoids resetting or querying the QA store.
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "今日热量")).firstMatch
        try reveal(ring, in: app)
        try requireExists(ring)
        let value = ring.value as? String ?? ""
        let expression = try NSRegularExpression(pattern: "已记录 ([0-9,，.]+) 千卡")
        guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value),
              let number = Double(value[range].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")) else {
            attachFailureEvidence(app: app, element: ring, context: "The real ring must expose a finite recorded kcal baseline.")
            XCTFail("Cannot read the actual Today energy value.")
            throw NavigationUIFailure.conditionNotMet
        }
        return number
    }

    private func deleteCurrentlyOpenedMeal(cancelFirst: Bool, in app: XCUIApplication) throws {
        let action = app.buttons["删除餐食"]
        try reveal(action, in: app)
        try tap(action)
        let dialog = app.sheets.firstMatch
        try requireExists(dialog)
        if cancelFirst {
            if dialog.buttons["取消"].exists {
                try tap(dialog.buttons["取消"])
            } else {
                // R2's real hierarchy presents confirmationDialog as a native
                // Popover without a cancel button. Its explicit dismiss region
                // is outside the popover; derive an uncovered point from the
                // two observed bounds rather than tapping a guessed location.
                let region = app.descendants(matching: .any).matching(identifier: "PopoverDismissRegion").firstMatch
                let popover = app.popovers.firstMatch
                try requireExists(region)
                try requireExists(popover)
                let bounds = region.frame
                let popup = popover.frame
                guard region.isHittable, bounds.width.isFinite, bounds.height.isFinite,
                      bounds.width > 44, bounds.height > 44 else {
                    XCTFail("The native popover must expose a usable actual dismiss region.")
                    throw NavigationUIFailure.conditionNotMet
                }
                let point = CGPoint(x: bounds.minX + 22, y: bounds.midY)
                guard bounds.contains(point), !popup.insetBy(dx: -1, dy: -1).contains(point) else {
                    XCTFail("Cancellation must target the observed native surface outside the confirmation.")
                    throw NavigationUIFailure.conditionNotMet
                }
                region.coordinate(withNormalizedOffset: CGVector(
                    dx: (point.x - bounds.minX) / bounds.width,
                    dy: (point.y - bounds.minY) / bounds.height
                )).tap()
            }
            XCTAssertTrue(dialog.waitForNonExistence(timeout: 5), "Cancel must dismiss only the deletion confirmation.")
            try requireExists(app.navigationBars["餐食详情"])
            try tap(action)
            try requireExists(dialog)
        }
        try tap(dialog.buttons["删除餐食"])
        XCTAssertTrue(app.navigationBars["餐食详情"].waitForNonExistence(timeout: 5))
    }

    private func changeMealDate(to date: Date, in app: XCUIApplication) throws {
        let picker = app.descendants(matching: .any).matching(identifier: "meal.time").firstMatch
        try reveal(picker, in: app)
        let dateButtons = picker.descendants(matching: .button).matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年.*"))
        guard dateButtons.count == 1 else {
            attachFailureEvidence(app: app, element: picker, context: "Expected one native compact calendar date button.")
            XCTFail("The real date picker must expose one date control.")
            throw NavigationUIFailure.missingControl
        }
        try tap(dateButtons.firstMatch)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        let targetMonth = formatter.string(from: date)
        let header = app.buttons["DatePicker.Show"]
        try requireExists(header)
        // A yesterday/today pair can straddle a month boundary. Navigate using
        // actual native month controls and its observed year/month, not coordinates.
        for _ in 0..<3 {
            guard let displayed = header.value as? String else {
                XCTFail("The native calendar must expose its displayed month.")
                throw NavigationUIFailure.conditionNotMet
            }
            if displayed == targetMonth { break }
            guard let monthDate = formatter.date(from: displayed) else {
                XCTFail("The actual displayed calendar month must be readable.")
                throw NavigationUIFailure.conditionNotMet
            }
            try tap(app.buttons[date < monthDate ? "DatePicker.PreviousMonth" : "DatePicker.NextMonth"])
        }
        XCTAssertEqual(header.value as? String, targetMonth)
        formatter.dateFormat = "M月d日"
        let shortDate = formatter.string(from: date)
        let days = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
            shortDate, "\(shortDate) ", "今天, \(shortDate) "
        ))
        guard days.count == 1 else {
            attachFailureEvidence(app: app, element: header, context: "Expected one native day button for \(shortDate); found \(days.count).")
            XCTFail("The intended calendar date must resolve uniquely.")
            throw NavigationUIFailure.missingControl
        }
        try tap(days.firstMatch)
        // R1 actual hierarchy exposes this native dismiss button. Do not blindly
        // tap the popover's background or force the date binding in the App.
        let dismissPopover = app.buttons["PopoverDismissRegion"]
        if dismissPopover.exists { try tap(dismissPopover) }
        formatter.dateFormat = "yyyy年M月d日"
        try requireExists(picker.descendants(matching: .button).matching(identifier: formatter.string(from: date)).firstMatch)
        try requireExists(mealEntryBar(in: app))
    }

    private func verifyRiceWeight(_ grams: Int, rice: String, in app: XCUIApplication) throws {
        let combined = "\(rice)、\(grams) g"
        // English system accessibility joins LabeledContent with a comma even when
        // its visible custom labels are Chinese. Keep the food and weight exact.
        let englishCombined = "\(rice), \(grams) g"
        // The expanded underlying row also exposes the identical saved weight.
        // Assert the frontmost detail snapshot, not hidden content behind its sheet.
        let detail = app.descendants(matching: .any).matching(identifier: "meal.detail").firstMatch
        try requireExists(detail)
        let row = detail.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label == %@ OR label == %@", combined, englishCombined, "\(grams) g"
        )).firstMatch
        try reveal(row, in: app)
        try requireExists(row, "The stored rice snapshot must retain the expected \(grams) g.")
    }

    private func dragSheetDown(from bar: XCUIElement, in app: XCUIApplication) {
        // Start on the real navigation title rather than a field/scroll view. The matching
        // untouched-form control proves that this gesture actually triggers dismissal.
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func saveFictitiousGoal(
        energy: String, saturatedFat: String, fibre: String, sourceNote: String? = nil,
        in app: XCUIApplication
    ) throws {
        try openGoalFromSettings(in: app)
        var lastEditedField: XCUIElement?
        for (label, value) in [
            ("热量预算 (kcal)", energy),
            ("蛋白质目标 (g)", "145"),
            ("碳水预算 (g)", "210"),
            ("脂肪预算 (g)", "60"),
            ("饱和脂肪上限 (g)", saturatedFat),
            ("纤维目标 (g)", fibre),
        ] {
            let field = goalField(label, in: app)
            try reveal(field, in: app)
            let current = field.value as? String ?? ""
            if value.isEmpty {
                if current.isEmpty || current == "未设置" { continue }
            } else if let currentNumber = Double(current), let intendedNumber = Double(value), currentNumber == intendedNumber {
                // The existing Double text may include .0. Skip only equal numbers, never blank vs 0.
                continue
            }
            // A goal is one multi-field entry session. Keep the real software
            // keyboard between fields instead of opening/closing it after every
            // number. Each field still requires a real tap, selection and exact
            // value assertion. Dedicated keyboard/draft tests keep per-input Done.
            try replaceText(in: field, with: value, app: app, dismissKeyboard: false)
            lastEditedField = field
        }
        if let lastEditedField {
            // Interactive scrolling can legitimately dismiss the keyboard while
            // revealing unchanged lower rows. Refocus the actual edited field if
            // needed; an edited session must still exercise the real Done button.
            if !app.keyboards.firstMatch.exists {
                try reveal(lastEditedField, in: app)
                try tap(lastEditedField)
                try revealInputAboveKeyboard(lastEditedField, in: app)
            }
            try finishKeyboardEditing(identifier: "goal.keyboardDone", in: app)
        }
        let formBar = app.navigationBars["每日预算与目标"]
        let save = formBar.buttons["保存"]
        XCTAssertFalse(app.switches["我已核对并确认预算、目标与上限"].exists, "The goal form must not require a second confirmation control.")
        if let sourceNote {
            let disclosure = app.buttons["goal.sourceDisclosure"]
            try reveal(disclosure, in: app)
            if disclosure.value as? String != "已展开" { try tap(disclosure) }
            let sources = app.buttons.matching(identifier: "goal.source")
            try reveal(sources.firstMatch, in: app)
            guard sources.count == 1 else {
                XCTFail("The goal form must expose one explicit source picker.")
                throw NavigationUIFailure.missingControl
            }
            try tap(sources.firstMatch)
            let selfSelected = app.buttons.matching(NSPredicate(format: "label == %@", "自行选择"))
            try requireExists(selfSelected.firstMatch)
            guard selfSelected.count == 1 else {
                XCTFail("The source menu must expose one Self Selected action.")
                throw NavigationUIFailure.missingControl
            }
            try tap(selfSelected.firstMatch)
            let note = try uniqueIdentifiedControl(identifier: "goal.sourceNote", in: app)
            try reveal(note, in: app)
            // A unique marker is sufficient to identify this append-only QA version.
            // Append through the real keyboard instead of replacing a long old note;
            // repeated runs retain prior notes and never mutate confirmed versions.
            try tap(note)
            try requireExists(app.keyboards.firstMatch)
            note.typeText(" · \(sourceNote)")
            XCTAssertTrue((note.value as? String ?? "").contains(sourceNote))
            try finishKeyboardEditing(identifier: "goal.keyboardDone", in: app)
        }
        let today = app.buttons["goal.effectiveToday"]
        try reveal(today, in: app)
        try tap(today)
        try waitFor(NSPredicate(format: "isEnabled == true"), on: save, message: "Valid input and date must enable the explicit Save confirmation action.")
        try tap(save)
        XCTAssertTrue(formBar.waitForNonExistence(timeout: 5), "Successful save must close the existing sheet.")
        try requireExists(app.navigationBars["设置"])
    }

    private func goalField(_ title: String, in app: XCUIApplication) -> XCUIElement {
        // UI-2B assigns identifiers directly to these six TextFields. Selection is independent
        // of translated/composed labels, while the exact visible title is asserted separately.
        let identifier: String
        switch title {
        case "热量预算 (kcal)": identifier = "goal.energy"
        case "蛋白质目标 (g)": identifier = "goal.protein"
        case "碳水预算 (g)": identifier = "goal.carbohydrate"
        case "脂肪预算 (g)": identifier = "goal.fat"
        case "饱和脂肪上限 (g)": identifier = "goal.saturatedFat"
        case "纤维目标 (g)": identifier = "goal.fibre"
        default:
            XCTFail("The test must request an explicitly named goal field.")
            return app.textFields["unexpected-goal-field"]
        }
        let matchingFields = app.textFields.matching(identifier: identifier)
        XCTAssertLessThanOrEqual(matchingFields.count, 1, "Each named goal field must be unambiguous.")
        let field = matchingFields.firstMatch
        if field.exists { verifyGoalFieldLabel(field) }
        return field
    }

    private func verifyGoalFieldLabel(_ field: XCUIElement) {
        let expected: String
        switch field.identifier {
        case "goal.energy": expected = "热量预算 (kcal)"
        case "goal.protein": expected = "蛋白质目标 (g)"
        case "goal.carbohydrate": expected = "碳水预算 (g)"
        case "goal.fat": expected = "脂肪预算 (g)"
        case "goal.saturatedFat": expected = "饱和脂肪上限 (g)"
        case "goal.fibre": expected = "纤维目标 (g)"
        default: return
        }
        XCTAssertEqual(field.label, expected, "The actual field must expose its visible title exactly once, not a duplicated label.")
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication, dismissKeyboard: Bool = true) throws {
        try reveal(field, in: app)
        let oldValue = field.value as? String ?? ""
        let placeholderValues = ["请输入", "未设置", "模板名称", "重量", "默认重量", "克重", "来源说明（可选）", "来源说明（必填）"]
        let hasExistingText = !oldValue.isEmpty && !placeholderValues.contains(oldValue)
        // At AX sizes the meal name is leading-aligned in a wide native field.
        // R7's real screenshot shows a centre press in blank space only offered
        // Select, not Select All. Use the observed text edge, like the goal fields.
        // Weight digits occupy this aligned text edge too; a centre press may only move the caret.
        let selectsTextAtAlignedEdge = field.identifier.hasPrefix("goal.")
            || field.identifier.hasPrefix("meal.weight.")
            || (field.identifier == "meal.name"
                && UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory)
        if field.identifier.hasPrefix("goal."), app.keyboards.firstMatch.exists {
            // With a previous input focused, the next row may sit behind the
            // floating Done toolbar despite reporting isHittable. Reveal its
            // complete input rectangle before attempting to transfer focus.
            try revealInputAboveKeyboard(field, in: app)
        }
        try tap(field)
        try revealInputAboveKeyboard(field, in: app)
        if field.identifier.hasPrefix("goal.") {
            // R5's event snapshot retained saturatedFat focus after revealing
            // the blank fibre row. Retap the now visible actual control before
            // selection/typeText; never redirect typing to the previous field.
            try tap(field)
        }
        if hasExistingText {
            // Hardware Command-A was ignored by the actual simulator in AX5 R3.
            // Use the real touch edit menu on the now-independent input frame,
            // then require its unique Select All action and exact resulting text.
            if selectsTextAtAlignedEdge {
                // R3's actual hierarchy/screenshot: this wide, trailing-aligned
                // TextField's centre was blank. Pressing it left the caret before
                // 30.0 and produced no menu. GoalSettingsView places text at the
                // trailing edge normally and leading edge at system AX sizes.
                // R4 long-pressing the number moved the caret but showed no
                // menu. Double-tap the actual text to request native selection.
                // Target that side inside the observed finite input bounds, not
                // a guessed screen point or a substitute for a failed button tap.
                let bounds = field.frame
                guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                    XCTFail("A native input edit gesture requires finite non-empty bounds.")
                    throw NavigationUIFailure.conditionNotMet
                }
                let leading = field.identifier == "goal.sourceNote"
                    || UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
                field.coordinate(withNormalizedOffset: CGVector(dx: leading ? 0.02 : 0.98, dy: 0.5))
                    .doubleTap()
            } else {
                field.press(forDuration: 1)
            }
            let selectAllLabels = NSPredicate(format: "label IN %@", ["全选", "Select All"])
            let menuItems = app.menuItems.matching(selectAllLabels)
            let buttons = app.buttons.matching(selectAllLabels)
            let menuAppeared = menuItems.firstMatch.waitForExistence(timeout: 5)
            if !menuAppeared { _ = buttons.firstMatch.waitForExistence(timeout: 5) }
            let actions = menuItems.allElementsBoundByIndex + buttons.allElementsBoundByIndex
            if actions.count == 1, let selectAll = actions.first {
                try tap(selectAll)
                field.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
            } else if actions.isEmpty, selectsTextAtAlignedEdge {
                // Native selection may already span the whole value, in which
                // case Select All is omitted. Cut is only evidence of *some*
                // selection: perform the unique real menu action and require
                // an entirely empty value before entering new text. Any residue
                // fails immediately; never blindly delete extra characters.
                let cutLabels = NSPredicate(format: "label IN %@", ["剪切", "Cut"])
                let cuts = app.menuItems.matching(cutLabels).allElementsBoundByIndex
                    + app.buttons.matching(cutLabels).allElementsBoundByIndex
                guard cuts.count == 1, let cut = cuts.first else {
                    attachFailureEvidence(app: app, element: field, context: "No unique native Select All or Cut selection action.")
                    XCTFail("Replacing old input requires a real unambiguous native selection action.")
                    throw NavigationUIFailure.missingControl
                }
                try tap(cut)
                guard let clearedValue = field.value as? String,
                      clearedValue.isEmpty || clearedValue == field.placeholderValue else {
                    attachFailureEvidence(app: app, element: field, context: "Native Cut left text; full selection was not established.")
                    XCTFail("The entire old value must be cleared before replacement.")
                    throw NavigationUIFailure.conditionNotMet
                }
                if !text.isEmpty { field.typeText(text) }
            } else {
                attachFailureEvidence(app: app, element: field, context: "Expected one real touch Select All action; found \(actions.count).")
                XCTFail("Native selection actions must be unambiguous.")
                throw NavigationUIFailure.missingControl
            }
        } else if !text.isEmpty {
            field.typeText(text)
        }
        if text.isEmpty {
            let clearedValue = field.value as? String ?? ""
            XCTAssertTrue(clearedValue.isEmpty || placeholderValues.contains(clearedValue))
        } else {
            XCTAssertEqual(field.value as? String, text)
        }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            attachFailureEvidence(app: app, element: field, context: "Actual software keyboard missing after text input.")
            XCTFail("Real text input must expose the software keyboard.")
            throw NavigationUIFailure.missingControl
        }
        if dismissKeyboard {
            let doneIdentifier: String
            switch field.identifier {
            case let identifier where identifier.hasPrefix("meal."):
                doneIdentifier = "meal.keyboardDone"
            case let identifier where identifier.hasPrefix("template."):
                doneIdentifier = "template.keyboardDone"
            case let identifier where identifier.hasPrefix("goal."):
                doneIdentifier = "goal.keyboardDone"
            default:
                attachFailureEvidence(app: app, element: field, context: "An unknown form field cannot select a keyboard Done action.")
                XCTFail("The form field must identify its own real keyboard Done button.")
                throw NavigationUIFailure.missingControl
            }
            try finishKeyboardEditing(identifier: doneIdentifier, in: app)
        }
    }

    private func finishKeyboardEditing(identifier: String, in app: XCUIApplication) throws {
        let keyboard = app.keyboards.firstMatch
        try requireExists(keyboard, "A real software keyboard must be open before testing Done.")
        let doneButtons = app.buttons.matching(identifier: identifier)
        let done = doneButtons.firstMatch
        guard done.waitForExistence(timeout: 5), doneButtons.count == 1 else {
            attachFailureEvidence(app: app, element: done, context: "Expected exactly one \(identifier) button; found \(doneButtons.count).")
            XCTFail("The current form must expose exactly one identified keyboard Done button.")
            throw NavigationUIFailure.missingControl
        }
        XCTAssertEqual(done.label, "完成", "The identified action must remain the visible Done control.")
        try tap(done)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "The real Done action must dismiss the keyboard.")
    }

    private func verifyTodayBudget(_ energy: Int, in app: XCUIApplication) throws {
        let grouped = energy.formatted(.number.locale(Locale(identifier: "zh_CN")))
        let ungrouped = String(energy)
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "今日热量")).firstMatch
        if ring.waitForExistence(timeout: 2) {
            try waitFor(
                NSPredicate(format: "value CONTAINS %@ OR value CONTAINS %@", "预算 \(grouped) 千卡", "预算 \(ungrouped) 千卡"),
                on: ring,
                message: "Today's real ring must read the newly saved budget."
            )
        } else {
            let disclosure = app.buttons["查看已保存预算与目标"]
            try reveal(disclosure, in: app)
            let budgetValue = app.staticTexts.matching(
                // R3's real hierarchy combines each LabeledContent row into one StaticText.
                // Keep the expected budget exact so stale 2150 cannot satisfy a 2350 assertion.
                NSPredicate(
                    format: "label == %@ OR label == %@ OR label == %@ OR label == %@",
                    "热量预算、\(grouped) kcal", "热量预算、\(ungrouped) kcal",
                    "\(grouped) kcal", "\(ungrouped) kcal"
                )
            ).firstMatch
            if !budgetValue.exists { disclosure.tap() }
            try requireExists(budgetValue, "The neutral empty-intake card must show the newly saved budget, not stale state.")
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        // Bounded scrolling waits for an observable control, never for an arbitrary fixed delay.
        for _ in 0..<16 {
            if element.waitForExistence(timeout: 1), element.isHittable {
                verifyGoalFieldLabel(element)
                return
            }
            let frame = element.exists ? element.frame : .zero
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.maxY).max() ?? app.frame.minY
            try scrollCurrentContentUp(in: app, towardTop: frame.height > 0 && frame.maxY <= navigationBottom)
        }
        try requireExists(element)
        try waitFor(liveHittablePredicate(), on: element, message: "The existing form control must be reachable.")
        verifyGoalFieldLabel(element)
    }

    private func scrollCurrentContentUp(in app: XCUIApplication, towardTop: Bool = false) throws {
        // Identify the actual frontmost form/list. Swiping the app's centre can
        // change the native AX DatePicker wheel instead of scrolling the form.
        let identifiers = ["template.form", "meal.form", "goal.form", "meal.detail", "goalHistory.detail", "goalHistory.list", "templates.list", "meal.history", "meal.start", "today.content"]
        guard let container = identifiers.lazy.compactMap({ identifier -> XCUIElement? in
            let matches = app.descendants(matching: .any).matching(identifier: identifier)
            guard matches.count == 1, matches.firstMatch.isHittable else { return nil }
            return matches.firstMatch
        }).first else {
            attachFailureEvidence(app: app, element: app, context: "No unique visible scroll container was found.")
            XCTFail("Scrolling requires a real identified frontmost content container.")
            throw NavigationUIFailure.missingControl
        }
        let frame = container.frame
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else {
            XCTFail("The actual scroll container must have finite non-empty bounds.")
            throw NavigationUIFailure.conditionNotMet
        }
        var visibleBottom = min(frame.maxY, app.frame.maxY)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            visibleBottom = min(visibleBottom, keyboard.frame.minY)
            let doneButtons = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".keyboardDone"))
                .allElementsBoundByIndex.filter(\.isHittable)
            if doneButtons.count == 1, let done = doneButtons.first {
                visibleBottom = min(visibleBottom, done.frame.minY)
            }
        }
        let visibleTop = max(frame.minY, app.frame.minY)
        let visibleHeight = visibleBottom - visibleTop
        guard visibleHeight.isFinite, visibleHeight > 44 else {
            XCTFail("The real content above the keyboard must expose a usable scroll region.")
            throw NavigationUIFailure.conditionNotMet
        }
        // This is a bounded scroll gesture, not a coordinate substitute for a
        // failed control tap. The destination is still checked by exists/hittable.
        let startY = (visibleTop + visibleHeight * (towardTop ? 0.25 : 0.72) - frame.minY) / frame.height
        let endY = (visibleTop + visibleHeight * (towardTop ? 0.72 : 0.25) - frame.minY) / frame.height
        let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: startY))
        let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func revealInputAboveKeyboard(_ field: XCUIElement, in app: XCUIApplication) throws {
        let keyboard = app.keyboards.firstMatch
        try requireExists(keyboard, "A real keyboard must appear after focusing an input.")
        for attempt in 0...4 {
            var inputBottom = keyboard.frame.minY
            let visibleDone = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".keyboardDone"))
                .allElementsBoundByIndex.filter(\.isHittable)
            guard visibleDone.count == 1, let done = visibleDone.first else {
                XCTFail("The focused form must expose its unique real keyboard Done control.")
                throw NavigationUIFailure.missingControl
            }
            inputBottom = min(inputBottom, done.frame.minY)
            if field.exists, field.isHittable, field.frame.maxY < inputBottom { return }
            if attempt < 4 { try scrollCurrentContentUp(in: app) }
        }
        attachFailureEvidence(app: app, element: field, context: "Input bottom remained covered by the real keyboard toolbar after four bounded scrolls and a final fresh check.")
        XCTFail("Input text must not be partly covered by keyboard Done.")
        throw NavigationUIFailure.conditionNotMet
    }

    private func tap(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard element.waitForExistence(timeout: timeout) else {
            if let app = diagnosticApplication {
                attachFailureEvidence(app: app, element: element, context: "The requested tap target did not exist.")
            }
            XCTFail("The requested visible control must exist.", file: file, line: line)
            throw NavigationUIFailure.missingControl
        }
        if !element.isHittable {
            let hittableCondition = XCTNSPredicateExpectation(predicate: liveHittablePredicate(), object: element)
            _ = XCTWaiter.wait(for: [hittableCondition], timeout: timeout)
        }
        // A fresh real getter is required even after waiting. Already reachable controls
        // need not spend five seconds polling, but no coordinate or old snapshot can
        // bypass this same existence/hit-testing check immediately before the tap.
        guard element.exists && element.isHittable else {
            if let app = diagnosticApplication {
                attachFailureEvidence(app: app, element: element, context: "The existing tap target did not become hittable.")
            }
            XCTFail("The requested control must be tappable.", file: file, line: line)
            throw NavigationUIFailure.conditionNotMet
        }
        element.tap()
    }

    private func liveHittablePredicate() -> NSPredicate {
        // Read XCUIElement's real Swift getter on each evaluation, not a string KVC key.
        // R2 failure attachments showed finite enabled targets with isHittable == true
        // immediately after the string-key predicate had nevertheless timed out.
        NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement else { return false }
            return element.exists && element.isHittable
        }
    }

    private func attachFailureEvidence(app: XCUIApplication, element: XCUIElement, context: String) {
        // These tests are simulator-only and all names/values are fictitious QA inputs.
        // Do not use this helper against a physical-device database or real health records.
        let exists = element.exists
        let metadata = """
        Context: \(context)
        QA app state: \(app.state.rawValue)
        Query: \(element.description)
        exists: \(exists)
        identifier: \(exists ? element.identifier : "<unresolved>")
        label: \(exists ? element.label : "<unresolved>")
        frame: \(exists ? String(describing: element.frame) : "<unresolved>")
        enabled: \(exists ? String(element.isEnabled) : "<unresolved>")
        hittable: \(exists ? String(element.isHittable) : "<unresolved>")
        """
        let target = XCTAttachment(string: metadata)
        target.name = "QA-failure-target-metadata"
        target.lifetime = .keepAlways
        add(target)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "QA-failure-app-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreen(app, name: "QA-failure-screen")
    }

    private func requireExists(
        _ element: XCUIElement,
        _ message: String = "The requested visible control must exist.",
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail(message, file: file, line: line)
            throw NavigationUIFailure.missingControl
        }
    }

    private func waitFor(
        _ predicate: NSPredicate,
        on element: XCUIElement,
        timeout: TimeInterval = 5,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if !predicate.evaluate(with: element) {
            let observedCondition = XCTNSPredicateExpectation(predicate: predicate, object: element)
            _ = XCTWaiter.wait(for: [observedCondition], timeout: timeout)
        }
        guard predicate.evaluate(with: element) else {
            XCTFail(message, file: file, line: line)
            throw NavigationUIFailure.conditionNotMet
        }
    }

    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum NavigationUIFailure: Error {
    case missingControl
    case conditionNotMet
}
