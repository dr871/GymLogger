import SwiftUI
import Charts

struct ProgressTab: View {
    @EnvironmentObject var store: Store
    @State private var selectedId: String?
    @State private var metric: ProgressMetric = .estimatedMax

    /// Only what you've actually done: an exercise you've never logged has
    /// nothing to plot, and offering it just raises the question.
    private var exercises: [Exercise] { store.data.loggedExercises }

    private var chosen: Exercise? {
        if let selectedId, let match = exercises.first(where: { $0.id == selectedId }) { return match }
        return exercises.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if exercises.isEmpty {
                        EmptyHint(text: "Nothing logged yet. Finish a session and your lifts show up here.")
                    } else {
                        SectionHeader(title: "Exercise")
                        picker

                        if let exercise = chosen {
                            let series = store.data.progressSeries(for: exercise.id)

                            VStack(alignment: .leading, spacing: 8) {
                                if let summary = store.data.progressSummary(for: exercise.id) {
                                    Text(summary.headline)
                                        .font(.app(22, weight: .bold))
                                        .foregroundStyle(Palette.text)
                                    if let trend = summary.trend {
                                        Text(trend)
                                            .font(.app(15))
                                            .foregroundStyle(trend == "Best yet" ? Palette.accent : Palette.muted)
                                    }
                                }

                                Text(chartTitle(exercise))
                                    .font(.app(13))
                                    .foregroundStyle(Palette.ghost)
                                    .padding(.top, 4)

                                if exercise.measure == .weight {
                                    Picker("Metric", selection: $metric) {
                                        ForEach(ProgressMetric.allCases) { m in
                                            Text(m.title).tag(m)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.vertical, 2)

                                    chart(series: series, metric: metric)
                                } else {
                                    chart(series: series, metric: nil)
                                }

                                records(for: exercise)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()

                            volumeCard
                                .padding(.top, 8)

                            SectionHeader(title: "Sessions")

                            ForEach(series.reversed()) { point in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Format.date(point.date))
                                            .font(.app(17, weight: .semibold))
                                            .foregroundStyle(Palette.text)
                                        Text(rowSubtitle(point))
                                            .font(.app(14))
                                            .foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Palette.line, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Progress")
            .screen()
        }
    }

    /// Personal records for the chosen exercise, derived from history.
    @ViewBuilder
    private func records(for exercise: Exercise) -> some View {
        let records = store.data.personalRecords(for: exercise.id)
        if !records.isEmpty {
            HStack(spacing: 8) {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.kind.title)
                            .font(.app(12))
                            .foregroundStyle(Palette.muted)
                        Text(record.text(measure: exercise.measure))
                            .font(.app(16, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.text)
                        Text(Format.date(record.date))
                            .font(.app(12))
                            .foregroundStyle(Palette.ghost)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.top, 4)
        }
    }

    /// Working sets per muscle, the last eight weeks, current week last.
    private var volumeCard: some View {
        let span = store.data.weeksOfHistory(max: 8)
        let weeks = store.data.weeklyVolume(weeks: span)
        let series = VolumeBar.rows(for: weeks)
        // Explicit types: the type-checker choked on this inline (17 min build).
        let firstWeek: Date = weeks.first?.weekStart ?? Date()
        let lastWeek: Date = weeks.last?.weekStart ?? Date()
        let windowEnd: Date = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: lastWeek) ?? lastWeek
        let domain: ClosedRange<Date> = firstWeek...windowEnd

        return VStack(alignment: .leading, spacing: 8) {
            Text(span == 1 ? "Sets per muscle — this week"
                            : "Sets per muscle — last \(span) weeks")
                .font(.app(14))
                .foregroundStyle(Palette.muted)

            if series.isEmpty {
                Text("Nothing logged in the last eight weeks.")
                    .font(.app(15))
                    .foregroundStyle(Palette.muted)
                    .padding(.vertical, 12)
            } else {
                Chart(series) { row in
                    BarMark(
                        x: .value("Week", row.week, unit: .weekOfYear),
                        y: .value("Sets", row.sets)
                    )
                    .foregroundStyle(by: .value("Muscle", row.muscle))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Palette.ghost)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel().foregroundStyle(Palette.ghost)
                    }
                }
                // Pin the axis to the whole window so empty weeks show as gaps
                // rather than the chart shrinking to whatever has data.
                .chartXScale(domain: domain)
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 210)

                if let now = weeks.last {
                    Text("This week: \(Format.muscleBreakdown(now))")
                        .font(.app(14))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(exercises) { exercise in
                    Button(exercise.name) { selectedId = exercise.id }
                        .buttonStyle(ChipStyle(filled: exercise.id == chosen?.id))
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// "Plank — best set (s)", or for assisted work a reminder that the line
    /// should be heading down.
    private func chartTitle(_ exercise: Exercise) -> String {
        switch exercise.measure {
        case .weight:
            // The picker already names the metric, so keep its capitalisation
            // ("est. 1rm" reads as a typo) and don't repeat it as a unit —
            // Reps is measured in reps.
            let unit = metric.unit
            guard unit.caseInsensitiveCompare(metric.title) != .orderedSame else {
                return "\(exercise.name) — \(metric.title)"
            }
            return "\(exercise.name) — \(metric.title) (\(unit))"
        case .assisted: return "\(exercise.name) — best set (\(exercise.measure.unit)) · lower is better"
        case .bodyweight, .time: return "\(exercise.name) — best set (\(exercise.measure.unit))"
        }
    }

    @ViewBuilder
    private func chart(series: [ProgressPoint], metric: ProgressMetric?) -> some View {
        let points = series.compactMap { point -> (ProgressPoint, Double)? in
            let value = metric.map { point.value(for: $0) } ?? point.value
            return value.map { (point, $0) }
        }

        if points.isEmpty {
            Text("No data yet — log this exercise and it will show up here.")
                .font(.app(15))
                .foregroundStyle(Palette.muted)
                .padding(.vertical, 20)
        } else {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Date", point.0.date), y: .value("Value", point.1))
                        .foregroundStyle(Palette.accent.opacity(0.14))
                    LineMark(x: .value("Date", point.0.date), y: .value("Value", point.1))
                        .foregroundStyle(Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Date", point.0.date), y: .value("Value", point.1))
                        .foregroundStyle(Palette.accent)
                        .annotation(position: .top) {
                            // Few sessions: two dots and a slope say less than
                            // two numbers do.
                            if points.count <= 6 {
                                Text(pointLabel(point.0, value: point.1, metric: metric))
                                    .font(.app(12, weight: .semibold))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel().foregroundStyle(Palette.ghost)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel().foregroundStyle(Palette.ghost)
                }
            }
            .frame(height: 190)
        }
    }

    /// For the metrics that come from one set, name that set — a line that
    /// rises purely on reps at an unchanged weight otherwise says nothing
    /// about why it rose.
    private func pointLabel(_ point: ProgressPoint, value: Double, metric: ProgressMetric?) -> String {
        switch metric {
        case .estimatedMax, .heaviest, nil:
            return point.topSetText ?? Format.weight(value)
        case .reps:
            return "\(Int(value))"
        case .volume:
            return Format.weight(value.rounded())
        }
    }

    private func rowSubtitle(_ point: ProgressPoint) -> String {
        var parts: [String] = []
        switch point.measure {
        case .weight:
            parts.append(point.topWeight.map { "\(Format.weight($0)) kg" } ?? "—")
            if let reps = point.topReps { parts.append("\(reps) reps") }
            if let max = point.bestEstimatedMax { parts.append("e1RM \(Format.weight((max * 10).rounded() / 10))") }
        case .assisted:
            parts.append(point.topWeight.map { "\(Format.weight($0)) kg assistance" } ?? "—")
            if let reps = point.topReps { parts.append("\(reps) reps") }
        case .bodyweight:
            parts.append(point.topReps.map { "\($0) reps" } ?? "—")
        case .time:
            parts.append(point.topReps.map { "\($0)s" } ?? "—")
        }
        parts.append("\(point.setCount) sets")
        return parts.joined(separator: " · ")
    }
}

/// One stacked segment of the weekly volume chart. A named type keeps the
/// chart's closure trivial for the type-checker.
private struct VolumeBar: Identifiable {
    let week: Date
    let muscle: String
    let sets: Int
    var id: String { "\(week.timeIntervalSince1970)-\(muscle)" }

    static func rows(for weeks: [WeekVolume]) -> [VolumeBar] {
        var rows: [VolumeBar] = []
        for week in weeks {
            for muscle in MuscleGroup.allCases {
                if let n = week.sets[muscle], n > 0 {
                    rows.append(VolumeBar(week: week.weekStart, muscle: muscle.title, sets: n))
                }
            }
            if week.unassignedSets > 0 {
                rows.append(VolumeBar(week: week.weekStart, muscle: "Unassigned", sets: week.unassignedSets))
            }
        }
        return rows
    }
}
