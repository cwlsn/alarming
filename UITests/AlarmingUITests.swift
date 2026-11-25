import XCTest

@MainActor
final class AlarmingUITests: XCTestCase {
    private let app = XCUIApplication()
    /// Generous, because a busy Mac slows the simulator far beyond a phone. Passing waits return at once.
    private static let wait: TimeInterval = 20

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
        _ = element.waitForExistence(timeout: Self.wait)
        // Rows touching the bottom edge count as hittable, but taps there go to the home indicator.
        let limit = app.frame.maxY - 100
        for _ in 0..<8 where !(element.exists && element.isHittable && element.frame.maxY < limit) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists && element.isHittable, "not visible: \(element)")
    }

    private func focus(_ field: XCUIElement) {
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.wait))
    }

    private func expectSelected(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: element)
        waitForExpectations(timeout: Self.wait)
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
        let add = app.buttons["Add alarm"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: Self.wait))
        // A busy simulator can drop a tap made while the list is still settling, so try once more.
        for _ in 0..<2 {
            add.tap()
            if app.pickerWheels.firstMatch.waitForExistence(timeout: Self.wait / 2) { return }
        }
        XCTFail("The time wheel did not open")
    }

    private func openRow(_ label: String) {
        app.buttons.matching(NSPredicate(format: "identifier == 'alarm-row' AND label CONTAINS %@", label)).firstMatch.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: Self.wait))
    }

    private func expectWake(_ prefix: String) {
        let wake = app.staticTexts["projected-wake"]
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", prefix), evaluatedWith: wake)
        waitForExpectations(timeout: Self.wait)
    }

    private func expectNoSeconds() {
        for text in [app.staticTexts["projected-wake"].label, app.descendants(matching: .any)["wake-chart"].label] {
            XCTAssertNil(text.range(of: #"\d+:\d+:\d+"#, options: .regularExpression), text)
        }
    }

    func testCreateEditToggleDelete() {
        launch()
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: Self.wait))
        capture("1-empty")
        openWheel()
        setSeven()
        app.buttons["Weekdays"].tap()
        app.buttons["Weekends"].swipeLeft()
        app.buttons["Mon, Tue, Thu"].firstMatch.tap()
        capture("2-editor-new")
        app.buttons["add-bottom"].tap()
        let row = app.buttons["alarm-row"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(row.label.contains("Alarm · Mon, Tue, Thu"), row.label)
        capture("3-list-one")
        let toggle = app.switches["Alarm on"]
        toggle.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)
        waitForExpectations(timeout: Self.wait)
        // Renaming must not turn an alarm on.
        row.tap()
        let label = app.textFields["Label"]
        XCTAssertTrue(label.waitForExistence(timeout: Self.wait))
        label.tap()
        label.typeText("Gym\n")
        app.buttons["Done"].firstMatch.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Gym'"), evaluatedWith: row)
        waitForExpectations(timeout: Self.wait)
        XCTAssertEqual(app.switches["Gym on"].value as? String, "0")
        // Choosing new days does, and swiping the sheet away saves.
        openRow("Gym")
        app.buttons["Weekdays"].tap()
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)), withVelocity: .fast, thenHoldForDuration: 0)
        expectation(for: NSPredicate(format: "label CONTAINS 'Weekdays'"), evaluatedWith: row)
        waitForExpectations(timeout: Self.wait)
        XCTAssertEqual(app.switches["Gym on"].value as? String, "1")
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: Self.wait))
    }

    func testQuickEntry() {
        launch()
        let field = app.textFields["Quick add"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait))
        focus(field)
        field.typeText("gym")
        XCTAssertTrue(app.staticTexts["Add a time, like 7:30 or in 20m"].exists)
        field.typeText(" 7:30am weekdays")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'gym · Weekdays'")).firstMatch.waitForExistence(timeout: Self.wait))
        capture("4-quick")
        field.typeText("\n")
        let row = app.buttons["alarm-row"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(row.label.contains("gym · Weekdays") && row.label.contains("7:30"), row.label)
        XCTAssertEqual(app.switches["gym on"].value as? String, "1")
    }

    func testSnoozeControlsAndRevert() {
        launch(["-seed"])
        XCTAssertTrue(app.switches["Work on"].waitForExistence(timeout: Self.wait))
        openRow("Work")
        expectWake("7:00")
        let chart = app.descendants(matching: .any)["wake-chart"]
        reveal(chart)
        XCTAssertTrue(chart.label.hasPrefix("Rings at") && chart.label.contains("6:55"), chart.label)
        capture("5-edit")
        chooseStyle("Divide")
        expectSelected(app.segmentedControls.buttons["÷ 2"])
        XCTAssertTrue(app.segmentedControls.buttons["Linear"].exists)
        expectWake("6:59")
        expectNoSeconds()
        let two = app.buttons["Snoozes, 2"]
        reveal(two)
        two.tap()
        expectWake("6:53")
        expectNoSeconds()
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
        XCTAssertTrue(app.staticTexts["No limit set"].waitForExistence(timeout: Self.wait))
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
        waitForExpectations(timeout: Self.wait)
        let stop = app.buttons["Stop sound"]
        XCTAssertTrue(stop.waitForExistence(timeout: Self.wait))
        capture("8-tone-playing")
        stop.tap()
        XCTAssertTrue(app.buttons["Play sound"].waitForExistence(timeout: Self.wait))
    }

    func testDayGroups() {
        launch()
        openWheel()
        app.buttons["Weekends"].swipeLeft()
        capture("H-day-chips")
        XCTAssertTrue(app.buttons["Wed, Fri"].exists)
        app.buttons["Edit day groups"].tap()
        XCTAssertTrue(app.navigationBars["Day groups"].waitForExistence(timeout: Self.wait))
        app.buttons["Add group"].tap()
        let added = app.otherElements.matching(identifier: "day-group").element(boundBy: 2)
        XCTAssertTrue(added.waitForExistence(timeout: Self.wait))
        added.buttons["Saturday"].tap()
        added.buttons["Monday"].tap()
        capture("I-day-groups")
        app.navigationBars["Day groups"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Mon, Sat"].waitForExistence(timeout: Self.wait))
        capture("J-day-chips-added")
        app.buttons["Edit day groups"].tap()
        let first = app.otherElements.matching(identifier: "day-group").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: Self.wait))
        first.swipeLeft()
        app.buttons["Delete"].tap()
        app.navigationBars["Day groups"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Mon, Sat"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.buttons["Mon, Tue, Thu"].exists)
    }

    func testOneTime() {
        launch()
        openWheel()
        setSeven()
        let oneTime = app.buttons["One-time"]
        oneTime.tap()
        expectSelected(oneTime)
        XCTAssertTrue(app.staticTexts["Rings once without snooze, then disappears when you stop it."].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.segmentedControls.buttons["Subtract"].exists)
        XCTAssertFalse(app.staticTexts["projected-wake"].exists)
        capture("L-one-time")
        // Days make it repeat, which brings snooze back as it was.
        app.buttons["Weekdays"].tap()
        XCTAssertFalse(oneTime.isSelected)
        expectWake("7:25")
        oneTime.tap()
        XCTAssertFalse(app.buttons["Weekdays"].isSelected)
        XCTAssertFalse(app.buttons["Monday"].isSelected)
        app.buttons["add-bottom"].tap()
        let row = app.buttons["alarm-row"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(row.label.contains("Alarm · One-time") && row.label.contains("7:00"), row.label)
        XCTAssertFalse(row.label.contains("Up by"), row.label)
        capture("M-one-time-list")
        // Kept as one-time when edited.
        openRow("One-time")
        XCTAssertTrue(app.buttons["One-time"].isSelected)
        XCTAssertFalse(app.segmentedControls.buttons["Subtract"].exists)
    }

    func testQuickEntryIsOneTimeWithoutDays() {
        launch()
        let field = app.textFields["Quick add"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait))
        focus(field)
        field.typeText("in 20m nap")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'nap · One-time'")).firstMatch.waitForExistence(timeout: Self.wait))
        field.typeText("\n")
        let row = app.buttons["alarm-row"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(row.label.contains("nap · One-time"), row.label)
    }

    func testAddButtons() {
        launch()
        openWheel()
        XCTAssertFalse(app.navigationBars.buttons["Cancel"].exists)
        let top = app.buttons["add-top"]
        XCTAssertEqual(top.label, "Add")
        capture("N-add-buttons")
        app.buttons["cancel-bottom"].tap()
        XCTAssertTrue(app.staticTexts["No alarms yet"].waitForExistence(timeout: Self.wait))
        openWheel()
        setSeven()
        app.buttons["add-top"].tap()
        XCTAssertTrue(app.buttons["alarm-row"].waitForExistence(timeout: Self.wait))
        // An existing alarm keeps Done and has no bottom buttons.
        openRow("Alarm")
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["add-bottom"].exists || app.buttons["cancel-bottom"].exists)
    }

    func testDenied() {
        launch(["-denied"])
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: Self.wait))
        capture("9-denied")
        openWheel()
        app.buttons["add-top"].tap()
        XCTAssertTrue(app.alerts["Alarm not saved"].waitForExistence(timeout: Self.wait))
    }

    func testSeededLists() {
        launch(["-seed"])
        let nap = app.switches["Nap on"]
        XCTAssertTrue(nap.waitForExistence(timeout: Self.wait))
        capture("A-list")
        nap.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: nap)
        waitForExpectations(timeout: Self.wait)
        app.terminate()
        launch(["-seed", "-dark"])
        XCTAssertTrue(nap.waitForExistence(timeout: Self.wait))
        capture("B-dark-list")
        openRow("Lie-in")
        capture("C-dark-edit")
    }

    func testDarkAndLargeText() {
        launch(["-seed", "-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["alarm-row"].firstMatch.waitForExistence(timeout: Self.wait))
        capture("D-large-list")
        openRow("Work")
        capture("E-large-edit")
        app.swipeUp()
        capture("F-large-edit2")
        app.swipeUp()
        capture("G-large-edit3")
    }
}
