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

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        let url = fileURL ?? Store.defaultFileURL()
        self.fileURL = url
        self.data = Store.load(from: url)
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

    static func load(from url: URL) -> AppData {
        guard let raw = try? Data(contentsOf: url) else { return .seed() }
        do {
            let decoded = try AppData.decoder().decode(AppData.self, from: raw)
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

    // MARK: - Rest timer

    /// Rest length is a setting, not history: read live so an edit mid-workout
    /// applies to the very next set.
    func startRest(exerciseId: String, label: String) {
        let seconds = data.restSec(for: exerciseId)
        cancelPendingNotification()

        let state = RestTimerState(
            exerciseId: exerciseId,
            label: label,
            endsAt: Date().addingTimeInterval(TimeInterval(seconds)),
            durationSec: seconds
        )
        data.timer = state
        scheduleNotification(for: state)
        Haptics.tick()
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
    }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refreshNotificationStatus()
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
