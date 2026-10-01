import XCTest
@testable import GymLoggerCore

/// The widget's whole job is one number. It has to be the right one, and it has
/// to degrade to something honest when there is nothing to show.
final class WidgetSnapshotTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: iso)!
    }

    private func snapshot(last: Date?, name: String? = "Full Body") -> WidgetSnapshot {
        WidgetSnapshot(workoutName: name, lastFinished: last, setsThisWeek: 24, generatedAt: at("2026-10-01T09:00:00Z"))
    }

    // MARK: - Counting days

    /// Evening session, morning glance: a wall-clock difference of 11 hours is
    /// still yesterday, and saying "Today" would be a lie.
    func testAnEveningSessionReadsAsYesterdayTheNextMorning() {
        let s = snapshot(last: at("2026-09-30T21:00:00Z"))
        XCTAssertEqual(s.daysSince(at("2026-10-01T08:00:00Z"), calendar: calendar), 1)
        XCTAssertEqual(s.headline(now: at("2026-10-01T08:00:00Z"), calendar: calendar), "Yesterday")
    }

    func testASessionEarlierTodayReadsAsToday() {
        let s = snapshot(last: at("2026-10-01T07:00:00Z"))
        XCTAssertEqual(s.headline(now: at("2026-10-01T20:00:00Z"), calendar: calendar), "Today")
    }

    func testALongerGapIsCountedInWholeDays() {
        let s = snapshot(last: at("2026-09-28T10:00:00Z"))
        XCTAssertEqual(s.headline(now: at("2026-10-01T09:00:00Z"), calendar: calendar), "3 days")
        XCTAssertEqual(s.compact(now: at("2026-10-01T09:00:00Z"), calendar: calendar), "3d")
    }

    /// Clock skew, a restored backup from another timezone: never show a
    /// negative day count.
    func testAFutureDateNeverCountsBackwards() {
        let s = snapshot(last: at("2026-10-05T10:00:00Z"))
        XCTAssertEqual(s.daysSince(at("2026-10-01T09:00:00Z"), calendar: calendar), 0)
    }

    // MARK: - Nothing to show

    func testNoHistorySaysSoRatherThanShowingZero() {
        let s = snapshot(last: nil)
        XCTAssertNil(s.daysSince(at("2026-10-01T09:00:00Z"), calendar: calendar))
        XCTAssertEqual(s.headline(now: at("2026-10-01T09:00:00Z"), calendar: calendar), "—")
        XCTAssertEqual(s.caption(now: at("2026-10-01T09:00:00Z"), calendar: calendar),
                       "No workouts logged yet")
    }

    func testTheCaptionNamesTheWorkoutWhenThereIsOne() {
        let s = snapshot(last: at("2026-09-29T10:00:00Z"))
        XCTAssertEqual(s.caption(now: at("2026-10-01T09:00:00Z"), calendar: calendar), "since Full Body")
    }

    func testAWorkoutWithoutANameStillReadsAsASentence() {
        let s = snapshot(last: at("2026-09-29T10:00:00Z"), name: nil)
        XCTAssertEqual(s.caption(now: at("2026-10-01T09:00:00Z"), calendar: calendar),
                       "since your last workout")
    }

    // MARK: - Building it from the store

    func testTheSnapshotIsBuiltFromFinishedSessionsOnly() {
        var data = AppData.seed()
        let template = data.templates[0].id
        data.startSession(templateId: template)
        let i = data.activeSessionIndex!
        data.sessions[i].startedAt = at("2026-09-29T09:00:00Z")
        data.sessions[i].entries[0].sets = [SetEntry(weight: 50, reps: 10, done: true)]
        data.finishSession(at: at("2026-09-29T10:00:00Z"))

        // An unfinished session in progress must not count as a workout done.
        data.startSession(templateId: template)

        let s = data.widgetSnapshot(now: at("2026-10-01T09:00:00Z"), calendar: calendar)
        XCTAssertEqual(s.lastFinished, at("2026-09-29T10:00:00Z"))
        XCTAssertEqual(s.headline(now: at("2026-10-01T09:00:00Z"), calendar: calendar), "2 days")
        XCTAssertNotNil(s.workoutName)
    }

    func testAnEmptyStoreProducesASnapshotRatherThanNothing() {
        let s = AppData().widgetSnapshot(now: at("2026-10-01T09:00:00Z"), calendar: calendar)
        XCTAssertNil(s.lastFinished)
        XCTAssertEqual(s.setsThisWeek, 0)
    }

    /// The widget decodes this in a separate process; it has to survive the trip.
    func testTheSnapshotSurvivesEncodingAndDecoding() throws {
        let s = snapshot(last: at("2026-09-29T10:00:00Z"))
        let encoded = try AppData.encoder().encode(s)
        XCTAssertEqual(try AppData.decoder().decode(WidgetSnapshot.self, from: encoded), s)
    }
}
