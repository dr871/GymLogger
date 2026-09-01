import SwiftUI
import UIKit

struct SessionView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDiscard = false
    @State private var confirmFinishEmpty = false
    @State private var showPicker = false

    var body: some View {
        Group {
            if let sessionIndex = store.data.activeSessionIndex {
                content(sessionIndex: sessionIndex)
            } else {
                EmptyHint(text: "No active session.")
                    .padding(.horizontal, 14)
            }
        }
        .screen()
        .navigationTitle(store.activeSession?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        // Phone on the bench between sets: don't make every glance cost a
        // Face ID. Only while this screen is up, so a forgotten session
        // doesn't pin the display on all evening.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") { finish() }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                // decimalPad has no return key, so give the user a way out.
                Button("Done") { hideKeyboard() }
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let timer = store.data.timer {
                RestBar(timer: timer)
                    .id(timer.notificationId)
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { exerciseId in
                store.addExerciseToSession(exerciseId: exerciseId)
                showPicker = false
            }
        }
        .alert("Discard this session?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) {
                store.discardSession()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Everything logged today is deleted.")
        }
        .alert("No sets ticked off", isPresented: $confirmFinishEmpty) {
            Button("Finish anyway") {
                store.finishSession()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(sessionIndex: Int) -> some View {
        let startedAt = store.data.sessions[sessionIndex].startedAt

        ScrollView {
            LazyVStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Started \(Format.time(startedAt)) · \(Format.duration(context.date.timeIntervalSince(startedAt)))")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }

                ForEach(Array(store.data.sessions[sessionIndex].entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    ExerciseCardView(
                        sessionIndex: sessionIndex,
                        entryIndex: entryIndex,
                        entry: entry
                    )
                }

                Button("+ Add exercise to today") { showPicker = true }
                    .buttonStyle(BigButtonStyle())

                Button("Discard this session") { confirmDiscard = true }
                    .buttonStyle(BigButtonStyle(destructive: true))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
    }

    private func finish() {
        guard let session = store.activeSession else { return }
        if session.completedSetCount == 0 {
            confirmFinishEmpty = true
        } else {
            store.finishSession()
            dismiss()
        }
    }
}

struct ExerciseCardView: View {
    @EnvironmentObject var store: Store

    let sessionIndex: Int
    let entryIndex: Int
    let entry: SessionEntry

    /// A finished card collapses, but a mis-tapped last set has to be undoable:
    /// tapping the count badge opens it back up.
    @State private var expanded = false
    @State private var confirmRemove = false

    private var showsRows: Bool { !entry.isComplete || expanded }

    private var lastEntry: LastEntry? {
        store.data.lastEntry(for: entry.exerciseId, excluding: store.data.sessions[sessionIndex].id)
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { entry.note },
            set: { store.setNote($0, entryIndex: entryIndex) }
        )
    }

    private var indicesAreValid: Bool {
        store.data.sessions.indices.contains(sessionIndex)
            && store.data.sessions[sessionIndex].entries.indices.contains(entryIndex)
    }

    var body: some View {
        // Discarding a session, or removing an exercise, can leave this card
        // holding an index that no longer exists — SwiftUI may re-evaluate a
        // child before its parent stops including it. One guard here keeps
        // every subscript below in range.
        if indicesAreValid {
            cardBody
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // A collapsed card keeps a written note — those machine settings are
            // the whole point of recording them — but drops an empty field.
            if showsRows || !entry.note.isEmpty {
                TextField("Machine settings (e.g. seat 4, handles 2)", text: noteBinding)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.warn)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                    .padding(.top, 4)
            }

            if entry.suggested && !entry.isComplete {
                suggestionBanner
            }

            if showsRows {
                setRows
                footer
            }
        }
        .card(dimmed: entry.isComplete && !expanded)
        .alert("Remove \(entry.name) from today?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { store.removeEntry(entryIndex: entryIndex) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything logged for it today is lost. It stays in the workout template.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                ExerciseEditorView(exerciseId: entry.exerciseId)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text("\(entry.sets.count) × \(entry.target.map(String.init) ?? "—") · rest \(store.data.restSec(for: entry.exerciseId))s")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("\(entry.doneSets.count)/\(entry.sets.count)")
                        .monospacedDigit()
                    if entry.isComplete {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(Palette.surface2)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!entry.isComplete)
            .accessibilityLabel(entry.isComplete ? (expanded ? "Collapse sets" : "Show sets") : "Sets done")
        }
    }

    /// Built as a single Text so the sentence wraps as one paragraph.
    private func suggestionText(_ suggestion: Suggestion) -> Text {
        Text("Hit every rep last time — try ")
            + Text("\(Format.weight(suggestion.weight)) kg").bold()
    }

    private var suggestionBanner: some View {
        let suggestion = store.data.suggestion(for: entry.exerciseId, excluding: store.data.sessions[sessionIndex].id)
        return VStack(alignment: .leading, spacing: 8) {
            suggestionText(suggestion)
                .foregroundStyle(Palette.accent)

            Button("Keep \(Format.weight(suggestion.lastWeight))") {
                store.ignoreSuggestion(entryIndex: entryIndex)
            }
            .buttonStyle(ChipStyle())
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Palette.accent.opacity(0.28), lineWidth: 1)
        )
        .padding(.top, 10)
    }

    private var setRows: some View {
        VStack(spacing: 8) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { setIndex, set in
                HStack(spacing: 6) {
                    Text("\(setIndex + 1)")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.ghost)
                        .frame(width: 20)

                    // Last session, greyed out, right beside today's fields.
                    Text(Format.lastSet(lastEntry?.entry.sets[safe: setIndex]))
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: 92, alignment: .leading)

                    WeightField(value: $store.data.sessions[sessionIndex].entries[entryIndex].sets[setIndex].weight)

                    RepsField(value: $store.data.sessions[sessionIndex].entries[entryIndex].sets[setIndex].reps)
                        .frame(maxWidth: 72)

                    TickButton(done: set.done) {
                        store.toggleSet(entryIndex: entryIndex, setIndex: setIndex)
                    }
                }
                .opacity(set.done ? 0.75 : 1)
            }
        }
        .padding(.top, 10)
    }

    private var footer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("+ Set") { store.addSet(entryIndex: entryIndex) }
                    .buttonStyle(ChipStyle())
                Button("− Set") { store.removeSet(entryIndex: entryIndex) }
                    .buttonStyle(ChipStyle())
                Button("Rest") { store.startRest(exerciseId: entry.exerciseId, label: entry.name) }
                    .buttonStyle(ChipStyle())
                Button("Remove") { confirmRemove = true }
                    .buttonStyle(ChipStyle(tint: Palette.danger))
            }
        }
        .padding(.top, 14)
    }
}

struct TickButton: View {
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(done ? Palette.accent : Palette.surface2)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(done ? Color.clear : Palette.line, lineWidth: 1)

                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.accentInk)
                } else {
                    // An empty square reads as a disabled field; a ring reads
                    // as "tap me".
                    Circle()
                        .stroke(Palette.ghost, lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: Metrics.tap, height: Metrics.tap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Mark set not done" : "Mark set done and start rest")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
