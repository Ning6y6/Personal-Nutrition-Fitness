import Foundation
import XCTest

/// Actual system-tab taps and existing form interactions, separate from PNG render tests.
/// Run only on the dedicated QA simulator, whose store contains fictitious inputs/public seeds.
/// No app reset, database inspection, test-only launch mode, network, export or restore is used.
@MainActor
final class NativeNavigationUITests: XCTestCase {
    func testFourTabsAndUnreleasedPages() throws {
        executionTimeAllowance = 120
        let app = try launchApp()
        defer { app.terminate() }

        try selectTab("今日", in: app)
        try requireExists(app.buttons["预算与目标"], "Today's existing budget shortcut must remain reachable.")

        try selectTab("扫描", in: app)
        try requireExists(app.staticTexts["扫描尚未开放"], "Scan must explicitly remain unavailable.")
        try requireExists(
            app.staticTexts["食品标签识别将在后续独立切片中开放。当前不会启动相机或上传照片。"],
            "The scan placeholder must explain its current boundary."
        )
        XCTAssertFalse(app.buttons["预算与目标"].exists, "Today's budget control must not leak into Scan.")
        attachScreen(app, name: "NativeNavigationUI-scan-placeholder")

        try selectTab("日历", in: app)
        try requireExists(app.staticTexts["日历尚未开放"], "Calendar must explicitly remain unavailable.")
        try requireExists(
            app.staticTexts["按日回顾将在日确认与历史目标等功能完成后开放。现在可在今日页查看全部历史餐食。"],
            "The calendar placeholder must not pretend that day-history logic is complete."
        )
        XCTAssertFalse(app.buttons["预算与目标"].exists)
        attachScreen(app, name: "NativeNavigationUI-calendar-placeholder")

        try selectTab("设置", in: app)
        try requireExists(app.buttons["每日预算与目标"], "Settings must expose the existing goal form.")
        try requireExists(app.buttons["本地备份"], "Settings must expose the existing backup flow.")
        XCTAssertFalse(app.buttons["预算与目标"].exists)

        try selectTab("今日", in: app)
        try requireExists(app.buttons["预算与目标"], "Returning to Today must preserve its dedicated toolbar.")
        attachScreen(app, name: "NativeNavigationUI-today-return")
    }

    func testSettingsSaveRefreshesPreviouslyDisplayedTodayBudget() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }

        // Establish an explicit baseline through the real form; works with or without an old goal.
        try saveFictitiousGoal(energy: "2150", saturatedFat: "0", fibre: "", in: app)
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

    func testCancelProtectsDraftWithoutChangingSavedTodayBudget() throws {
        executionTimeAllowance = 180
        let app = try launchApp()
        defer { app.terminate() }

        try saveFictitiousGoal(energy: "2350", saturatedFat: "15", fibre: "30", in: app)
        try selectTab("今日", in: app)
        try verifyTodayBudget(2_350, in: app)
        try openGoalFromSettings(in: app)
        try replaceText(in: goalField("热量预算 (kcal)", in: app), with: "9999", app: app)

        let formBar = app.navigationBars["每日预算与目标"]
        try tap(formBar.buttons["取消"])
        try tap(app.buttons["继续编辑"])
        try requireExists(formBar, "Continue editing must retain the real form.")
        XCTAssertEqual(goalField("热量预算 (kcal)", in: app).value as? String, "9999")
        XCTAssertFalse(formBar.buttons["保存"].isEnabled, "Changing a value must require renewed confirmation.")

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

    private func launchApp() throws -> XCUIApplication {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests are authorized only for a dedicated fictitious-data simulator, never a physical device.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.ning6y6.ShiHeng")
        // System-supported process-local locale settings, not an app-specific data/reset mode.
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        try requireExists(app.tabBars.buttons["今日"], "The native system TabView must actually appear.", timeout: 15)
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

    private func saveFictitiousGoal(energy: String, saturatedFat: String, fibre: String, in app: XCUIApplication) throws {
        try openGoalFromSettings(in: app)
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
            try replaceText(in: field, with: value, app: app)
        }
        let formBar = app.navigationBars["每日预算与目标"]
        let save = formBar.buttons["保存"]
        XCTAssertFalse(save.isEnabled, "Numeric edits must not silently confirm themselves.")
        let confirmation = app.switches["我已核对并确认预算、目标与上限"]
        try reveal(confirmation, in: app)
        if confirmation.value as? String != "1" {
            // R2's actual hierarchy exposed a full-width labelled Switch wrapping exactly one
            // unlabelled native switch. Tap the control, not the wrapper's centre on its text.
            let actualSwitches = confirmation.descendants(matching: .switch)
            guard actualSwitches.count == 1 else {
                XCTFail("The labelled confirmation row must contain one real native switch.")
                throw NavigationUIFailure.missingControl
            }
            try tap(actualSwitches.firstMatch)
        }
        try waitFor(NSPredicate(format: "value == %@", "1"), on: confirmation, message: "The real confirmation switch must visibly turn on.")
        try waitFor(NSPredicate(format: "isEnabled == true"), on: save, message: "Confirmed valid input must enable Save.")
        save.tap()
        XCTAssertTrue(formBar.waitForNonExistence(timeout: 5), "Successful save must close the existing sheet.")
        try requireExists(app.navigationBars["设置"])
    }

    private func goalField(_ title: String, in app: XCUIApplication) -> XCUIElement {
        // UI-2A's actual XCTest hierarchy exposed LabeledContent + the explicit field label
        // as "title、title". Match only that observed label or the corrected single label;
        // never substitute an unrelated or positional text field.
        let matchingFields = app.textFields.matching(
            NSPredicate(format: "label == %@ OR label == %@", title, "\(title)、\(title)")
        )
        XCTAssertLessThanOrEqual(matchingFields.count, 1, "Each named goal field must be unambiguous.")
        return matchingFields.firstMatch
    }

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) throws {
        try reveal(field, in: app)
        let oldValue = field.value as? String ?? ""
        let placeholderValues = ["请输入", "未设置"]
        let oldLength = placeholderValues.contains(oldValue) ? 0 : oldValue.count
        // These existing fields are trailing-aligned. Tap their trailing end before clearing;
        // verify the resulting value so a caret/replacement failure cannot pass silently.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let replacement = String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldLength) + text
        if !replacement.isEmpty { field.typeText(replacement) }
        if text.isEmpty {
            let clearedValue = field.value as? String ?? ""
            XCTAssertTrue(clearedValue.isEmpty || placeholderValues.contains(clearedValue))
        } else {
            XCTAssertEqual(field.value as? String, text)
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            try tap(app.buttons["完成"])
            XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5), "The real Done action must dismiss the keyboard.")
        }
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
        for _ in 0..<6 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            app.swipeUp()
        }
        try requireExists(element)
        try waitFor(NSPredicate(format: "isHittable == true"), on: element, message: "The existing form control must be reachable.")
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 5) throws {
        try requireExists(element, timeout: timeout)
        try waitFor(NSPredicate(format: "isHittable == true"), on: element, timeout: timeout, message: "The requested control must be tappable.")
        element.tap()
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
        let observedCondition = XCTNSPredicateExpectation(predicate: predicate, object: element)
        guard XCTWaiter.wait(for: [observedCondition], timeout: timeout) == .completed else {
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
