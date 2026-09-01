import SwiftUI
import Charts

struct ProgressTab: View {
    @EnvironmentObject var store: Store
    @State private var selectedId: String?

    private var exercises: [Exercise] { store.data.orderedExercises }

    private var chosen: Exercise? {
        if let selectedId, let match = exercises.first(where: { $0.id == selectedId }) { return match }
        return exercises.first { !store.data.progressSeries(for: $0.id).isEmpty } ?? exercises.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if exercises.isEmpty {
                        EmptyHint(text: "No exercises yet.")
                    } else {
                        picker

                        if let exercise = chosen {
                            let series = store.data.progressSeries(for: exercise.id)
                            // Weight is the point of the chart, but bodyweight
                            // work never has one — fall back to reps so the
                            // screen still says something useful.
                            let usesWeight = series.contains { $0.topWeight != nil }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(exercise.name) — top set (\(usesWeight ? "kg" : "reps"))")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.muted)

                                chart(series: series, usesWeight: usesWeight)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()

                            ForEach(series.reversed()) { point in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Format.date(point.date))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(Palette.text)
                                        Text(rowSubtitle(point))
                                            .font(.system(size: 14))
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

    @ViewBuilder
    private func chart(series: [ProgressPoint], usesWeight: Bool) -> some View {
        let points = series.compactMap { point -> (Date, Double)? in
            let value = usesWeight ? point.topWeight : point.topReps.map(Double.init)
            return value.map { (point.date, $0) }
        }

        if points.isEmpty {
            Text("No data yet — log this exercise and it will show up here.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .padding(.vertical, 20)
        } else {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Date", point.0), y: .value("Value", point.1))
                        .foregroundStyle(Palette.accent.opacity(0.14))
                    LineMark(x: .value("Date", point.0), y: .value("Value", point.1))
                        .foregroundStyle(Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Date", point.0), y: .value("Value", point.1))
                        .foregroundStyle(Palette.accent)
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

    private func rowSubtitle(_ point: ProgressPoint) -> String {
        var parts: [String] = []
        parts.append(point.topWeight.map { "\(Format.weight($0)) kg" } ?? "bodyweight")
        if let reps = point.topReps { parts.append("\(reps) reps") }
        parts.append("\(point.setCount) sets")
        return parts.joined(separator: " · ")
    }
}
