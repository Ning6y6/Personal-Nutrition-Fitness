import Foundation
import UIKit
import XCTest

/// Real form interactions on the dedicated fictitious-data QA simulator only.
/// Public rice is selected through native search; no database or App state is injected.
@MainActor
final class MealSnapshotEditingUITests: XCTestCase {
    private let riceName = "熟长粒白米饭（无盐）"
    private var diagnosticApplication: XCUIApplication?

    func testMetadataOnlySavePreservesRiceSnapshotAfterNameAndTimeChange() throws {
        executionTimeAllowance = 420
        let app = try launchApp()
        defer { app.terminate() }
        let token = String(UUID().uuidString.prefix(8))
        let originalName = "[UI测试] 快照元信息-\(token)"
        let editedName = "[UI测试] 快照改名-\(token)"
        try createRiceMeal(named: originalName, in: app)
        try openMeal(named: originalName, in: app)
        try assertEnergy(131, preview: false, in: app)
        let originalTime = try detailTime(in: app)

        try openEditor(in: app)
        let rowID = try componentRowID(in: app)
        try replaceText(app.textFields["meal.name"], with: editedName, in: app)
        try changeMealTimeUsingNativePicker(in: app)
        try assertEnergy(131, preview: true, in: app)
        try saveEditor(in: app)

        try assertEnergy(131, preview: false, in: app)
        try assertRiceWeight(100, in: app)
        XCTAssertNotEqual(try detailTime(in: app), originalTime, "A real picker change must survive the metadata-only save.")
        try openEditor(in: app)
        try reveal(app.textFields["meal.name"], in: app)
        XCTAssertEqual(app.textFields["meal.name"].value as? String, editedName)
        XCTAssertEqual(try componentRowID(in: app), rowID, "Metadata-only editing must preserve the persisted component UUID.")
        try tap(app.navigationBars["编辑餐食"].buttons["取消"], in: app)
        try require(app.navigationBars["餐食详情"], in: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists, "An untouched reopened editor must not become dirty.")
        attachScreen(app, name: "OPT14A-metadata-save-keeps-131kcal")
        try deleteOwnMeal(named: editedName, in: app)
    }

    func testWeightRoundTripRestoresPreviewAndPreservesOriginalComponent() throws {
        executionTimeAllowance = 360
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 快照往返-\(UUID().uuidString.prefix(8))"
        try createRiceMeal(named: name, in: app)
        try openMeal(named: name, in: app)
        try openEditor(in: app)
        let rowID = try componentRowID(in: app)
        let weight = app.textFields["meal.weight.\(rowID)"]
        try assertEnergy(131, preview: true, in: app)

        try replaceText(weight, with: "200", abovePreview: true, in: app)
        try assertEnergy(262, preview: true, in: app)
        try replaceText(weight, with: "100", abovePreview: true, in: app)
        try assertEnergy(131, preview: true, in: app)
        XCTAssertEqual(try componentRowID(abovePreview: true, in: app), rowID)
        try saveEditor(in: app)
        try assertEnergy(131, preview: false, in: app)
        try assertRiceWeight(100, in: app)

        try openEditor(in: app)
        XCTAssertEqual(try componentRowID(in: app), rowID, "Saving a restored quantity must retain its original component identity.")
        try reveal(weight, in: app)
        XCTAssertEqual(weight.value as? String, "100")
        try tap(app.navigationBars["编辑餐食"].buttons["取消"], in: app)
        try require(app.navigationBars["餐食详情"], in: app)
        XCTAssertFalse(app.buttons["放弃修改"].exists)
        attachScreen(app, name: "OPT14A-weight-roundtrip-restores-131kcal")
        try deleteOwnMeal(named: name, in: app)
    }

    func testWeightChangeContinueDiscardThenSaveDoublesOnlyOwnMeal() throws {
        executionTimeAllowance = 420
        let app = try launchApp()
        defer { app.terminate() }
        let name = "[UI测试] 快照翻倍-\(UUID().uuidString.prefix(8))"
        try createRiceMeal(named: name, in: app)
        try openMeal(named: name, in: app)
        try openEditor(in: app)
        let rowID = try componentRowID(in: app)
        let weight = app.textFields["meal.weight.\(rowID)"]
        try replaceText(weight, with: "200", in: app)
        try assertEnergy(262, preview: true, in: app)
        try tap(app.navigationBars["编辑餐食"].buttons["取消"], in: app)
        try tap(app.buttons["继续编辑"], in: app)
        try reveal(weight, preferUpWhenMissing: true, in: app)
        XCTAssertEqual(weight.value as? String, "200", "Continue editing must retain the typed quantity.")
        XCTAssertEqual(try componentRowID(in: app), rowID)
        try assertEnergy(262, preview: true, in: app)
        try tap(app.navigationBars["编辑餐食"].buttons["取消"], in: app)
        try tap(app.buttons["放弃修改"], in: app)
        try require(app.navigationBars["餐食详情"], in: app)
        try assertEnergy(131, preview: false, in: app)
        try assertRiceWeight(100, in: app)

        try openEditor(in: app)
        XCTAssertEqual(try componentRowID(in: app), rowID)
        try replaceText(weight, with: "200", in: app)
        try assertEnergy(262, preview: true, in: app)
        try saveEditor(in: app)
        attachScreen(app, name: "OPT14A-immediately-after-weight-save")
        let savedHierarchy = XCTAttachment(string: app.debugDescription)
        savedHierarchy.name = "OPT14A-immediately-after-weight-save-hierarchy"
        savedHierarchy.lifetime = .keepAlways
        add(savedHierarchy)
        try assertEnergy(262, preview: false, in: app)
        try assertRiceWeight(200, in: app)
        try tap(app.navigationBars["餐食详情"].buttons["关闭"], in: app)

        app.terminate()
        app.launch()
        try require(app.tabBars.buttons["今日"], timeout: 15, in: app)
        try openMeal(named: name, in: app)
        try assertEnergy(262, preview: false, in: app)
        try assertRiceWeight(200, in: app)
        attachScreen(app, name: "OPT14A-continued-discarded-and-persisted-262kcal")
        try deleteOwnMeal(named: name, in: app)
    }

    private func launchApp() throws -> XCUIApplication {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Snapshot editing writes are authorized only on a dedicated fictitious-data QA simulator.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.ning6y6.ShiHeng")
        diagnosticApplication = app
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        try require(app.tabBars.buttons["今日"], timeout: 15, in: app)
        return app
        #endif
    }

    private func createRiceMeal(named name: String, in app: XCUIApplication) throws {
        try tap(app.tabBars.buttons["今日"], in: app)
        try tap(app.buttons["today.recordMeal"], in: app)
        try tap(app.buttons["空白记录"], in: app)
        try replaceText(app.textFields["meal.name"], with: name, in: app)
        let foodControls = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.food."))
        try reveal(foodControls.firstMatch, in: app)
        guard foodControls.count == 1 else { throw fail("Expected one real food control in the blank one-row meal.", in: app) }
        try tap(foodControls.firstMatch, in: app)
        try require(app.navigationBars["选择食物"], in: app)
        let searches = app.searchFields
        try require(searches.firstMatch, in: app)
        guard searches.count == 1 else { throw fail("Expected one native food search field.", in: app) }
        try tap(searches.firstMatch, in: app)
        searches.firstMatch.typeText(riceName)
        XCTAssertEqual(searches.firstMatch.value as? String, riceName)
        try tap(app.keyboards.firstMatch.buttons["Search"], in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "food.select.", riceName))
        try reveal(results.firstMatch, in: app)
        guard results.count == 1,
              UUID(uuidString: String(results.firstMatch.identifier.dropFirst("food.select.".count))) != nil else {
            throw fail("The complete public rice name must resolve to one stable food UUID.", in: app)
        }
        try tap(results.firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["选择食物"].waitForNonExistence(timeout: 5))
        let rowID = try componentRowID(in: app)
        try replaceText(app.textFields["meal.weight.\(rowID)"], with: "100", in: app)
        try assertEnergy(131, preview: true, in: app)
        try saveEditor(in: app, title: "记录一餐")
        try require(app.navigationBars["今日"], in: app)
    }

    private func componentRowID(abovePreview: Bool = false, in app: XCUIApplication) throws -> String {
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "meal.weight."))
        try reveal(fields.firstMatch, preferUpWhenMissing: abovePreview, in: app)
        guard fields.count == 1 else { throw fail("This one-component meal must expose exactly one real quantity field.", in: app) }
        let id = String(fields.firstMatch.identifier.dropFirst("meal.weight.".count))
        guard UUID(uuidString: id) != nil else { throw fail("The quantity control must identify its actual row UUID.", in: app) }
        return id
    }

    private func openMeal(named name: String, in app: XCUIApplication) throws {
        func matchingHeader(in container: XCUIElement) -> XCUIElementQuery {
            container.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND (label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@)", "meal.row.", name, "\(name)、", "\(name), "))
        }
        var container = try identified("today.content", in: app)
        var headers = matchingHeader(in: container)
        if !headers.firstMatch.exists {
            try reveal(app.buttons["查看全部历史"], in: app)
            try tap(app.buttons["查看全部历史"], in: app)
            try require(app.navigationBars["历史餐食"], in: app)
            container = try identified("meal.history", in: app)
            headers = matchingHeader(in: container)
        }
        try reveal(headers.firstMatch, in: app)
        guard headers.count == 1 else { throw fail("The run-specific name must identify one saved meal header.", in: app) }
        let header = headers.firstMatch
        let id = String(header.identifier.dropFirst("meal.row.".count))
        guard UUID(uuidString: id) != nil else { throw fail("The saved meal header must identify a UUID.", in: app) }
        if header.value as? String != "已展开" { try tap(header, in: app) }
        let details = container.buttons.matching(identifier: "meal.details.\(id)")
        try reveal(details.firstMatch, in: app)
        guard details.count == 1 else { throw fail("The exact saved meal must expose one detail action.", in: app) }
        try tap(details.firstMatch, in: app)
        try require(app.navigationBars["餐食详情"], in: app)
    }

    private func openEditor(in app: XCUIApplication) throws {
        try tap(app.navigationBars["餐食详情"].buttons["编辑"], in: app)
        try require(app.navigationBars["编辑餐食"], in: app)
        try require(app.textFields["meal.name"], in: app)
    }

    private func saveEditor(in app: XCUIApplication, title: String = "编辑餐食") throws {
        let save = app.navigationBars[title].buttons["保存"]
        try require(save, in: app)
        guard save.isEnabled else { throw fail("The completely valid meal must permit its real Save action.", in: app) }
        try tap(save, in: app)
        guard app.textFields["meal.name"].waitForNonExistence(timeout: 5) else {
            throw fail("The valid Save must actually dismiss its editor.", in: app)
        }
    }

    private func assertEnergy(_ kcal: Int, preview: Bool, in app: XCUIApplication) throws {
        let container = try identified(preview ? "meal.form" : "meal.detail", in: app)
        let rows = container.descendants(matching: .any).matching(identifier: preview ? "meal.preview.energy" : "meal.detail.energy")
        try reveal(rows.firstMatch, in: app)
        guard rows.count == 1 else { throw fail("Expected one exact frontmost energy row.", in: app) }
        let row = rows.firstMatch
        let strings = [row.label, row.value as? String ?? ""] + row.staticTexts.allElementsBoundByIndex.map(\.label)
        let expected = "\(kcal) kcal"
        XCTAssertTrue(strings.contains { $0 == expected || $0.hasSuffix("、\(expected)") || $0.hasSuffix(", \(expected)") }, "The actual energy row must show exactly \(expected); observed \(strings).")
    }

    private func assertRiceWeight(_ grams: Int, in app: XCUIApplication) throws {
        let detail = try identified("meal.detail", in: app)
        let rows = detail.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "\(riceName)、\(grams) g", "\(riceName), \(grams) g"))
        try reveal(rows.firstMatch, preferUpWhenMissing: true, in: app)
        guard rows.count == 1 else { throw fail("The frontmost snapshot must contain exactly this public rice and \(grams) g.", in: app) }
    }

    private func detailTime(in app: XCUIApplication) throws -> String {
        let detail = try identified("meal.detail", in: app)
        let rows = detail.descendants(matching: .any).matching(identifier: "meal.detail.time")
        try reveal(rows.firstMatch, preferUpWhenMissing: true, in: app)
        guard rows.count == 1 else { throw fail("The frontmost detail must expose one persisted time value.", in: app) }
        let row = rows.firstMatch
        let text = ([row.label, row.value as? String ?? ""] + row.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
        guard !text.isEmpty else { throw fail("The persisted detail time must be readable.", in: app) }
        return text
    }

    private func changeMealTimeUsingNativePicker(in app: XCUIApplication) throws {
        let pickers = app.datePickers.matching(identifier: "meal.time")
        try reveal(pickers.firstMatch, in: app)
        guard pickers.count == 1 else { throw fail("Expected one actual meal date picker.", in: app) }
        let picker = pickers.firstMatch
        if picker.pickerWheels.count > 0 {
            // Actual accessibility layout uses date + hour + minute. Preserve the
            // observed locale suffix rather than guessing an English/Chinese value.
            guard picker.pickerWheels.count == 3 else { throw fail("Expected the observed three-wheel native meal picker.", in: app) }
            let hourWheel = picker.pickerWheels.element(boundBy: 1)
            try reveal(hourWheel, in: app)
            let original = try XCTUnwrap(hourWheel.value as? String)
            let digits = original.prefix(while: \.isNumber)
            guard let hour = Int(digits), (0...23).contains(hour) else { throw fail("The native hour wheel must expose a readable 24-hour value.", in: app) }
            let suffix = String(original.dropFirst(digits.count))
            let changed = "\((hour + 1) % 24)\(suffix)"
            hourWheel.adjust(toPickerWheelValue: changed)
            XCTAssertEqual(hourWheel.value as? String, changed)
            return
        }

        let dateButtons = picker.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年.*"))
        guard dateButtons.count == 1 else { throw fail("The compact native picker must expose one Chinese date action.", in: app) }
        try tap(dateButtons.firstMatch, in: app)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let target = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: Date.now))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月"
        let month = formatter.string(from: target)
        let header = app.buttons["DatePicker.Show"]
        try require(header, in: app)
        for _ in 0..<3 {
            let displayed = try XCTUnwrap(header.value as? String)
            if displayed == month { break }
            let monthDate = try XCTUnwrap(formatter.date(from: displayed))
            try tap(app.buttons[target < monthDate ? "DatePicker.PreviousMonth" : "DatePicker.NextMonth"], in: app)
        }
        XCTAssertEqual(header.value as? String, month)
        formatter.dateFormat = "M月d日"
        let day = formatter.string(from: target)
        let days = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", day, "\(day) ", "今天, \(day) "))
        guard days.count == 1 else { throw fail("The intended previous civil day must identify one native calendar action.", in: app) }
        try tap(days.firstMatch, in: app)
        let dismiss = app.buttons["PopoverDismissRegion"]
        if dismiss.exists { try tap(dismiss, in: app) }
        formatter.dateFormat = "yyyy年M月d日"
        try require(picker.buttons.matching(identifier: formatter.string(from: target)).firstMatch, in: app)
    }

    private func deleteOwnMeal(named name: String, in app: XCUIApplication) throws {
        guard name.hasPrefix("[UI测试] 快照") else { throw fail("Cleanup must only target this run's explicitly named synthetic meal.", in: app) }
        let detail = try identified("meal.detail", in: app)
        let names = detail.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@", name, "名称、\(name)", "名称, \(name)"))
        try reveal(names.firstMatch, preferUpWhenMissing: true, in: app)
        guard names.count == 1 else { throw fail("Cleanup requires this exact persisted synthetic meal name in the frontmost detail.", in: app) }
        let action = app.buttons["meal.delete"]
        try reveal(action, in: app)
        try tap(action, in: app)
        let title = "确定删除“\(name)”吗？"
        try require(app.staticTexts[title], in: app)
        let popovers = app.popovers.containing(.staticText, identifier: title)
        let dialogs = popovers.count > 0 ? popovers : app.sheets.containing(.staticText, identifier: title)
        guard dialogs.count == 1 else { throw fail("Cleanup requires the exact native confirmation for this synthetic meal.", in: app) }
        let deletes = dialogs.firstMatch.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "删除餐食", "meal.delete"))
        guard deletes.count == 1 else { throw fail("Cleanup requires one actual destructive confirmation, never its source button.", in: app) }
        try tap(deletes.firstMatch, in: app)
        XCTAssertTrue(app.navigationBars["餐食详情"].waitForNonExistence(timeout: 5))
    }

    private func replaceText(_ field: XCUIElement, with text: String, abovePreview: Bool = false, in app: XCUIApplication) throws {
        try reveal(field, preferUpWhenMissing: abovePreview, in: app)
        let original = field.value as? String ?? ""
        try tap(field, in: app)
        try revealInputAboveKeyboard(field, in: app)
        if !original.isEmpty, original != field.placeholderValue {
            let alignedEdge = field.identifier.hasPrefix("meal.weight.") || UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
            if alignedEdge {
                let frame = field.frame
                guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { throw fail("Native text selection requires real finite input bounds.", in: app) }
                let leading = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
                field.coordinate(withNormalizedOffset: CGVector(dx: leading ? 0.02 : 0.98, dy: 0.5)).doubleTap()
            } else {
                field.press(forDuration: 1)
            }
            let selectLabels = NSPredicate(format: "label IN %@", ["全选", "Select All"])
            let menus = app.menuItems.matching(selectLabels)
            let buttons = app.buttons.matching(selectLabels)
            if !menus.firstMatch.waitForExistence(timeout: 5) { _ = buttons.firstMatch.waitForExistence(timeout: 5) }
            let actions = menus.allElementsBoundByIndex + buttons.allElementsBoundByIndex
            if actions.count == 1, let selectAll = actions.first {
                try tap(selectAll, in: app)
                field.typeText(text)
            } else if actions.isEmpty, alignedEdge {
                let cutLabels = NSPredicate(format: "label IN %@", ["剪切", "Cut"])
                let cuts = app.menuItems.matching(cutLabels).allElementsBoundByIndex + app.buttons.matching(cutLabels).allElementsBoundByIndex
                guard cuts.count == 1, let cut = cuts.first else { throw fail("Expected one native Select All or a complete native selection with Cut.", in: app) }
                try tap(cut, in: app)
                let cleared = field.value as? String ?? ""
                guard cleared.isEmpty || cleared == field.placeholderValue else { throw fail("Native Cut must clear the entire prior value before replacement.", in: app) }
                field.typeText(text)
            } else {
                throw fail("The native edit menu must expose one unambiguous selection action.", in: app)
            }
        } else {
            field.typeText(text)
        }
        XCTAssertEqual(field.value as? String, text)
        try require(app.keyboards.firstMatch, in: app)
        try tap(app.buttons["meal.keyboardDone"], in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "The real Done action must dismiss the keyboard.")
    }

    private func identified(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let elements = app.descendants(matching: .any).matching(identifier: identifier)
        try require(elements.firstMatch, in: app)
        guard elements.count == 1 else { throw fail("Expected one actual \(identifier) container.", in: app) }
        return elements.firstMatch
    }

    private func reveal(_ element: XCUIElement, preferUpWhenMissing: Bool = false, in app: XCUIApplication) throws {
        for _ in 0..<16 {
            if element.waitForExistence(timeout: 1), element.isHittable { return }
            let frame = element.exists ? element.frame : .zero
            let top = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.maxY).max() ?? app.frame.minY
            let hasUsableFrame = frame.width.isFinite && frame.height.isFinite
                && frame.width > 0 && frame.height > 0
            // Native Form can recycle a known row after inspecting a later
            // preview. Its absent frame cannot tell us the scroll direction.
            try scrollContent(towardTop: hasUsableFrame ? frame.maxY <= top : preferUpWhenMissing, in: app)
        }
        throw fail("The actual requested control must become reachable through bounded native scrolling.", in: app)
    }

    private func revealInputAboveKeyboard(_ field: XCUIElement, in app: XCUIApplication) throws {
        try require(app.keyboards.firstMatch, in: app)
        for attempt in 0...4 {
            let done = app.buttons["meal.keyboardDone"]
            try require(done, in: app)
            let bottom = min(app.keyboards.firstMatch.frame.minY, done.frame.minY)
            if field.exists, field.isHittable, field.frame.maxY < bottom { return }
            if attempt < 4 { try scrollContent(towardTop: false, in: app) }
        }
        throw fail("The entire input must be above the actual keyboard and Done toolbar.", in: app)
    }

    private func scrollContent(towardTop: Bool, in app: XCUIApplication) throws {
        let identifiers = ["food.selection.list", "meal.form", "meal.detail", "meal.history", "meal.start", "today.content"]
        guard let container = identifiers.lazy.compactMap({ id -> XCUIElement? in
            let elements = app.descendants(matching: .any).matching(identifier: id)
            return elements.count == 1 && elements.firstMatch.isHittable ? elements.firstMatch : nil
        }).first else { throw fail("Scrolling requires an actual frontmost identified container.", in: app) }
        let frame = container.frame
        var bottom = min(frame.maxY, app.frame.maxY)
        if app.keyboards.firstMatch.exists {
            bottom = min(bottom, app.keyboards.firstMatch.frame.minY)
            let done = app.buttons["meal.keyboardDone"]
            if done.exists, done.isHittable { bottom = min(bottom, done.frame.minY) }
        }
        let top = max(frame.minY, app.frame.minY)
        let height = bottom - top
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0, height > 44 else { throw fail("The real scroll viewport must have finite usable bounds.", in: app) }
        let startY = (top + height * (towardTop ? 0.25 : 0.72) - frame.minY) / frame.height
        let endY = (top + height * (towardTop ? 0.72 : 0.25) - frame.minY) / frame.height
        // Scroll at the actual content edge so the AX date wheel is not adjusted.
        container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: startY)).press(
            forDuration: 0.05,
            thenDragTo: container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: endY))
        )
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        try require(element, in: app)
        if !element.isHittable {
            let visible = NSPredicate { candidate, _ in
                guard let value = candidate as? XCUIElement else { return false }
                return value.exists && value.isHittable
            }
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: element)], timeout: 5)
        }
        guard element.exists, element.isHittable else { throw fail("The actual requested control must be hittable immediately before tapping.", in: app) }
        element.tap()
    }

    private func require(_ element: XCUIElement, timeout: TimeInterval = 5, in app: XCUIApplication) throws {
        guard element.waitForExistence(timeout: timeout) else { throw fail("The requested native control must exist.", in: app) }
    }

    private func fail(_ message: String, in app: XCUIApplication) -> SnapshotUIError {
        XCTFail(message)
        if diagnosticApplication != nil {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "OPT14A-failure-native-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreen(app, name: "OPT14A-failure-screen")
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

private enum SnapshotUIError: Error {
    case missingNativeControl
}
