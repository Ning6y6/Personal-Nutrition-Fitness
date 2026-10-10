import Foundation
import UIKit
import XCTest

/// Actual native interactions on the dedicated synthetic-data QA simulator.
/// Never resets a store, opens its database, changes the clock, or runs on a physical device.
@MainActor
final class GoalHistoryUITests: XCTestCase {
    func testTodayChangesAppendHistoryAndTomorrowDoesNotApplyEarly() throws {
        executionTimeAllowance = 480
        let app = try launchApp()
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let firstNote = "[UI测试] 今日甲-\(token)"
        let secondNote = "[UI测试] 今日乙-\(token)"
        let futureNote = "[UI测试] 明日-\(token)"

        try saveGoal(energy: "3101", today: true, note: firstNote, app: app)
        try selectTab("今日", app: app)
        try verifyTodayBudget(3_101, app: app)
        try saveGoal(energy: "3102", today: true, note: secondNote, app: app)
        try selectTab("今日", app: app)
        try verifyTodayBudget(3_102, app: app)
        try saveGoal(energy: "3103", today: false, note: futureNote, app: app)
        try selectTab("今日", app: app)
        try verifyTodayBudget(3_102, app: app)

        try selectTab("设置", app: app)
        try tap(app.buttons["settings.goalHistory"], app: app)
        for (note, status, energy) in [
            (futureNote, "未来安排", "3,103"),
            (secondNote, "今日生效", "3,102"),
            (firstNote, "同日被后续确认替代", "3,101"),
        ] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "goalHistory.row.", note)).firstMatch
            try reveal(row, container: "goalHistory.list", app: app)
            XCTAssertTrue(row.label.contains(status), "Every appended version must retain its distinct status.")
            try tap(row, app: app)
            try require(app.navigationBars["目标版本详情"])
            let detailEnergy = app.descendants(matching: .any).matching(identifier: "goalHistory.detail.energy").firstMatch
            try require(detailEnergy)
            XCTAssertTrue(detailEnergy.label.contains(energy) || detailEnergy.label.contains(energy.replacingOccurrences(of: ",", with: "")))
            let sourceNote = app.staticTexts[note]
            try reveal(sourceNote, container: "goalHistory.detail", app: app)
            XCTAssertTrue(sourceNote.exists)
            try tap(app.navigationBars["目标版本详情"].buttons.firstMatch, app: app)
        }
        attach(app, name: "GoalHistoryUI-today-superseded-and-tomorrow-retained")
        try tap(app.navigationBars["目标历史"].buttons["完成"], app: app)
        try openGoal(app)
        XCTAssertEqual(Double(app.textFields["goal.energy"].value as? String ?? ""), 3_102)
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"], app: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists, "The default tomorrow presentation itself must remain clean.")
    }

    func testEffectiveDateAndSourceChangesRequireConfirmationAndProtectDraft() throws {
        executionTimeAllowance = 240
        let app = try launchApp()
        defer { app.terminate() }
        try openGoal(app)
        try fillNumericGoal(energy: "3201", app: app)
        try chooseSource("自行选择", app: app)
        let note = app.descendants(matching: .any).matching(identifier: "goal.sourceNote").firstMatch
        try reveal(note, container: "goal.form", app: app)
        try replaceNote(note, with: "", app: app)
        try confirm(app)
        try reveal(app.buttons["goal.effectiveToday"], container: "goal.form", app: app)
        try tap(app.buttons["goal.effectiveToday"], app: app)
        try assertUnconfirmed(app)
        try confirm(app)
        try chooseSource("参考已有建议", app: app)
        try assertUnconfirmed(app)
        try confirm(app)
        let clearedNote = note.value as? String ?? ""
        XCTAssertTrue(clearedNote.isEmpty || clearedNote == "来源说明（必填）", "The reference-source validation case must start with an actually empty note.")
        XCTAssertFalse(app.navigationBars["每日预算与目标"].buttons["保存"].isEnabled, "Confirmed reference goals still require their source note.")
        try reveal(note, container: "goal.form", app: app)
        try replaceNote(note, with: "[UI测试] 来源草稿", app: app)
        try assertUnconfirmed(app)
        try confirm(app)
        try wait(NSPredicate(format: "isEnabled == true"), on: app.navigationBars["每日预算与目标"].buttons["保存"])

        let bar = app.navigationBars["每日预算与目标"]
        try tap(bar.buttons["取消"], app: app)
        try tap(app.buttons["继续编辑"], app: app)
        try reveal(note, container: "goal.form", app: app)
        XCTAssertEqual(note.value as? String, "[UI测试] 来源草稿")
        XCTAssertTrue(bar.buttons["保存"].isEnabled, "Continue editing must retain the confirmed, valid source metadata without saving it.")
        attach(app, name: "GoalHistoryUI-date-and-source-protected-draft")
        try tap(bar.buttons["取消"], app: app)
        try tap(app.buttons["放弃修改"], app: app)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
    }

    /// Repeat with the simulator's actual system content size set to AX5.
    func testGoalHistoryControlsReachableAtCurrentSystemTextSize() throws {
        executionTimeAllowance = 240
        let app = try launchApp()
        defer { app.terminate() }
        try openGoal(app)
        for identifier in ["goal.effectiveDate", "goal.effectiveToday", "goal.effectiveTomorrow", "goal.source", "goal.sourceNote"] {
            let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            try reveal(control, container: "goal.form", app: app)
            XCTAssertTrue(control.isHittable, "All new native controls must be reachable at the real current text size.")
        }
        let confirmation = app.switches["我已核对并确认预算、目标与上限"]
        try reveal(confirmation, container: "goal.form", app: app)
        attach(app, name: "GoalHistoryUI-system-text-size-form")
        try tap(app.navigationBars["每日预算与目标"].buttons["取消"], app: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists)
        try tap(app.buttons["settings.goalHistory"], app: app)
        try require(app.navigationBars["目标历史"])
        let explanation = app.staticTexts["首个已知版本之前的目标未知，不能用当前目标还原。每次修改保留原版本；同日以最后确认为准。"]
        try reveal(explanation, container: "goalHistory.list", app: app)
        XCTAssertTrue(explanation.isHittable)
        attach(app, name: "GoalHistoryUI-system-text-size-history")
    }

    private func launchApp() throws -> XCUIApplication {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Goal history UI writes are authorized only on the dedicated synthetic-data QA simulator.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.ning6y6.ShiHeng")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        try require(app.tabBars.buttons["设置"])
        return app
        #endif
    }

    private func selectTab(_ title: String, app: XCUIApplication) throws {
        try tap(app.tabBars.buttons[title], app: app)
        try require(app.navigationBars[title])
    }

    private func openGoal(_ app: XCUIApplication) throws {
        try selectTab("设置", app: app)
        try tap(app.buttons["每日预算与目标"], app: app)
        try require(app.navigationBars["每日预算与目标"])
        try require(app.textFields["goal.energy"])
    }

    private func saveGoal(energy: String, today: Bool, note: String, app: XCUIApplication) throws {
        try openGoal(app)
        try fillNumericGoal(energy: energy, app: app)
        try chooseSource("自行选择", app: app)
        let dayButton = app.buttons[today ? "goal.effectiveToday" : "goal.effectiveTomorrow"]
        try reveal(dayButton, container: "goal.form", app: app)
        if today {
            try tap(dayButton, app: app)
        } else {
            // Do not tap Tomorrow: this proves the form's untouched default is tomorrow.
            let picker = app.datePickers["goal.effectiveDate"]
            try require(picker)
            let calendar = Calendar.current
            let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: .now))
            let components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            let expected = String(format: "%04d-%02d-%02d", try XCTUnwrap(components.year), try XCTUnwrap(components.month), try XCTUnwrap(components.day))
            let summary = app.staticTexts["goal.effectiveSummary"]
            try require(summary)
            XCTAssertEqual(summary.label, "将于 \(expected) 生效", "The selected native date must be tomorrow without tapping its shortcut.")
        }
        let sourceNote = app.descendants(matching: .any).matching(identifier: "goal.sourceNote").firstMatch
        try reveal(sourceNote, container: "goal.form", app: app)
        try replaceNote(sourceNote, with: note, app: app)
        try confirm(app)
        let bar = app.navigationBars["每日预算与目标"]
        try wait(NSPredicate(format: "isEnabled == true"), on: bar.buttons["保存"])
        try tap(bar.buttons["保存"], app: app)
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
    }

    private func fillNumericGoal(energy: String, app: XCUIApplication) throws {
        var lastEditedField: XCUIElement?
        for (identifier, text) in [("goal.energy", energy), ("goal.protein", "145"), ("goal.carbohydrate", "210"), ("goal.fat", "60"), ("goal.saturatedFat", "15"), ("goal.fibre", "30")] {
            let field = app.textFields[identifier]
            try reveal(field, container: "goal.form", app: app)
            if Double(field.value as? String ?? "") == Double(text) { continue }
            try replaceNumber(field, with: text, app: app)
            lastEditedField = field
        }
        if let lastEditedField {
            // Interactive scrolling may close the keyboard. Refocus the actual
            // edited field when needed, then exercise one native Done per entry session.
            if !app.keyboards.firstMatch.exists {
                try reveal(lastEditedField, container: "goal.form", app: app)
                try tap(lastEditedField, app: app)
                try revealInputAboveKeyboard(lastEditedField, app: app)
            }
            try finishKeyboard(app)
        }
    }

    private func replaceNumber(_ field: XCUIElement, with text: String, app: XCUIApplication) throws {
        let oldValue = field.value as? String ?? ""
        if app.keyboards.firstMatch.exists { try revealInputAboveKeyboard(field, app: app) }
        try tap(field, app: app)
        try revealInputAboveKeyboard(field, app: app)
        // Revealing a lower row can keep the previous field focused. Retap its
        // now fully visible real input before selection or typing.
        try tap(field, app: app)
        if !oldValue.isEmpty && oldValue != "请输入" && oldValue != "未设置" {
            let leading = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
            field.coordinate(withNormalizedOffset: CGVector(dx: leading ? 0.02 : 0.98, dy: 0.5)).doubleTap()
            let all = NSPredicate(format: "label IN %@", ["全选", "Select All"])
            let menu = app.menuItems.matching(all).firstMatch
            let button = app.buttons.matching(all).firstMatch
            if menu.waitForExistence(timeout: 3) {
                menu.tap()
            } else if button.waitForExistence(timeout: 3) {
                button.tap()
            } else {
                let cuts = app.menuItems.matching(NSPredicate(format: "label IN %@", ["剪切", "Cut"]))
                try require(cuts.firstMatch)
                XCTAssertEqual(cuts.count, 1)
                cuts.firstMatch.tap()
                let cleared = field.value as? String ?? ""
                XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue, "Native selection must clear the entire old value before replacement.")
            }
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func chooseSource(_ title: String, app: XCUIApplication) throws {
        let source = app.buttons["goal.source"]
        try reveal(source, container: "goal.form", app: app)
        try tap(source, app: app)
        try tap(app.buttons[title], app: app)
    }

    private func finishKeyboard(_ app: XCUIApplication) throws {
        try require(app.keyboards.firstMatch)
        try tap(app.buttons["goal.keyboardDone"], app: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    private func replaceNote(_ field: XCUIElement, with text: String, app: XCUIApplication) throws {
        let old = field.value as? String ?? ""
        try tap(field, app: app)
        try revealInputAboveKeyboard(field, app: app)
        try tap(field, app: app)
        if !old.isEmpty && old != "来源说明（可选）" && old != "来源说明（必填）" {
            field.press(forDuration: 1)
            let all = NSPredicate(format: "label IN %@", ["全选", "Select All"])
            let menu = app.menuItems.matching(all).firstMatch
            let button = app.buttons.matching(all).firstMatch
            if menu.waitForExistence(timeout: 3) {
                menu.tap()
            } else {
                try require(button)
                button.tap()
            }
        }
        if text.isEmpty {
            if !old.isEmpty && old != "来源说明（可选）" && old != "来源说明（必填）" { field.typeText(XCUIKeyboardKey.delete.rawValue) }
            let cleared = field.value as? String ?? ""
            XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue, "The whole source note must be cleared through native editing.")
        } else {
            field.typeText(text)
            XCTAssertEqual(field.value as? String, text)
        }
        try finishKeyboard(app)
    }

    private func confirm(_ app: XCUIApplication) throws {
        let row = app.switches["我已核对并确认预算、目标与上限"]
        try reveal(row, container: "goal.form", app: app)
        if row.value as? String != "1" {
            let controls = row.descendants(matching: .switch)
            XCTAssertEqual(controls.count, 1)
            try tap(controls.firstMatch, app: app)
        }
        try wait(NSPredicate(format: "value == %@", "1"), on: row)
    }

    private func assertUnconfirmed(_ app: XCUIApplication) throws {
        let row = app.switches["我已核对并确认预算、目标与上限"]
        try reveal(row, container: "goal.form", app: app)
        try wait(NSPredicate(format: "value == %@", "0"), on: row)
        XCTAssertFalse(app.navigationBars["每日预算与目标"].buttons["保存"].isEnabled)
    }

    private func verifyTodayBudget(_ energy: Int, app: XCUIApplication) throws {
        let grouped = energy.formatted(.number.locale(Locale(identifier: "zh_CN")))
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "今日热量")).firstMatch
        if ring.waitForExistence(timeout: 2) {
            try wait(NSPredicate(format: "value CONTAINS %@ OR value CONTAINS %@", "预算 \(grouped) 千卡", "预算 \(energy) 千卡"), on: ring)
        } else {
            let disclosure = app.buttons["查看已保存预算与目标"]
            try reveal(disclosure, container: "today.content", app: app)
            let value = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["热量预算、\(grouped) kcal", "热量预算、\(energy) kcal", "\(grouped) kcal", "\(energy) kcal"])).firstMatch
            if !value.exists { try tap(disclosure, app: app) }
            try require(value)
        }
    }

    private func reveal(_ element: XCUIElement, container: String, app: XCUIApplication) throws {
        for _ in 0..<18 {
            if element.exists, element.isHittable { return }
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.maxY).max() ?? app.frame.minY
            let towardTop = element.exists && element.frame.maxY <= navigationBottom
            try scrollContent(container, towardTop: towardTop, app: app)
        }
        try require(element)
        try wait(liveHittablePredicate(), on: element)
    }

    private func scrollContent(_ identifier: String, towardTop: Bool = false, app: XCUIApplication) throws {
        let container = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        try require(container)
        let frame = container.frame
        var visibleBottom = min(frame.maxY, app.frame.maxY)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            visibleBottom = min(visibleBottom, keyboard.frame.minY)
            let doneButtons = app.buttons.matching(identifier: "goal.keyboardDone").allElementsBoundByIndex.filter(\.isHittable)
            if doneButtons.count == 1, let done = doneButtons.first { visibleBottom = min(visibleBottom, done.frame.minY) }
        }
        let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.maxY).max() ?? app.frame.minY
        let visibleTop = max(frame.minY, navigationBottom)
        let height = visibleBottom - visibleTop
        guard height.isFinite, height > 44, frame.height > 0 else {
            XCTFail("The actual form must expose a usable scroll region above its native keyboard.")
            throw GoalHistoryUIFailure.conditionNotMet
        }
        let startY = (visibleTop + height * (towardTop ? 0.25 : 0.72) - frame.minY) / frame.height
        let endY = (visibleTop + height * (towardTop ? 0.72 : 0.25) - frame.minY) / frame.height
        let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: startY))
        let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func revealInputAboveKeyboard(_ field: XCUIElement, app: XCUIApplication) throws {
        let keyboard = app.keyboards.firstMatch
        try require(keyboard)
        for attempt in 0...4 {
            let visibleDone = app.buttons.matching(identifier: "goal.keyboardDone").allElementsBoundByIndex.filter(\.isHittable)
            guard visibleDone.count == 1, let done = visibleDone.first else {
                XCTFail("A focused goal input must expose one real keyboard Done action.")
                throw GoalHistoryUIFailure.missingControl
            }
            let inputBottom = min(keyboard.frame.minY, done.frame.minY)
            if field.exists, field.isHittable, field.frame.maxY < inputBottom { return }
            if attempt < 4 { try scrollContent("goal.form", app: app) }
        }
        attach(app, name: "GoalHistoryUI-input-covered-by-keyboard")
        XCTFail("Input text must be fully visible above the real keyboard toolbar after bounded scrolling.")
        throw GoalHistoryUIFailure.conditionNotMet
    }

    private func tap(_ element: XCUIElement, app: XCUIApplication) throws {
        if !element.exists { try require(element) }
        if !element.isHittable { try wait(liveHittablePredicate(), on: element) }
        guard element.exists && element.isHittable else {
            XCTFail("The real goal history target must remain hittable immediately before tapping.")
            throw GoalHistoryUIFailure.conditionNotMet
        }
        element.tap()
    }

    private func liveHittablePredicate() -> NSPredicate {
        NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement else { return false }
            return element.exists && element.isHittable
        }
    }

    private func require(_ element: XCUIElement) throws {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Required native goal history control is missing: \(element.identifier)")
            throw GoalHistoryUIFailure.missingControl
        }
    }

    private func wait(_ predicate: NSPredicate, on element: XCUIElement) throws {
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed else {
            XCTFail("Native goal history control did not reach the expected state: \(element.identifier)")
            throw GoalHistoryUIFailure.conditionNotMet
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum GoalHistoryUIFailure: Error { case missingControl, conditionNotMet }
