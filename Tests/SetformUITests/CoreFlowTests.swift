import XCTest

/// Drives the built app through the flows a lifter depends on. Most tests use the showcase library, which
/// saves nothing; the relaunch test uses its own data directory.
final class CoreFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String] = ["--showcase"], environment: [String: String] = [:]) {
        app.launchArguments = arguments
        app.launchEnvironment = environment
        app.launch()
    }

    /// Elements whose label or identifier contains the text.
    private func matches(_ text: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", text, text))
    }
    private func element(_ text: String) -> XCUIElement { matches(text).firstMatch }

    @discardableResult private func expect(_ text: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(text)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "Expected \"\(text)\" on screen", file: file, line: line)
        return found
    }
    private func expectGone(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element(text).waitForNonExistence(timeout: 5), "Expected \"\(text)\" to be gone", file: file, line: line)
    }
    /// Taps the first match that can be tapped; the same text may also sit behind a sheet.
    private func tap(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let first = expect(text, file: file, line: line)
        let target = first.isHittable ? first : matches(text).allElementsBoundByIndex.prefix(8).first { $0.isHittable } ?? first
        target.tap()
    }
    private func startWorkout(collapsed: Bool = true) {
        tap("train.start")
        expect("workout.finish")
        if collapsed { tap("workout.options"); tap("workout.collapseAll") }
    }

    func testWorkoutSwapRemoveUndoLogAndFinishReachesHistory() {
        launch()
        startWorkout()

        // A short swipe on a header shows Swap and Remove. Remove takes the exercise out; Undo puts it back.
        expect("Expand Overhead press").swipeLeft()
        tap("Remove Overhead press")
        expect("Removed Overhead press")
        expectGone("Expand Overhead press")
        tap("notice.undo")
        expect("Expand Overhead press")

        // Swap it for another exercise, today only.
        expect("Expand Overhead press").swipeLeft()
        tap("Swap Overhead press")
        tap("exercise.search")
        app.typeText("Seated dumbbell")
        tap("Seated dumbbell press")
        // The exercise swapped in arrives open.
        expect("Collapse Seated dumbbell press")
        expectGone("Expand Overhead press")

        // Log a set: the count moves and rest starts.
        tap("Expand Bench press")
        tap(".complete")
        expect("1 of 19")
        tap("rest.skip")

        // Finish opens the saved workout, which compares it with the last Push day and lists the change from the plan.
        tap("workout.finish")
        tap("workout.save")
        expect("history.compared")
        expect("Swapped Overhead press for Seated dumbbell press")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        expect("train.start")

        app.tabBars.buttons["History"].tap()
        tap("Log")
        expect("1 change from the plan")
    }

    func testSavedDaySwipeSwapsAndRemovesWithUndo() {
        launch()
        app.swipeUp()
        tap("train.day.")
        let header = expect("Collapse Barbell row")

        header.swipeLeft()
        tap("Swap Barbell row")
        tap("exercise.search")
        app.typeText("Seated cable")
        tap("Seated cable row")
        expect("Collapse Seated cable row")
        expectGone("Collapse Barbell row")

        expect("Collapse Seated cable row").swipeLeft()
        tap("Remove Seated cable row")
        expect("Removed Seated cable row")
        expectGone("Collapse Seated cable row")
        tap("notice.undo")
        expect("Seated cable row")
    }

    func testProgramImportAddsLoadsAndConfirms() {
        let csv = ["program,day,exercise", "Imported Block,Day A,Bench press", "Imported Block,Day A,Squat", "Imported Block,Day B,Deadlift"].joined(separator: "\n")
        launch(environment: ["SETFORM_IMPORT_CSV": csv])
        expect("Imported Block")
        tap("csv.addAndLoad")
        expect("Added Imported Block, now your current program")
        // Train now shows the imported program and its first day.
        expect("Programs, Imported Block, 2 days")
        expect("Day A")
    }

    func testHoldAndDragReordersExercises() {
        launch()
        startWorkout()
        let bench = expect("Expand Bench press"), incline = expect("Expand Incline dumbbell press")
        XCTAssertLessThan(bench.frame.minY, expect("Expand Overhead press").frame.minY)
        bench.press(forDuration: 0.8, thenDragTo: incline)
        // Bench press was first; it now sits below Overhead press.
        XCTAssertGreaterThan(expect("Expand Bench press").frame.minY, expect("Expand Overhead press").frame.minY)
    }

    func testHoldAndDragReordersSetsInASavedDay() {
        launch()
        app.swipeUp()
        tap("train.day.")
        // The day opens on its first exercise: a warm-up, then four working sets.
        let warmup = expect("Warm-up, set 1, change set type")
        warmup.press(forDuration: 0.8, thenDragTo: expect("Working, set 3, change set type"))
        // The warm-up is no longer first, and a working set is.
        expect("Working, set 1, change set type")
        expectGone("Warm-up, set 1, change set type")
    }

    func testRestShowsOnTheLockScreenAndClearsWhenTheWorkoutEnds() {
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        /// Locks the phone and wakes it, leaving the Lock Screen showing.
        func showLockScreen() {
            XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
            XCUIDevice.shared.press(.home)
        }
        launch()
        startWorkout()
        tap("Expand Bench press")
        tap(".complete")
        expect("rest.skip")

        // The Lock Screen carries the next exercise and the running rest.
        showLockScreen()
        XCTAssertTrue(board.staticTexts["Bench press"].waitForExistence(timeout: 10), "Expected the workout on the Lock Screen")
        XCTAssertTrue(board.staticTexts["Rest"].exists)

        // Minimized, the workout opens again from the link the Lock Screen and Dynamic Island use.
        app.activate()
        tap("Minimize workout")
        expect("workout.resume")
        XCUIDevice.shared.system.open(URL(string: "setform://workout")!)
        expect("workout.finish")

        // Finishing takes it off the Lock Screen.
        tap("rest.skip")
        tap("workout.finish")
        tap("workout.save")
        expect("history.compared")
        showLockScreen()
        XCTAssertTrue(board.staticTexts["Bench press"].waitForNonExistence(timeout: 10), "Expected the Lock Screen to be clear")
        app.activate()
    }

    func testLoggedSetSurvivesTheAppBeingKilled() {
        let directory = NSTemporaryDirectory() + "setform-uitest-" + UUID().uuidString
        launch(["--data-directory", directory])
        startWorkout(collapsed: false)
        tap(".complete")
        expect("1 of 11")
        // Killed with no chance to tidy up: the set must already be on disk.
        app.terminate()
        launch(["--data-directory", directory])
        tap("workout.resume")
        expect("1 of 11")
    }
}
