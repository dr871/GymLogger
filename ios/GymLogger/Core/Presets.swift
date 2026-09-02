import Foundation

// The standard splits people expect to already be there. Presets name their
// exercises rather than carrying ids: adding one reuses whatever is already in
// the library and only creates what's genuinely missing, so building "Push"
// after "Upper body" doesn't leave two Chest presses behind.

struct PresetItem: Hashable {
    let exerciseName: String
    let sets: Int
    let target: Int?
    /// nil falls back to `Settings.defaultRestSec` like any other exercise.
    var restSec: Int? = nil
    var bodyweight: Bool = false
}

struct WorkoutPreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    /// One line for the picker, so the choice can be made without opening it.
    let summary: String
    let items: [PresetItem]
}

extension WorkoutPreset {
    /// Machine-and-cable led, matching the exercises already seeded on day one.
    static let catalogue: [WorkoutPreset] = [
        WorkoutPreset(
            name: "Push",
            summary: "Chest, shoulders and triceps",
            items: [
                PresetItem(exerciseName: "Chest press", sets: 4, target: 10),
                PresetItem(exerciseName: "Incline chest press", sets: 3, target: 10),
                PresetItem(exerciseName: "Shoulder press", sets: 3, target: 10),
                PresetItem(exerciseName: "Lateral raise", sets: 3, target: 15),
                PresetItem(exerciseName: "Triceps pushdown", sets: 3, target: 12),
            ]
        ),
        WorkoutPreset(
            name: "Pull",
            summary: "Back and biceps",
            items: [
                PresetItem(exerciseName: "Lat pulldown", sets: 4, target: 10),
                PresetItem(exerciseName: "Seated cable row", sets: 3, target: 10),
                PresetItem(exerciseName: "Face pull", sets: 3, target: 15),
                PresetItem(exerciseName: "Bicep curl", sets: 3, target: 12),
                PresetItem(exerciseName: "Pull-up", sets: 3, target: 8, restSec: 150, bodyweight: true),
            ]
        ),
        WorkoutPreset(
            name: "Legs",
            summary: "Quads, hamstrings and calves",
            items: [
                PresetItem(exerciseName: "Leg press", sets: 4, target: 10, restSec: 120),
                PresetItem(exerciseName: "Leg extension", sets: 3, target: 12),
                PresetItem(exerciseName: "Leg curl", sets: 3, target: 12),
                PresetItem(exerciseName: "Romanian deadlift", sets: 3, target: 10, restSec: 120),
                PresetItem(exerciseName: "Calf raise", sets: 4, target: 15),
            ]
        ),
        WorkoutPreset(
            name: "Upper body",
            summary: "Everything above the waist",
            items: [
                PresetItem(exerciseName: "Chest press", sets: 3, target: 10),
                PresetItem(exerciseName: "Lat pulldown", sets: 3, target: 10),
                PresetItem(exerciseName: "Shoulder press", sets: 3, target: 10),
                PresetItem(exerciseName: "Seated cable row", sets: 3, target: 10),
                PresetItem(exerciseName: "Triceps pushdown", sets: 3, target: 12),
                PresetItem(exerciseName: "Bicep curl", sets: 3, target: 12),
            ]
        ),
        WorkoutPreset(
            name: "Lower body",
            summary: "Legs and core",
            items: [
                PresetItem(exerciseName: "Leg press", sets: 4, target: 10, restSec: 120),
                PresetItem(exerciseName: "Leg curl", sets: 3, target: 12),
                PresetItem(exerciseName: "Leg extension", sets: 3, target: 12),
                PresetItem(exerciseName: "Calf raise", sets: 3, target: 15),
                PresetItem(exerciseName: "Plank", sets: 3, target: 40, bodyweight: true),
            ]
        ),
        WorkoutPreset(
            name: "Full body",
            summary: "One session covering everything",
            items: [
                PresetItem(exerciseName: "Leg press", sets: 3, target: 12, restSec: 120),
                PresetItem(exerciseName: "Chest press", sets: 3, target: 12),
                PresetItem(exerciseName: "Lat pulldown", sets: 3, target: 12),
                PresetItem(exerciseName: "Seated cable row", sets: 3, target: 12),
                PresetItem(exerciseName: "Leg curl", sets: 3, target: 12),
                PresetItem(exerciseName: "Plank", sets: 3, target: 40, bodyweight: true),
            ]
        ),
    ]
}

extension AppData {
    /// Adds a preset as a new workout, creating only the exercises that aren't
    /// already in the library. Returns the new template's id.
    @discardableResult
    mutating func addPreset(_ preset: WorkoutPreset) -> String {
        var items: [TemplateItem] = []

        for item in preset.items {
            let existing = exercises.first {
                $0.name.compare(item.exerciseName, options: .caseInsensitive) == .orderedSame
            }

            let exerciseId: String
            if let existing {
                exerciseId = existing.id
            } else {
                let created = Exercise(
                    name: item.exerciseName,
                    restSec: item.restSec,
                    isBodyweight: item.bodyweight
                )
                exercises.append(created)
                exerciseId = created.id
            }

            items.append(TemplateItem(exerciseId: exerciseId, sets: item.sets, target: item.target))
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
