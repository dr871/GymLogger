import XCTest
@testable import GymLoggerCore

/// Weekly volume depends on which calendar week a session falls in, so these
/// tests can't use the real clock: "2 days ago" is last week every Monday and
/// Tuesday. They all run as if it were Wednesday 16 Sept 2026, midday.
let fixedWednesday: Date = {
    let c = Calendar(identifier: .iso8601)
    return c.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!
}()

/// One exercise, one template, and a way to log finished sessions on given
/// days with given per-set numbers.
private struct Bench {
    var data = AppData()
    let exerciseId: String
    /// What "days ago" counts back from.
    var now = Date()

    init(measure: Measure, muscle: MuscleGroup? = .legs) {
        var exercise = Exercise(name: "X", measure: measure)
        exercise.muscle = muscle
        exerciseId = exercise.id
        data.exercises = [exercise]
        data.templates = [WorkoutTemplate(name: "T", items: [
            TemplateItem(exerciseId: exercise.id, sets: 3, targetMin: 8, targetMax: 12)
        ])]
    }

    @discardableResult
    mutating func log(daysAgo: Int, _ sets: [(Double?, Int)], done: Bool = true) -> String {
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        let start = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        data.sessions[i].startedAt = start
        data.sessions[i].entries[0].sets = sets.map { SetEntry(weight: $0.0, reps: $0.1, done: done) }
        data.finishSession(at: start.addingTimeInterval(3600))
        return data.sessions[i].id
    }
}

final class PersonalRecordTests: XCTestCase {

    func testEstimatedMaxUsesEpley() {
        XCTAssertEqual(AppData.estimatedMax(weight: 80, reps: 12), 112, accuracy: 0.01)
        XCTAssertEqual(AppData.estimatedMax(weight: 100, reps: 1), 100, accuracy: 0.01)
    }

    func testWeightedWorkTracksHeaviestAndBestEstimatedMax() {
        var b = Bench(measure: .weight)
        b.log(daysAgo: 7, [(80, 12), (80, 12), (80, 12)])     // e1RM 112
        b.log(daysAgo: 3, [(82.5, 8), (82.5, 8), (82.5, 8)])  // heavier, but e1RM 104.5

        let records = b.data.personalRecords(for: b.exerciseId)
        XCTAssertEqual(records.first { $0.kind == .heaviest }?.value, 82.5)
        XCTAssertEqual(records.first { $0.kind == .estimatedMax }?.value ?? 0, 112, accuracy: 0.01)
        XCTAssertEqual(records.first { $0.kind == .estimatedMax }?.reps, 12)
    }

    func testOnlyTickedSetsCount() {
        var b = Bench(measure: .weight)
        b.log(daysAgo: 3, [(60, 10)])
        b.log(daysAgo: 1, [(999, 10)], done: false)
        XCTAssertEqual(b.data.personalRecords(for: b.exerciseId).first { $0.kind == .heaviest }?.value, 60)
    }

    func testAssistedRecordIsTheLeastHelp() {
        var b = Bench(measure: .assisted)
        b.log(daysAgo: 7, [(25, 8), (25, 8)])
        b.log(daysAgo: 3, [(20, 6), (22.5, 8)])
        let records = b.data.personalRecords(for: b.exerciseId)
        XCTAssertEqual(records.map(\.kind), [.leastAssistance])
        XCTAssertEqual(records[0].value, 20)
        XCTAssertEqual(records[0].reps, 6)
    }

    func testBodyweightRecordIsMostReps() {
        var b = Bench(measure: .bodyweight)
        b.log(daysAgo: 3, [(nil, 10), (nil, 12), (nil, 9)])
        let records = b.data.personalRecords(for: b.exerciseId)
        XCTAssertEqual(records.map(\.kind), [.mostReps])
        XCTAssertEqual(records[0].value, 12)
    }

    func testTimedRecordIsTheLongestHold() {
        var b = Bench(measure: .time)
        b.log(daysAgo: 3, [(nil, 40), (nil, 45)])
        let records = b.data.personalRecords(for: b.exerciseId)
        XCTAssertEqual(records.map(\.kind), [.longestHold])
        XCTAssertEqual(records[0].value, 45)
    }

    func testNoHistoryMeansNoRecords() {
        let b = Bench(measure: .weight)
        XCTAssertTrue(b.data.personalRecords(for: b.exerciseId).isEmpty)
    }

    func testARecordIsOnlyNewWhenItStrictlyBeatsEveryEarlierSession() {
        var b = Bench(measure: .weight)
        let first = b.log(daysAgo: 7, [(80, 10)])
        let tie = b.log(daysAgo: 5, [(80, 10)])
        let better = b.log(daysAgo: 3, [(82.5, 10)])

        XCTAssertEqual(b.data.recordsSet(in: first).map(\.record.kind).sorted { $0.rawValue < $1.rawValue },
                       [.estimatedMax, .heaviest], "the first session sets the baseline")
        XCTAssertTrue(b.data.recordsSet(in: tie).isEmpty, "matching a record isn't setting one")
        XCTAssertEqual(b.data.recordsSet(in: better).count, 2)
    }

    func testRecordsSetInASessionIgnoreLaterSessions() {
        var b = Bench(measure: .weight)
        let middle = b.log(daysAgo: 5, [(85, 10)])
        b.log(daysAgo: 1, [(90, 10)])
        XCTAssertEqual(b.data.recordsSet(in: middle).count, 2, "judged against what came before it, not after")
    }
}

final class WeeklyVolumeTests: XCTestCase {

    private var monday: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    func testSetsAreCountedPerMusclePerWeek() {
        var b = Bench(measure: .weight, muscle: .legs)
        b.now = fixedWednesday
        b.log(daysAgo: 1, [(80, 10), (80, 10), (80, 10)])
        b.log(daysAgo: 2, [(80, 10), (80, 10)])

        let weeks = b.data.weeklyVolume(weeks: 1, endingAt: fixedWednesday, calendar: monday)
        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].sets[.legs], 5)
        XCTAssertEqual(weeks[0].totalSets, 5)
    }

    func testOnlyTickedSetsCountTowardsVolume() {
        var b = Bench(measure: .weight, muscle: .chest)
        b.now = fixedWednesday
        b.log(daysAgo: 1, [(80, 10), (80, 10)], done: false)
        XCTAssertEqual(b.data.weeklyVolume(weeks: 1, endingAt: fixedWednesday, calendar: monday)[0].totalSets, 0)
    }

    func testEmptyWeeksAreIncludedSoAChartIsContinuous() {
        var b = Bench(measure: .weight, muscle: .back)
        b.now = fixedWednesday
        b.log(daysAgo: 21, [(60, 10)])
        let weeks = b.data.weeklyVolume(weeks: 4, endingAt: fixedWednesday, calendar: monday)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(weeks[0].weekStart < weeks[3].weekStart, "oldest first")
        XCTAssertEqual(weeks.map(\.totalSets).reduce(0, +), 1)
        XCTAssertEqual(weeks.last?.totalSets, 0)
    }

    func testWeeksStartOnTheCalendarsFirstWeekday() {
        let b = Bench(measure: .weight)
        let week = b.data.weeklyVolume(weeks: 1, calendar: monday)[0]
        XCTAssertEqual(monday.component(.weekday, from: week.weekStart), 2, "Monday")
        XCTAssertEqual(monday.dateComponents([.hour, .minute], from: week.weekStart), DateComponents(hour: 0, minute: 0))
    }

    func testAnExerciseWithoutAMuscleIsCountedAsUnassigned() {
        var b = Bench(measure: .weight, muscle: nil)
        b.now = fixedWednesday
        b.log(daysAgo: 1, [(80, 10), (80, 10)])
        let week = b.data.weeklyVolume(weeks: 1, endingAt: fixedWednesday, calendar: monday)[0]
        XCTAssertTrue(week.sets.isEmpty)
        XCTAssertEqual(week.unassignedSets, 2)
        XCTAssertEqual(week.totalSets, 2)
    }

    func testTheMuscleIsReadFromTheExerciseNotSnapshotted() {
        var b = Bench(measure: .weight, muscle: .legs)
        b.now = fixedWednesday
        b.log(daysAgo: 1, [(80, 10)])
        b.data.exercises[0].muscle = .core
        XCTAssertEqual(b.data.weeklyVolume(weeks: 1, endingAt: fixedWednesday, calendar: monday)[0].sets[.core], 1,
                       "recategorising an exercise moves its whole history — that's the point")
    }
}

final class MuscleAssignmentTests: XCTestCase {

    func testSeededExercisesHaveMuscles() {
        let muscles = AppData.seed().exercises.map(\.muscle)
        XCTAssertEqual(muscles, [.legs, .chest, .back, .back, .legs, .core])
    }

    func testACatalogueExerciseArrivesWithItsMuscle() {
        var data = AppData()
        let id = data.addExercise(named: "Lateral raise")
        XCTAssertEqual(data.exercise(id: id)?.muscle, .shoulders)
    }

    func testACustomExerciseHasNoMuscleUntilYouPickOne() {
        var data = AppData()
        let id = data.addExercise(named: "Sled push")
        XCTAssertNil(data.exercise(id: id)?.muscle)
    }

    func testAnOlderBackupDecodesWithoutAMuscle() throws {
        let json = #"{"id":"e","name":"Chest press"}"#
        XCTAssertNil(try AppData.decoder().decode(Exercise.self, from: Data(json.utf8)).muscle)
    }

    func testMuscleRoundTrips() throws {
        var data = AppData()
        var exercise = Exercise(name: "X")
        exercise.muscle = .shoulders
        data.exercises = [exercise]
        let restored = try AppData.decoder().decode(AppData.self, from: try data.exportJSON())
        XCTAssertEqual(restored.exercises[0].muscle, .shoulders)
    }
}
