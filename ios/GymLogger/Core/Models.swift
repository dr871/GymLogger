import Foundation

// Pure value types, Foundation only — no SwiftUI, no Combine — so the whole
// data layer builds and tests on any platform, not just in Xcode.

struct Exercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var notes: String = ""
    /// nil falls back to `Settings.defaultRestSec`.
    var restSec: Int?
    /// nil falls back to `Settings.defaultIncrement`.
    var increment: Double?
    /// Pull-ups, dips, planks: there is no weight to log, so sets are ticked
    /// off on reps alone and the weight field is hidden.
    var isBodyweight: Bool = false

    init(id: String = newID("ex"), name: String, notes: String = "", restSec: Int? = nil, increment: Double? = nil, isBodyweight: Bool = false) {
        self.id = id
        self.name = name
        self.notes = notes
        self.restSec = restSec
        self.increment = increment
        self.isBodyweight = isBodyweight
    }
}

struct TemplateItem: Codable, Hashable {
    var exerciseId: String
    var sets: Int
    /// Target reps. The plank uses this for seconds.
    var target: Int?
}

struct WorkoutTemplate: Codable, Identifiable, Hashable {
    var id: String = newID("tpl")
    var name: String
    var items: [TemplateItem]
}

struct SetEntry: Codable, Hashable, Identifiable {
    var id: String = newID("set")
    var weight: Double?
    var reps: Int?
    var done: Bool = false
}

struct SessionEntry: Codable, Hashable, Identifiable {
    var id: String = newID("en")
    var exerciseId: String
    /// Snapshotted so renaming an exercise later doesn't rewrite history.
    var name: String
    var target: Int?
    var note: String = ""
    var sets: [SetEntry] = []
    /// True when this entry opened with an increase suggested.
    var suggested: Bool = false
    /// Snapshotted alongside `name` and `target`, so flipping the exercise's
    /// flag — or deleting it — can't retroactively invalidate a logged session.
    var bodyweight: Bool = false

    var doneSets: [SetEntry] { sets.filter(\.done) }
    var isComplete: Bool { !sets.isEmpty && doneSets.count == sets.count }
    var hasWork: Bool { !doneSets.isEmpty }

    /// Ticking a set is a claim that it happened, so it has to carry what was
    /// lifted. Bodyweight work is the exception: reps are the whole record.
    func canComplete(setIndex: Int) -> Bool {
        guard sets.indices.contains(setIndex) else { return false }
        let set = sets[setIndex]
        guard let reps = set.reps, reps > 0 else { return false }
        if bodyweight { return true }
        return (set.weight ?? 0) > 0
    }
}

struct Session: Codable, Identifiable, Hashable {
    var id: String = newID("s")
    var templateId: String
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    var entries: [SessionEntry]

    var isFinished: Bool { finishedAt != nil }
    var completedSetCount: Int { entries.reduce(0) { $0 + $1.doneSets.count } }
    var workedExerciseCount: Int { entries.filter(\.hasWork).count }
    var duration: TimeInterval? { finishedAt.map { $0.timeIntervalSince(startedAt) } }
}

struct Settings: Codable, Hashable {
    var defaultRestSec: Int = 90
    var defaultIncrement: Double = 2.5
    /// When a backup was last handed off via the share sheet. The phone is the
    /// only copy, so Home nudges when this gets stale.
    var lastExportedAt: Date?
}

/// The rest timer is stored as an absolute end time, never a remaining count.
/// Everything is derived from the wall clock, so backgrounding, locking the
/// phone or force-quitting mid-rest can't desynchronise it.
struct RestTimerState: Codable, Hashable {
    var exerciseId: String
    var label: String
    var endsAt: Date
    var durationSec: Int
    /// Identifier of the pending local notification, so it can be cancelled.
    var notificationId: String = UUID().uuidString

    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(now))
    }

    func isDone(at now: Date = Date()) -> Bool {
        remaining(at: now) <= 0
    }

    /// 0...1, for the progress fill.
    func elapsedFraction(at now: Date = Date()) -> Double {
        guard durationSec > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / Double(durationSec)))
    }
}

struct AppData: Codable {
    var version: Int = 1
    var settings = Settings()
    /// Arrays rather than dictionaries: order is meaningful and deterministic.
    var exercises: [Exercise] = []
    var templates: [WorkoutTemplate] = []
    var sessions: [Session] = []
    var activeSessionId: String?
    var timer: RestTimerState?
}

func newID(_ prefix: String) -> String {
    prefix + "_" + UUID().uuidString.prefix(8).lowercased()
}

extension AppData {
    /// The workout as it stands today, pre-loaded on first launch.
    static func seed() -> AppData {
        let legPress = Exercise(name: "Leg press", restSec: 120)
        let chestPress = Exercise(name: "Chest press")
        let latPulldown = Exercise(name: "Lat pulldown")
        let cableRow = Exercise(name: "Seated cable row")
        let legCurl = Exercise(name: "Leg curl")
        let plank = Exercise(name: "Plank", isBodyweight: true)

        let exercises = [legPress, chestPress, latPulldown, cableRow, legCurl, plank]

        let template = WorkoutTemplate(
            name: "Full Body",
            items: [
                TemplateItem(exerciseId: legPress.id, sets: 3, target: 12),
                TemplateItem(exerciseId: chestPress.id, sets: 3, target: 12),
                TemplateItem(exerciseId: latPulldown.id, sets: 3, target: 12),
                TemplateItem(exerciseId: cableRow.id, sets: 3, target: 12),
                TemplateItem(exerciseId: legCurl.id, sets: 3, target: 12),
                TemplateItem(exerciseId: plank.id, sets: 3, target: 40),
            ]
        )

        var data = AppData()
        data.exercises = exercises
        data.templates = [template]
        return data
    }
}
