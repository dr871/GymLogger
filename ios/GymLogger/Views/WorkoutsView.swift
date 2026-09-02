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
                        WorkoutRow(name: template.name, detail: "\(template.items.count) exercises")
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
                        Button {
                            store.data.addPreset(preset)
                            dismiss()
                        } label: {
                            WorkoutRow(
                                name: preset.name,
                                detail: "\(preset.summary) · \(preset.items.count) exercises"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Exercises you already have are reused, not duplicated.")
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
