import XCTest

/// End-to-end tests over the flows actually used in a gym, driven through the
/// real UI. The unit tests cover what the app calculates; these cover whether
/// you can get at it — which is where every bug found on a phone has been.
///
/// Each test launches with --uitest-reset, so it starts from the seeded Full
/// Body workout in a throwaway file and never touches real data.
final class WorkoutFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"]
        app.launch()
    }

    // MARK: - Helpers

    private func tap(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "never found \(what)")
        element.tap()
    }

    private func startFullBody() {
        tap(app.buttons.containing(.staticText, identifier: "Start Full Body").firstMatch, "Start Full Body")
        XCTAssertTrue(app.staticTexts["Leg press"].waitForExistence(timeout: 10), "session didn't open")
    }

    private func openWorkoutEditor() {
        tap(app.buttons.containing(.staticText, identifier: "Workouts").firstMatch, "the Workouts row")
        tap(app.buttons.containing(.staticText, identifier: "Full Body").firstMatch, "the Full Body workout")
    }

    /// The first weight box on screen.
    private var firstWeightField: XCUIElement { app.textFields["weight-Leg press-0"] }

    /// How many sets are ticked off for an exercise, e.g. "1/3".
    private func doneCount(_ exercise: String) -> String? {
        app.buttons["setCount-\(exercise)"].value as? String
    }

    /// The number pad has no return key, so every screen with one has a Done
    /// button. Leaving the keyboard up hides content and blocks scrolling.
    private func dismissKeyboard() {
        let done = app.buttons["Done"]
        if done.exists && done.isHittable { done.tap() }
    }

    /// XCUITest doesn't scroll on its own: a button below the fold is simply
    /// "not there" until something brings it into view.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 10) -> Bool {
        dismissKeyboard()
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            let list = app.scrollViews.firstMatch
            (list.exists ? list : app).swipeUp()
        }
        return element.exists && element.isHittable
    }

    // MARK: - Logging a set

    func testASetCannotBeTickedUntilItIsLogged() {
        startFullBody()

        XCTAssertEqual(doneCount("Leg press"), "0/3", "should start with nothing done")
        let tick = app.buttons["Mark set done and start rest"].firstMatch
        XCTAssertTrue(tick.waitForExistence(timeout: 10))
        XCTAssertFalse(tick.isEnabled, "no weight entered yet, so the tick is unavailable")
        XCTAssertTrue(app.staticTexts["Enter a weight to tick a set off."].exists,
                      "and it should say why")
    }

    func testEnteringAWeightLetsYouTickTheSetOff() {
        startFullBody()

        tap(firstWeightField, "the weight box")
        firstWeightField.typeText("60")

        let tick = app.buttons["Mark set done and start rest"].firstMatch
        XCTAssertTrue(tick.isEnabled, "a logged set should be tickable")
        tick.tap()

        XCTAssertEqual(doneCount("Leg press"), "1/3", "the set didn't count")
    }

    // MARK: - Finishing, history and sharing

    func testFinishingASessionPutsItInHistoryAndItCanBeShared() {
        startFullBody()
        tap(firstWeightField, "the weight box")
        firstWeightField.typeText("60")
        dismissKeyboard()
        tap(app.buttons["Mark set done and start rest"].firstMatch, "the tick")

        let finish = app.buttons["finishWorkout"]
        XCTAssertTrue(scrollTo(finish), "Finish should be at the end of the session")
        finish.tap()

        // Finishing can pop a records summary; get past it before moving on.
        let nice = app.buttons["Nice"]
        if nice.waitForExistence(timeout: 3) { nice.tap() }

        tap(app.buttons["History"], "the History tab")
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 10), "History didn't open")

        // The row reads "Thu, 24 Sep, Full Body · 1 exercise · 1 set".
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Full Body'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the finished session isn't in History")
        row.tap()

        let share = app.buttons["Share this workout"]
        XCTAssertTrue(scrollTo(share), "no way to share the session")
        share.tap()

        // The summary itself is the share sheet's header.
        let summary = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Full Body —'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "the share sheet had no summary in it")
    }

    // MARK: - Editing a workout

    func testRemovingAnExerciseFromAWorkoutDoesNotCrash() {
        openWorkoutEditor()

        let removes = app.buttons.matching(identifier: "Remove")
        XCTAssertTrue(scrollTo(removes.firstMatch), "no Remove buttons in the editor")
        let before = removes.count
        removes.firstMatch.tap()

        XCTAssertEqual(app.state, .runningForeground, "the app died removing an exercise")
        XCTAssertTrue(app.buttons["+ Add exercise"].waitForExistence(timeout: 5), "editor should still be up")
        XCTAssertEqual(app.buttons.matching(identifier: "Remove").count, before - 1, "the exercise should be gone")
    }

    func testAnExerciseCanBeAddedFromTheCatalogue() {
        openWorkoutEditor()

        let add = app.buttons["+ Add exercise"]
        XCTAssertTrue(scrollTo(add), "+ Add exercise")
        add.tap()
        let search = app.textFields["Search or name a new exercise"]
        tap(search, "the search box")
        search.typeText("Hip thrust")

        tap(app.buttons.containing(.staticText, identifier: "Hip thrust").firstMatch, "the Hip thrust row")

        XCTAssertTrue(app.staticTexts["Hip thrust"].waitForExistence(timeout: 10),
                      "the exercise wasn't added to the workout")
    }

    // MARK: - Backup

    func testExportOffersTheBackupFile() {
        tap(app.buttons["Settings"], "the Settings tab")
        let export = app.buttons["Export all data (JSON)"]
        XCTAssertTrue(scrollTo(export), "no Export button")
        export.tap()

        // Regression: this sheet used to open empty, with no file in it.
        let file = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'gymlogger-'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15), "the share sheet had no file in it")
    }
}
