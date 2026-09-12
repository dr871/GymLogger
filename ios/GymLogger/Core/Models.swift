import Foundation

// Pure value types, Foundation only — no SwiftUI, no Combine — so the whole
// data layer builds and tests on any platform, not just in Xcode.

/// How an exercise is measured — which decides what a set has to record, what
/// the fields are called, and what "progress" means.
enum Measure: String, Codable, CaseIterable, Hashable {
    /// Load on the machine or bar. Progress is more weight.
    case weight
    /// Assisted pull-ups and dips: the weight logged is the *help*. Progress
    /// is less of it, down to zero.
    case assisted
    /// Pull-ups, dips, push-ups: reps are the whole record.
    case bodyweight
    /// Planks and holds: seconds, stored in `reps`.
    case time

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .assisted: return "Assisted"
        case .bodyweight: return "Bodyweight"
        case .time: return "Time"
        }
    }

    /// Whether a set carries a weight at all.
    var usesWeight: Bool { self == .weight || self == .assisted }

    /// What `SetEntry.reps` counts.
    var repsNoun: String { self == .time ? "secs" : "reps" }

    /// Appended to a rep count when shown: "40s".
    var repsSuffix: String { self == .time ? "s" : "" }

    /// The unit on a progress chart.
    var unit: String {
        switch self {
        case .weight: return "kg"
        case .assisted: return "kg assistance"
        case .bodyweight: return "reps"
        case .time: return "s"
        }
    }

    /// Assisted work improves by needing less help.
    var lowerIsBetter: Bool { self == .assisted }

    /// A sensible range when nothing better is known.
    var defaultTarget: (min: Int, max: Int) {
        switch self {
        case .weight, .assisted: return (8, 12)
        case .bodyweight: return (5, 10)
        case .time: return (30, 60)
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var notes: String = ""
    /// nil falls back to `Settings.defaultRestSec`.
    var restSec: Int?
    /// nil falls back to `Settings.defaultIncrement`. For assisted work it is
    /// how much less help to suggest.
    var increment: Double?
    var measure: Measure = .weight

    init(id: String = newID("ex"), name: String, notes: String = "", restSec: Int? = nil, increment: Double? = nil, measure: Measure = .weight) {
        self.id = id
        self.name = name
        self.notes = notes
        self.restSec = restSec
        self.increment = increment
        self.measure = measure
    }
}

struct TemplateItem: Codable, Hashable {
    var exerciseId: String
    var sets: Int
    /// The rep range to work in (seconds for timed work). Equal ends are a
    /// fixed target; nil ends mean "no target", which also means no bump.
    var targetMin: Int?
    var targetMax: Int?
}

extension TemplateItem {
    /// A fixed target: both ends of the range are the same number.
    init(exerciseId: String, sets: Int, target: Int?) {
        self.init(exerciseId: exerciseId, sets: sets, targetMin: target, targetMax: target)
    }
}

/// "8–12", "12", "30–60s", or "—" when there is no target at all.
func targetLabel(min: Int?, max: Int?, measure: Measure) -> String {
    let lo = min ?? max
    let hi = max ?? min
    guard let lo, let hi else { return "—" }
    let core = lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    return core + measure.repsSuffix
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
    /// The range this session was aiming at, snapshotted from the template.
    var targetMin: Int?
    var targetMax: Int?
    var note: String = ""
    var sets: [SetEntry] = []
    /// True when this entry opened with an increase suggested.
    var suggested: Bool = false
    /// Snapshotted alongside `name` and the range, so changing how the exercise
    /// is measured — or deleting it — can't retroactively invalidate a session.
    var measure: Measure = .weight

    var doneSets: [SetEntry] { sets.filter(\.done) }
    var isComplete: Bool { !sets.isEmpty && doneSets.count == sets.count }
    var hasWork: Bool { !doneSets.isEmpty }

    var targetText: String { targetLabel(min: targetMin, max: targetMax, measure: measure) }

    /// Ticking a set is a claim that it happened, so it has to carry what was
    /// actually done — and that depends on how the exercise is measured.
    func canComplete(setIndex: Int) -> Bool {
        guard sets.indices.contains(setIndex) else { return false }
        let set = sets[setIndex]
        guard let reps = set.reps, reps > 0 else { return false }
        switch measure {
        case .weight:
            return (set.weight ?? 0) > 0
        case .assisted:
            // The help has to be entered, but 0 is a real answer: unassisted.
            guard let help = set.weight else { return false }
            return help >= 0
        case .bodyweight, .time:
            return true
        }
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
        let plank = Exercise(name: "Plank", measure: .time)

        let exercises = [legPress, chestPress, latPulldown, cableRow, legCurl, plank]

        let template = WorkoutTemplate(
            name: "Full Body",
            items: [
                TemplateItem(exerciseId: legPress.id, sets: 3, target: 12),
                TemplateItem(exerciseId: chestPress.id, sets: 3, target: 12),
                TemplateItem(exerciseId: latPulldown.id, sets: 3, target: 12),
                TemplateItem(exerciseId: cableRow.id, sets: 3, target: 12),
                TemplateItem(exerciseId: legCurl.id, sets: 3, target: 12),
                TemplateItem(exerciseId: plank.id, sets: 3, targetMin: 30, targetMax: 60),
            ]
        )

        var data = AppData()
        data.exercises = exercises
        data.templates = [template]
        return data
    }
}
