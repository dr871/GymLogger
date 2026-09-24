import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    let sessions = store.data.finishedSessions
                    if sessions.isEmpty {
                        EmptyHint(text: "No finished sessions yet.")
                    } else {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(sessionId: session.id)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("History")
            .screen()
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let sessionId: String
    @State private var confirmDelete = false
    @State private var pendingDelete = false

    private var sessionIndex: Int? {
        store.data.sessions.firstIndex { $0.id == sessionId }
    }

    var body: some View {
        Group {
            if let index = sessionIndex {
                detail(index: index)
            } else {
                EmptyHint(text: "This session no longer exists.").padding(.horizontal, 14)
            }
        }
        .screen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .font(.app(17, weight: .semibold))
            }
        }
        .onDisappear {
            // Mutate only once every field bound to this session's index is
            // off screen — see pendingDelete.
            if pendingDelete { store.deleteSession(id: sessionId) }
        }
        .alert("Delete this session?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                pendingDelete = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes it from history and progress.")
        }
    }

    @ViewBuilder
    private func detail(index: Int) -> some View {
        let session = store.data.sessions[index]

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.longDate(session.startedAt))
                        .font(.app(22, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text(subtitle(for: session))
                        .font(.app(14))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 4)

                let records = store.data.recordsSet(in: session.id)
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Records set")
                            .font(.app(13))
                            .foregroundStyle(Palette.muted)
                        ForEach(Array(records.enumerated()), id: \.offset) { _, hit in
                            if let entry = session.entries.first(where: { $0.exerciseId == hit.exerciseId }) {
                                Text("\(entry.name) — \(hit.record.kind.title.lowercased()) \(hit.record.text(measure: entry.measure))")
                                    .font(.app(15, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                ForEach(Array(session.entries.enumerated()), id: \.element.id) { entryIndex, entry in
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.app(19, weight: .bold))
                                .foregroundStyle(Palette.text)
                            if !entry.note.isEmpty {
                                Text(entry.note)
                                    .font(.app(13))
                                    .foregroundStyle(Palette.warn)
                            }
                        }

                        if entry.doneSets.isEmpty {
                            Text("Not logged")
                                .font(.app(15))
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(Array(entry.sets.enumerated()), id: \.element.id) { setIndex, set in
                                if set.done {
                                    HStack(spacing: 8) {
                                        Text(entry.workingIndex(of: setIndex).map { "\($0 + 1)" } ?? "W")
                                            .font(.app(14, weight: set.warmup ? .semibold : .regular))
                                            .foregroundStyle(set.warmup ? Palette.warn : Palette.ghost)
                                            .frame(minWidth: 20)

                                        if entry.measure.usesWeight {
                                            WeightField(value: $store.data.sessions[index].entries[entryIndex].sets[setIndex].weight,
                                                        placeholder: entry.measure == .assisted ? "assist" : "kg")
                                        }

                                        RepsField(value: $store.data.sessions[index].entries[entryIndex].sets[setIndex].reps,
                                                  placeholder: entry.measure.repsNoun)

                                        if entry.measure == .time {
                                            Text("s").font(.app(15)).foregroundStyle(Palette.muted)
                                        }

                                        Image(systemName: "checkmark")
                                            .font(.app(18, weight: .bold))
                                            .foregroundStyle(Palette.accentInk)
                                            .frame(width: Metrics.tap, height: Metrics.tap)
                                            .background(Palette.accent)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                Button("Delete this session") { confirmDelete = true }
                    .buttonStyle(BigButtonStyle(destructive: true))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
    }

    private func subtitle(for session: Session) -> String {
        var parts = [session.name, Format.time(session.startedAt)]
        if let duration = session.duration {
            parts.append(Format.duration(duration))
        } else {
            parts.append("in progress")
        }
        return parts.joined(separator: " · ")
    }
}
