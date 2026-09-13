import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var showSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let active = store.activeSession {
                        Button {
                            showSession = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Resume \(active.name)")
                                    .font(.system(size: 21, weight: .bold))
                                Text("\(active.completedSetCount) set\(active.completedSetCount == 1 ? "" : "s") done · started \(Format.time(active.startedAt))")
                                    .font(.system(size: 14))
                                    .opacity(0.75)
                            }
                        }
                        .buttonStyle(BigButtonStyle(primary: true))
                    } else if store.data.templates.isEmpty {
                        EmptyHint(text: "No workouts yet. Add a standard one, or build your own.")
                    } else {
                        ForEach(store.data.templates) { template in
                            Button {
                                store.startSession(templateId: template.id)
                                showSession = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Start \(template.name)")
                                        .font(.system(size: 21, weight: .bold))
                                    Text("\(template.items.count) exercise\(template.items.count == 1 ? "" : "s")")
                                        .font(.system(size: 14))
                                        .opacity(0.75)
                                }
                            }
                            .buttonStyle(BigButtonStyle(primary: template.id == store.data.templates.first?.id))
                        }
                    }

                    if store.activeSession == nil {
                        NavigationLink {
                            WorkoutsView()
                        } label: {
                            WorkoutRow(
                                name: store.data.templates.isEmpty ? "Add a workout" : "Workouts",
                                detail: "Design a workout, or add or remove exercises"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let week = thisWeek {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("This week")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.muted)
                            Text("\(week.now.totalSets) set\(week.now.totalSets == 1 ? "" : "s") · last week \(week.last.totalSets)")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Text(Format.muscleBreakdown(week.now))
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    SectionHeader(title: "Recent sessions")

                    let recent = Array(store.data.finishedSessions.prefix(5))
                    if recent.isEmpty {
                        EmptyHint(text: "Nothing logged yet. Your first session becomes the baseline for everything after it.")
                    } else {
                        ForEach(recent) { session in
                            NavigationLink {
                                SessionDetailView(sessionId: session.id)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let nudge = exportNudge {
                        Text(nudge)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("GymLogger")
            .navigationDestination(isPresented: $showSession) { SessionView() }
            .alert("New records", isPresented: Binding(
                get: { store.finishSummary != nil },
                set: { if !$0 { store.finishSummary = nil } }
            ), presenting: store.finishSummary) { _ in
                Button("Nice", role: .cancel) {}
            } message: { summary in
                Text(summary.lines.joined(separator: "\n"))
            }
            .screen()
        }
    }

    /// Sets this week and last, once there is anything to say.
    private var thisWeek: (now: WeekVolume, last: WeekVolume)? {
        let weeks = store.data.weeklyVolume(weeks: 2)
        guard weeks.count == 2, weeks[0].totalSets + weeks[1].totalSets > 0 else { return nil }
        return (weeks[1], weeks[0])
    }

    /// The phone is the only copy. Say so, quietly, once there's something
    /// worth losing and it's been a while.
    private var exportNudge: String? {
        guard !store.data.finishedSessions.isEmpty else { return nil }
        guard let days = store.daysSinceExport else {
            return "This history exists only on this phone. Settings › Export to keep a copy elsewhere."
        }
        guard days >= 14 else { return nil }
        return "Last exported \(days) days ago. Settings › Export to refresh the copy off this phone."
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.date(session.startedAt))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text("\(session.name) · \(session.workedExerciseCount) exercise\(session.workedExerciseCount == 1 ? "" : "s") · \(session.completedSetCount) set\(session.completedSetCount == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Palette.ghost)
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
}
