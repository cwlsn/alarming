import XCTest

@MainActor
final class ChainTests: XCTestCase {
    /// Runs on failure too, so a test can never leave an alarm ringing.
    override func tearDown() async throws {
        let app = XCUIApplication()
        app.activate()
        let empty = NSPredicate(format: "label == 'none'")
        var cleared = false
        for _ in 0..<3 where !cleared {
            app.buttons["Cancel all"].tap()
            cleared = await XCTWaiter().fulfillment(of: [XCTNSPredicateExpectation(predicate: empty, object: app.staticTexts["states"])], timeout: 5) == .completed
        }
        XCTAssertTrue(cleared, "an alarm is still set")
        app.terminate()
    }

    func testChainWithAppTerminated() {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launch()
        app.buttons["Clear log"].tap()
        let start = app.buttons["One-time in 15s (30, 20, 10)"]
        start.tap()
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        let denied = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AUTH denied'")).firstMatch
        if denied.waitForExistence(timeout: 3) {
            // The iOS 27 simulator denies without prompting, so grant in Settings instead.
            app.buttons["Open Settings"].tap()
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
            sleep(3)
            let apps = settings.buttons["com.apple.settings.apps"].firstMatch
            for _ in 0..<6 where !(apps.exists && apps.isHittable) { settings.swipeUp() }
            capture("settings-root", settings)
            if apps.exists {
                apps.tap()
                let row = settings.buttons.matching(NSPredicate(format: "label CONTAINS 'Alarming Spike' AND NOT (label CONTAINS 'Return')")).firstMatch
                _ = row.waitForExistence(timeout: 10)
                capture("settings-apps", settings)
                if row.exists { row.tap() }
            }
            let toggle = settings.switches.matching(NSPredicate(format: "label CONTAINS[c] 'alarm'")).firstMatch
            let found = toggle.waitForExistence(timeout: 15)
            capture("settings", settings)
            XCTAssertTrue(found, "no alarm permission switch")
            guard found else { return }
            if toggle.value as? String == "0" {
                let inner = toggle.switches.firstMatch
                (inner.exists ? inner : toggle).tap()
            }
            sleep(1)
            capture("settings-after", settings)
            app.activate()
            app.buttons["Clear log"].tap()
            start.tap()
        }
        expectOneAlarm(in: app)
        app.terminate()
        for seconds in [30, 20, 10] {
            let snooze = springboard.buttons["Snooze \(seconds)s"].firstMatch
            let found = snooze.waitForExistence(timeout: 50)
            capture("before-\(seconds)", springboard)
            XCTAssertTrue(found, "no snooze \(seconds)")
            if !found { break }
            snooze.tap()
            sleep(3)
            capture("after-\(seconds)", springboard)
        }
        expectHiddenFinalRing(4, in: springboard)
        app.activate()
        sleep(3)
        capture("log", app)
        let log = app.staticTexts["log"]
        for _ in 0..<4 where !log.exists { app.swipeUp() }
        if log.exists { print("SPIKELOG\n" + log.label + "\nENDSPIKELOG") }
        for _ in 0..<4 { app.swipeDown() }
    }

    /// A ring that never had a snooze button, with no countdown before it.
    func testRingWithoutSnooze() {
        let app = XCUIApplication()
        schedule("One-time in 15s, no snooze", in: app)
        expectFinalRing(1, in: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
    }

    /// A countdown with no ring before it.
    func testCountdownWithoutSnooze() {
        schedule("Countdown 15s, no snooze", in: XCUIApplication())
        expectFinalRing(1, in: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
    }

    func testLastRingAfterOneSnooze() { snoozeOnce("One-time in 15s (10)", isHidden: true) }
    func testLastRingFixed() { snoozeOnce("Last ring fixed (10)") }
    func testLastRingTwoButtons() { snoozeOnce("Last ring two buttons (10)") }

    private func snoozeOnce(_ name: String, isHidden: Bool = false) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        schedule(name, in: XCUIApplication())
        let snooze = springboard.buttons["Snooze 10s"].firstMatch
        XCTAssertTrue(snooze.waitForExistence(timeout: 30))
        if snooze.exists { snooze.tap() }
        if isHidden { expectHiddenFinalRing(2, in: springboard) } else { expectFinalRing(2, in: springboard) }
    }

    /// Needs alarm permission, which `testChainWithAppTerminated` grants.
    private func schedule(_ name: String, in app: XCUIApplication) {
        app.launch()
        app.buttons["Clear log"].tap()
        app.buttons[name].tap()
        expectOneAlarm(in: app)
        app.terminate()
    }

    /// A leftover alarm would make the run meaningless.
    private func expectOneAlarm(in app: XCUIApplication) {
        let set = NSPredicate(format: "label MATCHES '[0-9A-F]{4}:(scheduled|countdown)'")
        expectation(for: set, evaluatedWith: app.staticTexts["states"])
        waitForExpectations(timeout: 10)
    }

    /// Fails as unexpected success if a later iOS shows this ring, so the workaround can be removed.
    private func expectHiddenFinalRing(_ number: Int, in springboard: XCUIApplication) {
        XCTExpectFailure("iOS 27.2 hides a countdown ring that follows a snooze and has only Stop") {
            expectFinalRing(number, in: springboard)
        }
    }

    /// The last ring must be visible and stoppable, not just alerting.
    private func expectFinalRing(_ number: Int, in springboard: XCUIApplication) {
        let title = springboard.staticTexts["Ring \(number)"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 30), "ring \(number) is not visible")
        XCTAssertTrue(springboard.buttons["Stop"].firstMatch.exists, "ring \(number) cannot be stopped")
        XCTAssertFalse(springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Snooze'")).firstMatch.exists)
        capture("final", springboard)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
