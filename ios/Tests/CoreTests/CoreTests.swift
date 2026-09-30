import XCTest
@testable import GymLoggerCore

final class CoreTests: XCTestCase {

    // MARK: - Helpers

    /// Logs a finished session: one entry per (exerciseId, weight, reps) triple.
    @discardableResult
    private func logSession(
        _ data: inout AppData,
        daysAgo: Int,
        _ work: [(exerciseId: String, weight: Double?, reps: Int?, setsDone: Int)]
    ) -> Session {
        let template = data.templates[0]
        let started = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))

        var entries: [SessionEntry] = []
        for item in template.items {
            guard let hit = work.first(where: { $0.exerciseId == item.exerciseId }) else { continue }
            var entry = data.buildEntry(exerciseId: item.exerciseId, sets: item.sets, targetMin: item.targetMin, targetMax: item.targetMax)
            for i in entry.sets.indices {
                entry.sets[i].weight = hit.weight
                entry.sets[i].reps = hit.reps
                entry.sets[i].done = i < hit.setsDone
            }
            entries.append(entry)
        }

        let session = Session(templateId: template.id, name: template.name,
                              startedAt: started, finishedAt: started.addingTimeInterval(3600),
                              entries: entries)
        data.sessions.append(session)
        return session
    }

    private func seeded() -> (AppData, [String: String]) {
        let data = AppData.seed()
        var ids: [String: String] = [:]
        for ex in data.exercises { ids[ex.name] = ex.id }
        return (data, ids)
    }

    // MARK: - Seed

    func testSeedMatchesTheCurrentWorkout() {
        let (data, _) = seeded()
        XCTAssertEqual(data.exercises.map(\.name),
                       ["Leg press", "Chest press", "Lat pulldown", "Seated cable row", "Leg curl", "Plank"])
        XCTAssertEqual(data.templates.count, 1)
        XCTAssertEqual(data.templates[0].name, "Full Body")
        XCTAssertEqual(data.templates[0].items.map(\.sets), [3, 3, 3, 3, 3, 3])
        XCTAssertEqual(data.templates[0].items.map(\.targetMin), [12, 12, 12, 12, 12, 30])
        XCTAssertEqual(data.templates[0].items.map(\.targetMax), [12, 12, 12, 12, 12, 60])
        XCTAssertEqual(data.exercises.map(\.measure), [.weight, .weight, .weight, .weight, .weight, .time])
    }

    func testLegPressRestsLongerThanTheRest() {
        let (data, ids) = seeded()
        XCTAssertEqual(data.restSec(for: ids["Leg press"]!), 120)
        XCTAssertEqual(data.restSec(for: ids["Chest press"]!), 90)
    }

    // MARK: - First session

    func testFirstSessionHasNoWeightButPrefillsTargetReps() {
        let (data, ids) = seeded()
        let entry = data.buildEntry(exerciseId: ids["Leg press"]!, sets: 3, target: 12)
        XCTAssertEqual(entry.sets.count, 3)
        XCTAssertNil(entry.sets[0].weight)
        XCTAssertEqual(entry.sets[0].reps, 12)
    }

    // MARK: - Prefilling from last time

    /// The app never proposes a weight of its own. Gym stacks move in pin
    /// positions plus small add-on tabs, so a computed number is as likely to
    /// be unloadable as not — it shows what you did and you change it.
    func testPrefillRepeatsLastSessionEvenWhenEveryRepWasHit() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])

        let last = data.lastTime(for: legPress)
        XCTAssertEqual(last.weight, 60)
        XCTAssertEqual(last.reps, 12)

        let entry = data.buildEntry(exerciseId: legPress, sets: 3, target: 12)
        XCTAssertEqual(entry.sets.map(\.weight), [60, 60, 60], "no bump, ever")
    }

    func testPrefillUsesTheHeaviestSetWhenTheyDiffer() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        var session = logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])
        session.entries[0].sets[2].weight = 45          // dropped the last set
        data.sessions[data.sessions.count - 1] = session

        XCTAssertEqual(data.lastTime(for: legPress).weight, 60)
    }

    func testAnUntickedSetIsNotWhatYouLifted() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        var session = logSession(&data, daysAgo: 2, [(legPress, 60, 12, 2)])   // 2 of 3 ticked
        session.entries[0].sets[2].weight = 100
        data.sessions[data.sessions.count - 1] = session

        XCTAssertEqual(data.lastTime(for: legPress).weight, 60, "an untouched set says nothing")
    }

    func testTimedWorkPrefillsSecondsAndHasNoWeight() {
        var (data, ids) = seeded()
        let plank = ids["Plank"]!
        logSession(&data, daysAgo: 2, [(plank, nil, 40, 3)])

        let last = data.lastTime(for: plank)
        XCTAssertNil(last.weight)
        XCTAssertEqual(last.reps, 40)
    }

    // MARK: - Last session lookup

    func testLastSessionIsPerExerciseNotPerSession() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        let chestPress = ids["Chest press"]!

        logSession(&data, daysAgo: 7, [(legPress, 60, 12, 3), (chestPress, 40, 12, 3)])
        logSession(&data, daysAgo: 2, [(chestPress, 42.5, 12, 3)])   // skipped leg press

        XCTAssertEqual(data.lastEntry(for: legPress)?.entry.sets.first?.weight, 60,
                       "skipping a machine must not lose its target")
        XCTAssertEqual(data.lastEntry(for: chestPress)?.entry.sets.first?.weight, 42.5)
    }

    func testAnUnworkedEntryIsNotTreatedAsLastSession() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 7, [(legPress, 60, 12, 3)])
        logSession(&data, daysAgo: 2, [(legPress, 999, 12, 0)])   // opened, never ticked

        XCTAssertEqual(data.lastEntry(for: legPress)?.entry.sets.first?.weight, 60)
    }

    func testTodaysSessionIsExcludedFromItsOwnLookup() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])
        let todayId = data.startSession(templateId: data.templates[0].id)!

        XCTAssertEqual(data.lastEntry(for: legPress, excluding: todayId)?.entry.sets.first?.weight, 60)
    }

    func testAnInProgressSessionIsNotAlreadyHistory() {
        var (data, ids) = seeded()
        data.startSession(templateId: data.templates[0].id)
        XCTAssertNil(data.lastEntry(for: ids["Leg press"]!))
    }

    // MARK: - Starting a session

    func testStartingASessionPrefillsFromLastTime() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])

        data.startSession(templateId: data.templates[0].id)
        let entry = data.activeSession!.entries[0]

        XCTAssertEqual(entry.sets.map(\.weight), [60, 60, 60])
        XCTAssertEqual(entry.sets.map(\.reps), [12, 12, 12])
        XCTAssertTrue(entry.sets.allSatisfy { !$0.done })
    }

    func testStartingASessionCarriesTheNoteForward() {
        var (data, ids) = seeded()
        data.exercises[0].notes = "seat 4, handles 2"
        data.startSession(templateId: data.templates[0].id)
        XCTAssertEqual(data.activeSession!.entries[0].note, "seat 4, handles 2")
        XCTAssertEqual(data.activeSession!.entries[0].name, "Leg press")
        _ = ids
    }

    func testFinishAndDiscard() {
        var (data, _) = seeded()
        data.startSession(templateId: data.templates[0].id)
        data.finishSession()
        XCTAssertNil(data.activeSessionId)
        XCTAssertEqual(data.finishedSessions.count, 1)

        data.startSession(templateId: data.templates[0].id)
        data.discardSession()
        XCTAssertNil(data.activeSessionId)
        XCTAssertEqual(data.sessions.count, 1, "a discarded session leaves nothing behind")
    }

    func testRenamingAnExerciseLeavesHistoryAlone() {
        var (data, ids) = seeded()
        logSession(&data, daysAgo: 2, [(ids["Leg press"]!, 60, 12, 3)])
        data.exercises[0].name = "Leg press (new machine)"

        XCTAssertEqual(data.finishedSessions[0].entries[0].name, "Leg press")
    }

    func testNoteEditsFollowYouForwardAndStickToHistory() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        data.startSession(templateId: data.templates[0].id)
        let index = data.activeSessionIndex!

        data.setNote("seat 4, handles 2", exerciseId: legPress, sessionIndex: index, entryIndex: 0)
        XCTAssertEqual(data.exercise(id: legPress)?.notes, "seat 4, handles 2")
        XCTAssertEqual(data.sessions[index].entries[0].note, "seat 4, handles 2")

        data.finishSession()
        data.startSession(templateId: data.templates[0].id)
        XCTAssertEqual(data.activeSession!.entries[0].note, "seat 4, handles 2")
    }

    // MARK: - Progress

    func testProgressSeriesRunsOldestFirst() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 7, [(legPress, 60, 12, 3)])
        logSession(&data, daysAgo: 4, [(legPress, 62.5, 12, 3)])
        logSession(&data, daysAgo: 1, [(legPress, 65, 12, 3)])

        let series = data.progressSeries(for: legPress)
        XCTAssertEqual(series.map(\.topWeight), [60, 62.5, 65])
        XCTAssertTrue(series[0].date < series[1].date)
    }

    func testProgressSeriesKeepsRepsForBodyweightWork() {
        var (data, ids) = seeded()
        let plank = ids["Plank"]!
        logSession(&data, daysAgo: 4, [(plank, nil, 40, 3)])
        logSession(&data, daysAgo: 1, [(plank, nil, 45, 3)])

        let series = data.progressSeries(for: plank)
        XCTAssertEqual(series.compactMap(\.topWeight), [], "no weights to plot")
        XCTAssertEqual(series.map(\.topReps), [40, 45], "so the chart falls back to these")
    }

    func testOrderedExercisesFollowsTheWorkout() {
        var (data, _) = seeded()
        data.exercises.append(Exercise(name: "Calf raise"))   // not in any template
        XCTAssertEqual(data.orderedExercises.map(\.name),
                       ["Leg press", "Chest press", "Lat pulldown", "Seated cable row", "Leg curl", "Plank", "Calf raise"])
    }

    // MARK: - Rest timer (wall clock)

    func testTimerCountsDownFromTheWallClock() {
        let start = Date()
        let timer = RestTimerState(exerciseId: "x", label: "Leg press",
                                   endsAt: start.addingTimeInterval(120), durationSec: 120)

        XCTAssertEqual(timer.remaining(at: start), 120, accuracy: 0.01)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(30)), 90, accuracy: 0.01)
        XCTAssertFalse(timer.isDone(at: start.addingTimeInterval(119)))
    }

    func testATimerThatExpiredWhileAwayReadsDoneNotNegative() {
        let start = Date()
        let timer = RestTimerState(exerciseId: "x", label: "Leg press",
                                   endsAt: start.addingTimeInterval(90), durationSec: 90)
        let muchLater = start.addingTimeInterval(6000)

        XCTAssertTrue(timer.isDone(at: muchLater))
        XCTAssertEqual(timer.remaining(at: muchLater), 0, "never counts past zero")
        XCTAssertEqual(timer.elapsedFraction(at: muchLater), 1)
    }

    func testTimerFillTracksElapsedTime() {
        let start = Date()
        let timer = RestTimerState(exerciseId: "x", label: "", endsAt: start.addingTimeInterval(100), durationSec: 100)
        XCTAssertEqual(timer.elapsedFraction(at: start), 0, accuracy: 0.01)
        XCTAssertEqual(timer.elapsedFraction(at: start.addingTimeInterval(25)), 0.25, accuracy: 0.01)
    }

    // MARK: - Persistence

    func testDataSurvivesARoundTrip() throws {
        var (data, ids) = seeded()
        data.exercises[0].notes = "seat 4, handles 2"
        logSession(&data, daysAgo: 2, [(ids["Leg press"]!, 60, 12, 3)])
        data.startSession(templateId: data.templates[0].id)
        data.timer = RestTimerState(exerciseId: ids["Leg press"]!, label: "Leg press",
                                    endsAt: Date().addingTimeInterval(120), durationSec: 120)

        let encoded = try data.exportJSON()
        let decoded = try AppData.decoder().decode(AppData.self, from: encoded)

        XCTAssertEqual(decoded.exercises.map(\.name), data.exercises.map(\.name))
        XCTAssertEqual(decoded.exercises[0].notes, "seat 4, handles 2")
        XCTAssertEqual(decoded.sessions.count, data.sessions.count)
        XCTAssertEqual(decoded.activeSessionId, data.activeSessionId)
        XCTAssertEqual(decoded.timer?.durationSec, 120)
        XCTAssertEqual(decoded.settings.defaultRestSec, 90)
        XCTAssertEqual(decoded.sessions[0].entries[0].sets[0].weight, 60)
    }

    func testExportIsReadableJSON() throws {
        var (data, _) = seeded()
        data.startSession(templateId: data.templates[0].id)
        let json = String(data: try data.exportJSON(), encoding: .utf8)!

        XCTAssertTrue(json.contains("\"Leg press\""))
        XCTAssertTrue(json.contains("\n"), "pretty-printed so a human can read the backup")
    }

    func testDecodingToleratesAFileFromAnOlderBuild() throws {
        // Only the fields that existed at v1 — everything else must default.
        let json = """
        {"version":1,"exercises":[{"id":"ex_1","name":"Leg press"}],"templates":[],"sessions":[]}
        """.data(using: .utf8)!

        let decoded = try AppData.decoder().decode(AppData.self, from: json)
        XCTAssertEqual(decoded.exercises[0].name, "Leg press")
        XCTAssertEqual(decoded.exercises[0].notes, "")
        XCTAssertNil(decoded.exercises[0].restSec)
        XCTAssertEqual(decoded.settings.defaultRestSec, 90)
    }

    func testAMalformedFieldFallsBackInsteadOfLosingEverything() throws {
        // "sets" is a string where an array belongs, and restSec is nonsense.
        let json = """
        {"version":1,
         "exercises":[{"id":"ex_1","name":"Leg press","restSec":"oops","notes":"seat 4"}],
         "templates":[{"id":"t1","name":"Full Body","items":"broken"}],
         "sessions":[]}
        """.data(using: .utf8)!

        let decoded = try AppData.decoder().decode(AppData.self, from: json)
        XCTAssertEqual(decoded.exercises[0].name, "Leg press")
        XCTAssertEqual(decoded.exercises[0].notes, "seat 4", "the good fields still survive")
        XCTAssertNil(decoded.exercises[0].restSec, "the bad one falls back")
        XCTAssertEqual(decoded.templates[0].items, [], "and so does the bad array")
    }

    func testASetMissingItsDoneFlagIsTreatedAsNotDone() throws {
        let json = """
        {"sessions":[{"id":"s1","templateId":"t1","name":"Full Body",
          "startedAt":"2026-01-01T10:00:00Z","finishedAt":"2026-01-01T11:00:00Z",
          "entries":[{"id":"e1","exerciseId":"ex_1","name":"Leg press","target":12,
            "sets":[{"id":"st1","weight":60,"reps":12}]}]}]}
        """.data(using: .utf8)!

        let decoded = try AppData.decoder().decode(AppData.self, from: json)
        let entry = decoded.sessions[0].entries[0]
        XCTAssertEqual(entry.sets[0].weight, 60)
        XCTAssertFalse(entry.sets[0].done)
        XCTAssertFalse(entry.hasWork, "an un-ticked set is not history")
    }

    func testGarbageFileThrowsRatherThanSilentlyReturningNothing() {
        let json = "this is not json at all".data(using: .utf8)!
        // Store catches this and preserves the original file; the decoder's job
        // is simply to be honest that it failed.
        XCTAssertThrowsError(try AppData.decoder().decode(AppData.self, from: json))
    }
}

final class LibraryAndRestoreTests: XCTestCase {

    func testDeletingAnExerciseRemovesItFromEveryTemplateButNotHistory() {
        var data = AppData.seed()
        let legPress = data.exercises[0].id
        data.startSession(templateId: data.templates[0].id)
        data.sessions[0].entries[0].sets[0].done = true
        data.finishSession()

        data.deleteExercise(id: legPress)

        XCTAssertNil(data.exercise(id: legPress))
        XCTAssertFalse(data.templates[0].items.contains { $0.exerciseId == legPress })
        XCTAssertEqual(data.templates[0].items.count, 5)
        XCTAssertEqual(data.sessions[0].entries[0].name, "Leg press", "history keeps its snapshot")
        XCTAssertNotNil(data.lastEntry(for: legPress), "and the lookup still works on the id")
    }

    func testDeletingAnExerciseLeavesOtherTemplatesAlone() {
        var data = AppData.seed()
        let plank = data.exercises[5].id
        data.templates.append(WorkoutTemplate(name: "Core", items: [TemplateItem(exerciseId: plank, sets: 3, target: 60)]))

        data.deleteExercise(id: data.exercises[0].id)

        XCTAssertEqual(data.templates[1].items.count, 1)
        XCTAssertEqual(data.orderedExercises.count, 5)
    }

    func testRestoreRoundTripsAnExport() throws {
        var original = AppData.seed()
        original.exercises[0].notes = "seat 4"
        original.startSession(templateId: original.templates[0].id)
        original.sessions[0].entries[0].sets[0].done = true
        original.sessions[0].entries[0].sets[0].weight = 60
        original.finishSession()
        original.settings.lastExportedAt = Date()

        let restored = try AppData.restore(from: try original.exportJSON())

        XCTAssertEqual(restored.exercises.map(\.name), original.exercises.map(\.name))
        XCTAssertEqual(restored.exercises[0].notes, "seat 4")
        XCTAssertEqual(restored.sessions.count, 1)
        XCTAssertEqual(restored.sessions[0].entries[0].sets[0].weight, 60)
        XCTAssertNotNil(restored.settings.lastExportedAt)
    }

    func testRestoreRefusesGarbage() {
        XCTAssertThrowsError(try AppData.restore(from: "not json".data(using: .utf8)!)) { error in
            XCTAssertEqual(error as? RestoreError, .unreadable)
        }
    }

    func testRestoreRefusesAnEmptyStore() {
        let empty = "{\"version\":1,\"exercises\":[],\"templates\":[],\"sessions\":[]}".data(using: .utf8)!
        XCTAssertThrowsError(try AppData.restore(from: empty)) { error in
            XCTAssertEqual(error as? RestoreError, .empty)
        }
    }

    func testRestoreDropsAnExpiredTimerAndADanglingActiveSession() throws {
        var data = AppData.seed()
        data.activeSessionId = "s_gone"
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(-60), durationSec: 90)

        let restored = try AppData.restore(from: try data.exportJSON())

        XCTAssertNil(restored.activeSessionId)
        XCTAssertNil(restored.timer)
    }

    func testRestoreKeepsALiveTimerAndARealActiveSession() throws {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(60), durationSec: 90)

        let restored = try AppData.restore(from: try data.exportJSON())

        XCTAssertEqual(restored.activeSessionId, data.activeSessionId)
        XCTAssertNotNil(restored.timer)
    }

    func testPreviewDescribesWhatARestoreWouldBring() {
        var data = AppData.seed()
        for days in [10, 5, 1] {
            data.startSession(templateId: data.templates[0].id)
            let i = data.activeSessionIndex!
            data.sessions[i].startedAt = Date().addingTimeInterval(TimeInterval(-days * 86_400))
            data.sessions[i].entries[0].sets[0].done = true
            data.finishSession(at: data.sessions[i].startedAt.addingTimeInterval(3600))
        }
        data.startSession(templateId: data.templates[0].id)

        let preview = data.preview
        XCTAssertEqual(preview.exerciseCount, 6)
        XCTAssertEqual(preview.templateCount, 1)
        XCTAssertEqual(preview.sessionCount, 3, "in-progress session is not counted as history")
        XCTAssertTrue(preview.hasActiveSession)
        XCTAssertTrue(preview.firstSession! < preview.lastSession!)
    }

    func testDeletingASessionRemovesItAndAnyTimerItOwned() {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        let active = data.activeSessionId!
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(60), durationSec: 90)

        data.deleteSession(id: active)

        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertNil(data.activeSessionId)
        XCTAssertNil(data.timer, "the rest timer belonged to the session that just went")
    }

    func testDeletingOneSessionLeavesTheOthers() {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        data.sessions[0].entries[0].sets[0].done = true
        data.finishSession()
        let keep = data.sessions[0].id
        data.startSession(templateId: data.templates[0].id)
        let drop = data.activeSessionId!

        data.deleteSession(id: drop)

        XCTAssertEqual(data.sessions.map(\.id), [keep])
    }

    func testPruneLeavesARunningTimerAlone() {
        var data = AppData.seed()
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(30), durationSec: 90)
        data.pruneExpiredTimer()
        XCTAssertNotNil(data.timer)
    }
}

/// Ticking a set off is a claim that the set happened, so it has to carry what
/// was actually done — and what that means depends on how the exercise is
/// measured.
final class SetCompletionTests: XCTestCase {

    private func entry(weight: Double?, reps: Int?, measure: Measure) -> SessionEntry {
        SessionEntry(
            exerciseId: "ex_1",
            name: "Chest press",
            targetMin: 8,
            targetMax: 12,
            sets: [SetEntry(weight: weight, reps: reps)],
            measure: measure
        )
    }

    private func canComplete(_ weight: Double?, _ reps: Int?, _ measure: Measure) -> Bool {
        entry(weight: weight, reps: reps, measure: measure).canComplete(setIndex: 0)
    }

    // Weight: both numbers, both above zero.
    func testWeightedNeedsAWeightAndReps() {
        XCTAssertTrue(canComplete(60, 12, .weight))
        XCTAssertFalse(canComplete(nil, 12, .weight))
        XCTAssertFalse(canComplete(60, nil, .weight))
        XCTAssertFalse(canComplete(0, 12, .weight), "zero is not a weight")
        XCTAssertFalse(canComplete(60, 0, .weight), "zero is not a rep count")
    }

    // Assisted: the assistance must be entered, and zero means unassisted.
    func testAssistedNeedsRepsAndAnEnteredAssistance() {
        XCTAssertTrue(canComplete(20, 8, .assisted))
        XCTAssertTrue(canComplete(0, 8, .assisted), "0 kg assistance is a real, unassisted rep")
        XCTAssertFalse(canComplete(nil, 8, .assisted), "the assistance has to be entered, even if it's 0")
        XCTAssertFalse(canComplete(-5, 8, .assisted))
        XCTAssertFalse(canComplete(20, 0, .assisted))
    }

    // Bodyweight: reps are the whole record.
    func testBodyweightNeedsOnlyReps() {
        XCTAssertTrue(canComplete(nil, 8, .bodyweight))
        XCTAssertFalse(canComplete(nil, nil, .bodyweight))
        XCTAssertFalse(canComplete(nil, 0, .bodyweight))
    }

    // Time: seconds live in `reps`.
    func testTimedNeedsOnlySeconds() {
        XCTAssertTrue(canComplete(nil, 40, .time))
        XCTAssertFalse(canComplete(nil, nil, .time))
        XCTAssertFalse(canComplete(nil, 0, .time))
    }

    func testAnOutOfRangeSetIsNeverCompletable() {
        XCTAssertFalse(entry(weight: 60, reps: 12, measure: .weight).canComplete(setIndex: 5))
    }

    /// The flag is snapshotted like `name` and `target`, so flipping or deleting
    /// the exercise later can't retroactively invalidate a logged session.
    func testTheEntrySnapshotsTheExercisesMeasure() {
        var data = AppData.seed()
        let pullUp = Exercise(name: "Pull-up", measure: .bodyweight)
        data.exercises.append(pullUp)

        let entry = data.buildEntry(exerciseId: pullUp.id, sets: 3, target: 8)
        XCTAssertEqual(entry.measure, .bodyweight)

        data.deleteExercise(id: pullUp.id)
        XCTAssertEqual(entry.measure, .bodyweight, "a logged entry keeps its own copy")
    }

    func testAnOlderBackupDecodesAsWeighted() throws {
        let json = #"{"id":"ex_1","name":"Chest press","notes":""}"#
        let exercise = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        XCTAssertEqual(exercise.name, "Chest press")
        XCTAssertEqual(exercise.measure, .weight)
    }
}

/// A catalogue to build from, and the standard splits made out of it.
final class ExerciseCatalogueTests: XCTestCase {

    func testTheCatalogueCoversEveryMuscleGroup() {
        for muscle in MuscleGroup.allCases {
            XCTAssertFalse(ExerciseCatalogue.grouped(muscle).isEmpty, "\(muscle) has nothing in it")
        }
    }

    func testCatalogueNamesAreUnique() {
        let names = ExerciseCatalogue.all.map { $0.name.lowercased() }
        XCTAssertEqual(names.count, Set(names).count)
    }

    /// The catalogue owns rest and bodyweight defaults, so a preset naming
    /// something outside it would silently create a bare exercise.
    func testEveryPresetItemExistsInTheCatalogue() {
        for preset in WorkoutPreset.catalogue {
            for item in preset.items {
                XCTAssertNotNil(ExerciseCatalogue.entry(named: item.exerciseName),
                                "\(preset.name) names \(item.exerciseName), which isn't in the catalogue")
            }
        }
    }

    /// Everything seeded on first launch must match the catalogue by name, or
    /// adding a standard workout would duplicate the user's own exercises.
    func testSeededExercisesAreAllInTheCatalogue() {
        for exercise in AppData.seed().exercises {
            XCTAssertNotNil(ExerciseCatalogue.entry(named: exercise.name), exercise.name)
        }
    }

    func testAddingACatalogueExerciseCarriesItsDefaults() throws {
        var data = AppData()

        let id = data.addExercise(named: "Pull-up")

        let created = try XCTUnwrap(data.exercises.first { $0.id == id })
        XCTAssertEqual(created.name, "Pull-up")
        XCTAssertEqual(created.measure, .bodyweight)
        XCTAssertEqual(created.restSec, 150)
    }

    func testTheCatalogueKnowsHowEachExerciseIsMeasured() {
        XCTAssertEqual(ExerciseCatalogue.entry(named: "Plank")?.measure, .time)
        XCTAssertEqual(ExerciseCatalogue.entry(named: "Assisted pull-up")?.measure, .assisted)
        XCTAssertEqual(ExerciseCatalogue.entry(named: "Assisted dip")?.measure, .assisted)
        XCTAssertEqual(ExerciseCatalogue.entry(named: "Pull-up")?.measure, .bodyweight)
        XCTAssertEqual(ExerciseCatalogue.entry(named: "Chest press")?.measure, .weight)
    }

    func testAddingAnExerciseTwiceReusesTheFirst() {
        var data = AppData.seed()
        let before = data.exercises.count

        let first = data.addExercise(named: "chest press")
        let second = data.addExercise(named: "Chest press")

        XCTAssertEqual(first, second)
        XCTAssertEqual(data.exercises.count, before, "matched by name, case-insensitively")
    }

    func testAnExerciseOutsideTheCatalogueIsStillCreated() throws {
        var data = AppData()

        let id = data.addExercise(named: "Sled push")

        let created = try XCTUnwrap(data.exercises.first { $0.id == id })
        XCTAssertEqual(created.name, "Sled push")
        XCTAssertEqual(created.measure, .weight)
        XCTAssertNil(created.restSec)
    }
}

/// Standard workouts people expect to find, without hand-building them.
final class PresetWorkoutTests: XCTestCase {

    func testEveryPresetIsNonEmptyAndNamed() {
        XCTAssertFalse(WorkoutPreset.catalogue.isEmpty)
        for preset in WorkoutPreset.catalogue {
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.items.isEmpty, "\(preset.name) has no exercises")
        }
    }

    func testAddingAPresetCreatesTheWorkoutAndItsMissingExercises() throws {
        var data = AppData()
        let preset = WorkoutPreset.catalogue[0]

        let id = try XCTUnwrap(data.addPreset(preset))

        let template = try XCTUnwrap(data.template(id: id))
        XCTAssertEqual(template.name, preset.name)
        XCTAssertEqual(template.items.count, preset.items.count)
        XCTAssertEqual(data.exercises.count, preset.items.count)
    }

    /// Adding "Push" after "Upper body" must not create a second Chest press.
    func testAPresetReusesExercisesAlreadyInTheLibrary() {
        var data = AppData.seed()
        let before = data.exercises.count
        let preset = WorkoutPreset(
            name: "Reuse test",
            summary: "",
            items: [PresetItem(exerciseName: "chest press", sets: 3, range: 10...10)]
        )

        data.addPreset(preset)

        XCTAssertEqual(data.exercises.count, before, "matched an existing exercise by name")
        XCTAssertEqual(data.templates.last?.items.first?.exerciseId,
                       data.exercises.first { $0.name == "Chest press" }?.id)
    }

    func testAddingTheSamePresetTwiceDoesNotCollideOnName() {
        var data = AppData()
        let preset = WorkoutPreset.catalogue[0]

        data.addPreset(preset)
        data.addPreset(preset)

        XCTAssertEqual(data.templates.count, 2)
        XCTAssertNotEqual(data.templates[0].name, data.templates[1].name)
    }

    /// The whole point of the fix: one exercise out of six, not six minus five.
    func testAPresetCanBringInJustTheChosenExercises() throws {
        var data = AppData()
        let upper = try XCTUnwrap(WorkoutPreset.catalogue.first { $0.name == "Upper body" })

        let id = try XCTUnwrap(data.addPreset(upper, including: ["Shoulder press"]))

        let template = try XCTUnwrap(data.template(id: id))
        XCTAssertEqual(template.items.count, 1)
        XCTAssertEqual(data.exercises.count, 1, "only the chosen exercise reaches the library")
        XCTAssertEqual(data.exercises.first?.name, "Shoulder press")
    }

    func testChoosingNothingAddsNoWorkoutAtAll() {
        var data = AppData()
        let preset = WorkoutPreset.catalogue[0]

        XCTAssertNil(data.addPreset(preset, including: []))
        XCTAssertTrue(data.templates.isEmpty)
        XCTAssertTrue(data.exercises.isEmpty)
    }

    func testAPresetKeepsTheSetsAndRepsOfTheChosenExercises() throws {
        var data = AppData()
        let push = try XCTUnwrap(WorkoutPreset.catalogue.first { $0.name == "Push" })

        let id = try XCTUnwrap(data.addPreset(push, including: ["Lateral raise"]))

        let template = try XCTUnwrap(data.template(id: id))
        XCTAssertEqual(template.items.first?.sets, 3)
        XCTAssertEqual(template.items.first?.targetMin, 12)
        XCTAssertEqual(template.items.first?.targetMax, 15)
    }

    func testEveryPresetItemHasASaneRange() {
        for preset in WorkoutPreset.catalogue {
            for item in preset.items {
                let lo = try? XCTUnwrap(item.targetMin, "\(item.exerciseName) has no lower target")
                let hi = try? XCTUnwrap(item.targetMax, "\(item.exerciseName) has no upper target")
                if let lo, let hi { XCTAssertLessThanOrEqual(lo, hi, item.exerciseName) }
            }
        }
        let plank = WorkoutPreset.catalogue.flatMap(\.items).first { $0.exerciseName == "Plank" }
        XCTAssertEqual(plank?.targetMin, 30)
        XCTAssertEqual(plank?.targetMax, 60)
    }
}


/// Double progression: climb the rep range at a weight, then move the weight
/// and drop back to the bottom of the range. Each measure moves differently.
/// Prefill across the four measures. Nothing here computes a number: each
/// case asserts that today opens showing exactly what last session held.
final class PrefillAcrossMeasuresTests: XCTestCase {

    /// One exercise, one template with the given range, one finished session
    /// with the given per-set numbers. Returns the exercise id.
    private func history(measure: Measure, range: (Int, Int),
                         sets: [(weight: Double?, reps: Int)], into data: inout AppData) -> String {
        let exercise = Exercise(name: "X", measure: measure)
        data.exercises = [exercise]
        data.templates = [WorkoutTemplate(name: "T", items: [
            TemplateItem(exerciseId: exercise.id, sets: sets.count, targetMin: range.0, targetMax: range.1)
        ])]
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        for (n, set) in sets.enumerated() {
            data.sessions[i].entries[0].sets[n].weight = set.weight
            data.sessions[i].entries[0].sets[n].reps = set.reps
            data.sessions[i].entries[0].sets[n].done = true
        }
        data.finishSession()
        return exercise.id
    }

    func testWeightHoldsEvenAtTheTopOfTheRange() {
        var data = AppData()
        _ = history(measure: .weight, range: (8, 12), sets: [(60, 12), (60, 12), (60, 12)], into: &data)

        data.startSession(templateId: data.templates[0].id)
        let entry = data.activeSession!.entries[0]

        XCTAssertEqual(entry.sets.map(\.weight), [60, 60, 60], "topping the range is not a bump")
        XCTAssertEqual(entry.sets.map(\.reps), [12, 12, 12], "and reps do not reset")
    }

    func testWeightRepeatsMidRangeSetForSet() {
        var data = AppData()
        _ = history(measure: .weight, range: (8, 12), sets: [(60, 10), (60, 9), (60, 8)], into: &data)

        data.startSession(templateId: data.templates[0].id)
        XCTAssertEqual(data.activeSession!.entries[0].sets.map(\.reps), [10, 9, 8])
    }

    func testAssistedPrefillsTheLeastAssistance() {
        var data = AppData()
        let id = history(measure: .assisted, range: (8, 12), sets: [(20, 12), (15, 12), (18, 12)], into: &data)

        XCTAssertEqual(data.lastTime(for: id).weight, 15, "lower assistance is the better set")

        data.startSession(templateId: data.templates[0].id)
        XCTAssertEqual(data.activeSession!.entries[0].sets.map(\.weight), [15, 15, 15])
    }

    func testBodyweightPrefillsRepsAndNeverAWeight() {
        var data = AppData()
        let id = history(measure: .bodyweight, range: (8, 12), sets: [(nil, 12), (nil, 12), (nil, 12)], into: &data)

        XCTAssertNil(data.lastTime(for: id).weight)

        data.startSession(templateId: data.templates[0].id)
        let entry = data.activeSession!.entries[0]
        XCTAssertTrue(entry.sets.allSatisfy { $0.weight == nil })
        XCTAssertEqual(entry.sets.map(\.reps), [12, 12, 12])
    }

    func testTimedWorkPrefillsTheSameSeconds() {
        var data = AppData()
        _ = history(measure: .time, range: (30, 60), sets: [(nil, 40), (nil, 40), (nil, 40)], into: &data)

        data.startSession(templateId: data.templates[0].id)
        XCTAssertEqual(data.activeSession!.entries[0].sets.map(\.reps), [40, 40, 40],
                       "no five-second nudge")
    }

    func testWithNoHistoryTheRangeBottomIsUsed() {
        var data = AppData()
        let exercise = Exercise(name: "X", measure: .weight)
        data.exercises = [exercise]
        data.templates = [WorkoutTemplate(name: "T", items: [
            TemplateItem(exerciseId: exercise.id, sets: 3, targetMin: 8, targetMax: 12)
        ])]

        data.startSession(templateId: data.templates[0].id)
        let entry = data.activeSession!.entries[0]
        XCTAssertTrue(entry.sets.allSatisfy { $0.weight == nil })
        XCTAssertEqual(entry.sets.map(\.reps), [8, 8, 8])
    }
}

final class MeasureAndRangeDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try AppData.decoder().decode(type, from: Data(json.utf8))
    }

    func testAnOldBodyweightFlagBecomesTheBodyweightMeasure() throws {
        XCTAssertEqual(try decode(Exercise.self, #"{"id":"e","name":"Pull-up","isBodyweight":true}"#).measure, .bodyweight)
        XCTAssertEqual(try decode(Exercise.self, #"{"id":"e","name":"Chest press","isBodyweight":false}"#).measure, .weight)
    }

    func testAMeasureDecodesByName() throws {
        XCTAssertEqual(try decode(Exercise.self, #"{"id":"e","name":"Plank","measure":"time"}"#).measure, .time)
        XCTAssertEqual(try decode(Exercise.self, #"{"id":"e","name":"Dip","measure":"assisted"}"#).measure, .assisted)
    }

    func testAnUnknownMeasureFallsBackToWeight() throws {
        XCTAssertEqual(try decode(Exercise.self, #"{"id":"e","name":"X","measure":"telepathy"}"#).measure, .weight)
    }

    func testAnOldSingleTargetBecomesBothEndsOfTheRange() throws {
        let item = try decode(TemplateItem.self, #"{"exerciseId":"e","sets":3,"target":10}"#)
        XCTAssertEqual(item.targetMin, 10)
        XCTAssertEqual(item.targetMax, 10)

        let entry = try decode(SessionEntry.self, #"{"id":"en","exerciseId":"e","name":"X","target":12,"bodyweight":true}"#)
        XCTAssertEqual(entry.targetMin, 12)
        XCTAssertEqual(entry.targetMax, 12)
        XCTAssertEqual(entry.measure, .bodyweight)
    }

    func testARangeRoundTrips() throws {
        var data = AppData()
        let exercise = Exercise(name: "Plank", measure: .time)
        data.exercises = [exercise]
        data.templates = [WorkoutTemplate(name: "T", items: [
            TemplateItem(exerciseId: exercise.id, sets: 3, targetMin: 30, targetMax: 60)
        ])]
        data.startSession(templateId: data.templates[0].id)

        let restored = try AppData.decoder().decode(AppData.self, from: try data.exportJSON())

        XCTAssertEqual(restored.exercises[0].measure, .time)
        XCTAssertEqual(restored.templates[0].items[0].targetMin, 30)
        XCTAssertEqual(restored.templates[0].items[0].targetMax, 60)
        XCTAssertEqual(restored.sessions[0].entries[0].measure, .time)
        XCTAssertEqual(restored.sessions[0].entries[0].targetMax, 60)
    }

    func testTheExportNoLongerWritesTheOldKeys() throws {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        let json = String(decoding: try data.exportJSON(), as: UTF8.self)
        XCTAssertFalse(json.contains("\"isBodyweight\""))
        XCTAssertFalse(json.contains("\"bodyweight\""))
        XCTAssertFalse(json.contains("\"target\""))
        XCTAssertTrue(json.contains("\"measure\""))
    }
}

/// Progress plots whatever the exercise is measured in.
final class MeasuredProgressTests: XCTestCase {

    private func log(_ data: inout AppData, daysAgo: Int, sets: [(Double?, Int)]) {
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        data.sessions[i].startedAt = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        for (n, set) in sets.enumerated() where n < data.sessions[i].entries[0].sets.count {
            data.sessions[i].entries[0].sets[n].weight = set.0
            data.sessions[i].entries[0].sets[n].reps = set.1
            data.sessions[i].entries[0].sets[n].done = true
        }
        data.finishSession(at: data.sessions[i].startedAt.addingTimeInterval(3600))
    }

    private func store(measure: Measure) -> AppData {
        var data = AppData()
        let exercise = Exercise(name: "X", measure: measure)
        data.exercises = [exercise]
        data.templates = [WorkoutTemplate(name: "T", items: [TemplateItem(exerciseId: exercise.id, sets: 3, target: 8)])]
        return data
    }

    func testAssistedPlotsTheLeastAssistanceAndSaysLowerIsBetter() {
        var data = store(measure: .assisted)
        log(&data, daysAgo: 4, sets: [(20, 8), (20, 8), (25, 8)])
        log(&data, daysAgo: 1, sets: [(15, 8), (15, 8), (15, 8)])

        let series = data.progressSeries(for: data.exercises[0].id)
        XCTAssertEqual(series.map(\.value), [20, 15], "the best set is the one with the least help")
        XCTAssertEqual(series.map(\.measure), [.assisted, .assisted])
        XCTAssertTrue(Measure.assisted.lowerIsBetter)
        XCTAssertFalse(Measure.weight.lowerIsBetter)
    }

    func testTimedWorkPlotsSeconds() {
        var data = store(measure: .time)
        log(&data, daysAgo: 4, sets: [(nil, 40), (nil, 40), (nil, 35)])
        log(&data, daysAgo: 1, sets: [(nil, 45), (nil, 45), (nil, 45)])

        let series = data.progressSeries(for: data.exercises[0].id)
        XCTAssertEqual(series.map(\.value), [40, 45])
        XCTAssertEqual(Measure.time.unit, "s")
    }

    func testWeightedWorkKeepsTheHeaviestSetAndPlotsTheEstimatedMax() {
        var data = store(measure: .weight)
        log(&data, daysAgo: 1, sets: [(60, 8), (62.5, 8), (60, 8)])
        let point = data.progressSeries(for: data.exercises[0].id)[0]
        XCTAssertEqual(point.topWeight, 62.5)
        XCTAssertEqual(point.value ?? 0, 62.5 * (1 + 8.0 / 30), accuracy: 0.01)
    }
}
