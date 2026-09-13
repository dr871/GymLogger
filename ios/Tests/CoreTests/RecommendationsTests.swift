import XCTest
@testable import GymLoggerCore

private struct Rig {
    var data = AppData()
    let exerciseId: String

    init(measure: Measure = .weight, range: (Int, Int) = (8, 12), muscle: MuscleGroup? = .legs) {
        let exercise = Exercise(name: "X", measure: measure, muscle: muscle)
        exerciseId = exercise.id
        data.exercises = [exercise]
        data.templates = [WorkoutTemplate(name: "T", items: [
            TemplateItem(exerciseId: exercise.id, sets: 3, targetMin: range.0, targetMax: range.1)
        ])]
    }

    /// Logs a finished session. `warmups` are prepended and ticked too.
    @discardableResult
    mutating func log(daysAgo: Int, warmups: [(Double?, Int)] = [], _ sets: [(Double?, Int)]) -> String {
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        let start = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        data.sessions[i].startedAt = start
        data.sessions[i].entries[0].sets =
            warmups.map { SetEntry(weight: $0.0, reps: $0.1, done: true, warmup: true) }
            + sets.map { SetEntry(weight: $0.0, reps: $0.1, done: true) }
        data.finishSession(at: start.addingTimeInterval(3600))
        return data.sessions[i].id
    }
}

/// Warm-up sets are logged but never *count*: not for progression, records,
/// volume, or "did this session do this exercise".
final class WarmupSetTests: XCTestCase {

    func testAWarmupNeverEarnsTheBump() {
        var r = Rig()
        r.log(daysAgo: 2, warmups: [(40, 12), (60, 12)], [(80, 12), (80, 12), (80, 12)])
        let s = r.data.suggestion(for: r.exerciseId)
        XCTAssertTrue(s.earned)
        XCTAssertEqual(s.weight, 82.5)
        XCTAssertEqual(s.lastWeight, 80, "the 60 kg warm-up is not last time's weight")
    }

    func testAMissedWarmupDoesNotBlockTheBump() {
        var r = Rig()
        r.log(daysAgo: 2, warmups: [(40, 5)], [(80, 12), (80, 12), (80, 12)])
        XCTAssertTrue(r.data.suggestion(for: r.exerciseId).earned, "5 reps on a warm-up isn't a failed set")
    }

    func testWarmupsAreLeftOutOfRecordsVolumeAndProgress() {
        var r = Rig()
        r.log(daysAgo: 2, warmups: [(200, 1)], [(80, 10), (80, 10)])

        XCTAssertEqual(r.data.personalRecords(for: r.exerciseId).first { $0.kind == .heaviest }?.value, 80)
        var monday = Calendar(identifier: .iso8601); monday.firstWeekday = 2
        XCTAssertEqual(r.data.weeklyVolume(weeks: 1, calendar: monday)[0].totalSets, 2)
        XCTAssertEqual(r.data.progressSeries(for: r.exerciseId).first?.topWeight, 80)
    }

    func testOnlyWarmupsIsNotHistory() {
        var r = Rig()
        r.log(daysAgo: 2, warmups: [(40, 10)], [])
        XCTAssertNil(r.data.lastEntry(for: r.exerciseId), "a session of only warm-ups says nothing about what you can lift")
    }

    func testStartingASessionPrefillsFromWorkingSetsOnly() {
        var r = Rig()
        r.log(daysAgo: 2, warmups: [(40, 12)], [(80, 12), (80, 11), (80, 10)])
        r.data.startSession(templateId: r.data.templates[0].id)
        let entry = r.data.activeSession!.entries[0]
        XCTAssertEqual(entry.sets.map(\.reps), [12, 11, 10], "aligned to last time's working sets, not its warm-up")
        XCTAssertTrue(entry.sets.allSatisfy { !$0.warmup })
    }

    func testAddingAWarmupPutsItFirstAtRoughlyHalfTheLoad() {
        var r = Rig()
        r.log(daysAgo: 2, [(80, 12), (80, 12), (80, 12)])
        r.data.startSession(templateId: r.data.templates[0].id)
        let s = r.data.activeSessionIndex!

        r.data.addWarmup(sessionIndex: s, entryIndex: 0)

        let sets = r.data.sessions[s].entries[0].sets
        XCTAssertEqual(sets.count, 4)
        XCTAssertTrue(sets[0].warmup)
        XCTAssertEqual(sets[0].weight, 42.5, "half of 82.5, rounded to the 2.5 kg increment")
        XCTAssertEqual(sets[0].reps, 8, "bottom of the range")
        XCTAssertFalse(sets[0].done)
    }

    func testAWarmupWithNoWorkingWeightHasNoWeight() {
        var r = Rig(measure: .bodyweight, range: (5, 8))
        r.data.startSession(templateId: r.data.templates[0].id)
        let s = r.data.activeSessionIndex!
        r.data.addWarmup(sessionIndex: s, entryIndex: 0)
        XCTAssertNil(r.data.sessions[s].entries[0].sets[0].weight)
        XCTAssertEqual(r.data.sessions[s].entries[0].sets[0].reps, 5)
    }

    func testWarmupsStillNeedTheirNumbersToBeTicked() {
        let entry = SessionEntry(exerciseId: "e", name: "X", sets: [SetEntry(weight: nil, reps: 8, warmup: true)])
        XCTAssertFalse(entry.canComplete(setIndex: 0))
    }

    func testWorkingSetNumbersSkipWarmups() {
        let entry = SessionEntry(exerciseId: "e", name: "X", sets: [
            SetEntry(weight: 40, reps: 10, warmup: true),
            SetEntry(weight: 80, reps: 10),
            SetEntry(weight: 80, reps: 10),
        ])
        XCTAssertEqual(entry.workingIndex(of: 0), nil)
        XCTAssertEqual(entry.workingIndex(of: 1), 0)
        XCTAssertEqual(entry.workingIndex(of: 2), 1)
    }

    func testAnOlderBackupDecodesSetsAsWorking() throws {
        let json = #"{"id":"s","weight":60,"reps":10,"done":true}"#
        XCTAssertFalse(try AppData.decoder().decode(SetEntry.self, from: Data(json.utf8)).warmup)
    }
}

/// The chart should move during the rep-climb, so weighted work plots an
/// estimated one-rep max rather than the bar weight.
final class EstimatedMaxProgressTests: XCTestCase {

    func testWeightedWorkPlotsTheBestEstimatedMax() {
        var r = Rig()
        r.log(daysAgo: 7, [(80, 8), (80, 8), (80, 8)])     // 101.3
        r.log(daysAgo: 4, [(80, 12), (80, 12), (80, 12)])  // 112 — same weight, more reps
        r.log(daysAgo: 1, [(82.5, 8), (82.5, 8), (82.5, 8)]) // 104.5

        let series = r.data.progressSeries(for: r.exerciseId)
        XCTAssertEqual(series.map { ($0.value ?? 0).rounded() }, [101, 112, 105])
        XCTAssertEqual(series.map(\.topWeight), [80, 80, 82.5], "the bar weight is still there for the row")
    }

    func testTheEstimateComesFromTheBestSetNotTheHeaviest() {
        var r = Rig()
        r.log(daysAgo: 1, [(82.5, 5), (80, 12)])   // 96.25 vs 112
        XCTAssertEqual(r.data.progressSeries(for: r.exerciseId)[0].value ?? 0, 112, accuracy: 0.01)
    }

    func testOtherMeasuresAreUnchanged() {
        var a = Rig(measure: .assisted, range: (5, 8))
        a.log(daysAgo: 1, [(20, 8), (15, 8)])
        XCTAssertEqual(a.data.progressSeries(for: a.exerciseId)[0].value, 15)

        var t = Rig(measure: .time, range: (30, 60))
        t.log(daysAgo: 1, [(nil, 40), (nil, 45)])
        XCTAssertEqual(t.data.progressSeries(for: t.exerciseId)[0].value, 45)
    }
}

/// With more than one workout, Home should lead with the one that's waited
/// longest.
final class NextWorkoutTests: XCTestCase {

    private func twoTemplates() -> AppData {
        var data = AppData.seed()
        data.templates.append(WorkoutTemplate(name: "B", items: data.templates[0].items))
        return data
    }

    private func finish(_ data: inout AppData, templateId: String, daysAgo: Int) {
        data.startSession(templateId: templateId)
        let i = data.activeSessionIndex!
        data.sessions[i].startedAt = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        data.sessions[i].entries[0].sets[0].weight = 60
        data.sessions[i].entries[0].sets[0].done = true
        data.finishSession(at: data.sessions[i].startedAt.addingTimeInterval(3600))
    }

    func testWithOneWorkoutItIsTheNextOne() {
        let data = AppData.seed()
        XCTAssertEqual(data.nextTemplateId, data.templates[0].id)
    }

    func testANeverDoneWorkoutComesFirst() {
        var data = twoTemplates()
        finish(&data, templateId: data.templates[0].id, daysAgo: 1)
        XCTAssertEqual(data.nextTemplateId, data.templates[1].id)
    }

    func testOtherwiseTheLeastRecentlyDoneWins() {
        var data = twoTemplates()
        finish(&data, templateId: data.templates[0].id, daysAgo: 6)
        finish(&data, templateId: data.templates[1].id, daysAgo: 2)
        XCTAssertEqual(data.nextTemplateId, data.templates[0].id)
        finish(&data, templateId: data.templates[0].id, daysAgo: 1)
        XCTAssertEqual(data.nextTemplateId, data.templates[1].id)
    }

    func testTiesKeepTemplateOrder() {
        let data = twoTemplates()
        XCTAssertEqual(data.nextTemplateId, data.templates[0].id, "neither done: the first listed")
    }

    func testLastDoneIsPerTemplate() {
        var data = twoTemplates()
        finish(&data, templateId: data.templates[1].id, daysAgo: 3)
        XCTAssertNil(data.lastFinished(templateId: data.templates[0].id))
        XCTAssertNotNil(data.lastFinished(templateId: data.templates[1].id))
    }

    func testNoWorkoutsMeansNoNext() {
        XCTAssertNil(AppData().nextTemplateId)
    }
}

final class TemplateEditingTests: XCTestCase {

    func testDuplicatingAWorkoutCopiesItsExercisesUnderANewName() throws {
        var data = AppData.seed()
        let original = data.templates[0]

        let id = try XCTUnwrap(data.duplicateTemplate(id: original.id))

        XCTAssertEqual(data.templates.count, 2)
        let copy = try XCTUnwrap(data.template(id: id))
        XCTAssertEqual(copy.name, "Full Body copy")
        XCTAssertEqual(copy.items, original.items)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(data.templates[1].id, id, "lands right after the original")
    }

    func testDuplicatingTwiceDoesNotCollideOnName() {
        var data = AppData.seed()
        data.duplicateTemplate(id: data.templates[0].id)
        data.duplicateTemplate(id: data.templates[0].id)
        XCTAssertEqual(Set(data.templates.map(\.name)).count, 3)
    }

    func testDuplicatingNothingDoesNothing() {
        var data = AppData.seed()
        XCTAssertNil(data.duplicateTemplate(id: "nope"))
        XCTAssertEqual(data.templates.count, 1)
    }

    func testAddingToATemplateUsesTheMeasuresDefaultRange() throws {
        var data = AppData.seed()
        let plank = try XCTUnwrap(data.exercises.first { $0.name == "Plank" })
        let pullUp = Exercise(name: "Pull-up", measure: .bodyweight)
        data.exercises.append(pullUp)

        XCTAssertTrue(data.addToTemplate(templateId: data.templates[0].id, exerciseId: pullUp.id))
        let added = try XCTUnwrap(data.templates[0].items.last)
        XCTAssertEqual(added.exerciseId, pullUp.id)
        XCTAssertEqual(added.sets, 3)
        XCTAssertEqual(added.targetMin, 5)
        XCTAssertEqual(added.targetMax, 10)

        XCTAssertFalse(data.addToTemplate(templateId: data.templates[0].id, exerciseId: plank.id),
                       "already in it — nothing added")
        XCTAssertEqual(data.templates[0].items.filter { $0.exerciseId == plank.id }.count, 1)
    }

    func testTemplateContainsIsHowTheSessionKnowsWhetherToOffer() {
        let data = AppData.seed()
        XCTAssertTrue(data.templateContains(templateId: data.templates[0].id, exerciseId: data.exercises[0].id))
        XCTAssertFalse(data.templateContains(templateId: data.templates[0].id, exerciseId: "ex_missing"))
    }
}

/// ± by the increment, applied to every set not yet ticked.
final class WeightSteppingTests: XCTestCase {

    private func active() -> (AppData, Int) {
        var r = Rig()
        r.log(daysAgo: 2, [(80, 10), (80, 10), (80, 10)])
        r.data.startSession(templateId: r.data.templates[0].id)
        return (r.data, r.data.activeSessionIndex!)
    }

    func testStepsEveryPendingSet() {
        var (data, s) = active()
        data.sessions[s].entries[0].sets[0].done = true
        data.adjustWeight(sessionIndex: s, entryIndex: 0, by: 2.5)
        XCTAssertEqual(data.sessions[s].entries[0].sets.map(\.weight), [80, 82.5, 82.5])
        data.adjustWeight(sessionIndex: s, entryIndex: 0, by: -5)
        XCTAssertEqual(data.sessions[s].entries[0].sets.map(\.weight), [80, 77.5, 77.5])
    }

    func testAnEmptyWeightStepsFromZero() {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        let s = data.activeSessionIndex!
        data.adjustWeight(sessionIndex: s, entryIndex: 0, by: 2.5)
        XCTAssertEqual(data.sessions[s].entries[0].sets[0].weight, 2.5)
    }

    func testNeverBelowZero() {
        var (data, s) = active()
        data.adjustWeight(sessionIndex: s, entryIndex: 0, by: -500)
        XCTAssertEqual(data.sessions[s].entries[0].sets.map(\.weight), [0, 0, 0])
    }

    func testWarmupsStepToo() {
        var (data, s) = active()
        data.addWarmup(sessionIndex: s, entryIndex: 0)
        data.adjustWeight(sessionIndex: s, entryIndex: 0, by: 2.5)
        XCTAssertEqual(data.sessions[s].entries[0].sets[0].weight, 42.5)
    }
}

final class SchemaVersionTests: XCTestCase {
    func testNewFilesSayVersionTwo() {
        XCTAssertEqual(AppData.seed().version, 2)
    }

    func testAVersionOneFileStillLoadsAndReportsItself() throws {
        let json = #"{"version":1,"exercises":[{"id":"e","name":"X","isBodyweight":true}],"templates":[],"sessions":[]}"#
        let decoded = try AppData.decoder().decode(AppData.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.exercises[0].measure, .bodyweight)
    }
}
