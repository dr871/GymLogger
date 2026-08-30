import SwiftUI

struct TemplateEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let templateId: String
    @State private var showPicker = false
    @State private var confirmDelete = false

    private var index: Int? {
        store.data.templates.firstIndex { $0.id == templateId }
    }

    var body: some View {
        Group {
            if let index {
                editor(index: index)
            } else {
                EmptyHint(text: "This workout no longer exists.").padding(.horizontal, 14)
            }
        }
        .screen()
        .navigationTitle("Edit workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { exerciseId in
                if let index {
                    store.data.templates[index].items.append(
                        TemplateItem(exerciseId: exerciseId, sets: 3, target: 12)
                    )
                }
                showPicker = false
            }
        }
        .alert("Delete this workout?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                store.data.templates.removeAll { $0.id == templateId }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past sessions are kept.")
        }
    }

    @ViewBuilder
    private func editor(index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LabeledField(label: "Name") {
                    TextField("Workout name", text: $store.data.templates[index].name)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(Palette.text)
                }

                SectionHeader(title: "Exercises")

                let items = store.data.templates[index].items
                if items.isEmpty {
                    EmptyHint(text: "No exercises yet.")
                }

                ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink {
                            ExerciseEditorView(exerciseId: item.exerciseId)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.exercise(id: item.exerciseId)?.name ?? "Missing exercise")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(Palette.text)
                                Text("rest \(store.data.restSec(for: item.exerciseId))s · +\(Format.weight(store.data.increment(for: item.exerciseId))) kg")
                                    .font(.system(size: 13))
                                    .foregroundColor(Palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sets").font(.system(size: 13)).foregroundColor(Palette.muted)
                                RepsField(value: Binding(
                                    get: { store.data.templates[index].items[itemIndex].sets },
                                    set: { store.data.templates[index].items[itemIndex].sets = max(1, $0 ?? 3) }
                                ), placeholder: "3")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target reps").font(.system(size: 13)).foregroundColor(Palette.muted)
                                RepsField(value: $store.data.templates[index].items[itemIndex].target, placeholder: "12")
                            }
                        }

                        // Buttons, not drag handles: reordering has to work with
                        // damp fingers and one hand.
                        HStack(spacing: 8) {
                            Button("▲ Up") { move(index: index, from: itemIndex, by: -1) }
                                .buttonStyle(ChipStyle())
                                .disabled(itemIndex == 0)
                            Button("▼ Down") { move(index: index, from: itemIndex, by: 1) }
                                .buttonStyle(ChipStyle())
                                .disabled(itemIndex == items.count - 1)
                            Button("Remove") {
                                store.data.templates[index].items.remove(at: itemIndex)
                            }
                            .buttonStyle(ChipStyle(tint: Palette.danger))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                Button("+ Add exercise") { showPicker = true }
                    .buttonStyle(BigButtonStyle())

                if store.data.templates.count > 1 {
                    Button("Delete this workout") { confirmDelete = true }
                        .buttonStyle(BigButtonStyle(destructive: true))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
    }

    private func move(index: Int, from itemIndex: Int, by delta: Int) {
        let target = itemIndex + delta
        guard store.data.templates[index].items.indices.contains(target) else { return }
        let item = store.data.templates[index].items.remove(at: itemIndex)
        store.data.templates[index].items.insert(item, at: target)
    }
}

struct ExerciseEditorView: View {
    @EnvironmentObject var store: Store
    let exerciseId: String

    private var index: Int? {
        store.data.exercises.firstIndex { $0.id == exerciseId }
    }

    var body: some View {
        Group {
            if let index {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledField(label: "Name") {
                            TextField("Name", text: $store.data.exercises[index].name)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(Palette.text)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Machine settings note")
                                .font(.system(size: 14))
                                .foregroundColor(Palette.muted)
                            TextField("e.g. seat 4, handles 2", text: $store.data.exercises[index].notes)
                                .foregroundColor(Palette.warn)
                                .padding(.horizontal, 12)
                                .frame(minHeight: Metrics.tap)
                                .background(Palette.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Palette.line, lineWidth: 1)
                        )

                        Text("The note shows on this exercise every session.")
                            .font(.system(size: 13))
                            .foregroundColor(Palette.muted)

                        LabeledField(label: "Rest timer (sec)") {
                            RepsField(value: $store.data.exercises[index].restSec,
                                      placeholder: "\(store.data.settings.defaultRestSec)")
                        }

                        LabeledField(label: "Increase step (kg)") {
                            WeightField(value: $store.data.exercises[index].increment,
                                        placeholder: Format.weight(store.data.settings.defaultIncrement))
                        }

                        Text("Leave blank to use the defaults from Settings.")
                            .font(.system(size: 13))
                            .foregroundColor(Palette.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            } else {
                EmptyHint(text: "This exercise no longer exists.").padding(.horizontal, 14)
            }
        }
        .screen()
        .navigationTitle("Edit exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }
}

struct ExercisePickerView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let onPick: (String) -> Void
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("New exercise name", text: $newName)
                            .foregroundColor(Palette.text)
                            .padding(.horizontal, 12)
                            .frame(minHeight: Metrics.tap)
                            .background(Palette.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button("Create") {
                            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let exercise = Exercise(name: trimmed)
                            store.data.exercises.append(exercise)
                            onPick(exercise.id)
                        }
                        .buttonStyle(ChipStyle())
                    }

                    SectionHeader(title: "Existing")

                    ForEach(store.data.orderedExercises) { exercise in
                        Button {
                            onPick(exercise.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(Palette.text)
                                    Text(subtitle(for: exercise))
                                        .font(.system(size: 14))
                                        .foregroundColor(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "plus").foregroundColor(Palette.ghost)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .frame(minHeight: Metrics.tap)
                            .background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Palette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .screen()
        }
    }

    private func subtitle(for exercise: Exercise) -> String {
        var parts = ["rest \(store.data.restSec(for: exercise.id))s"]
        if !exercise.notes.isEmpty { parts.append(exercise.notes) }
        return parts.joined(separator: " · ")
    }
}
