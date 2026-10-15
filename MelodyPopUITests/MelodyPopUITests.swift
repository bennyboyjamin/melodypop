import XCTest

final class MelodyPopUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(student: String? = "Mia", skipModeSelection: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        if skipModeSelection { app.launchArguments.append("-uitest-skip-mode-selection") }
        if let student { app.launchArguments += ["-uitest-student", student] }
        app.launch()
        return app
    }

    func testOnboardingCreatesProfileAndShowsModeSelection() {
        let app = launch(student: nil, skipModeSelection: false)
        let name = app.textFields["profile-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Leo")
        app.buttons["create-profile"].tap()
        XCTAssertTrue(app.buttons["select-mode-microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["select-mode-midi"].exists)
        XCTAssertTrue(app.buttons["select-mode-touch"].exists)
        app.buttons["select-mode-touch"].tap()
        app.buttons["start-learning"].tap()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hi, Leo!"].exists)
    }

    func testVirtualPianoPlaysHighlightsRecordsAndPlaysBack() {
        let app = launch()
        app.tabBars.buttons["Piano"].tap()
        let middleC = app.otherElements["key-60"]
        XCTAssertTrue(middleC.waitForExistence(timeout: 10), "Middle C should be visible on the keyboard")

        middleC.tap()
        XCTAssertTrue(app.staticTexts["Last note: C4"].waitForExistence(timeout: 3))

        // Octave shifting moves the visible range.
        let range = app.staticTexts["keyboard-range"]
        let before = range.label
        app.buttons["octave-up"].tap()
        XCTAssertNotEqual(range.label, before)
        XCTAssertTrue(app.otherElements["key-72"].waitForExistence(timeout: 3))
        app.otherElements["key-72"].tap()
        XCTAssertTrue(app.staticTexts["Last note: C5"].waitForExistence(timeout: 3))
        app.buttons["octave-down"].tap()

        // Record a short phrase, then play it back.
        app.buttons["record-button"].tap()
        for key in ["key-60", "key-62", "key-64"] {
            app.otherElements[key].tap()
        }
        app.buttons["stop-recording"].tap()
        let playBack = app.buttons["play-recording"]
        XCTAssertTrue(playBack.waitForExistence(timeout: 3))
        playBack.tap()
        XCTAssertTrue(app.buttons["stop-playback"].waitForExistence(timeout: 3))
        // Playback finishes on its own.
        XCTAssertTrue(playBack.waitForExistence(timeout: 10))
        app.buttons["save-recording"].tap()
        XCTAssertTrue(app.staticTexts["saved-message"].waitForExistence(timeout: 3))
    }

    func testLessonOneWithVirtualPianoAndModeSwitching() {
        let app = launch()
        let lesson = app.buttons["lesson-1"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()

        XCTAssertTrue(app.buttons["mode-touch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode-microphone"].exists)
        XCTAssertTrue(app.buttons["mode-midi"].exists)
        app.buttons["start-button"].tap()

        let progress = app.staticTexts["progress-label"]
        let middleC = app.otherElements["key-60"]
        XCTAssertTrue(middleC.waitForExistence(timeout: 5))
        middleC.tap()
        middleC.tap()
        XCTAssertEqual(progress.label, "2 of 7")

        // A wrong note does not advance.
        app.otherElements["key-62"].tap()
        XCTAssertEqual(progress.label, "2 of 7")

        // Switch to Connect My Keyboard mid-lesson, then back: progress is kept.
        app.buttons["mode-midi"].tap()
        XCTAssertEqual(progress.label, "2 of 7")
        app.buttons["mode-touch"].tap()
        let resume = app.buttons["resume-button"]
        if resume.waitForExistence(timeout: 2) { resume.tap() }
        XCTAssertEqual(progress.label, "2 of 7")

        for _ in 0..<5 { app.otherElements["key-60"].tap() }

        let accuracy = app.staticTexts["result-accuracy"]
        XCTAssertTrue(accuracy.waitForExistence(timeout: 5))
        // 6 perfect + 1 note with one mistake (graded "good" = 0.85) → (6 + 0.85) / 7 = 98%.
        XCTAssertEqual(accuracy.label, "98%")
        app.buttons["result-done"].tap()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
    }
}
