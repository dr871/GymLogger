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

    // MARK: - What the log is told

    /// Every one of these recoveries is deliberately invisible on screen. The
    /// log is the only place they are recorded, so each one is checked.

    func testADamagedLiveFileIsRecordedAsAnError() throws {
        let log = DiagnosticLog()
        file.log = log
        try write("{ not json", to: file.url)
        _ = file.load()
        let messages = log.events.map(\.message).joined(separator: " | ")
        // Two errors, both true: the file was set aside, and with no mirror to
        // fall back on the app started empty.
        XCTAssertTrue(log.events.allSatisfy { $0.level == .error }, messages)
        XCTAssertTrue(log.events.contains { $0.message.contains("data.corrupt.json") }, messages)
        XCTAssertTrue(log.events.contains { $0.message.contains("seeded workout") }, messages)
    }

    func testFallingBackToTheMirrorIsRecorded() throws {
        let log = DiagnosticLog()
        file.log = log
        try file.save(seeded(note: "kept"))
        try write("{ not json", to: file.url)
        XCTAssertEqual(file.load().exercises[0].notes, "kept")
        XCTAssertTrue(log.events.contains { $0.message.contains("mirror") },
                      log.events.map(\.message).joined(separator: " | "))
    }

    func testNoUsableFileAtAllIsRecordedAsAnError() {
        let log = DiagnosticLog()
        file.log = log
        _ = file.load()
        XCTAssertTrue(log.events.contains { $0.message.contains("seeded workout") },
                      log.events.map(\.message).joined(separator: " | "))
    }

    func testAFileFromANewerBuildIsRecordedWithBothVersions() throws {
        let log = DiagnosticLog()
        file.log = log
        var data = AppData.seed()
        data.version = AppData.schemaVersion + 2
        try write(String(decoding: try data.exportJSON(), as: UTF8.self), to: file.url)
        _ = file.load()
        let message = log.events.map(\.message).joined(separator: " | ")
        XCTAssertTrue(message.contains("schema \(AppData.schemaVersion + 2)"), message)
        XCTAssertTrue(message.contains("supports \(AppData.schemaVersion)"), message)
    }

    /// A healthy launch should say nothing at all — a log full of routine
    /// noise is one nobody reads.
    func testAGoodFileRecordsNothing() throws {
        let log = DiagnosticLog()
        file.log = log
        try file.save(seeded(note: "fine"))
        _ = file.load()
        XCTAssertEqual(log.events, [])
    }

    // MARK: - Loading

    /// A path whose parent is a regular file, so creating the directory under
    /// it fails with ENOTDIR — on macOS and on Linux, as root or not.
    private func blockedPath(_ name: String) -> URL {
        let blocker = dir.appendingPathComponent("blocker")
        FileManager.default.createFile(atPath: blocker.path, contents: Data())
        return blocker.appendingPathComponent(name)
    }

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
                               mirror: blockedPath("mirror.json"))
        XCTAssertNoThrow(try blocked.save(seeded(note: "kept")))
        XCTAssertEqual(blocked.load().exercises[0].notes, "kept")
    }

    func testAnUnwritableLiveFileThrows() {
        let blocked = DataFile(url: blockedPath("data.json"), mirror: nil)
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

/// A file from a build that knew more than this one does.
final class NewerSchemaTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gymlogger-newer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The same shape as a real export, plus fields a later version added.
    private func futureFile() -> Data {
        """
        {"version": 99,
         "settings": {"defaultRestSec": 90},
         "exercises": [{"id":"ex_1","name":"Leg press","notes":"Seat 2","equipment":"machine"}],
         "templates": [],
         "sessions": [{"id":"s_1","templateId":"t","name":"Full Body",
           "startedAt":"2026-09-29T09:12:53Z","finishedAt":"2026-09-29T10:04:15Z",
           "bodyweightKg": 78.5,
           "entries":[{"id":"e_1","exerciseId":"ex_1","name":"Leg press","targetMin":8,"targetMax":12,
             "sets":[{"id":"st_1","weight":59,"reps":12,"done":true,"tempo":"3-1-2"}]}]}]}
        """.data(using: .utf8)!
    }

    func testRestoreRefusesABackupFromTheFuture() {
        XCTAssertThrowsError(try AppData.restore(from: futureFile())) { error in
            XCTAssertEqual(error as? RestoreError,
                           .tooNew(fileVersion: 99, appVersion: AppData.schemaVersion))
        }
    }

    func testRestoreStillAcceptsThisVersionAndOlder() throws {
        var current = AppData.seed()
        current.startSession(templateId: current.templates[0].id)
        current.sessions[0].entries[0].sets[0].done = true
        current.finishSession()
        XCTAssertNoThrow(try AppData.restore(from: try current.exportJSON()))

        let older = #"{"version":1,"exercises":[{"id":"ex_1","name":"Leg press"}],"templates":[],"sessions":[]}"#
        XCTAssertNoThrow(try AppData.restore(from: older.data(using: .utf8)!))
    }

    func testLoadingANewerLiveFileKeepsTheOriginalVerbatim() throws {
        let live = dir.appendingPathComponent("data.json")
        let raw = futureFile()
        try raw.write(to: live)

        let file = DataFile(url: live, mirror: nil)
        let loaded = file.load()

        // It still opens — refusing to start would help nobody.
        XCTAssertEqual(loaded.exercises.first?.name, "Leg press")

        // But the richer original is kept, because saving would strip it.
        let kept = dir.appendingPathComponent("data.v99.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path),
                      "a file from a newer build must survive this one saving over it")
        XCTAssertEqual(try Data(contentsOf: kept), raw, "kept byte for byte")

        try file.save(loaded)
        XCTAssertEqual(try Data(contentsOf: kept), raw, "and the save does not touch it")
    }

    func testAnOrdinaryFileIsNotCopiedAside() throws {
        let live = dir.appendingPathComponent("data.json")
        try AppData.seed().exportJSON().write(to: live)

        _ = DataFile(url: live, mirror: nil).load()

        let strays = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0 != "data.json" }
        XCTAssertTrue(strays.isEmpty, "found \(strays)")
    }
}
