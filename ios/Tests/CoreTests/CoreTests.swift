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
