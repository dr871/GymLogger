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
            var entry = data.buildEntry(exerciseId: item.exerciseId, sets: item.sets, target: item.target)
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
        XCTAssertEqual(data.templates[0].items.map(\.target), [12, 12, 12, 12, 12, 40])
    }

    func testLegPressRestsLongerThanTheRest() {
        let (data, ids) = seeded()
        XCTAssertEqual(data.restSec(for: ids["Leg press"]!), 120)
        XCTAssertEqual(data.restSec(for: ids["Chest press"]!), 90)
        XCTAssertEqual(data.increment(for: ids["Leg press"]!), 2.5)
    }

    // MARK: - First session

    func testFirstSessionHasNoWeightButPrefillsTargetReps() {
        let (data, ids) = seeded()
        let entry = data.buildEntry(exerciseId: ids["Leg press"]!, sets: 3, target: 12)
        XCTAssertEqual(entry.sets.count, 3)
        XCTAssertNil(entry.sets[0].weight)
        XCTAssertEqual(entry.sets[0].reps, 12)
        XCTAssertFalse(entry.suggested)
    }

    // MARK: - The suggestion rule

    func testHittingEveryRepEarnsTheBump() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])

        let suggestion = data.suggestion(for: legPress)
        XCTAssertTrue(suggestion.earned)
        XCTAssertEqual(suggestion.weight, 62.5)
        XCTAssertEqual(suggestion.lastWeight, 60)
    }

    func testMissingRepsOnOneSetHoldsTheWeight() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        var session = logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])
        session.entries[0].sets[2].reps = 10          // last set fell short
        data.sessions[data.sessions.count - 1] = session

        let suggestion = data.suggestion(for: legPress)
        XCTAssertFalse(suggestion.earned)
        XCTAssertEqual(suggestion.weight, 60, "should prefill last weight, not a bump")
    }

    func testAnUntickedSetHoldsTheWeight() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 2, [(legPress, 60, 12, 2)])   // only 2 of 3 ticked

        let suggestion = data.suggestion(for: legPress)
        XCTAssertFalse(suggestion.earned)
        XCTAssertEqual(suggestion.weight, 60)
    }

    func testBeatingTheTargetStillEarnsTheBump() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        logSession(&data, daysAgo: 2, [(legPress, 60, 14, 3)])

        XCTAssertTrue(data.suggestion(for: legPress).earned)
        XCTAssertEqual(data.suggestion(for: legPress).weight, 62.5)
    }

    func testBodyweightWorkGetsNoWeightSuggestion() {
        var (data, ids) = seeded()
        let plank = ids["Plank"]!
        logSession(&data, daysAgo: 2, [(plank, nil, 40, 3)])

        let suggestion = data.suggestion(for: plank)
        XCTAssertFalse(suggestion.earned, "nothing to bump when no weight was logged")
        XCTAssertNil(suggestion.weight)
    }

    func testPerExerciseIncrementOverridesTheDefault() {
        var (data, ids) = seeded()
        let legPress = ids["Leg press"]!
        data.exercises[0].increment = 5
        logSession(&data, daysAgo: 2, [(legPress, 60, 12, 3)])

        XCTAssertEqual(data.suggestion(for: legPress).weight, 65)
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

        XCTAssertEqual(entry.sets.map(\.weight), [62.5, 62.5, 62.5])
        XCTAssertEqual(entry.sets.map(\.reps), [12, 12, 12])
        XCTAssertTrue(entry.sets.allSatisfy { !$0.done })
        XCTAssertTrue(entry.suggested)
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
        XCTAssertEqual(decoded.settings.defaultIncrement, 2.5)
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

    func testPruneLeavesARunningTimerAlone() {
        var data = AppData.seed()
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(30), durationSec: 90)
        data.pruneExpiredTimer()
        XCTAssertNotNil(data.timer)
    }
}

/// Ticking a set off is a claim that the set happened, so it has to carry what
/// was actually lifted. Bodyweight work is the deliberate exception.
final class SetCompletionTests: XCTestCase {

    private func entry(weight: Double?, reps: Int?, bodyweight: Bool) -> SessionEntry {
        SessionEntry(
            exerciseId: "ex_1",
            name: "Chest press",
            target: 12,
            sets: [SetEntry(weight: weight, reps: reps)],
            bodyweight: bodyweight
        )
    }

    func testALoadedSetNeedsAWeight() {
        XCTAssertFalse(entry(weight: nil, reps: 12, bodyweight: false).canComplete(setIndex: 0))
    }

    func testALoadedSetNeedsReps() {
        XCTAssertFalse(entry(weight: 60, reps: nil, bodyweight: false).canComplete(setIndex: 0))
    }

    func testZeroIsNotAWeight() {
        XCTAssertFalse(entry(weight: 0, reps: 12, bodyweight: false).canComplete(setIndex: 0))
    }

    func testZeroIsNotARepCount() {
        XCTAssertFalse(entry(weight: 60, reps: 0, bodyweight: false).canComplete(setIndex: 0))
    }

    func testAFullyLoggedSetCanBeTicked() {
        XCTAssertTrue(entry(weight: 60, reps: 12, bodyweight: false).canComplete(setIndex: 0))
    }

    func testBodyweightWorkNeedsOnlyReps() {
        XCTAssertTrue(entry(weight: nil, reps: 8, bodyweight: true).canComplete(setIndex: 0))
    }

    func testBodyweightWorkStillNeedsReps() {
        XCTAssertFalse(entry(weight: nil, reps: nil, bodyweight: true).canComplete(setIndex: 0))
    }

    func testAnOutOfRangeSetIsNeverCompletable() {
        XCTAssertFalse(entry(weight: 60, reps: 12, bodyweight: false).canComplete(setIndex: 5))
    }

    /// The flag is snapshotted like `name` and `target`, so flipping or deleting
    /// the exercise later can't retroactively invalidate a logged session.
    func testTheEntrySnapshotsTheExercisesBodyweightFlag() {
        var data = AppData.seed()
        let pullUp = Exercise(name: "Pull-up", isBodyweight: true)
        data.exercises.append(pullUp)

        let entry = data.buildEntry(exerciseId: pullUp.id, sets: 3, target: 8)
        XCTAssertTrue(entry.bodyweight)

        data.deleteExercise(id: pullUp.id)
        XCTAssertTrue(entry.bodyweight, "a logged entry keeps its own copy")
    }

    func testAnOlderBackupDecodesAsNotBodyweight() throws {
        let json = #"{"id":"ex_1","name":"Chest press","notes":""}"#
        let exercise = try JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        XCTAssertEqual(exercise.name, "Chest press")
        XCTAssertFalse(exercise.isBodyweight)
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
        XCTAssertTrue(created.isBodyweight)
        XCTAssertEqual(created.restSec, 150)
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
        XCTAssertFalse(created.isBodyweight)
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
            items: [PresetItem(exerciseName: "chest press", sets: 3, target: 10)]
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
        XCTAssertEqual(template.items.first?.target, 15)
    }
}
