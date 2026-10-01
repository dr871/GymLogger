import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

/// Owns the single source of truth and its file on disk. All the interesting
/// logic lives in `AppData` (Core/), which is plain Foundation and unit-tested;
/// this layer adds persistence, notifications and SwiftUI plumbing.
@MainActor
final class Store: ObservableObject {

    @Published var data: AppData {
        didSet { scheduleSave() }
    }

    /// Records set by the session that just finished, for Home to celebrate.
    struct FinishSummary: Identifiable {
        var id: String
        var lines: [String]
    }
    @Published var finishSummary: FinishSummary?

    @Published private(set) var notificationsAllowed = false
    @Published private(set) var notificationsDenied = false

    /// Reading and writing live in Core, where they are unit-tested.
    private let file: DataFile
    private var saveTask: Task<Void, Never>?
    private let notificationDelegate = NotificationDelegate()
    /// Kept beside the data file, in its own file: the events most worth
    /// reading are about the data file being unreadable.
    let diagnostics = DiagnosticLog()
    private let diagnosticsURL: URL
    private var lastSnapshot: WidgetSnapshot?

    /// UI tests pass --uitest-reset so each run starts from the seeded workout
    /// in a throwaway file, and never touches real data or the Files-app copy.
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-reset")
    }

    init(fileURL: URL? = nil) {
        let testing = Store.isUITesting
        let url = fileURL ?? (testing ? Store.throwawayFileURL() : Store.defaultFileURL())
        let diagnosticsURL = url.deletingLastPathComponent().appendingPathComponent("diagnostics.json")
        self.diagnosticsURL = diagnosticsURL
        diagnostics.load(from: diagnosticsURL)
        // The log is handed to DataFile before the first read, because the
        // first read is where most of what's worth recording happens.
        self.file = DataFile(url: url, mirror: testing ? nil : Store.backupURL(), log: diagnostics)
        self.data = file.load()
        diagnostics.record(.info, "Launched \(Store.versionText)")
        diagnostics.save(to: diagnosticsURL)
        refreshWidget()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // Loaded from the mirror (or seeded)? Put a live file back straight
        // away rather than waiting for the next edit to do it.
        if !FileManager.default.fileExists(atPath: url.path) { saveNow() }
    }

    // MARK: - Persistence

    nonisolated static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("GymLogger", isDirectory: true)
            .appendingPathComponent("data.json")
    }

    nonisolated static func throwawayFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uitest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("data.json")
    }

    /// A copy of the live file, kept current, in the app's Documents folder —
    /// which iOS shows in the Files app. The live file stays private in
    /// Application Support so a stray delete in Files costs nothing.
    nonisolated static func backupURL() -> URL? {
        guard let docs = try? FileManager.default.url(for: .documentDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true) else { return nil }
        return docs.appendingPathComponent("GymLogger-backup.json")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try file.save(data)
        } catch {
            note(.error, "Save failed: \(error.localizedDescription)")
        }
        diagnostics.save(to: diagnosticsURL)
        refreshWidget()
    }

    /// Writes the shared snapshot and nudges the widget — but only when
    /// something it shows has actually changed. Saves run every few seconds
    /// during a workout, and WidgetKit reloads are a budget, not a free call.
    private func refreshWidget() {
        // UI tests run against a throwaway file so they never touch real data.
        // The shared snapshot is real data too — a test run must not blank the
        // widget on the device it is running on.
        guard !Store.isUITesting else { return }
        let snapshot = data.widgetSnapshot()
        if var previous = lastSnapshot {
            previous.generatedAt = snapshot.generatedAt
            if previous == snapshot { return }
        }
        lastSnapshot = snapshot
        AppGroup.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Convenience accessors

    var activeSession: Session? { data.activeSession }

    func exercise(id: String) -> Exercise? { data.exercise(id: id) }

    // MARK: - Session actions

    func startSession(templateId: String) {
        data.startSession(templateId: templateId)
        note(.info, "Session started — \(data.activeSession?.entries.count ?? 0) exercises")
    }

    func finishSession() {
        cancelRest()
        let id = data.activeSessionId
        data.finishSession()
        guard let id, let session = data.sessions.first(where: { $0.id == id }) else { return }
        note(.info, "Session finished — \(session.entries.count) exercises, "
         + "\(session.entries.reduce(0) { $0 + $1.doneWorkingSets.count }) sets")
        let records = data.recordsSet(in: id)
        guard !records.isEmpty else { return }
        let lines = records.compactMap { hit -> String? in
            guard let entry = session.entries.first(where: { $0.exerciseId == hit.exerciseId }) else { return nil }
            return "\(entry.name) — \(hit.record.kind.title.lowercased()) \(hit.record.text(measure: entry.measure))"
        }
        finishSummary = FinishSummary(id: id, lines: lines)
    }

    func discardSession() {
        cancelRest()
        data.discardSession()
        note(.info, "Session discarded before finishing")
    }

    func deleteSession(id: String) {
        if data.activeSessionId == id { cancelRest() }
        // Counts, so a session that disappears can be told apart from one that
        // was deliberately deleted — which is exactly what the log was missing.
        let sets = data.sessions.first(where: { $0.id == id })
            .map { $0.entries.reduce(0) { $0 + $1.doneWorkingSets.count } } ?? 0
        data.deleteSession(id: id)
        note(.info, "Session deleted — \(sets) sets, \(data.sessions.count) remaining")
    }

    func toggleSet(entryIndex: Int, setIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex),
              data.sessions[s].entries[entryIndex].sets.indices.contains(setIndex) else { return }

        let nowDone = !data.sessions[s].entries[entryIndex].sets[setIndex].done

        // Ticking needs a fully logged set; unticking is always allowed, so a
        // set can never end up stuck done because its numbers were cleared.
        if nowDone, !data.sessions[s].entries[entryIndex].canComplete(setIndex: setIndex) { return }

        data.sessions[s].entries[entryIndex].sets[setIndex].done = nowDone

        if nowDone {
            let entry = data.sessions[s].entries[entryIndex]
            startRest(exerciseId: entry.exerciseId, label: entry.name)
        }
    }

    func addSet(entryIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex) else { return }
        let entry = data.sessions[s].entries[entryIndex]
        let previous = entry.sets.last
        data.sessions[s].entries[entryIndex].sets.append(
            SetEntry(weight: previous?.weight, reps: previous?.reps ?? entry.targetMin, done: false)
        )
    }

    func toggleWarmup(entryIndex: Int, setIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex),
              data.sessions[s].entries[entryIndex].sets.indices.contains(setIndex) else { return }
        data.sessions[s].entries[entryIndex].sets[setIndex].warmup.toggle()
    }

    func removeSet(entryIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex),
              data.sessions[s].entries[entryIndex].sets.count > 1 else { return }
        data.sessions[s].entries[entryIndex].sets.removeLast()
    }

    func removeEntry(entryIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex) else { return }
        data.sessions[s].entries.remove(at: entryIndex)
    }

    func addExerciseToSession(exerciseId: String) {
        guard let s = data.activeSessionIndex else { return }
        let range = (data.exercise(id: exerciseId)?.measure ?? .weight).defaultTarget
        data.sessions[s].entries.append(
            data.buildEntry(exerciseId: exerciseId, sets: 3, targetMin: range.min, targetMax: range.max)
        )
    }

    func setNote(_ note: String, entryIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex) else { return }
        let exerciseId = data.sessions[s].entries[entryIndex].exerciseId
        data.setNote(note, exerciseId: exerciseId, sessionIndex: s, entryIndex: entryIndex)
    }

    // MARK: - Library

    func deleteExercise(id: String) {
        data.deleteExercise(id: id)
        note(.info, "Exercise deleted — \(data.exercises.count) remaining")
    }

    // MARK: - Restore

    struct PendingRestore {
        let data: AppData
        let preview: RestorePreview
    }

    /// Reads and validates a backup without touching the live store, so the
    /// user can see what they're about to replace everything with.
    func previewRestore(url: URL) throws -> PendingRestore {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? Data(contentsOf: url) else { throw RestoreError.unreadable }
        let restored = try AppData.restore(from: raw)
        return PendingRestore(data: restored, preview: restored.preview)
    }

    func commitRestore(_ pending: PendingRestore) {
        cancelRest()
        note(.info, "Backup restored — \(pending.data.sessions.count) sessions replaced "
             + "\(data.sessions.count)")
        data = pending.data
        if let timer = data.timer { scheduleNotification(for: timer) }
        saveNow()
    }

    /// Plain-text summary of a finished session, for the share sheet.
    func shareText(sessionId: String) -> String? {
        data.shareText(for: sessionId)
    }

    func markExported() {
        data.settings.lastExportedAt = Date()
    }

    /// Days since a backup last left the phone; nil when never.
    var daysSinceExport: Int? {
        guard let at = data.settings.lastExportedAt else { return nil }
        return Int(Date().timeIntervalSince(at) / 86_400)
    }

    // MARK: - Rest timer

    /// Rest length is a setting, not history: read live so an edit mid-workout
    /// applies to the very next set.
    func startRest(exerciseId: String, label: String) {
        // The editors accept 0; a zero-length rest is a bar that reads "done"
        // the instant it appears, so floor it here rather than in the fields.
        let seconds = max(1, data.restSec(for: exerciseId))
        cancelPendingNotification()

        let state = RestTimerState(
            exerciseId: exerciseId,
            label: label,
            endsAt: Date().addingTimeInterval(TimeInterval(seconds)),
            durationSec: seconds
        )
        data.timer = state
        Haptics.tick()

        Task {
            await requestPermissionIfUndecided()
            // Cancelled or replaced while the prompt was up? Then this one
            // must not be scheduled, or it fires as an orphan.
            guard data.timer?.notificationId == state.notificationId else { return }
            scheduleNotification(for: state)
        }
    }

    func addRestTime(_ seconds: Int) {
        guard var timer = data.timer else { return }
        cancelPendingNotification()
        timer.endsAt = timer.endsAt.addingTimeInterval(TimeInterval(seconds))
        timer.durationSec += seconds
        timer.notificationId = UUID().uuidString
        data.timer = timer
        scheduleNotification(for: timer)
    }

    func cancelRest() {
        cancelPendingNotification()
        data.timer = nil
    }

    // MARK: - Notifications

    /// The whole reason this is a native app: a local notification is scheduled
    /// with the system, so rest finishing reaches you with the app backgrounded,
    /// the phone locked, or the app killed outright.
    private func scheduleNotification(for state: RestTimerState) {
        let seconds = state.remaining()
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Rest done"
        content.body = state.label.isEmpty ? "Next set" : "Next set: \(state.label)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: state.notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelPendingNotification() {
        guard let id = data.timer?.notificationId else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        notificationsDenied = settings.authorizationStatus == .denied
    }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refreshNotificationStatus()
    }

    /// First rest timer of the app's life: this is the moment the permission
    /// prompt explains itself, so ask here rather than at launch.
    private func requestPermissionIfUndecided() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        await requestNotificationPermission()
    }

    // MARK: - Export

    /// Writes the backup to a temp file for the share sheet.
    func exportFile() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "gymlogger-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.exportJSON().write(to: url, options: .atomic)
            note(.info, "Backup exported — \(data.sessions.count) sessions")
            return url
        } catch {
            note(.error, "Backup export failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Diagnostics

    /// Record and persist in one step, so an event survives even if whatever
    /// went wrong takes the app down immediately afterwards.
    func note(_ level: DiagnosticEvent.Level, _ message: String) {
        diagnostics.record(level, message)
        diagnostics.save(to: diagnosticsURL)
    }

    /// Writes the report to a temp file for the share sheet. Plain text, so it
    /// can be read in the share sheet's preview without sending it anywhere.
    func diagnosticsFile() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "gymlogger-diagnostics-\(formatter.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Data(diagnostics.reportText(context: diagnosticContext()).utf8)
                .write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// "1.0 (28)" — the same pair the IPA was built with, so a report names a
    /// build exactly.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static var deviceModel: String {
        // On a simulator uname() reports the Mac's architecture, which tells a
        // reader nothing. The simulator names the device it is pretending to be.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (simulator)"
        }
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return model.isEmpty ? "unknown" : model
    }

    private func diagnosticContext() -> DiagnosticContext {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let loggedSets = data.sessions.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.doneWorkingSets.count } }

        var files = [fact("data.json", file.url)]
        if let mirror = Store.backupURL() { files.append(fact(mirror.lastPathComponent, mirror)) }
        let folder = file.url.deletingLastPathComponent()
        let aside = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?
            .filter { $0.hasPrefix("data.") && $0 != "data.json" }
            .sorted() ?? []
        files += aside.map { fact($0, folder.appendingPathComponent($0)) }

        return DiagnosticContext(
            appVersion: Store.versionText,
            system: "iOS \(v.majorVersion).\(v.minorVersion)",
            device: Store.deviceModel,
            generatedAt: Date(),
            schemaVersion: data.version,
            supportedSchemaVersion: AppData.schemaVersion,
            exercises: data.exercises.count,
            workouts: data.templates.count,
            sessions: data.sessions.count,
            loggedSets: loggedSets,
            lastSession: data.sessions.compactMap(\.finishedAt).max(),
            lastExported: data.settings.lastExportedAt,
            files: files
        )
    }

    private func fact(_ name: String, _ url: URL) -> FileFact {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return FileFact(name: name, exists: false, bytes: nil, modified: nil)
        }
        return FileFact(name: name,
                        exists: true,
                        bytes: (attrs[.size] as? NSNumber)?.intValue,
                        modified: attrs[.modificationDate] as? Date)
    }
}

/// Without a delegate, iOS suppresses a notification whose app is in the
/// foreground. Rest can finish while you're looking at the Progress tab, or
/// while the phone lies on the bench with the app open — so present it anyway.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
