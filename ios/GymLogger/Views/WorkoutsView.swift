import SwiftUI

/// One workouts screen, reached from both Home and Settings — designing a
/// workout shouldn't be something you have to know to look for under Settings.
struct WorkoutsView: View {
    @EnvironmentObject var store: Store
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.data.templates.isEmpty {
                    EmptyHint(text: "No workouts yet. Start from a standard one below, or build your own.")
                }

                ForEach(store.data.templates) { template in
                    NavigationLink {
                        TemplateEditorView(templateId: template.id)
                    } label: {
                        WorkoutRow(
                            name: template.name,
                            detail: "\(template.items.count) exercise\(template.items.count == 1 ? "" : "s")"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button("+ New workout") { showNew = true }
                    .buttonStyle(BigButtonStyle())
                    .padding(.top, 4)

                Text("Add a standard workout to start from, then change anything in it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .navigationTitle("Workouts")
        .sheet(isPresented: $showNew) { NewWorkoutSheet() }
        .screen()
    }
}

/// The standard splits, plus the blank slate. Picking one only ever adds — it
/// never touches the workouts already there.
struct NewWorkoutSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Standard workouts")

                    ForEach(WorkoutPreset.catalogue) { preset in
                        NavigationLink {
                            PresetDetailView(preset: preset, onAdd: { dismiss() })
                        } label: {
                            WorkoutRow(
                                name: preset.name,
                                detail: "\(preset.summary) · \(preset.items.count) exercises"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("You pick which exercises to bring in. Ones you already have are reused, not duplicated.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)

                    SectionHeader(title: "Or start empty")

                    Button("Blank workout") {
                        store.data.templates.append(WorkoutTemplate(name: "New workout", items: []))
                        dismiss()
                    }
                    .buttonStyle(BigButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("New workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .screen()
        }
    }
}

struct WorkoutRow: View {
    let name: String
    let detail: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.ghost)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: Metrics.tap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }
}


/// A preset is a starting point, not a package deal: everything is ticked, and
/// you untick down to whatever you actually wanted.
struct PresetDetailView: View {
    @EnvironmentObject var store: Store
    let preset: WorkoutPreset
    let onAdd: () -> Void

    @State private var chosen: Set<String>

    init(preset: WorkoutPreset, onAdd: @escaping () -> Void) {
        self.preset = preset
        self.onAdd = onAdd
        _chosen = State(initialValue: Set(preset.items.map(\.exerciseName)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(preset.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button(chosen.count == preset.items.count ? "None" : "All") {
                        chosen = chosen.count == preset.items.count
                            ? []
                            : Set(preset.items.map(\.exerciseName))
                    }
                    .buttonStyle(ChipStyle())
                }

                ForEach(preset.items) { item in
                    Button {
                        if chosen.contains(item.exerciseName) {
                            chosen.remove(item.exerciseName)
                        } else {
                            chosen.insert(item.exerciseName)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: chosen.contains(item.exerciseName) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(chosen.contains(item.exerciseName) ? Palette.accent : Palette.ghost)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exerciseName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Text("\(item.sets) × \(item.target.map(String.init) ?? "—")\(store.data.exercises.contains { $0.name.compare(item.exerciseName, options: .caseInsensitive) == .orderedSame } ? " · already in your library" : "")")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .frame(minHeight: Metrics.tap)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Palette.line, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(addTitle) {
                    store.data.addPreset(preset, including: chosen)
                    onAdd()
                }
                .buttonStyle(BigButtonStyle(primary: true))
                .disabled(chosen.isEmpty)
                .opacity(chosen.isEmpty ? 0.4 : 1)
                .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .screen()
    }

    private var addTitle: String {
        switch chosen.count {
        case 0: return "Pick at least one"
        case 1: return "Add 1 exercise"
        default: return "Add \(chosen.count) exercises"
        }
    }
}
