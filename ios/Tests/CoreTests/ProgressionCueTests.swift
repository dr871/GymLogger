import XCTest
@testable import GymLoggerCore

private struct Log {
    var data = AppData()
    let id: String

    init(_ measure: Measure = .weight, min: Int?, max: Int?) {
        let e = Exercise(name: "X", measure: measure, muscle: .legs)
        id = e.id
        data.exercises = [e]
        data.templates = [WorkoutTemplate(name: "T",
                                          items: [TemplateItem(exerciseId: e.id, sets: 3,
                                                               targetMin: min, targetMax: max)])]
    }

    /// `sets` is (weight, reps, warmup) — weight is the assistance for
    /// assisted work, and ignored where the measure carries none.
    mutating func session(daysAgo: Int, _ sets: [(Double?, Int, Bool)]) {
        data.startSession(templateId: data.templates[0].id)
        let i = data.activeSessionIndex!
        let start = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        data.sessions[i].startedAt = start
        data.sessions[i].entries[0].sets = sets.map {
            SetEntry(weight: $0.0, reps: $0.1, done: true, warmup: $0.2)
        }
        data.finishSession(at: start.addingTimeInterval(3600))
    }

    mutating func session(daysAgo: Int, _ sets: [(Double?, Int)]) {
        session(daysAgo: daysAgo, sets.map { ($0.0, $0.1, false) })
    }
}

/// Double progression: the reps climb through the range, then the weight moves
/// and the reps start again at the bottom. The app can't name the next weight
/// — this user's machines don't move in fixed steps — but it can say when the
/// range has nothing left to give.
final class ProgressionCueTests: XCTestCase {

    // MARK: - When it fires

    func testEverySetAtTheTopOfTheRangeEarnsTheCue() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 3, [(50, 12), (50, 12), (50, 12)])
        XCTAssertEqual(log.data.progressionCue(for: log.id), "Topped the range last time — add weight")
    }

    func testBeatingTheTopOfTheRangeCountsAsToppingIt() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 3, [(50, 13), (50, 12), (50, 14)])
        XCTAssertNotNil(log.data.progressionCue(for: log.id))
    }

    func testAFixedTargetIsAHitWhenEverySetMeetsIt() {
        var log = Log(min: 10, max: 10)
        log.session(daysAgo: 3, [(50, 10), (50, 10), (50, 10)])
        XCTAssertNotNil(log.data.progressionCue(for: log.id))
    }

    // MARK: - When it stays quiet

    func testOneSetShortOfTheTopIsNotTheTop() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 3, [(50, 12), (50, 12), (50, 11)])
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    /// Real logging, 29 Sep: 59x12, 59x12, then a back-off at 45x15. Every set
    /// reached 12, but the 15 came at a lighter weight — that is not evidence
    /// the 59 is ready to move.
    func testAHighRepBackOffSetDoesNotEarnTheCue() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 2, [(59, 12), (59, 12), (45, 15)])
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    func testRampingUpToOneHeavySetIsNotTheTopEither() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 2, [(40, 12), (45, 12), (50, 12)])
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    func testNoRangeMeansNothingToTop() {
        var log = Log(min: nil, max: nil)
        log.session(daysAgo: 3, [(50, 20), (50, 20), (50, 20)])
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    func testAnExerciseNeverLoggedHasNoCue() {
        let log = Log(min: 8, max: 12)
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    func testGoingUpClearsTheCue() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 7, [(50, 12), (50, 12), (50, 12)])
        XCTAssertNotNil(log.data.progressionCue(for: log.id))
        log.session(daysAgo: 2, [(55, 8), (55, 8), (55, 8)])
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    func testWarmupsAreNotJudgedAgainstTheRange() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 3, [(20, 5, true), (50, 12, false), (50, 12, false), (50, 12, false)])
        XCTAssertNotNil(log.data.progressionCue(for: log.id))
    }

    func testAnUnfinishedSetIsNotEvidence() {
        var log = Log(min: 8, max: 12)
        log.data.startSession(templateId: log.data.templates[0].id)
        let i = log.data.activeSessionIndex!
        log.data.sessions[i].entries[0].sets = [SetEntry(weight: 50, reps: 12, done: false)]
        XCTAssertNil(log.data.progressionCue(for: log.id))
    }

    func testTheCueReadsTheLastSessionNotThePresentOne() {
        var log = Log(min: 8, max: 12)
        log.session(daysAgo: 4, [(50, 12), (50, 12), (50, 12)])
        log.data.startSession(templateId: log.data.templates[0].id)
        let active = log.data.sessions[log.data.activeSessionIndex!].id
        XCTAssertNotNil(log.data.progressionCue(for: log.id, excluding: active))
    }

    // MARK: - The other measures

    /// Assisted work gets lighter as it gets stronger, so the cue has to point
    /// the other way.
    func testAssistedWorkIsToldToDropTheHelp() {
        var log = Log(.assisted, min: 6, max: 10)
        log.session(daysAgo: 3, [(20, 10), (20, 10), (20, 10)])
        XCTAssertEqual(log.data.progressionCue(for: log.id), "Topped the range last time — less help")
    }

    /// There is no weight to add to a press-up, so the range itself is what
    /// moves.
    func testBodyweightWorkIsToldToRaiseTheRange() {
        var log = Log(.bodyweight, min: 10, max: 15)
        log.session(daysAgo: 3, [(nil, 15), (nil, 15), (nil, 15)])
        XCTAssertEqual(log.data.progressionCue(for: log.id), "Topped the range last time — raise it")
    }

    func testTimedWorkIsToldToRaiseTheHold() {
        var log = Log(.time, min: 30, max: 60)
        log.session(daysAgo: 3, [(nil, 60), (nil, 60)])
        XCTAssertEqual(log.data.progressionCue(for: log.id), "Held the top last time — raise it")
    }
}
