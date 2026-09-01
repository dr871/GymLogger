import Foundation
import SwiftUI
import UserNotifications

/// Owns the single source of truth and its file on disk. All the interesting
/// logic lives in `AppData` (Core/), which is plain Foundation and unit-tested;
/// this layer adds persistence, notifications and SwiftUI plumbing.
@MainActor
final class Store: ObservableObject {

    @Published var data: AppData {
        didSet { scheduleSave() }
    }

    @Published private(set) var notificationsAllowed = false
    @Published private(set) var notificationsDenied = false

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private let notificationDelegate = NotificationDelegate()

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Store.defaultFileURL()
        self.fileURL = url
        self.data = Store.load(from: url)
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    // MARK: - Persistence

    static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("GymLogger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    /// A copy of the live file, kept current, in the app's Documents folder —
    /// which iOS shows in the Files app under On My iPhone. The live file stays
    /// private in Application Support so a stray delete in Files costs nothing.
    static func backupURL() -> URL? {
        guard let docs = try? FileManager.default.url(for: .documentDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true) else { return nil }
        return docs.appendingPathComponent("GymLogger-backup.json")
    }

    static func load(from url: URL) -> AppData {
        guard let raw = try? Data(contentsOf: url) else { return .seed() }
        do {
            var decoded = try AppData.decoder().decode(AppData.self, from: raw)
            decoded.pruneExpiredTimer()
            // An empty file is indistinguishable from a fresh install for the
            // user, so give them the seeded workout rather than a blank app.
            return decoded.exercises.isEmpty && decoded.sessions.isEmpty ? .seed() : decoded
        } catch {
            // Unreadable: keep the original beside it rather than overwriting
            // the only copy of someone's training history.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return .seed()
        }
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
            let encoded = try data.exportJSON()
            try encoded.write(to: fileURL, options: .atomic)
            if let backup = Store.backupURL() {
                try? encoded.write(to: backup, options: .atomic)
            }
        } catch {
            print("GymLogger: save failed — \(error)")
        }
    }

    // MARK: - Convenience accessors

    var activeSession: Session? { data.activeSession }

    func exercise(id: String) -> Exercise? { data.exercise(id: id) }

    // MARK: - Session actions

    func startSession(templateId: String) {
        data.startSession(templateId: templateId)
    }

    func finishSession() {
        cancelRest()
        data.finishSession()
    }

    func discardSession() {
        cancelRest()
        data.discardSession()
    }

    func deleteSession(id: String) {
        if data.activeSessionId == id { cancelRest() }
        data.deleteSession(id: id)
    }

    func toggleSet(entryIndex: Int, setIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex),
              data.sessions[s].entries[entryIndex].sets.indices.contains(setIndex) else { return }

        let nowDone = !data.sessions[s].entries[entryIndex].sets[setIndex].done
        data.sessions[s].entries[entryIndex].sets[setIndex].done = nowDone

        if nowDone {
            let entry = data.sessions[s].entries[entryIndex]
            startRest(exerciseId: entry.exerciseId, label: entry.name)
        }
    }

    /// Reverts the prefilled bump back to last session's weight for sets not yet
    /// ticked — the explicit "ignore the suggestion" escape hatch.
    func ignoreSuggestion(entryIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex) else { return }

        let entry = data.sessions[s].entries[entryIndex]
        let suggestion = data.suggestion(for: entry.exerciseId, excluding: data.sessions[s].id)

        data.sessions[s].entries[entryIndex].suggested = false
        for i in data.sessions[s].entries[entryIndex].sets.indices
        where !data.sessions[s].entries[entryIndex].sets[i].done {
            data.sessions[s].entries[entryIndex].sets[i].weight = suggestion.lastWeight
        }
    }

    func addSet(entryIndex: Int) {
        guard let s = data.activeSessionIndex,
              data.sessions[s].entries.indices.contains(entryIndex) else { return }
        let entry = data.sessions[s].entries[entryIndex]
        let previous = entry.sets.last
        data.sessions[s].entries[entryIndex].sets.append(
            SetEntry(weight: previous?.weight, reps: previous?.reps ?? entry.target, done: false)
        )
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
        data.sessions[s].entries.append(data.buildEntry(exerciseId: exerciseId, sets: 3, target: 12))
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
        data = pending.data
        if let timer = data.timer { scheduleNotification(for: timer) }
        saveNow()
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
            return url
        } catch {
            return nil
        }
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
