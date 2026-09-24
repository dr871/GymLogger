import XCTest
@testable import GymLoggerCore

/// The file that holds everything. A mistake here loses someone's training
/// history, so every path is exercised: missing, empty, valid, damaged, and
/// damaged-with-an-intact-copy-next-door.
final class DataFileTests: XCTestCase {

    private var dir: URL!
    private var file: DataFile!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gymlogger-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = DataFile(url: dir.appendingPathComponent("data.json"),
                        mirror: dir.appendingPathComponent("GymLogger-backup.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func seeded(note: String) -> AppData {
        var data = AppData.seed()
        data.exercises[0].notes = note
        return data
    }

    // MARK: - Loading

    func testNoFileYetGivesTheSeededWorkout() {
        let loaded = file.load()
        XCTAssertEqual(loaded.templates.first?.name, "Full Body")
        XCTAssertEqual(loaded.exercises.count, 6)
    }

    func testAFileThatWasWrittenComesBack() throws {
        try file.save(seeded(note: "seat 4"))
        XCTAssertEqual(file.load().exercises[0].notes, "seat 4")
    }

    func testAnEmptyStoreIsTreatedAsAFreshInstall() throws {
        try write(#"{"version":2,"exercises":[],"templates":[],"sessions":[]}"#, to: file.url)
        XCTAssertEqual(file.load().exercises.count, 6, "a blank app helps nobody")
    }

    func testADamagedFileFallsBackToTheMirror() throws {
        try file.save(seeded(note: "seat 4"))
        try write("{ not json at all", to: file.url)

        let loaded = file.load()

        XCTAssertEqual(loaded.exercises[0].notes, "seat 4", "the intact copy next door")
        XCTAssertFalse(loaded.exercises.isEmpty)
    }

    func testADamagedFileIsKeptAsideNotOverwritten() throws {
        try file.save(seeded(note: "seat 4"))
        try write("{ not json at all", to: file.url)

        _ = file.load()

        let aside = file.url.deletingPathExtension().appendingPathExtension("corrupt.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "{ not json at all")
    }

    func testADamagedFileWithNoMirrorGivesTheSeed() throws {
        let lonely = DataFile(url: dir.appendingPathComponent("only.json"), mirror: nil)
        try write("{ not json at all", to: lonely.url)
        XCTAssertEqual(lonely.load().exercises.count, 6)
    }

    func testBothCopiesDamagedStillOpensTheApp() throws {
        try write("{ not json", to: file.url)
        try write("{ also not json", to: file.mirror!)
        XCTAssertEqual(file.load().exercises.count, 6)
    }

    func testTheMirrorIsNeverKeptAsideWhenItIsTheDamagedOne() throws {
        try write("{ not json", to: file.url)
        try write("{ also not json", to: file.mirror!)
        _ = file.load()
        let mirrorAside = file.mirror!.deletingPathExtension().appendingPathExtension("corrupt.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mirrorAside.path),
                       "only the live file is set aside; the mirror is a copy")
    }

    func testARestTimerThatExpiredWhileAwayIsDropped() throws {
        var data = AppData.seed()
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(-60), durationSec: 90)
        try file.save(data)
        XCTAssertNil(file.load().timer)
    }

    func testARestTimerStillRunningSurvives() throws {
        var data = AppData.seed()
        data.timer = RestTimerState(exerciseId: "x", label: "", endsAt: Date().addingTimeInterval(120), durationSec: 180)
        try file.save(data)
        XCTAssertNotNil(file.load().timer)
    }

    // MARK: - Saving

    func testSavingWritesBothCopies() throws {
        try file.save(seeded(note: "seat 4"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.mirror!.path))
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8),
                       try String(contentsOf: file.mirror!, encoding: .utf8))
    }

    func testSavingCreatesTheFolderItNeeds() throws {
        let nested = DataFile(url: dir.appendingPathComponent("deep/down/data.json"), mirror: nil)
        try nested.save(AppData.seed())
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.url.path))
    }

    func testSavingOverAnExistingFileReplacesIt() throws {
        try file.save(seeded(note: "first"))
        try file.save(seeded(note: "second"))
        XCTAssertEqual(file.load().exercises[0].notes, "second")
    }

    /// A failing mirror write must not cost the live save — the mirror is a
    /// convenience, the live file is the data.
    func testAnUnwritableMirrorDoesNotStopTheRealSave() throws {
        let blocked = DataFile(url: dir.appendingPathComponent("data.json"),
                               mirror: URL(fileURLWithPath: "/System/nope/mirror.json"))
        XCTAssertNoThrow(try blocked.save(seeded(note: "kept")))
        XCTAssertEqual(blocked.load().exercises[0].notes, "kept")
    }

    func testAnUnwritableLiveFileThrows() {
        let blocked = DataFile(url: URL(fileURLWithPath: "/System/nope/data.json"), mirror: nil)
        XCTAssertThrowsError(try blocked.save(AppData.seed()))
    }

    func testAFullRoundTripKeepsSessionsAndSettings() throws {
        var data = AppData.seed()
        data.startSession(templateId: data.templates[0].id)
        data.sessions[0].entries[0].sets[0].weight = 60
        data.sessions[0].entries[0].sets[0].done = true
        data.finishSession()
        data.settings.defaultRestSec = 120

        try file.save(data)
        let loaded = file.load()

        XCTAssertEqual(loaded.sessions.count, 1)
        XCTAssertEqual(loaded.sessions[0].entries[0].sets[0].weight, 60)
        XCTAssertEqual(loaded.settings.defaultRestSec, 120)
        XCTAssertNil(loaded.activeSessionId)
    }
}
