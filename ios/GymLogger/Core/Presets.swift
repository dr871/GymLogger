import Foundation

// A catalogue of standard exercises, and the standard splits built from them.
// The catalogue is the single source of truth for an exercise's rest and
// bodyweight defaults; presets only name what they want and how many sets.
// Adding either reuses whatever is already in the library by name, so nothing
// gets duplicated.

enum MuscleGroup: String, Codable, CaseIterable, Hashable {
    case chest, back, shoulders, arms, legs, core

    var title: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }
}

struct CatalogueExercise: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let muscle: MuscleGroup
    /// nil falls back to `Settings.defaultRestSec`.
    var restSec: Int? = nil
    var measure: Measure = .weight
}

enum ExerciseCatalogue {
    static let all: [CatalogueExercise] = [
        // Chest
        CatalogueExercise(name: "Chest press", muscle: .chest),
        CatalogueExercise(name: "Incline chest press", muscle: .chest),
        CatalogueExercise(name: "Chest fly", muscle: .chest),
        CatalogueExercise(name: "Push-up", muscle: .chest, measure: .bodyweight),
        CatalogueExercise(name: "Dip", muscle: .chest, restSec: 120, measure: .bodyweight),
        CatalogueExercise(name: "Assisted dip", muscle: .chest, restSec: 120, measure: .assisted),

        // Back
        CatalogueExercise(name: "Lat pulldown", muscle: .back),
        CatalogueExercise(name: "Seated cable row", muscle: .back),
        CatalogueExercise(name: "Bent-over row", muscle: .back, restSec: 120),
        CatalogueExercise(name: "Face pull", muscle: .back),
        CatalogueExercise(name: "Straight-arm pulldown", muscle: .back),
        CatalogueExercise(name: "Pull-up", muscle: .back, restSec: 150, measure: .bodyweight),
        CatalogueExercise(name: "Assisted pull-up", muscle: .back, restSec: 150, measure: .assisted),

        // Shoulders
        CatalogueExercise(name: "Shoulder press", muscle: .shoulders),
        CatalogueExercise(name: "Lateral raise", muscle: .shoulders),
        CatalogueExercise(name: "Rear delt fly", muscle: .shoulders),
        CatalogueExercise(name: "Upright row", muscle: .shoulders),

        // Arms
        CatalogueExercise(name: "Bicep curl", muscle: .arms),
        CatalogueExercise(name: "Hammer curl", muscle: .arms),
        CatalogueExercise(name: "Triceps pushdown", muscle: .arms),
        CatalogueExercise(name: "Overhead triceps extension", muscle: .arms),

        // Legs
        CatalogueExercise(name: "Leg press", muscle: .legs, restSec: 120),
        CatalogueExercise(name: "Squat", muscle: .legs, restSec: 150),
        CatalogueExercise(name: "Romanian deadlift", muscle: .legs, restSec: 120),
        CatalogueExercise(name: "Leg extension", muscle: .legs),
        CatalogueExercise(name: "Leg curl", muscle: .legs),
        CatalogueExercise(name: "Hip thrust", muscle: .legs, restSec: 120),
        CatalogueExercise(name: "Walking lunge", muscle: .legs, restSec: 120),
        CatalogueExercise(name: "Calf raise", muscle: .legs),

        // Core
        CatalogueExercise(name: "Plank", muscle: .core, measure: .time),
        CatalogueExercise(name: "Hanging leg raise", muscle: .core, measure: .bodyweight),
        CatalogueExercise(name: "Cable crunch", muscle: .core),
        CatalogueExercise(name: "Back extension", muscle: .core, measure: .bodyweight),
    ]

    static func entry(named name: String) -> CatalogueExercise? {
        all.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    static func grouped(_ muscle: MuscleGroup) -> [CatalogueExercise] {
        all.filter { $0.muscle == muscle }
    }
}

struct PresetItem: Identifiable, Hashable {
    var id: String { exerciseName }
    let exerciseName: String
    let sets: Int
    let targetMin: Int?
    let targetMax: Int?

    init(exerciseName: String, sets: Int, range: ClosedRange<Int>) {
        self.exerciseName = exerciseName
        self.sets = sets
        self.targetMin = range.lowerBound
        self.targetMax = range.upperBound
    }

    var targetText: String {
        targetLabel(min: targetMin, max: targetMax,
                    measure: ExerciseCatalogue.entry(named: exerciseName)?.measure ?? .weight)
    }
}

struct WorkoutPreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    /// One line for the picker, so the choice can be made without opening it.
    let summary: String
    let items: [PresetItem]
}

extension WorkoutPreset {
    static let catalogue: [WorkoutPreset] = [
        WorkoutPreset(
            name: "Push",
            summary: "Chest, shoulders and triceps",
            items: [
                PresetItem(exerciseName: "Chest press", sets: 4, range: 8...12),
                PresetItem(exerciseName: "Incline chest press", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Shoulder press", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Lateral raise", sets: 3, range: 12...15),
                PresetItem(exerciseName: "Triceps pushdown", sets: 3, range: 10...15),
            ]
        ),
        WorkoutPreset(
            name: "Pull",
            summary: "Back and biceps",
            items: [
                PresetItem(exerciseName: "Lat pulldown", sets: 4, range: 8...12),
                PresetItem(exerciseName: "Seated cable row", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Face pull", sets: 3, range: 12...15),
                PresetItem(exerciseName: "Bicep curl", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Pull-up", sets: 3, range: 5...8),
            ]
        ),
        WorkoutPreset(
            name: "Legs",
            summary: "Quads, hamstrings and calves",
            items: [
                PresetItem(exerciseName: "Leg press", sets: 4, range: 8...12),
                PresetItem(exerciseName: "Leg extension", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Leg curl", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Romanian deadlift", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Calf raise", sets: 4, range: 12...15),
            ]
        ),
        WorkoutPreset(
            name: "Upper body",
            summary: "Everything above the waist",
            items: [
                PresetItem(exerciseName: "Chest press", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Lat pulldown", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Shoulder press", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Seated cable row", sets: 3, range: 8...12),
                PresetItem(exerciseName: "Triceps pushdown", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Bicep curl", sets: 3, range: 10...15),
            ]
        ),
        WorkoutPreset(
            name: "Lower body",
            summary: "Legs and core",
            items: [
                PresetItem(exerciseName: "Leg press", sets: 4, range: 8...12),
                PresetItem(exerciseName: "Leg curl", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Leg extension", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Calf raise", sets: 3, range: 12...15),
                PresetItem(exerciseName: "Plank", sets: 3, range: 30...60),
            ]
        ),
        WorkoutPreset(
            name: "Full body",
            summary: "One session covering everything",
            items: [
                PresetItem(exerciseName: "Leg press", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Chest press", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Lat pulldown", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Seated cable row", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Leg curl", sets: 3, range: 10...15),
                PresetItem(exerciseName: "Plank", sets: 3, range: 30...60),
            ]
        ),
    ]
}

extension AppData {
    /// Returns the id of the exercise with this name, creating it from the
    /// catalogue's defaults if the library doesn't have it yet. The one place
    /// that decides "reuse or create", so nothing is ever duplicated.
    @discardableResult
    mutating func addExercise(named name: String) -> String {
        if let existing = exercises.first(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            return existing.id
        }

        let entry = ExerciseCatalogue.entry(named: name)
        let created = Exercise(
            name: entry?.name ?? name,
            restSec: entry?.restSec,
            measure: entry?.measure ?? .weight,
            muscle: entry?.muscle
        )
        exercises.append(created)
        return created.id
    }

    /// Adds a preset as a new workout. `including` picks which of its exercises
    /// to bring in — wanting one exercise out of six shouldn't mean taking all
    /// six and deleting five. Passing nil takes everything.
    @discardableResult
    mutating func addPreset(_ preset: WorkoutPreset, including chosen: Set<String>? = nil) -> String? {
        let wanted = preset.items.filter { chosen?.contains($0.exerciseName) ?? true }
        guard !wanted.isEmpty else { return nil }

        let items = wanted.map {
            TemplateItem(exerciseId: addExercise(named: $0.exerciseName), sets: $0.sets,
                         targetMin: $0.targetMin, targetMax: $0.targetMax)
        }

        let template = WorkoutTemplate(name: uniqueTemplateName(preset.name), items: items)
        templates.append(template)
        return template.id
    }

    /// "Push", then "Push 2" — so adding one twice stays tellable apart.
    private func uniqueTemplateName(_ wanted: String) -> String {
        guard templates.contains(where: { $0.name == wanted }) else { return wanted }
        var n = 2
        while templates.contains(where: { $0.name == "\(wanted) \(n)" }) { n += 1 }
        return "\(wanted) \(n)"
    }
}
