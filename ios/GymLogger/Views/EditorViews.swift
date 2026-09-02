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
                        .foregroundStyle(Palette.text)
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
                                    .foregroundStyle(Palette.text)
                                Text("rest \(store.data.restSec(for: item.exerciseId))s · +\(Format.weight(store.data.increment(for: item.exerciseId))) kg")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sets").font(.system(size: 13)).foregroundStyle(Palette.muted)
                                RepsField(value: Binding(
                                    get: { store.data.templates[index].items[itemIndex].sets },
                                    set: { if let v = $0 { store.data.templates[index].items[itemIndex].sets = v } }
                                ), placeholder: "3")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target reps").font(.system(size: 13)).foregroundStyle(Palette.muted)
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
    @Environment(\.dismiss) private var dismiss
    let exerciseId: String
    @State private var confirmDelete = false
    @State private var pendingDelete = false

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
                                .foregroundStyle(Palette.text)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Machine settings note")
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.muted)
                            TextField("e.g. seat 4, handles 2", text: $store.data.exercises[index].notes)
                                .foregroundStyle(Palette.warn)
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
                            .foregroundStyle(Palette.muted)

                        LabeledField(label: "Bodyweight") {
                            Toggle("", isOn: $store.data.exercises[index].isBodyweight)
                                .labelsHidden()
                                .tint(Palette.accent)
                        }

                        Text("Pull-ups, dips, planks. Sets are ticked off on reps alone and the weight box is hidden.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)

                        LabeledField(label: "Rest timer (sec)") {
                            RepsField(value: $store.data.exercises[index].restSec,
                                      placeholder: "\(store.data.settings.defaultRestSec)")
                        }

                        if !store.data.exercises[index].isBodyweight {
                            LabeledField(label: "Increase step (kg)") {
                                WeightField(value: $store.data.exercises[index].increment,
                                            placeholder: Format.weight(store.data.settings.defaultIncrement))
                            }
                        }

                        Text("Leave blank to use the defaults from Settings.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)

                        Button("Delete this exercise") { confirmDelete = true }
                            .buttonStyle(BigButtonStyle(destructive: true))
                            .padding(.top, 20)
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
        .onDisappear {
            // Deferred so no field bound to this exercise's index is on screen
            // when it goes.
            if pendingDelete { store.deleteExercise(id: exerciseId) }
        }
        .alert("Delete this exercise?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                pendingDelete = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It comes out of every workout. Past sessions keep their records.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }
}

/// Adding one exercise at a time. The standard catalogue is browsable here so
/// building a workout never means typing names by hand — or pulling in a whole
/// preset just to get at one of its exercises.
struct ExercisePickerView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let onPick: (String) -> Void
    @State private var search = ""

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    /// What's already in the library, so it's never offered twice.
    private var mine: [Exercise] {
        store.data.orderedExercises.filter { matches($0.name) }
    }

    private func catalogue(_ muscle: MuscleGroup) -> [CatalogueExercise] {
        ExerciseCatalogue.grouped(muscle).filter { entry in
            matches(entry.name) && !store.data.exercises.contains {
                $0.name.compare(entry.name, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    /// Only worth offering once the search matches nothing already on offer.
    private var canCreate: Bool {
        guard !query.isEmpty else { return false }
        return mine.isEmpty && MuscleGroup.allCases.allSatisfy { catalogue($0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search or name a new exercise", text: $search)
                        .foregroundStyle(Palette.text)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(minHeight: Metrics.tap)
                        .background(Palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if canCreate {
                        Button("Create “\(query)”") {
                            onPick(store.data.addExercise(named: query))
                        }
                        .buttonStyle(BigButtonStyle())
                    }

                    if !mine.isEmpty {
                        SectionHeader(title: "Your exercises")
                        ForEach(mine) { exercise in
                            row(name: exercise.name, detail: subtitle(for: exercise)) {
                                onPick(exercise.id)
                            }
                        }
                    }

                    ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                        let entries = catalogue(muscle)
                        if !entries.isEmpty {
                            SectionHeader(title: muscle.title)
                            ForEach(entries) { entry in
                                row(name: entry.name, detail: detail(for: entry)) {
                                    onPick(store.data.addExercise(named: entry.name))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .screen()
        }
    }

    private func row(name: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                Image(systemName: "plus").foregroundStyle(Palette.ghost)
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

    private func subtitle(for exercise: Exercise) -> String {
        var parts = ["rest \(store.data.restSec(for: exercise.id))s"]
        if exercise.isBodyweight { parts.append("bodyweight") }
        if !exercise.notes.isEmpty { parts.append(exercise.notes) }
        return parts.joined(separator: " · ")
    }

    private func detail(for entry: CatalogueExercise) -> String {
        var parts = ["rest \(entry.restSec ?? store.data.settings.defaultRestSec)s"]
        if entry.bodyweight { parts.append("bodyweight") }
        return parts.joined(separator: " · ")
    }
}
