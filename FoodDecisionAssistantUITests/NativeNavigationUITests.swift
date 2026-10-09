import Foundation
import XCTest

/// Actual system-tab taps and existing form interactions, separate from PNG render tests.
/// Run only on the dedicated QA simulator, whose store contains fictitious inputs/public seeds.
/// No app reset, database inspection, test-only launch mode, network, export or restore is used.
@MainActor
final class NativeNavigationUITests: XCTestCase {
    // Only the simulator application launched by this test is included in failure evidence.
    // This reference is never used to mutate an app store or bypass a failed interaction.
    private var diagnosticApplication: XCUIApplication?

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

    func testSettingsSaveRefreshesPreviouslyDisplayedTodayBudget() throws {
        // Saves two real forms, clears/restores optional fields and verifies
        // both committed budgets; retain a finite multi-step allowance.
        executionTimeAllowance = 360
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
        let app = try launchApp()
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

        let confirmation = app.switches["我已核对并确认预算、目标与上限"]
        try reveal(confirmation, in: app)
        XCTAssertEqual(confirmation.value as? String, "0", "Editing must reset confirmation, not silently confirm a new value.")
        let actualSwitches = confirmation.descendants(matching: .switch)
        guard actualSwitches.count == 1 else {
            attachFailureEvidence(app: app, element: confirmation, context: "The footer must expose one actual native confirmation switch.")
            XCTFail("The confirmation row must contain one native switch.")
            throw NavigationUIFailure.missingControl
        }
        try tap(actualSwitches.firstMatch)
        try waitFor(NSPredicate(format: "value == %@", "1"), on: confirmation, message: "The visible native switch must actually turn on.")
        attachScreen(app, name: "NativeMealEntryUI-system-text-size-goal-footer")

        // No Save action: even valid footer interactions must not write a new QA goal.
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

    private func launchApp() throws -> XCUIApplication {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests are authorized only for a dedicated fictitious-data simulator, never a physical device.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.ning6y6.ShiHeng")
        diagnosticApplication = app
        // System-supported process-local locale settings, not an app-specific data/reset mode.
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
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
        app.navigationBars.matching(identifier: "记录一餐")
            .containing(.button, identifier: "保存").firstMatch
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
        let candidates = app.navigationBars["常用模板"].exists
            ? app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "template.manage."))
            : app.buttons
        let buttons = candidates.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", name, "\(name)、"))
        if buttons.count == 1 { return buttons.firstMatch }
        let containingText = candidates.containing(.staticText, identifier: name)
        XCTAssertLessThanOrEqual(containingText.count, 1, "The run-specific record name must be unambiguous.")
        return containingText.firstMatch
    }

    private func openMeal(named name: String, in app: XCUIApplication) throws {
        var row = namedRecordButton(name, in: app)
        if !row.exists {
            let history = app.buttons["查看全部历史"]
            try reveal(history, in: app)
            try tap(history)
            try requireExists(app.navigationBars["历史餐食"])
            row = namedRecordButton(name, in: app)
        }
        try reveal(row, in: app)
        try tap(row)
        try requireExists(app.navigationBars["餐食详情"])
    }

    private func verifyRiceWeight(_ grams: Int, rice: String, in app: XCUIApplication) throws {
        let combined = "\(rice)、\(grams) g"
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", combined, "\(grams) g")).firstMatch
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

    private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) throws {
        try reveal(field, in: app)
        let oldValue = field.value as? String ?? ""
        let placeholderValues = ["请输入", "未设置", "模板名称", "重量", "默认重量", "克重"]
        let hasExistingText = !oldValue.isEmpty && !placeholderValues.contains(oldValue)
        try tap(field)
        try revealInputAboveKeyboard(field, in: app)
        if hasExistingText {
            // Hardware Command-A was ignored by the actual simulator in AX5 R3.
            // Use the real touch edit menu on the now-independent input frame,
            // then require its unique Select All action and exact resulting text.
            field.press(forDuration: 1)
            let selectAllLabels = NSPredicate(format: "label IN %@", ["全选", "Select All"])
            let menuItems = app.menuItems.matching(selectAllLabels)
            let buttons = app.buttons.matching(selectAllLabels)
            let menuAppeared = menuItems.firstMatch.waitForExistence(timeout: 5)
            if !menuAppeared { _ = buttons.firstMatch.waitForExistence(timeout: 5) }
            let actions = menuItems.allElementsBoundByIndex + buttons.allElementsBoundByIndex
            guard actions.count == 1, let selectAll = actions.first else {
                attachFailureEvidence(app: app, element: field, context: "Expected one real touch Select All action; found \(actions.count).")
                XCTFail("Replacing old input requires an actual unique native Select All action.")
                throw NavigationUIFailure.missingControl
            }
            try tap(selectAll)
            field.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
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
            attachFailureEvidence(app: app, element: field, context: "Actual software keyboard missing after text input; Done was not tested.")
            XCTFail("Text input must expose the software keyboard so its real Done action is verified.")
            throw NavigationUIFailure.missingControl
        }
        do {
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
            let doneButtons = app.buttons.matching(identifier: doneIdentifier)
            let done = doneButtons.firstMatch
            guard done.waitForExistence(timeout: 5), doneButtons.count == 1 else {
                attachFailureEvidence(app: app, element: done, context: "Expected exactly one \(doneIdentifier) button; found \(doneButtons.count).")
                XCTFail("The current form must expose exactly one identified keyboard Done button.")
                throw NavigationUIFailure.missingControl
            }
            XCTAssertEqual(done.label, "完成", "The identified action must remain the visible Done control.")
            try tap(done)
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
        for _ in 0..<16 {
            if element.waitForExistence(timeout: 1), element.isHittable {
                verifyGoalFieldLabel(element)
                return
            }
            try scrollCurrentContentUp(in: app)
        }
        try requireExists(element)
        try waitFor(liveHittablePredicate(), on: element, message: "The existing form control must be reachable.")
        verifyGoalFieldLabel(element)
    }

    private func scrollCurrentContentUp(in app: XCUIApplication) throws {
        // Identify the actual frontmost form/list. Swiping the app's centre can
        // change the native AX DatePicker wheel instead of scrolling the form.
        let identifiers = ["template.form", "meal.form", "goal.form", "templates.list", "meal.start", "today.content"]
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
        let startY = (visibleTop + visibleHeight * 0.72 - frame.minY) / frame.height
        let endY = (visibleTop + visibleHeight * 0.25 - frame.minY) / frame.height
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
