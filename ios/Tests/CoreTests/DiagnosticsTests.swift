import XCTest
@testable import GymLoggerCore

/// The log exists for the moment someone says "my history is gone". It has to
/// survive that moment, say something useful about it, and give away nothing
/// else.
final class DiagnosticsTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    private func context(_ events: Int = 0) -> DiagnosticContext {
        DiagnosticContext(
            appVersion: "1.0 (28)",
            system: "iOS 27.0",
            device: "iPhone17,1",
            generatedAt: epoch,
            schemaVersion: 3,
            supportedSchemaVersion: 3,
            exercises: 9,
            workouts: 1,
            sessions: 3,
            loggedSets: 24,
            lastSession: epoch,
            lastExported: nil,
            timeZone: TimeZone(identifier: "UTC")!
        )
    }

    // MARK: - Keeping events

    func testEventsAreKeptInTheOrderTheyHappened() {
        let log = DiagnosticLog()
        log.record(.info, "one", at: epoch)
        log.record(.error, "two", at: epoch)
        XCTAssertEqual(log.events.map(\.message), ["one", "two"])
    }

    /// A crash loop could record the same failure hundreds of times; the file
    /// must not grow without end.
    func testTheOldestEventsGoOnceTheLimitIsReached() {
        let log = DiagnosticLog()
        for i in 0..<(DiagnosticLog.limit + 25) {
            log.record(.info, "event \(i)", at: epoch)
        }
        XCTAssertEqual(log.events.count, DiagnosticLog.limit)
        XCTAssertEqual(log.events.first?.message, "event 25")
        XCTAssertEqual(log.events.last?.message, "event \(DiagnosticLog.limit + 24)")
    }

    // MARK: - Surviving a restart

    func testTheLogSurvivesBeingWrittenAndReadBack() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diag-\(UUID().uuidString)")
            .appendingPathComponent("diagnostics.json")
        let log = DiagnosticLog()
        log.record(.warning, "live file unreadable", at: epoch)
        log.record(.error, "save failed", at: epoch)
        log.save(to: url)

        let reloaded = DiagnosticLog()
        reloaded.load(from: url)
        XCTAssertEqual(reloaded.events.map(\.message), ["live file unreadable", "save failed"])
        XCTAssertEqual(reloaded.events.map(\.level), [.warning, .error])
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testAMissingLogFileIsNotAnError() {
        let log = DiagnosticLog()
        log.record(.info, "kept", at: epoch)
        log.load(from: URL(fileURLWithPath: "/nonexistent/diagnostics.json"))
        XCTAssertEqual(log.events.map(\.message), ["kept"])
    }

    // MARK: - The report

    func testTheReportLeadsWithTheBuildAndTheCounts() {
        let log = DiagnosticLog()
        let text = log.reportText(context: context())
        XCTAssertTrue(text.contains("App:        1.0 (28)"), text)
        XCTAssertTrue(text.contains("iOS 27.0 · iPhone17,1"), text)
        XCTAssertTrue(text.contains("Exercises:     9"), text)
        XCTAssertTrue(text.contains("Sessions:      3 (24 sets logged)"), text)
        XCTAssertTrue(text.contains("Last exported: never"), text)
    }

    /// Newest first: a report is read from the top, and the thing that just
    /// went wrong is the reason it was sent.
    func testEventsAreReportedNewestFirst() {
        let log = DiagnosticLog()
        log.record(.info, "older", at: epoch)
        log.record(.error, "newer", at: epoch.addingTimeInterval(60))
        let text = log.reportText(context: context())
        let newer = try! XCTUnwrap(text.range(of: "newer"))
        let older = try! XCTUnwrap(text.range(of: "older"))
        XCTAssertLessThan(newer.lowerBound, older.lowerBound, text)
    }

    func testAnEmptyLogSaysSoRatherThanShowingNothing() {
        XCTAssertTrue(DiagnosticLog().reportText(context: context()).contains("Nothing recorded."))
    }

    /// A file written by a newer build is the one case where the schema number
    /// is worth spelling out.
    func testAFileFromANewerBuildIsCalledOutInTheReport() {
        var c = context()
        c.schemaVersion = 5
        let text = DiagnosticLog().reportText(context: c)
        XCTAssertTrue(text.contains("Schema:        5 — this build supports 3"), text)
    }

    func testFilesAreListedWithSizesAndAbsenceIsStated() {
        var c = context()
        c.files = [
            FileFact(name: "data.json", exists: true, bytes: 17_062, modified: epoch),
            FileFact(name: "data.corrupt.json", exists: false, bytes: nil, modified: nil),
        ]
        let text = DiagnosticLog().reportText(context: c)
        XCTAssertTrue(text.contains("data.json: 16.7 KB"), text)
        XCTAssertTrue(text.contains("data.corrupt.json: absent"), text)
    }

    // MARK: - What it must not contain

    /// The report is meant to be sendable. Someone's exercises, workout names
    /// and weights are not diagnostics.
    func testTheReportCarriesNoWorkoutContent() {
        var data = AppData.seed()
        let names = data.exercises.map(\.name) + data.templates.map(\.name)
        XCTAssertFalse(names.isEmpty)

        let log = DiagnosticLog()
        log.record(.error, "save failed: no space left on device", at: epoch)
        var c = context()
        c.exercises = data.exercises.count
        let text = log.reportText(context: c)

        for name in names {
            XCTAssertFalse(text.contains(name), "report leaked \"\(name)\"")
        }
        XCTAssertTrue(text.contains("No workout content is included"), text)
    }
}
