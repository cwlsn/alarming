import XCTest

@MainActor
final class AlarmingUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 3)
        // Rows touching the bottom edge count as hittable, but taps there go to the home indicator.
        let limit = app.frame.maxY - 100
        for _ in 0..<8 where !(element.exists && element.isHittable && element.frame.maxY < limit) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists && element.isHittable, "not visible: \(element)")
    }

    private func chooseStyle(_ name: String) {
        let segment = app.segmentedControls.buttons[name]
        reveal(segment)
        segment.tap()
    }

    private func setSeven() {
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "7")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "00")
        app.pickerWheels.element(boundBy: 2).adjust(toPickerWheelValue: "AM")
    }

    private func openWheel() {
        app.buttons["Add alarm"].firstMatch.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
    }

    private func openRow(_ label: String) {
        app.buttons.matching(NSPredicate(format: "identifier == 'alarm-row' AND label CONTAINS %@", label)).firstMatch.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
    }

    private func expectWake(_ prefix: String) {
        let wake = app.staticTexts["projected-wake"]
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", prefix), evaluatedWith: wake)
        waitForExpectations(timeout: 5)
    }

    func testCreateEditToggleDelete() {
        launch()
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 5))
        capture("1-empty")
        openWheel()
        setSeven()
        app.buttons["Weekdays"].tap()
        app.buttons["Mon, Tue, Thu"].firstMatch.swipeLeft()
        app.buttons["Mon, Tue, Thu"].firstMatch.tap()
        capture("2-editor-new")
        app.buttons["Add"].tap()
        let row = app.buttons["alarm-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Alarm · Mon, Tue, Thu"), row.label)
        capture("3-list-one")
        let toggle = app.switches["Alarm on"]
        toggle.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        // Renaming must not turn an alarm on.
        row.tap()
        let label = app.textFields["Label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText("Gym\n")
        app.buttons["Done"].firstMatch.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Gym'"), evaluatedWith: row)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.switches["Gym on"].value as? String, "0")
        // Choosing new days does, and swiping the sheet away saves.
        openRow("Gym")
        app.buttons["Weekdays"].tap()
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)), withVelocity: .fast, thenHoldForDuration: 0)
        expectation(for: NSPredicate(format: "label CONTAINS 'Weekdays'"), evaluatedWith: row)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.switches["Gym on"].value as? String, "1")
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: 5))
    }

    func testQuickEntry() {
        launch()
        let field = app.textFields["Quick add"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("gym")
        XCTAssertTrue(app.staticTexts["Add a time, like 7:30 or in 20m"].exists)
        field.typeText(" 7:30am weekdays")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'gym · Weekdays'")).firstMatch.waitForExistence(timeout: 3))
        capture("4-quick")
        field.typeText("\n")
        let row = app.buttons["alarm-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("gym · Weekdays") && row.label.contains("7:30"), row.label)
        XCTAssertEqual(app.switches["gym on"].value as? String, "1")
    }

    func testSnoozeControlsAndRevert() {
        launch(["-seed"])
        XCTAssertTrue(app.switches["Work on"].waitForExistence(timeout: 5))
        openRow("Work")
        expectWake("7:00")
        let chart = app.descendants(matching: .any)["wake-chart"]
        reveal(chart)
        XCTAssertTrue(chart.label.hasPrefix("Rings at") && chart.label.contains("6:55"), chart.label)
        capture("5-edit")
        chooseStyle("Divide")
        XCTAssertTrue(app.segmentedControls.buttons["Linear"].exists && app.segmentedControls.buttons["÷ 2"].isSelected)
        expectWake("6:58:07")
        let two = app.buttons["Snoozes, 2"]
        reveal(two)
        two.tap()
        expectWake("6:52:30")
        XCTAssertTrue(two.isSelected)
        XCTAssertFalse(app.buttons["Snoozes, 5"].isEnabled)
        capture("6-edit-options")
        app.buttons["Snoozes, Custom"].tap()
        let fewer = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Decrement'")).firstMatch
        reveal(fewer)
        fewer.tap()
        expectWake("6:45")
        capture("6-edit-limited")
        let limited = app.descendants(matching: .any)["wake-chart"]
        XCTAssertFalse(limited.label.contains("6:55"), limited.label)
        app.buttons["Revert"].tap()
        expectWake("7:00")
        app.segmentedControls.buttons["Off"].tap()
        expectWake("6:30")
        capture("7-edit-off")
    }

    func testCustomSnooze() {
        launch()
        openWheel()
        setSeven()
        expectWake("7:25")
        chooseStyle("Linear")
        expectWake("7:30")
        let ten = app.buttons["First snooze, 10 min"]
        reveal(ten)
        ten.tap()
        expectWake("7:20")
        let custom = app.buttons["Snoozes, Custom"]
        reveal(custom)
        custom.tap()
        let more = app.buttons.matching(NSPredicate(format: "label ENDSWITH 'Increment'")).firstMatch
        reveal(more)
        more.tap()
        expectWake("7:30")
        // Past the highest number is no limit, which has no wake time to project.
        for _ in 0..<8 { more.tap() }
        XCTAssertTrue(app.staticTexts["No limit set"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["projected-wake"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["wake-chart"].label, "Snoozes without a limit")
        capture("K-no-limit")
    }

    func testTonePicker() {
        launch()
        openWheel()
        let menu = app.buttons["tone-menu"]
        reveal(menu)
        XCTAssertEqual(menu.value as? String, "System default")
        for choice in ["Subtract", "First snooze, 15 min", "Snoozes, 2"] {
            XCTAssertTrue(app.buttons[choice].isSelected, choice)
        }
        menu.tap()
        capture("8-tone-menu")
        app.buttons["Marimba"].tap()
        expectation(for: NSPredicate(format: "value == 'Marimba'"), evaluatedWith: menu)
        waitForExpectations(timeout: 5)
        let stop = app.buttons["Stop sound"]
        XCTAssertTrue(stop.waitForExistence(timeout: 3))
        capture("8-tone-playing")
        stop.tap()
        XCTAssertTrue(app.buttons["Play sound"].waitForExistence(timeout: 3))
    }

    func testDayGroups() {
        launch()
        openWheel()
        app.buttons["Weekends"].swipeLeft()
        capture("H-day-chips")
        XCTAssertTrue(app.buttons["Wed, Fri"].exists)
        app.buttons["Edit day groups"].tap()
        XCTAssertTrue(app.navigationBars["Day groups"].waitForExistence(timeout: 5))
        app.buttons["Add group"].tap()
        let added = app.otherElements.matching(identifier: "day-group").element(boundBy: 2)
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.buttons["Saturday"].tap()
        added.buttons["Monday"].tap()
        capture("I-day-groups")
        app.navigationBars["Day groups"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Mon, Sat"].waitForExistence(timeout: 5))
        capture("J-day-chips-added")
        app.buttons["Edit day groups"].tap()
        let first = app.otherElements.matching(identifier: "day-group").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.swipeLeft()
        app.buttons["Delete"].tap()
        app.navigationBars["Day groups"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Mon, Sat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Mon, Tue, Thu"].exists)
    }

    func testDenied() {
        launch(["-denied"])
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 5))
        capture("9-denied")
        openWheel()
        app.buttons["Add"].tap()
        XCTAssertTrue(app.alerts["Alarm not saved"].waitForExistence(timeout: 5))
    }

    func testSeededLists() {
        launch(["-seed"])
        let nap = app.switches["Nap on"]
        XCTAssertTrue(nap.waitForExistence(timeout: 5))
        capture("A-list")
        nap.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: nap)
        waitForExpectations(timeout: 5)
        app.terminate()
        launch(["-seed", "-dark"])
        XCTAssertTrue(nap.waitForExistence(timeout: 5))
        capture("B-dark-list")
        openRow("Lie-in")
        capture("C-dark-edit")
    }

    func testDarkAndLargeText() {
        launch(["-seed", "-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["alarm-row"].firstMatch.waitForExistence(timeout: 5))
        capture("D-large-list")
        openRow("Work")
        capture("E-large-edit")
        app.swipeUp()
        capture("F-large-edit2")
        app.swipeUp()
        capture("G-large-edit3")
    }
}
