import Foundation
import XCTest

/// Uses native forms only on a dedicated QA simulator with fictitious data.
/// Cards remain in that QA library because OPT-13 intentionally has no deletion.
/// Meals are uniquely named and only this run's own saved meals are deleted.
@MainActor
final class PersonalFoodUITests: XCTestCase {
    private let rice = "熟长粒白米饭（无盐）"
    private var diagnosticApplication: XCUIApplication?

    func testSearchCreatedHoneyRequiresExplicitSelectionAndSurvivesParentCancellation() throws {
        executionTimeAllowance = 600
        let app = try launchApp()
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let foodName = "[UI测试] 蜂蜜-\(token)"
        let mealName = "[UI测试] 个人蜂蜜餐-\(token)"
        try newMeal(named: mealName, in: app)
        let row = try singleRow(prefix: "meal", in: app)
        try replace(field("meal.weight.\(row)", in: app), with: "60", done: "meal.keyboardDone", in: app)
        try openSelector(row: row, prefix: "meal", in: app)
        try search(foodName, in: app)
        try require(app.staticTexts["没有找到食物"], in: app)
        try tapRevealed(app.buttons["food.personal.create"], towardTop: true, in: app)
        try fillCard(name: foodName, protein: false, in: app)
        try saveCard(in: app)
        try require(app.navigationBars["选择食物"], in: app)
        try require(app.staticTexts["food.personal.savedStatus"], in: app)
        XCTAssertFalse(app.navigationBars["今日"].isHittable, "Saving the library card must leave this unrecorded meal's selector open.")
        let select = app.buttons["food.personal.selectSaved"]
        try reveal(select, towardTop: true, in: app)
        XCTAssertEqual(select.label, "选择\(foodName)")
        attachScreen(app, name: "OPT13-card-saved-selector-still-open-no-intake")
        try tap(select, in: app)
        try assertRow(row, prefix: "meal", name: foodName, rawWeight: "60", in: app)
        try cancelChangedForm(prefix: "meal", in: app)
        try tap(app.navigationBars["记录一餐"].buttons["取消"], in: app)
        XCTAssertFalse(savedMealHeader(name: mealName, in: app).exists)

        app.terminate()
        app.launch()
        try require(app.tabBars.buttons["设置"], timeout: 15, in: app)
        try openMyFoods(in: app)
        let cardID = try personalCardID(named: foodName, in: app)
        try tap(app.buttons["myFoods.food.\(cardID)"], in: app)
        XCTAssertEqual(try revealedValue("personalFood.energy", towardTop: true, in: app).flatMap(Double.init), 300)
        XCTAssertEqual(try revealedValue("personalFood.fat", in: app).flatMap(Double.init), 0)
        let fibre = field("personalFood.fibre", in: app)
        try reveal(fibre, in: app)
        XCTAssertTrue(isBlank(fibre), "Unknown fibre must remain blank after a file-backed app restart.")
        try tap(app.buttons["personalFood.cancel"], in: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists, "Reading a persisted card must not dirty it.")

        try newMeal(named: mealName, in: app)
        let savedRow = try singleRow(prefix: "meal", in: app)
        try chooseFood(foodName, row: savedRow, prefix: "meal", in: app)
        try replace(field("meal.weight.\(savedRow)", in: app), with: "60", done: "meal.keyboardDone", in: app)
        try assertEnergy(180, preview: true, in: app)
        try saveMeal(title: "记录一餐", in: app)
        app.terminate()
        app.launch()
        try require(app.tabBars.buttons["今日"], timeout: 15, in: app)
        try openMeal(mealName, in: app)
        try assertEnergy(180, preview: false, in: app)
        try assertDetailFood(foodName, grams: 60, in: app)
        attachScreen(app, name: "OPT13-honey60g-persists180kcal")
        try deleteOwnMeal(mealName, in: app)
    }

    func testEditingPersonalProteinCardPreservesOldMealsAndRefreshesNewSelections() throws {
        executionTimeAllowance = 900
        let app = try launchApp()
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let foodName = "[UI测试] 蛋白粉-\(token)"
        let oldName = "[UI测试] 旧蛋白粉餐-\(token)"
        let renamed = "[UI测试] 旧蛋白粉改名-\(token)"
        let newName = "[UI测试] 新蛋白粉餐-\(token)"
        try openMyFoods(in: app)
        try tapRevealed(app.buttons["myFoods.create"], towardTop: true, in: app)
        try fillCard(name: foodName, protein: true, in: app)
        try saveCard(in: app)
        let cardID = try personalCardID(named: foodName, in: app)
        try record(foodName, grams: 30, named: oldName, expectedKcal: 120, in: app)

        try openMyFoods(in: app)
        let card = app.buttons["myFoods.food.\(cardID)"]
        try tapRevealed(card, in: app)
        XCTAssertEqual(try revealedValue("personalFood.energy", towardTop: true, in: app).flatMap(Double.init), 400)
        try replace(field("personalFood.energy", in: app), with: "450", done: "personalFood.keyboardDone", towardTop: true, in: app)
        try saveCard(in: app)
        try require(app.staticTexts["myFoods.savedStatus"], in: app)
        try reveal(card, in: app)
        let summary = ([card.label] + card.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
        XCTAssertTrue(summary.contains("450 kcal"), "The already open library context must immediately show the committed edit.")
        try tap(app.tabBars.buttons["今日"], in: app)
        try openMeal(oldName, in: app)
        try assertEnergy(120, preview: false, in: app)
        try openMealEditor(in: app)
        let oldID = try singleRow(prefix: "meal", in: app)
        try replace(field("meal.name", in: app), with: renamed, done: "meal.keyboardDone", towardTop: true, in: app)
        try saveMeal(title: "编辑餐食", in: app)
        try assertEnergy(120, preview: false, in: app)
        try openMealEditor(in: app)
        XCTAssertEqual(try singleRow(prefix: "meal", in: app), oldID)
        try replace(field("meal.weight.\(oldID)", in: app), with: "40", done: "meal.keyboardDone", in: app)
        try assertEnergy(160, preview: true, in: app)
        try saveMeal(title: "编辑餐食", in: app)
        try assertEnergy(160, preview: false, in: app)
        try tap(app.navigationBars["餐食详情"].buttons["关闭"], in: app)
        try record(foodName, grams: 30, named: newName, expectedKcal: 135, in: app)
        app.terminate()
        app.launch()
        try require(app.tabBars.buttons["今日"], timeout: 15, in: app)
        try openMeal(renamed, in: app)
        try assertEnergy(160, preview: false, in: app)
        try assertDetailFood(foodName, grams: 40, in: app)
        try deleteOwnMeal(renamed, in: app)
        try openMeal(newName, in: app)
        try assertEnergy(135, preview: false, in: app)
        try assertDetailFood(foodName, grams: 30, in: app)
        attachScreen(app, name: "OPT13-new-current-card30g135kcal-old-snapshot-protected")
        try deleteOwnMeal(newName, in: app)
    }

    func testInvalidPersonalFoodRetainsRawInputAndDiscardCreatesNoCard() throws {
        executionTimeAllowance = 420
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 无效个人卡-\(UUID().uuidString.prefix(8))"
        try openMyFoods(in: app)
        try tapRevealed(app.buttons["myFoods.create"], towardTop: true, in: app)
        try fillCard(name: name, protein: false, includeSalt: false, in: app)
        XCTAssertFalse(app.buttons["personalFood.save"].isEnabled, "Missing salt must never silently become zero.")
        let salt = field("personalFood.salt", in: app)
        try reveal(salt, towardTop: true, in: app)
        XCTAssertTrue(isBlank(salt))
        try replace(salt, with: ".", done: "personalFood.keyboardDone", in: app)
        XCTAssertFalse(app.buttons["personalFood.save"].isEnabled, "An incomplete decimal must remain invalid.")
        try tap(app.buttons["personalFood.cancel"], in: app)
        try tap(app.buttons["继续编辑"], in: app)
        XCTAssertEqual(try revealedValue("personalFood.salt", towardTop: true, in: app), ".")
        XCTAssertEqual(try revealedValue("personalFood.name", towardTop: true, in: app), name)
        XCTAssertFalse(app.buttons["personalFood.save"].isEnabled)
        attachScreen(app, name: "OPT13-invalid-salt-continued-raw-input-preserved")
        try tap(app.buttons["personalFood.cancel"], in: app)
        try tap(app.buttons["放弃修改"], in: app)
        try require(app.navigationBars["我的食物"], in: app)
        XCTAssertFalse(personalCard(named: name, in: app).exists, "Explicit discard must not create a card.")
        app.terminate()
        app.launch()
        try require(app.tabBars.buttons["设置"], timeout: 15, in: app)
        try openMyFoods(in: app)
        XCTAssertFalse(personalCard(named: name, in: app).exists, "The invalid draft must not appear after reopening the file-backed app.")
    }

    func testTemplatePersonalFoodCreationChangesOnlyInitiatingRowAndKeepsRawWeights() throws {
        executionTimeAllowance = 600
        let app = try launchApp()
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let foodName = "[UI测试] 模板蜂蜜-\(token)"
        try tap(app.tabBars.buttons["今日"], in: app)
        try tap(app.buttons["today.recordMeal"], in: app)
        try tap(app.navigationBars["记录一餐"].buttons["管理常用模板"], in: app)
        try tap(app.navigationBars["常用模板"].buttons["新建"], in: app)
        let first = try singleRow(prefix: "template", in: app)
        try chooseFood(rice, row: first, prefix: "template", in: app)
        try replace(field("template.weight.\(first)", in: app), with: "100.0", done: "template.keyboardDone", in: app)
        try tapRevealed(app.buttons["添加食物"], in: app)
        let others = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "template.weight.", "template.weight.\(first)"))
        try reveal(others.firstMatch, in: app)
        guard others.count == 1 else { throw fail("One add must create exactly one new template row.", in: app) }
        let second = String(others.firstMatch.identifier.dropFirst("template.weight.".count))
        XCTAssertNotEqual(first, second)
        try replace(others.firstMatch, with: ".", done: "template.keyboardDone", in: app)
        try openSelector(row: second, prefix: "template", in: app)
        try search(foodName, in: app)
        try require(app.staticTexts["没有找到食物"], in: app)
        try tapRevealed(app.buttons["food.personal.create"], towardTop: true, in: app)
        try fillCard(name: foodName, protein: false, in: app)
        try saveCard(in: app)
        try require(app.navigationBars["选择食物"], in: app)
        try require(app.staticTexts["food.personal.savedStatus"], in: app)
        try tapRevealed(app.buttons["food.personal.selectSaved"], towardTop: true, in: app)
        try assertRow(first, prefix: "template", name: rice, rawWeight: "100.0", towardTop: true, in: app)
        try assertRow(second, prefix: "template", name: foodName, rawWeight: ".", in: app)
        XCTAssertFalse(app.navigationBars["新建常用模板"].buttons["保存"].isEnabled, "Creating a card must not drop or repair the invalid initiating quantity.")
        try tap(app.navigationBars["新建常用模板"].buttons["取消"], in: app)
        try tap(app.buttons["继续编辑"], in: app)
        try assertRow(first, prefix: "template", name: rice, rawWeight: "100.0", towardTop: true, in: app)
        try assertRow(second, prefix: "template", name: foodName, rawWeight: ".", in: app)
        attachScreen(app, name: "OPT13-template-only-initiating-UUID-changed-raw-weights-preserved")
        try cancelChangedForm(prefix: "template", in: app)
        try tap(app.navigationBars["常用模板"].buttons["完成"], in: app)
        try tap(app.navigationBars["记录一餐"].buttons["取消"], in: app)
        try require(app.navigationBars["今日"], in: app)
    }

    /// Exercises real responder transitions without creating a food card.
    /// The same typed values must survive navigation, dismissal and activation.
    func testPersonalFoodKeyboardCompletionSurvivesFocusNavigationAndAppActivation() throws {
        executionTimeAllowance = 600
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 焦点生命周期-\(UUID().uuidString.prefix(8))"
        try openMyFoods(in: app)
        try tapRevealed(app.buttons["myFoods.create"], towardTop: true, in: app)
        let nameInput = try focusPersonalInput("name", towardTop: true, in: app)
        nameInput.typeText(name)
        XCTAssertEqual(nameInput.value as? String, name)
        _ = try personalKeyboardCompletion(in: app)
        attachScreen(app, name: "PersonalFoodPolish-name-keyboard-completion-visible")

        // Do not dismiss the text keyboard before switching to decimal input.
        let energy = try focusPersonalInput("energy", in: app)
        energy.typeText("300")
        XCTAssertEqual(energy.value as? String, "300")
        _ = try personalKeyboardCompletion(in: app)
        let fat = try focusPersonalInput("fat", in: app)
        fat.typeText("0")
        XCTAssertEqual(fat.value as? String, "0")
        try closePersonalKeyboard(in: app)

        _ = try focusPersonalInput("energy", towardTop: true, in: app)
        let (form, viewport) = try contentViewport(keyboardDone: "personalFood.keyboardDone", in: app)
        let keyboard = app.keyboards.firstMatch
        try require(keyboard, in: app)
        let formFrame = form.frame
        let keyboardFrame = keyboard.frame
        guard usable(formFrame), usable(keyboardFrame), app.frame.contains(keyboardFrame),
              viewport.maxY <= keyboardFrame.minY else {
            throw fail("Interactive dismissal requires the actual content viewport and visible keyboard bounds.", in: app)
        }
        // A short content-only scroll can move rows without dismissing an
        // interactive keyboard. Continue this real drag through its lower edge.
        let startY = (viewport.minY + viewport.height * 0.25 - formFrame.minY) / formFrame.height
        let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: startY))
        let end = keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.95))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "A real interactive scroll must dismiss this keyboard.")
        let afterScroll = try focusPersonalInput("energy", towardTop: true, in: app)
        XCTAssertEqual(afterScroll.value as? String, "300")
        try closePersonalKeyboard(in: app)

        try tapRevealed(field("personalFood.category", in: app), towardTop: true, in: app)
        // Pick a concrete visible native option; AX5 menus can virtualize other
        // options. Never tap a guessed coordinate or scroll the underlying Form.
        var chosenCategory: String?
        for title in ["蛋白质主食材", "主食与谷物", "混合餐食", "饮品", "油脂", "调味品"] {
            let options = app.buttons.matching(NSPredicate(format: "label == %@", title))
                .allElementsBoundByIndex.filter(\.isHittable)
            if options.count == 1, let option = options.first {
                chosenCategory = title
                try tap(option, in: app)
                break
            }
        }
        guard let chosenCategory else { throw fail("The native category picker must expose one real visible category option.", in: app) }
        let category = field("personalFood.category", in: app)
        try reveal(category, towardTop: true, in: app)
        XCTAssertTrue(([category.label, category.value as? String ?? ""]).joined(separator: " ").contains(chosenCategory))
        let afterPicker = try focusPersonalInput("energy", in: app)
        XCTAssertEqual(afterPicker.value as? String, "300")

        XCUIDevice.shared.press(.home)
        app.activate()
        try require(app.buttons["personalFood.cancel"], in: app)
        if app.keyboards.firstMatch.exists {
            _ = try personalKeyboardCompletion(in: app)
        } else {
            _ = try focusPersonalInput("energy", towardTop: true, in: app)
        }
        XCTAssertEqual(field("personalFood.energy", in: app).value as? String, "300", "Background and foreground transitions must preserve the actual raw input.")
        try closePersonalKeyboard(in: app)

        _ = try focusPersonalInput("energy", towardTop: true, in: app)
        try tap(app.buttons["personalFood.cancel"], in: app)
        try tap(app.buttons["继续编辑"], in: app)
        let continued = try focusPersonalInput("energy", towardTop: true, in: app)
        XCTAssertEqual(continued.value as? String, "300")
        try closePersonalKeyboard(in: app)
        try tap(app.buttons["personalFood.cancel"], in: app)
        try tap(app.buttons["放弃修改"], in: app)
        try require(app.navigationBars["我的食物"], in: app)
        XCTAssertFalse(personalCard(named: name, in: app).exists)

        try tapRevealed(app.buttons["myFoods.create"], towardTop: true, in: app)
        let reopened = try focusPersonalInput("name", towardTop: true, in: app)
        XCTAssertTrue(isBlank(reopened), "A discarded card must reopen as a clean new form.")
        try closePersonalKeyboard(in: app)
        try tap(app.buttons["personalFood.cancel"], in: app)
        try require(app.navigationBars["我的食物"], in: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists)
    }

    /// Saves exactly one fictitious card, checks the long last-row editor and
    /// captures the actual list appearance. It never records an intake.
    func testPersonalFoodSourceKeyboardAndSavedListRemainUsable() throws {
        executionTimeAllowance = 600
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 食物列表验收-\(UUID().uuidString.prefix(8))"
        let source = "虚构验收样本，用于检查来源说明长文字输入、键盘完成按钮、保存后重新打开以及所有文字原样保留，不代表实际包装营养数据。"
        try openMyFoods(in: app)
        try tapRevealed(app.buttons["myFoods.create"], towardTop: true, in: app)
        for (key, raw) in [
            ("name", name), ("energy", "300"), ("fat", "0"),
            ("saturatedFat", "0"), ("carbohydrate", "75"),
            ("sugar", "75"), ("protein", "0"), ("salt", "0")
        ] {
            let input = try focusPersonalInput(key, in: app)
            input.typeText(raw)
            XCTAssertEqual(input.value as? String, raw)
            try closePersonalKeyboard(in: app)
        }
        let sourceInput = try focusPersonalInput("sourceNote", in: app)
        sourceInput.typeText(source)
        XCTAssertEqual(sourceInput.value as? String, source)
        _ = try personalKeyboardCompletion(in: app)
        attachScreen(app, name: "PersonalFoodPolish-long-source-keyboard-completion-visible")
        try closePersonalKeyboard(in: app)
        try saveCard(in: app)
        let cardID = try personalCardID(named: name, in: app)
        let row = app.buttons["myFoods.food.\(cardID)"]
        try reveal(row, in: app)
        attachScreen(app, name: "PersonalFoodPolish-saved-list-native-row")
        try tap(row, in: app)
        try require(app.navigationBars["编辑我的食物"], in: app)
        XCTAssertEqual(try revealedValue("personalFood.name", towardTop: true, in: app), name)
        XCTAssertEqual(try revealedValue("personalFood.sourceNote", in: app), source)
        _ = try focusPersonalInput("sourceNote", in: app)
        try closePersonalKeyboard(in: app)
        try tap(app.buttons["personalFood.cancel"], in: app)
        try require(app.navigationBars["我的食物"], in: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists, "Focusing an unchanged saved card must not create a draft edit.")
        try tapRevealed(app.buttons["myFoods.create"], towardTop: true, in: app)
        _ = try focusPersonalInput("name", towardTop: true, in: app)
        try closePersonalKeyboard(in: app)
        try tap(app.buttons["personalFood.cancel"], in: app)
        try require(app.navigationBars["我的食物"], in: app)
    }

    private func focusPersonalInput(_ key: String, towardTop: Bool = false, in app: XCUIApplication) throws -> XCUIElement {
        let input = field("personalFood.\(key)", in: app)
        try revealPersonalInput(input, towardTop: towardTop, in: app)
        try tap(input, in: app)
        _ = try personalKeyboardCompletion(in: app)
        try revealPersonalInput(input, towardTop: towardTop, in: app)
        return input
    }

    private func revealPersonalInput(_ input: XCUIElement, towardTop: Bool, in app: XCUIApplication) throws {
        var geometry: [String] = []
        for attempt in 0...12 {
            _ = input.waitForExistence(timeout: 1)
            let (container, viewport) = try contentViewport(in: app)
            let frame = input.exists ? input.frame : .zero
            geometry.append("\(attempt): target=\(frame), viewport=\(viewport)")
            if input.exists, input.isHittable, usable(frame), viewport.contains(frame) { return }
            guard attempt < 12 else { break }
            guard usable(frame) else {
                try scroll(towardTop: towardTop, in: app)
                continue
            }
            // Centre the real control with a bounded, slow drag. Fixed large
            // swipes oscillate past a short AX5 input while the keyboard stays up.
            let desiredDelta = viewport.midY - frame.midY
            let maximumStep = viewport.height * 0.35
            let delta = max(-maximumStep, min(maximumStep, desiredDelta))
            let bounds = container.frame
            let start = container.coordinate(withNormalizedOffset: CGVector(
                dx: 0.04, dy: (viewport.midY - delta / 2 - bounds.minY) / bounds.height
            ))
            let end = container.coordinate(withNormalizedOffset: CGVector(
                dx: 0.04, dy: (viewport.midY + delta / 2 - bounds.minY) / bounds.height
            ))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let attachment = XCTAttachment(string: geometry.joined(separator: "\n"))
        attachment.name = "PersonalFoodPolish-input-viewport-geometry"
        attachment.lifetime = .keepAlways
        add(attachment)
        throw fail("The entire personal-food input must fit below navigation and above its actual keyboard completion after bounded positioning.", in: app)
    }

    private func personalKeyboardCompletion(in app: XCUIApplication) throws -> XCUIElement {
        let keyboard = app.keyboards.firstMatch
        try require(keyboard, in: app)
        let completions = app.buttons.matching(identifier: "personalFood.keyboardDone")
        try require(completions.firstMatch, in: app)
        guard completions.count == 1 else { throw fail("Each actual personal-food keyboard must expose one unique completion action.", in: app) }
        let done = completions.firstMatch
        let frame = done.frame
        let keyboardFrame = keyboard.frame
        guard done.isHittable, usable(frame), app.frame.contains(frame),
              frame.maxY <= keyboardFrame.minY else {
            attachScreen(app, name: "PersonalFoodPolish-keyboard-completion-not-visible")
            throw fail("The complete real keyboard completion button must remain hittable above the keyboard.", in: app)
        }
        XCTAssertEqual(done.label, "完成")
        return done
    }

    private func closePersonalKeyboard(in app: XCUIApplication) throws {
        try tap(personalKeyboardCompletion(in: app), in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The unique visible completion action must actually dismiss the software keyboard.")
    }

    private func launchApp() throws -> XCUIApplication {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Personal food writes are authorized only on a dedicated fictitious-data QA simulator.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.ning6y6.ShiHeng")
        diagnosticApplication = app
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        try require(app.tabBars.buttons["今日"], timeout: 15, in: app)
        return app
        #endif
    }

    private func fillCard(name: String, protein: Bool, includeSalt: Bool = true, in app: XCUIApplication) throws {
        try require(app.navigationBars["新建我的食物"], in: app)
        let nameField = field("personalFood.name", in: app)
        try reveal(nameField, towardTop: true, in: app)
        if nameField.value as? String != name {
            try replace(nameField, with: name, done: "personalFood.keyboardDone", in: app)
        }
        XCTAssertFalse(app.buttons["personalFood.save"].isEnabled)
        let nutrients = protein
            ? [("energy", "400"), ("fat", "6"), ("saturatedFat", "2"), ("carbohydrate", "10"), ("sugar", "3"), ("protein", "80"), ("salt", "0.5")]
            : [("energy", "300"), ("fat", "0"), ("saturatedFat", "0"), ("carbohydrate", "75"), ("sugar", "75"), ("protein", "0"), ("salt", "0")]
        for (key, value) in nutrients where includeSalt || key != "salt" {
            try replace(field("personalFood.\(key)", in: app), with: value, done: "personalFood.keyboardDone", in: app)
        }
        let fibre = field("personalFood.fibre", in: app)
        try reveal(fibre, in: app)
        XCTAssertTrue(isBlank(fibre), "The fixture intentionally leaves fibre unknown, without substituting zero.")
        try replace(field("personalFood.sourceNote", in: app), with: "虚构QA样本，非实际包装数值", done: "personalFood.keyboardDone", in: app)
        XCTAssertEqual(app.buttons["personalFood.save"].isEnabled, includeSalt)
    }

    private func saveCard(in app: XCUIApplication) throws {
        let save = app.buttons["personalFood.save"]
        try require(save, in: app)
        guard save.isEnabled else { throw fail("A fully valid per-100g card must enable its actual Save.", in: app) }
        try tap(save, in: app)
        XCTAssertTrue(app.buttons["personalFood.save"].waitForNonExistence(timeout: 5))
    }

    private func openMyFoods(in app: XCUIApplication) throws {
        try tap(app.tabBars.buttons["设置"], in: app)
        if app.navigationBars["我的食物"].exists { return }
        try tapRevealed(app.buttons["settings.myFoods"], in: app)
        try require(app.navigationBars["我的食物"], in: app)
    }

    private func personalCard(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND (label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@)", "myFoods.food.", name, "\(name)、", "\(name), ")).firstMatch
    }

    private func personalCardID(named name: String, in app: XCUIApplication) throws -> String {
        let card = personalCard(named: name, in: app)
        try reveal(card, in: app)
        let id = String(card.identifier.dropFirst("myFoods.food.".count))
        guard UUID(uuidString: id) != nil else { throw fail("The run-specific card must expose its stable food UUID.", in: app) }
        return id
    }

    private func newMeal(named name: String, in app: XCUIApplication) throws {
        try tap(app.tabBars.buttons["今日"], in: app)
        try tap(app.buttons["today.recordMeal"], in: app)
        try tap(app.buttons["空白记录"], in: app)
        try replace(field("meal.name", in: app), with: name, done: "meal.keyboardDone", in: app)
    }

    private func record(_ food: String, grams: Int, named name: String, expectedKcal: Int, in app: XCUIApplication) throws {
        try newMeal(named: name, in: app)
        let row = try singleRow(prefix: "meal", in: app)
        try chooseFood(food, row: row, prefix: "meal", in: app)
        try replace(field("meal.weight.\(row)", in: app), with: String(grams), done: "meal.keyboardDone", in: app)
        try assertEnergy(expectedKcal, preview: true, in: app)
        try saveMeal(title: "记录一餐", in: app)
    }

    private func singleRow(prefix: String, in app: XCUIApplication) throws -> String {
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).weight."))
        try reveal(fields.firstMatch, in: app)
        guard fields.count == 1 else { throw fail("The known single-row fixture requires one actual quantity control.", in: app) }
        let id = String(fields.firstMatch.identifier.dropFirst("\(prefix).weight.".count))
        guard UUID(uuidString: id) != nil else { throw fail("Quantity must identify the real component UUID.", in: app) }
        return id
    }

    private func openSelector(row: String, prefix: String, in app: XCUIApplication) throws {
        try tapRevealed(app.buttons["\(prefix).food.\(row)"], in: app)
        try require(app.navigationBars["选择食物"], in: app)
    }

    private func search(_ query: String, in app: XCUIApplication) throws {
        let searches = app.searchFields
        try require(searches.firstMatch, in: app)
        guard searches.count == 1 else { throw fail("The selector must have one actual native search field.", in: app) }
        let search = searches.firstMatch
        try tap(search, in: app)
        let old = search.value as? String ?? ""
        if !old.isEmpty, old != search.placeholderValue {
            guard search.buttons.count == 1 else { throw fail("Native search must expose one clear-text action.", in: app) }
            try tap(search.buttons.firstMatch, in: app)
        }
        search.typeText(query)
        XCTAssertEqual(search.value as? String, query)
        try tap(app.keyboards.firstMatch.buttons["Search"], in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    private func chooseFood(_ name: String, row: String, prefix: String, in app: XCUIApplication) throws {
        try openSelector(row: row, prefix: prefix, in: app)
        try search(name, in: app)
        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "food.select.", name))
        try reveal(results.firstMatch, in: app)
        guard results.count == 1 else { throw fail("A full unique food name must identify one real search result.", in: app) }
        try tap(results.firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["选择食物"].waitForNonExistence(timeout: 5))
        let food = app.buttons["\(prefix).food.\(row)"]
        try reveal(food, in: app)
        XCTAssertEqual(food.value as? String, name)
    }

    private func assertRow(_ row: String, prefix: String, name: String, rawWeight: String, towardTop: Bool = false, in app: XCUIApplication) throws {
        let food = app.buttons["\(prefix).food.\(row)"]
        try reveal(food, towardTop: towardTop, in: app)
        XCTAssertEqual(food.value as? String, name)
        XCTAssertEqual(try revealedValue("\(prefix).weight.\(row)", in: app), rawWeight)
    }

    private func cancelChangedForm(prefix: String, in app: XCUIApplication) throws {
        let title = prefix == "meal" ? "记录一餐" : "新建常用模板"
        let bars = app.navigationBars.matching(identifier: title).containing(.button, identifier: "保存")
        guard bars.count == 1 else { throw fail("Cancel must target the actual form that owns Save, not its underlying start page.", in: app) }
        try tap(bars.firstMatch.buttons["取消"], in: app)
        try tap(app.buttons["放弃修改"], in: app)
        XCTAssertTrue(app.textFields["\(prefix).name"].waitForNonExistence(timeout: 5))
    }

    private func saveMeal(title: String, in app: XCUIApplication) throws {
        let save = app.navigationBars[title].buttons["保存"]
        try require(save, in: app)
        guard save.isEnabled else { throw fail("The valid meal must enable Save.", in: app) }
        try tap(save, in: app)
        XCTAssertTrue(app.textFields["meal.name"].waitForNonExistence(timeout: 5))
    }

    private func openMealEditor(in app: XCUIApplication) throws {
        try tap(app.navigationBars["餐食详情"].buttons["编辑"], in: app)
        try require(app.navigationBars["编辑餐食"], in: app)
    }

    private func savedMealHeader(name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND (label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@)", "meal.row.", name, "\(name)、", "\(name), ")).firstMatch
    }

    private func openMeal(_ name: String, in app: XCUIApplication) throws {
        let header = savedMealHeader(name: name, in: app)
        if !header.exists {
            try tapRevealed(app.buttons["查看全部历史"], in: app)
            try require(app.navigationBars["历史餐食"], in: app)
        }
        try reveal(header, in: app)
        let id = String(header.identifier.dropFirst("meal.row.".count))
        guard UUID(uuidString: id) != nil else { throw fail("Only the exact synthetic saved meal may be opened.", in: app) }
        if header.value as? String != "已展开" { try tap(header, in: app) }
        try tapRevealed(app.buttons["meal.details.\(id)"], in: app)
        try require(app.navigationBars["餐食详情"], in: app)
    }

    private func assertEnergy(_ kcal: Int, preview: Bool, in app: XCUIApplication) throws {
        let row = app.descendants(matching: .any).matching(identifier: preview ? "meal.preview.energy" : "meal.detail.energy").firstMatch
        try reveal(row, in: app)
        let values = [row.label, row.value as? String ?? ""] + row.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(values.contains { $0 == "\(kcal) kcal" || $0.hasSuffix("、\(kcal) kcal") || $0.hasSuffix(", \(kcal) kcal") }, "Expected exactly \(kcal) kcal, observed \(values).")
    }

    private func assertDetailFood(_ name: String, grams: Int, in app: XCUIApplication) throws {
        let rows = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "\(name)、\(grams) g", "\(name), \(grams) g"))
        try reveal(rows.firstMatch, towardTop: true, in: app)
    }

    private func deleteOwnMeal(_ name: String, in app: XCUIApplication) throws {
        guard name.hasPrefix("[UI测试] "), name.contains("蛋白粉") || name.contains("蜂蜜") else {
            throw fail("Cleanup is restricted to this run's named personal-food QA meals.", in: app)
        }
        let details = app.descendants(matching: .any).matching(identifier: "meal.detail")
        guard details.count == 1 else { throw fail("Cleanup requires one frontmost saved-meal detail.", in: app) }
        let names = details.firstMatch.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@", name, "名称、\(name)", "名称, \(name)"))
        try reveal(names.firstMatch, towardTop: true, in: app)
        guard names.count == 1 else { throw fail("Cleanup must verify the exact saved name before deleting.", in: app) }
        try tapRevealed(app.buttons["meal.delete"], in: app)
        let title = "确定删除“\(name)”吗？"
        try require(app.staticTexts[title], in: app)
        let popovers = app.popovers.containing(.staticText, identifier: title)
        let dialogs = popovers.count > 0 ? popovers : app.sheets.containing(.staticText, identifier: title)
        guard dialogs.count == 1 else { throw fail("Deletion requires the exact run-specific native confirmation.", in: app) }
        let deletes = dialogs.firstMatch.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "删除餐食", "meal.delete"))
        guard deletes.count == 1 else { throw fail("Expected one explicit destructive confirmation for this own QA meal.", in: app) }
        try tap(deletes.firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["餐食详情"].waitForNonExistence(timeout: 5))
    }

    private func field(_ id: String, in app: XCUIApplication) -> XCUIElement {
        // Resolve by stable identifier after native scrolling, rather than
        // choosing a control type while an offscreen field is virtualized.
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func revealedValue(_ id: String, towardTop: Bool = false, in app: XCUIApplication) throws -> String? {
        let input = field(id, in: app)
        try reveal(input, towardTop: towardTop, in: app)
        return input.value as? String
    }

    private func isBlank(_ input: XCUIElement) -> Bool {
        let value = input.value as? String ?? ""
        return value.isEmpty || value == input.placeholderValue
    }

    private func replace(_ input: XCUIElement, with text: String, done: String, towardTop: Bool = false, in app: XCUIApplication) throws {
        try reveal(input, towardTop: towardTop, in: app)
        let old = input.value as? String ?? ""
        try tap(input, in: app)
        try require(app.keyboards.firstMatch, in: app)
        try revealInput(input, done: done, in: app)
        if !old.isEmpty, old != input.placeholderValue {
            let isWeight = input.identifier.hasPrefix("meal.weight.") || input.identifier.hasPrefix("template.weight.")
            if isWeight {
                // WeightTextField aligns its short text at the trailing edge.
                // Select the real glyphs, as the existing snapshot UI tests do;
                // a long press in the wide field's blank centre selects nothing.
                let frame = input.frame
                guard usable(frame) else { throw fail("Native text selection requires the actual input bounds.", in: app) }
                input.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).doubleTap()
            } else {
                input.press(forDuration: 1)
            }
            let labels = NSPredicate(format: "label IN %@", ["全选", "Select All"])
            _ = app.menuItems.matching(labels).firstMatch.waitForExistence(timeout: 5)
            let menu = app.menuItems.matching(labels).allElementsBoundByIndex + app.buttons.matching(labels).allElementsBoundByIndex
            if menu.count == 1, let selectAll = menu.first {
                try tap(selectAll, in: app)
            } else {
                let cuts = NSPredicate(format: "label IN %@", ["剪切", "Cut"])
                let actions = app.menuItems.matching(cuts).allElementsBoundByIndex + app.buttons.matching(cuts).allElementsBoundByIndex
                guard actions.count == 1, let cut = actions.first else { throw fail("Replacing real text requires native Select All or a complete Cut selection.", in: app) }
                try tap(cut, in: app)
                guard isBlank(input) else { throw fail("Cut must clear the full old value before replacement.", in: app) }
            }
        }
        input.typeText(text)
        XCTAssertEqual(input.value as? String, text)
        try tap(app.buttons[done], in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    private func revealInput(_ input: XCUIElement, done: String, in app: XCUIApplication) throws {
        try require(app.keyboards.firstMatch, in: app)
        for attempt in 0...4 {
            let finish = app.buttons[done]
            try require(finish, in: app)
            let (_, viewport) = try contentViewport(keyboardDone: done, in: app)
            let frame = input.exists ? input.frame : .zero
            if input.exists, input.isHittable, usable(frame), viewport.contains(frame) { return }
            if attempt < 4 {
                try scroll(towardTop: usable(frame) && frame.minY < viewport.minY, in: app)
            }
        }
        throw fail("The entire actual input must remain below the navigation bar and above its real keyboard and completion toolbar.", in: app)
    }

    private func tapRevealed(_ element: XCUIElement, towardTop: Bool = false, in app: XCUIApplication) throws {
        try reveal(element, towardTop: towardTop, in: app)
        try tap(element, in: app)
    }

    private func reveal(_ element: XCUIElement, towardTop: Bool = false, in app: XCUIApplication) throws {
        for _ in 0..<16 {
            _ = element.waitForExistence(timeout: 1)
            let (_, viewport) = try contentViewport(in: app)
            // Read current geometry on each attempt. Native Form may retain an
            // isHittable=true snapshot for a field hidden behind the status bar.
            let frame = element.exists ? element.frame : .zero
            if element.exists, element.isHittable, usable(frame), viewport.contains(frame) { return }
            try scroll(towardTop: usable(frame) ? frame.minY < viewport.minY : towardTop, in: app)
        }
        throw fail("The complete actual control must be inside the visible native content viewport after bounded scrolling.", in: app)
    }

    private func contentViewport(keyboardDone: String? = nil, in app: XCUIApplication) throws -> (XCUIElement, CGRect) {
        let ids = ["personalFood.form", "food.selection.list", "myFoods.list", "template.form", "meal.form", "meal.detail", "meal.history", "meal.start", "templates.list", "settings.form", "today.content"]
        guard let container = ids.lazy.compactMap({ id -> XCUIElement? in
            let matches = app.descendants(matching: .any).matching(identifier: id)
            return matches.count == 1 && matches.firstMatch.isHittable ? matches.firstMatch : nil
        }).first else { throw fail("Scrolling requires one actual frontmost identified content container.", in: app) }
        let frame = container.frame
        let appFrame = app.frame
        let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.maxY).max() ?? appFrame.minY
        let top = max(frame.minY, appFrame.minY, navigationBottom)
        var bottom = min(frame.maxY, appFrame.maxY)
        if let tabTop = app.tabBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.minY).min() {
            bottom = min(bottom, tabTop)
        }
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            bottom = min(bottom, keyboard.frame.minY)
            let finishes = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", ".keyboardDone"))
                .allElementsBoundByIndex.filter(\.isHittable)
            guard finishes.count == 1, let finish = finishes.first,
                  keyboardDone == nil || finish.identifier == keyboardDone else {
                throw fail("An active form keyboard must expose its one real, identified completion toolbar.", in: app)
            }
            bottom = min(bottom, finish.frame.minY)
        }
        let viewport = CGRect(
            x: max(frame.minX, appFrame.minX), y: top,
            width: min(frame.maxX, appFrame.maxX) - max(frame.minX, appFrame.minX),
            height: bottom - top
        )
        guard usable(frame), usable(viewport), viewport.height > 44 else {
            throw fail("The native content viewport between navigation and keyboard must have finite usable geometry.", in: app)
        }
        return (container, viewport)
    }

    private func usable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    private func scroll(towardTop: Bool, in app: XCUIApplication) throws {
        let (container, viewport) = try contentViewport(in: app)
        let frame = container.frame
        let startY = (viewport.minY + viewport.height * (towardTop ? 0.25 : 0.72) - frame.minY) / frame.height
        let endY = (viewport.minY + viewport.height * (towardTop ? 0.72 : 0.25) - frame.minY) / frame.height
        container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: startY)).press(
            forDuration: 0.05,
            thenDragTo: container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: endY))
        )
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        try require(element, in: app)
        let id = element.identifier
        let isInput = element.elementType == .textField || element.elementType == .textView
        let isBodyAction = id.hasPrefix("myFoods.food.") || id == "myFoods.create"
            || id == "settings.myFoods" || id.hasPrefix("food.select.")
            || id.hasPrefix("food.personal.") || id.hasPrefix("meal.food.")
            || id.hasPrefix("template.food.") || id.hasPrefix("meal.row.")
            || id.hasPrefix("meal.details.") || id == "meal.delete"
        if isInput || isBodyAction {
            try reveal(element, in: app)
            let (_, viewport) = try contentViewport(in: app)
            let frame = element.frame
            guard element.isHittable, usable(frame), viewport.contains(frame) else {
                throw fail("A native body tap requires the whole current control below navigation and above the keyboard.", in: app)
            }
        }
        // Toolbar taps stay native; their expected visible result is verified by
        // callers. Never replace an occluded input tap with screen coordinates.
        element.tap()
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval = 5, in app: XCUIApplication) throws {
        guard element.waitForExistence(timeout: timeout) else { throw fail("The requested native control must exist.", in: app) }
    }

    private func fail(_ message: String, in app: XCUIApplication) -> PersonalFoodUIError {
        XCTFail(message)
        if diagnosticApplication != nil {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "OPT13-failure-native-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreen(app, name: "OPT13-failure-screen")
        }
        return .missingNativeControl
    }

    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum PersonalFoodUIError: Error {
    case missingNativeControl
}
