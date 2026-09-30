import SwiftUI
import UIKit

struct SessionView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDiscard = false
    @State private var confirmFinishEmpty = false
    @State private var showPicker = false
    /// An exercise just added to today that the workout itself doesn't have.
    /// Set once the picker has fully gone: presenting a dialog while a sheet
    /// is still dismissing gets silently dropped.
    @State private var offerToTemplate: String?
    @State private var pendingOffer: String?

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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                // decimalPad has no return key, so give the user a way out.
                Button("Done") { hideKeyboard() }
                    .font(.app(17, weight: .semibold))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let timer = store.data.timer {
                RestBar(timer: timer)
                    .id(timer.notificationId)
            }
        }
        .sheet(isPresented: $showPicker, onDismiss: {
            offerToTemplate = pendingOffer
            pendingOffer = nil
        }) {
            ExercisePickerView { exerciseId in
                store.addExerciseToSession(exerciseId: exerciseId)
                if let templateId = store.activeSession?.templateId,
                   store.data.template(id: templateId) != nil,
                   !store.data.templateContains(templateId: templateId, exerciseId: exerciseId) {
                    pendingOffer = exerciseId
                }
                showPicker = false
            }
        }
        .confirmationDialog(
            "Also add \(offerToTemplate.flatMap { store.exercise(id: $0)?.name } ?? "it") to \(store.activeSession?.name ?? "the workout")?",
            isPresented: Binding(get: { offerToTemplate != nil }, set: { if !$0 { offerToTemplate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Add to the workout") {
                if let exerciseId = offerToTemplate, let templateId = store.activeSession?.templateId {
                    store.data.addToTemplate(templateId: templateId, exerciseId: exerciseId)
                }
            }
            Button("Just today", role: .cancel) {}
        } message: {
            Text("It's in today's session either way. Adding it to the workout means it's there next time too.")
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
                        .font(.app(14))
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

                // At the end of the list, where you are when the workout is
                // over — not under your thumb at the top all session.
                Button("Finish workout") { finish() }
                    .buttonStyle(BigButtonStyle(primary: true))
                    .accessibilityIdentifier("finishWorkout")
                    .padding(.top, 8)

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
    /// A running hold on one timed set: tap ▶ to start, ■ to write the seconds.
    @State private var hold: (setIndex: Int, start: Date)?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Set-row boxes grow with the text size so nothing clips.
    @ScaledMetric private var numberColumn: CGFloat = 24
    @ScaledMetric private var repsWidth: CGFloat = 72

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
                    .font(.app(14))
                    .foregroundStyle(Palette.warn)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                    .padding(.top, 4)
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
                        .font(.app(19, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text("\(entry.workingSets.count) × \(entry.targetText)\(entry.sets.count > entry.workingSets.count ? " + warm-up" : "") · rest \(store.data.restSec(for: entry.exerciseId))s")
                        .font(.app(13))
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
                            .font(.app(11, weight: .semibold))
                    }
                }
                .font(.app(13))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(Palette.surface2)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!entry.isComplete)
            .accessibilityLabel(entry.isComplete ? (expanded ? "Collapse sets" : "Show sets") : "Sets done")
            .accessibilityValue("\(entry.doneSets.count)/\(entry.sets.count)")
            .accessibilityIdentifier("setCount-\(entry.name)")
        }
    }

    /// Built as a single Text so the sentence wraps as one paragraph.
                private var setRows: some View {
        VStack(spacing: 8) {
            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { setIndex, set in
                let working = entry.workingIndex(of: setIndex)
                AdaptiveRow(spacing: 6) {
                  HStack(spacing: 6) {
                    // The set number doubles as the warm-up toggle: "W" sets
                    // are logged but don't count for anything.
                    Button {
                        store.toggleWarmup(entryIndex: entryIndex, setIndex: setIndex)
                    } label: {
                        Text(working.map { "\($0 + 1)" } ?? "W")
                            .font(.app(14, weight: set.warmup ? .semibold : .regular))
                            .foregroundStyle(set.warmup ? Palette.warn : Palette.ghost)
                            .frame(width: numberColumn, height: Metrics.tap)
                    }
                    .buttonStyle(.plain)
                    .disabled(set.done)
                    .accessibilityLabel(set.warmup ? "Warm-up set. Make it a working set" : "Working set \((working ?? 0) + 1). Make it a warm-up")

                    // Last session's matching working set, greyed out beside
                    // today's fields. Warm-ups don't line up with anything.
                    Text(set.warmup ? "warm-up" : Format.lastSet(working.flatMap { lastEntry?.entry.workingSets[safe: $0] }, measure: entry.measure))
                        .font(.app(14))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: 88, alignment: .leading)
                  }

                  HStack(spacing: 6) {

                    // Nothing to log for pull-ups or a plank, so no empty box.
                    if entry.measure.usesWeight {
                        WeightField(value: $store.data.sessions[sessionIndex].entries[entryIndex].sets[setIndex].weight,
                                    placeholder: entry.measure == .assisted ? "assist" : "kg")
                            .accessibilityIdentifier("weight-\(entry.name)-\(setIndex)")
                    }

                    if entry.measure == .time, let hold, hold.setIndex == setIndex {
                        // Counting up in place of the field until ■ is tapped.
                        TimelineView(.periodic(from: hold.start, by: 1)) { context in
                            let elapsed = Int(context.date.timeIntervalSince(hold.start).rounded(.down))
                            Text("\(elapsed)s")
                                .font(.app(18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: repsWidth, minHeight: Metrics.tap)
                                .onChange(of: elapsed) { _, now in
                                    if now == set.reps { Haptics.done() }   // reached the target
                                }
                        }
                        Button {
                            let seconds = Int(Date().timeIntervalSince(hold.start).rounded())
                            store.data.sessions[sessionIndex].entries[entryIndex].sets[setIndex].reps = max(1, seconds)
                            self.hold = nil
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.app(16, weight: .semibold))
                                .frame(width: Metrics.tap, height: Metrics.tap)
                        }
                        .buttonStyle(ChipStyle(filled: true))
                        .accessibilityLabel("Stop the hold and log the seconds")
                    } else {
                        RepsField(value: $store.data.sessions[sessionIndex].entries[entryIndex].sets[setIndex].reps,
                                  placeholder: entry.measure.repsNoun)
                            .frame(maxWidth: repsWidth)

                        if entry.measure == .time {
                            Button {
                                hideKeyboard()
                                hold = (setIndex, Date())
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.app(16, weight: .semibold))
                                    .frame(width: Metrics.tap, height: Metrics.tap)
                            }
                            .buttonStyle(ChipStyle())
                            .disabled(set.done || hold != nil)
                            .accessibilityLabel("Start timing this hold")
                        }
                    }

                    TickButton(done: set.done, enabled: set.done || entry.canComplete(setIndex: setIndex)) {
                        store.toggleSet(entryIndex: entryIndex, setIndex: setIndex)
                    }
                  }
                }
                .opacity(set.done ? 0.75 : 1)
            }

            if let blocked = blockedReason {
                Text(blocked)
                    .font(.app(13))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 10)
    }

    /// Shown only while something is actually blocked, so a disabled tick never
    /// looks like a dead control.
    private var blockedReason: String? {
        let pending = entry.sets.indices.filter { !entry.sets[$0].done }
        guard pending.contains(where: { !entry.canComplete(setIndex: $0) }) else { return nil }

        let needsReps = pending.contains { (entry.sets[$0].reps ?? 0) <= 0 }
        switch entry.measure {
        case .bodyweight:
            return "Enter reps to tick a set off."
        case .time:
            return "Enter the seconds held to tick a set off."
        case .assisted:
            let needsHelp = pending.contains { entry.sets[$0].weight == nil || entry.sets[$0].weight! < 0 }
            switch (needsHelp, needsReps) {
            case (true, true): return "Enter the assistance (0 if none) and reps to tick a set off."
            case (true, false): return "Enter the assistance — 0 if none — to tick a set off."
            default: return "Enter reps to tick a set off."
            }
        case .weight:
            let needsWeight = pending.contains { (entry.sets[$0].weight ?? 0) <= 0 }
            switch (needsWeight, needsReps) {
            case (true, true): return "Enter a weight and reps to tick a set off."
            case (true, false): return "Enter a weight to tick a set off."
            default: return "Enter reps to tick a set off."
            }
        }
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
    var enabled: Bool = true
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
                        .font(.app(20, weight: .bold))
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
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(done ? "Mark set not done" : "Mark set done and start rest")
        .accessibilityHint(enabled ? "" : "Enter this set's numbers first")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
