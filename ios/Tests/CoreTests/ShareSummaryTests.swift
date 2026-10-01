import XCTest
@testable import GymLoggerCore

/// A finished session, built at a fixed date so the text is deterministic.
private func session(_ data: inout AppData, name: String = "Full Body",
                     daysAgo: Int = 0,
                     entries: [(String, Measure, [(Double?, Int)])],
                     minutes: Int = 45) -> String {
    let base = Calendar(identifier: .iso8601)
        .date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 18))!
    let start = base.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
    var built: [SessionEntry] = []
    for (name, measure, sets) in entries {
        let id = data.exercises.first { $0.name == name }?.id ?? {
            let e = Exercise(name: name, measure: measure)
            data.exercises.append(e)
            return e.id
        }()
        built.append(SessionEntry(
            exerciseId: id, name: name, targetMin: 8, targetMax: 12,
            sets: sets.map { SetEntry(weight: $0.0, reps: $0.1, done: true) },
            measure: measure
        ))
    }
    let s = Session(templateId: "t", name: name, startedAt: start,
                    finishedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                    entries: built)
    data.sessions.append(s)
    return s.id
}

final class ShareSummaryTests: XCTestCase {

    func testSummaryLeadsWithTheWorkoutDateAndTotals() throws {
        var data = AppData()
        let id = session(&data, entries: [("Leg press", .weight, [(80, 12), (80, 12), (80, 12)])])
        let text = try XCTUnwrap(data.shareText(for: id))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertTrue(lines[0].hasPrefix("Full Body"), lines[0])
        XCTAssertTrue(lines[0].contains("22 Sep"), lines[0])
        XCTAssertTrue(lines[1].contains("45 min"), lines[1])
        XCTAssertTrue(lines[1].contains("3 sets"), lines[1])
    }

    func testOneLinePerExerciseInTheExerciseUnits() throws {
        var data = AppData()
        let id = session(&data, entries: [
            ("Leg press", .weight, [(80, 12), (80, 12), (80, 11)]),
            ("Assisted pull-up", .assisted, [(20, 8), (20, 8)]),
            ("Push-up", .bodyweight, [(nil, 15), (nil, 12)]),
            ("Plank", .time, [(nil, 45), (nil, 40)]),
        ])
        let text = try XCTUnwrap(data.shareText(for: id))

        XCTAssertTrue(text.contains("Leg press — 80 kg × 12, 12, 11"), text)
        XCTAssertTrue(text.contains("Assisted pull-up — 20 kg assist × 8, 8"), text)
        XCTAssertTrue(text.contains("Push-up — 15, 12 reps"), text)
        XCTAssertTrue(text.contains("Plank — 45s, 40s"), text)
    }

    func testAChangingWeightIsShownPerSet() throws {
        var data = AppData()
        let id = session(&data, entries: [("Leg press", .weight, [(80, 12), (82.5, 10)])])
        let text = try XCTUnwrap(data.shareText(for: id))
        XCTAssertTrue(text.contains("Leg press — 80 kg × 12, 82.5 kg × 10"), text)
    }

    func testWarmupsAndUntickedSetsAreLeftOut() throws {
        var data = AppData()
        let id = session(&data, entries: [("Leg press", .weight, [(80, 12)])])
        let i = data.sessions.firstIndex { $0.id == id }!
        data.sessions[i].entries[0].sets.insert(SetEntry(weight: 40, reps: 10, done: true, warmup: true), at: 0)
        data.sessions[i].entries[0].sets.append(SetEntry(weight: 999, reps: 1, done: false))

        let text = try XCTUnwrap(data.shareText(for: id))
        XCTAssertFalse(text.contains("40 kg"), text)
        XCTAssertFalse(text.contains("999"), text)
        XCTAssertTrue(text.contains("1 set"), text)
    }

    func testAnExerciseWithNothingLoggedIsLeftOut() throws {
        var data = AppData()
        let id = session(&data, entries: [("Leg press", .weight, [(80, 12)]), ("Plank", .time, [])])
        let text = try XCTUnwrap(data.shareText(for: id))
        XCTAssertFalse(text.contains("Plank"), text)
    }

    func testRecordsAreListedAtTheEnd() throws {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(80, 10)])])
        let second = session(&data, entries: [("Leg press", .weight, [(85, 10)])])
        let text = try XCTUnwrap(data.shareText(for: second))
        XCTAssertTrue(text.contains("Best yet: Leg press 85 kg × 10"), text)
    }

    func testNoRecordsMeansNoRecordLine() throws {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(85, 10)])])
        let second = session(&data, entries: [("Leg press", .weight, [(80, 10)])])
        let text = try XCTUnwrap(data.shareText(for: second))
        XCTAssertFalse(text.contains("Best yet"), text)
    }

    func testAnUnfinishedOrMissingSessionHasNoSummary() {
        var data = AppData()
        let id = session(&data, entries: [("Leg press", .weight, [(80, 12)])])
        let i = data.sessions.firstIndex { $0.id == id }!
        data.sessions[i].finishedAt = nil
        XCTAssertNil(data.shareText(for: id))
        XCTAssertNil(data.shareText(for: "nope"))
    }
}

/// One record per exercise, and nothing shouted about the first time you do it.
final class RecordReportingTests: XCTestCase {

    func testAnExercisesFirstSessionSetsNoRecords() {
        var data = AppData()
        let id = session(&data, entries: [("Leg press", .weight, [(80, 10)])])
        XCTAssertTrue(data.recordsSet(in: id).isEmpty, "a baseline isn't a record")
    }

    func testBeatingYourBestReportsOneLineNotTwo() {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(80, 10)])])
        let second = session(&data, entries: [("Leg press", .weight, [(85, 10)])])

        let hits = data.recordsSet(in: second)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.record.kind, .heaviest, "the heaviest set is the headline")
    }

    func testMoreRepsAtTheSameWeightStillCounts() {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(80, 8)])])
        let second = session(&data, entries: [("Leg press", .weight, [(80, 12)])])

        let hits = data.recordsSet(in: second)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.record.kind, .estimatedMax, "same weight, more reps — the estimate carries it")
    }

    func testEachExerciseGetsAtMostOneLine() {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(80, 10)]), ("Chest press", .weight, [(40, 10)])])
        let second = session(&data, entries: [("Leg press", .weight, [(85, 12)]), ("Chest press", .weight, [(45, 12)])])

        let hits = data.recordsSet(in: second)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(Set(hits.map(\.exerciseId)).count, 2)
    }

    func testMatchingYourBestSetsNothing() {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(80, 10)])])
        let second = session(&data, entries: [("Leg press", .weight, [(80, 10)])])
        XCTAssertTrue(data.recordsSet(in: second).isEmpty)
    }

    func testTheHeaviestRecordKeepsTheBestSetAtThatWeight() throws {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(60, 10)])])
        let second = session(&data, entries: [("Leg press", .weight, [(70, 10), (70, 12)])])

        let hit = try XCTUnwrap(data.recordsSet(in: second).first)
        XCTAssertEqual(hit.record.value, 70)
        XCTAssertEqual(hit.record.reps, 12, "70 × 12 beats 70 × 10 at the same weight")
    }

    func testAllTimeRecordsStillListEveryKind() {
        var data = AppData()
        _ = session(&data, daysAgo: 7, entries: [("Leg press", .weight, [(80, 10)])])
        let kinds = data.personalRecords(for: data.exercises[0].id).map(\.kind)
        XCTAssertEqual(kinds, [.heaviest, .estimatedMax], "the Progress tab still shows both")
    }
}
