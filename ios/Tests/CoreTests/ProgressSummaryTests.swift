import XCTest
@testable import GymLoggerCore

private struct Log {
    var data = AppData()
    let id: String

    init(_ measure: Measure = .weight) {
        let e = Exercise(name: "X", measure: measure, muscle: .legs)
        id = e.id
        data.exercises = [e]
        data.templates = [WorkoutTemplate(name: "T", items: [TemplateItem(exerciseId: e.id, sets: 3, target: 10)])]
    }

    mutating func session(daysAgo: Int, _ sets: [(Double?, Int)]) {
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        let start = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        data.sessions[i].startedAt = start
        data.sessions[i].entries[0].sets = sets.map { SetEntry(weight: $0.0, reps: $0.1, done: true) }
        data.finishSession(at: start.addingTimeInterval(3600))
    }
}

/// The chart says "something went up". The summary should say what, and by how
/// much, in the words you'd use yourself.
final class ProgressSummaryTests: XCTestCase {

    func testNoHistoryHasNoSummary() {
        let log = Log()
        XCTAssertNil(log.data.progressSummary(for: log.id))
    }

    func testTheHeadlineIsWhatYouLastDid() throws {
        var log = Log()
        log.session(daysAgo: 2, [(70, 10), (70, 12)])
        let summary = try XCTUnwrap(log.data.progressSummary(for: log.id))
        XCTAssertEqual(summary.headline, "70 kg × 12")
    }

    func testAFirstSessionSaysSoRatherThanClaimingProgress() throws {
        var log = Log()
        log.session(daysAgo: 2, [(70, 10)])
        let summary = try XCTUnwrap(log.data.progressSummary(for: log.id))
        XCTAssertEqual(summary.trend, "First time logged")
    }

    func testBeatingEverythingBeforeReadsAsBestYet() throws {
        var log = Log()
        log.session(daysAgo: 9, [(60, 10)])
        log.session(daysAgo: 2, [(70, 10)])
        XCTAssertEqual(try XCTUnwrap(log.data.progressSummary(for: log.id)).trend, "Best yet")
    }

    func testAnImprovementOnLastTimeIsQuantified() throws {
        var log = Log()
        log.session(daysAgo: 16, [(80, 12)])   // best ever
        log.session(daysAgo: 9, [(60, 10)])
        log.session(daysAgo: 2, [(65, 10)])    // better than last time, not a best
        XCTAssertEqual(try XCTUnwrap(log.data.progressSummary(for: log.id)).trend, "Up 5 kg on last time")
    }

    func testGoingBackwardsIsSaidPlainly() throws {
        var log = Log()
        log.session(daysAgo: 9, [(70, 10)])
        log.session(daysAgo: 2, [(65, 10)])
        XCTAssertEqual(try XCTUnwrap(log.data.progressSummary(for: log.id)).trend, "Down 5 kg on last time")
    }

    func testRepeatingLastTimeSaysSo() throws {
        var log = Log()
        log.session(daysAgo: 9, [(70, 10)])
        log.session(daysAgo: 2, [(70, 10)])
        XCTAssertEqual(try XCTUnwrap(log.data.progressSummary(for: log.id)).trend, "Same as last time")
    }

    func testSameWeightWithMoreRepsIsNamedAsProgress() throws {
        var log = Log()
        log.session(daysAgo: 16, [(80, 12)])   // best ever, so today isn't a best
        log.session(daysAgo: 9, [(70, 10)])
        log.session(daysAgo: 2, [(70, 12)])
        XCTAssertEqual(try XCTUnwrap(log.data.progressSummary(for: log.id)).trend,
                       "Same weight, 2 more reps")
    }

    func testTimedWorkTalksInSeconds() throws {
        var log = Log(.time)
        log.session(daysAgo: 9, [(nil, 40)])
        log.session(daysAgo: 2, [(nil, 45)])
        let summary = try XCTUnwrap(log.data.progressSummary(for: log.id))
        XCTAssertEqual(summary.headline, "45s")
        XCTAssertEqual(summary.trend, "Best yet")
    }

    func testBodyweightWorkTalksInReps() throws {
        var log = Log(.bodyweight)
        log.session(daysAgo: 9, [(nil, 12)])
        log.session(daysAgo: 2, [(nil, 10)])
        let summary = try XCTUnwrap(log.data.progressSummary(for: log.id))
        XCTAssertEqual(summary.headline, "10 reps")
        XCTAssertEqual(summary.trend, "Down 2 reps on last time")
    }

    func testAssistedWorkCountsLessHelpAsProgress() throws {
        var log = Log(.assisted)
        log.session(daysAgo: 9, [(25, 8)])
        log.session(daysAgo: 2, [(20, 8)])
        let summary = try XCTUnwrap(log.data.progressSummary(for: log.id))
        XCTAssertEqual(summary.headline, "20 kg assist × 8")
        XCTAssertEqual(summary.trend, "Best yet", "less help is better")
    }

    func testAssistedGoingUpIsGoingBackwards() throws {
        var log = Log(.assisted)
        log.session(daysAgo: 16, [(15, 8)])
        log.session(daysAgo: 9, [(20, 8)])
        log.session(daysAgo: 2, [(25, 8)])
        XCTAssertEqual(try XCTUnwrap(log.data.progressSummary(for: log.id)).trend,
                       "Down 5 kg on last time", "more help than last time")
    }
}

/// Progress should only offer exercises you have actually done.
final class LoggedExerciseTests: XCTestCase {

    private func store() -> AppData {
        var data = AppData.seed()
        // Log leg press twice and chest press once; nothing else.
        for (name, daysAgo) in [("Leg press", 9), ("Chest press", 5), ("Leg press", 2)] {
            data.startSession(templateId: data.templates[0].id)
            let i = data.activeSessionIndex!
            data.sessions[i].startedAt = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            for e in data.sessions[i].entries.indices where data.sessions[i].entries[e].name == name {
                data.sessions[i].entries[e].sets[0].weight = 60
                data.sessions[i].entries[e].sets[0].reps = 10
                data.sessions[i].entries[e].sets[0].done = true
            }
            data.finishSession(at: data.sessions[i].startedAt.addingTimeInterval(3600))
        }
        return data
    }

    func testOnlyExercisesWithLoggedSetsAreListed() {
        let names = store().loggedExercises.map(\.name)
        XCTAssertEqual(Set(names), ["Leg press", "Chest press"])
        XCTAssertFalse(names.contains("Plank"), "never done, so it has nothing to show")
    }

    func testTheMostRecentlyTrainedComesFirst() {
        XCTAssertEqual(store().loggedExercises.first?.name, "Leg press")
    }

    func testNothingLoggedMeansAnEmptyList() {
        XCTAssertTrue(AppData.seed().loggedExercises.isEmpty)
    }

    func testAnExerciseDeletedFromTheLibraryDropsOut() {
        var data = store()
        data.deleteExercise(id: data.exercises.first { $0.name == "Leg press" }!.id)
        XCTAssertEqual(data.loggedExercises.map(\.name), ["Chest press"])
    }

    /// The volume chart shouldn't draw eight weeks when you've trained for one.
    func testWeeksOfHistoryGrowsWithUse() {
        var monday = Calendar(identifier: .iso8601); monday.firstWeekday = 2
        XCTAssertEqual(AppData.seed().weeksOfHistory(calendar: monday), 1, "no history: just this week")
        XCTAssertLessThanOrEqual(store().weeksOfHistory(calendar: monday), 8)
        XCTAssertGreaterThanOrEqual(store().weeksOfHistory(calendar: monday), 2)
    }

    func testWeeksOfHistoryIsCappedAtTheMaximumAsked() {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        data.sessions[i].startedAt = Date().addingTimeInterval(-365 * 86_400)
        data.sessions[i].entries[0].sets[0].done = true
        data.finishSession(at: data.sessions[i].startedAt)
        XCTAssertEqual(data.weeksOfHistory(max: 8), 8)
    }
}
