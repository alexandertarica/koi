import XCTest

@MainActor
final class StageDemoTests: XCTestCase {
    func testStagePitchFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-koiStage"]
        app.launch()

        let jasmineGreeting = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Jasmine")).firstMatch
        XCTAssertTrue(jasmineGreeting.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Mark Morning walk open"].waitForExistence(timeout: 5), "The stage day should visibly show Morning walk complete")
        let startingBalance = score(in: app)
        XCTAssertTrue((45...55).contains(startingBalance), "Stage starts at \(startingBalance), expected 45–55")

        app.buttons["Movement"].tap()
        let workoutButton = app.buttons["stage.workout.log"]
        XCTAssertTrue(workoutButton.waitForExistence(timeout: 5))
        workoutButton.tap()
        app.buttons["Hub"].tap()
        let workoutCoach = app.staticTexts["stage.coach.message"]
        XCTAssertTrue(workoutCoach.waitForExistence(timeout: 5))
        XCTAssertTrue(workoutCoach.label.localizedCaseInsensitiveContains("protein"))
        app.buttons["stage.coach.accept"].tap()

        XCTAssertTrue(app.staticTexts["stage.intake.adjustmentNote"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stage.intake.adjustmentNote"].label, "Adjusted for today's workout")
        app.buttons["stage.food.log"].tap()
        let upload = app.buttons["Upload a photo"]
        XCTAssertTrue(upload.waitForExistence(timeout: 5))
        upload.tap()
        selectFirstPhoto(in: app)

        XCTAssertTrue(app.staticTexts["Added to today's totals."].waitForExistence(timeout: 45))
        app.buttons["Hub"].tap()
        let endingBalance = score(in: app)
        XCTAssertGreaterThan(endingBalance, startingBalance, "Balance should rise after the protein-bar photo is saved")

        app.buttons["stage.pond.open"].tap()
        XCTAssertTrue(app.staticTexts["stage.pond.sample"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["stage.pond.jasmine"].label, "Jasmine")
        XCTAssertEqual(app.staticTexts["stage.pond.rank.jasmine"].label, "3")
        for member in ["alex", "maya", "riley", "sam"] {
            XCTAssertTrue(app.staticTexts["stage.pond.member.\(member)"].exists, "Missing sample member \(member)")
        }

        app.buttons["Close"].tap()
        let runCoach = app.staticTexts["stage.coach.message"]
        XCTAssertTrue(runCoach.waitForExistence(timeout: 8))
        XCTAssertTrue(runCoach.label.contains("3-mile run"))
        XCTAssertTrue(runCoach.label.contains("9 AM class"))
        app.buttons["stage.coach.accept"].tap()

        let runTodo = app.buttons["stage.todo.run"]
        XCTAssertTrue(runTodo.waitForExistence(timeout: 8))
        app.buttons["Grid view"].tap()
        let importantRun = app.buttons["stage.todo.run"]
        if !importantRun.exists { app.swipeUp() }
        XCTAssertTrue(importantRun.waitForExistence(timeout: 5))
        let importantQuadrant = app.otherElements["stage.todo.important"]
        XCTAssertTrue(importantQuadrant.waitForExistence(timeout: 5))
        XCTAssertTrue(importantQuadrant.descendants(matching: .any)["stage.todo.run"].exists)

        app.terminate()
    }

    private func score(in app: XCUIApplication) -> Int {
        let score = app.staticTexts["stage.balance.score"]
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        return Int(score.label) ?? 0
    }

    private func selectFirstPhoto(in app: XCUIApplication) {
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "Photos picker did not show a photo")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let addButton = app.buttons["Add"]
        if addButton.waitForExistence(timeout: 2) { addButton.tap() }
    }
}
