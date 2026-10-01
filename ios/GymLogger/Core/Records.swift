import Foundation

// Personal records and weekly volume. Both are derived from history on demand
// and never stored, so they can't drift from the sessions they describe.

enum RecordKind: String, CaseIterable, Hashable {
    case heaviest, estimatedMax, leastAssistance, mostReps, longestHold

    var title: String {
        switch self {
        case .heaviest: return "Heaviest"
        case .estimatedMax: return "Est. 1RM"
        case .leastAssistance: return "Least help"
        case .mostReps: return "Most reps"
        case .longestHold: return "Longest hold"
        }
    }
}

struct PersonalRecord: Equatable, Identifiable {
    var id: String { kind.rawValue }
    var kind: RecordKind
    var value: Double
    /// The reps of the set that earned it, where that adds meaning.
    var reps: Int?
    var date: Date
    var sessionId: String

    /// "82.5 kg × 8", "112 kg", "20 kg × 6", "12 reps", "45s".
    func text(measure: Measure) -> String {
        func kg(_ v: Double) -> String { v == v.rounded() ? "\(Int(v)) kg" : "\(v) kg" }
        switch kind {
        case .heaviest, .leastAssistance:
            return reps.map { "\(kg(value)) × \($0)" } ?? kg(value)
        case .estimatedMax:
            return kg((value * 10).rounded() / 10)
        case .mostReps:
            return "\(Int(value)) reps"
        case .longestHold:
            return "\(Int(value))s"
        }
    }
}

struct WeekVolume: Equatable, Identifiable {
    var id: Date { weekStart }
    var weekStart: Date
    /// Working sets per muscle group.
    var sets: [MuscleGroup: Int]
    /// Sets on exercises with no muscle group chosen yet.
    var unassignedSets: Int

    var totalSets: Int { sets.values.reduce(0, +) + unassignedSets }
}

extension AppData {

    // MARK: - Personal records

    /// Epley: what one rep would be, given a set of `reps` at `weight`.
    static func estimatedMax(weight: Double, reps: Int) -> Double {
        reps <= 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// The best ever, per record kind, across every finished session.
    func personalRecords(for exerciseId: String) -> [PersonalRecord] {
        bestRecords(in: finishedSessions, for: exerciseId)
    }

    /// Records first achieved in this session: strictly better than every
    /// session before it.
    ///
    /// At most one per exercise, and nothing at all for an exercise's first
    /// session — a baseline isn't a record, and celebrating every kind for
    /// every exercise buried the one line that mattered. `.heaviest` is the
    /// headline where there is one; otherwise the estimate carries it, which
    /// is what catches more reps at the same weight.
    func recordsSet(in sessionId: String) -> [(exerciseId: String, record: PersonalRecord)] {
        guard let session = sessions.first(where: { $0.id == sessionId }), session.isFinished else { return [] }
        let earlier = finishedSessions.filter { $0.startedAt < session.startedAt && $0.id != sessionId }
        let headline: [RecordKind] = [.heaviest, .leastAssistance, .mostReps, .longestHold, .estimatedMax]

        var out: [(exerciseId: String, record: PersonalRecord)] = []
        for entry in session.entries where entry.hasWork {
            guard !out.contains(where: { $0.exerciseId == entry.exerciseId }) else { continue }
            let previous = bestRecords(in: earlier, for: entry.exerciseId)
            guard !previous.isEmpty else { continue }   // first time — nothing to beat

            let beaten = bestRecords(in: [session], for: entry.exerciseId).filter { record in
                guard let old = previous.first(where: { $0.kind == record.kind }) else { return false }
                return record.kind == .leastAssistance ? record.value < old.value : record.value > old.value
            }
            if let best = headline.compactMap({ kind in beaten.first { $0.kind == kind } }).first {
                out.append((entry.exerciseId, best))
            }
        }
        return out
    }

    // MARK: - Sharing

    /// A plain-text summary of a finished session, for sending to someone who
    /// asked what you did. Warm-ups and un-ticked sets are left out, as is any
    /// exercise that wasn't actually logged.
    func shareText(for sessionId: String, calendar: Calendar = .current) -> String? {
        guard let session = sessions.first(where: { $0.id == sessionId }), session.isFinished else { return nil }

        let date = DateFormatter()
        date.calendar = calendar
        date.locale = .current
        date.setLocalizedDateFormatFromTemplate("EEE d MMM")

        var lines = ["\(session.name) — \(date.string(from: session.startedAt))"]

        var totals: [String] = []
        if let duration = session.duration {
            totals.append("\(Int((duration / 60).rounded())) min")
        }
        let sets = session.entries.reduce(0) { $0 + $1.doneWorkingSets.count }
        totals.append("\(sets) set\(sets == 1 ? "" : "s")")
        lines.append(totals.joined(separator: " · "))
        lines.append("")

        for entry in session.entries where entry.hasWork {
            lines.append("\(entry.name) — \(Self.setsText(entry))")
        }

        let records = recordsSet(in: sessionId)
        if !records.isEmpty {
            lines.append("")
            for hit in records {
                let name = session.entries.first { $0.exerciseId == hit.exerciseId }?.name ?? "Exercise"
                let measure = session.entries.first { $0.exerciseId == hit.exerciseId }?.measure ?? .weight
                lines.append("Best yet: \(name) \(hit.record.text(measure: measure))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "80 kg × 12, 12, 11" while the weight holds, "80 kg × 12, 82.5 kg × 10"
    /// when it changes, and just the reps or seconds where there is no weight.
    private static func setsText(_ entry: SessionEntry) -> String {
        let done = entry.doneWorkingSets
        func kg(_ v: Double?) -> String {
            guard let v else { return "—" }
            let n = v == v.rounded() ? "\(Int(v))" : "\(v)"
            return entry.measure == .assisted ? "\(n) kg assist" : "\(n) kg"
        }

        switch entry.measure {
        case .time:
            return done.map { "\($0.reps ?? 0)s" }.joined(separator: ", ")
        case .bodyweight:
            return done.map { "\($0.reps ?? 0)" }.joined(separator: ", ") + " reps"
        case .weight, .assisted:
            let weights = Set(done.map { $0.weight ?? -1 })
            if weights.count == 1 {
                return "\(kg(done.first?.weight)) × " + done.map { "\($0.reps ?? 0)" }.joined(separator: ", ")
            }
            return done.map { "\(kg($0.weight)) × \($0.reps ?? 0)" }.joined(separator: ", ")
        }
    }

    private func bestRecords(in sessions: [Session], for exerciseId: String) -> [PersonalRecord] {
        var best: [RecordKind: PersonalRecord] = [:]

        func consider(_ kind: RecordKind, _ value: Double, reps: Int?, in session: Session, lowerIsBetter: Bool = false) {
            guard let current = best[kind] else {
                best[kind] = PersonalRecord(kind: kind, value: value, reps: reps, date: session.startedAt, sessionId: session.id)
                return
            }
            let better = lowerIsBetter ? value < current.value : value > current.value
            // Same weight: keep the set that did more with it. Otherwise ties
            // go to the earlier session — that's when the record was set.
            let tie = value == current.value
            let betterReps = tie && (reps ?? 0) > (current.reps ?? 0)
            let sameButEarlier = tie && (reps ?? 0) == (current.reps ?? 0) && session.startedAt < current.date
            if better || betterReps || sameButEarlier {
                best[kind] = PersonalRecord(kind: kind, value: value, reps: reps, date: session.startedAt, sessionId: session.id)
            }
        }

        for session in sessions {
            for entry in session.entries where entry.exerciseId == exerciseId {
                for set in entry.doneWorkingSets {
                    guard let reps = set.reps, reps > 0 else { continue }
                    switch entry.measure {
                    case .weight:
                        guard let w = set.weight, w > 0 else { continue }
                        consider(.heaviest, w, reps: reps, in: session)
                        consider(.estimatedMax, AppData.estimatedMax(weight: w, reps: reps), reps: reps, in: session)
                    case .assisted:
                        guard let help = set.weight, help >= 0 else { continue }
                        consider(.leastAssistance, help, reps: reps, in: session, lowerIsBetter: true)
                    case .bodyweight:
                        consider(.mostReps, Double(reps), reps: nil, in: session)
                    case .time:
                        consider(.longestHold, Double(reps), reps: nil, in: session)
                    }
                }
            }
        }
        return RecordKind.allCases.compactMap { best[$0] }
    }

    // MARK: - What the chart means

    /// The chart shows a shape. This says what it means, in the words you would
    /// use yourself: what you last did, and whether that was any good.
    struct ProgressSummary: Equatable {
        /// What you last did: "70 kg × 12", "45s", "10 reps".
        var headline: String
        /// How it compares: "Best yet", "Up 5 kg on last time", "First time
        /// logged". nil only when there is nothing to say.
        var trend: String?
    }

    func progressSummary(for exerciseId: String) -> ProgressSummary? {
        let series = progressSeries(for: exerciseId)
        guard let latest = series.last, latest.value != nil else { return nil }
        let measure = exercise(id: exerciseId)?.measure ?? latest.measure

        let headline: String
        // The reps of the best set, not the best reps of the day: a back-off
        // set is lighter and higher-rep, and pairing its reps with the heavy
        // weight would name a set that never happened.
        switch measure {
        case .weight:
            headline = "\(Self.number(latest.topWeight ?? 0)) kg × \(latest.topSetReps ?? 0)"
        case .assisted:
            headline = "\(Self.number(latest.topWeight ?? 0)) kg assist × \(latest.topSetReps ?? 0)"
        case .bodyweight:
            headline = "\(latest.topReps ?? 0) reps"
        case .time:
            headline = "\(latest.topReps ?? 0)s"
        }

        // Compare what you'd say out loud: the weight on the machine, or the
        // reps and seconds where there is no weight. (The chart plots estimated
        // 1RM for weighted work, but "up 6.67 kg" is nobody's idea of progress.)
        func compared(_ point: ProgressPoint) -> Double? {
            measure.usesWeight ? point.topWeight : point.topReps.map(Double.init)
        }
        guard let current = compared(latest) else { return nil }

        let earlier = series.dropLast()
        guard let previous = earlier.last, let previousValue = compared(previous) else {
            return ProgressSummary(headline: headline, trend: "First time logged")
        }

        // Assisted work improves by going down; everything else by going up.
        let best = measure.lowerIsBetter
            ? earlier.compactMap(compared).min().map { current < $0 } ?? true
            : earlier.compactMap(compared).max().map { current > $0 } ?? true
        if best { return ProgressSummary(headline: headline, trend: "Best yet") }

        let change = current - previousValue
        if change == 0 {
            // Same load: more reps at it is still progress worth naming.
            let reps = (latest.topReps ?? 0) - (previous.topReps ?? 0)
            guard measure.usesWeight, reps != 0 else {
                return ProgressSummary(headline: headline, trend: "Same as last time")
            }
            let word = abs(reps) == 1 ? "rep" : "reps"
            return ProgressSummary(headline: headline,
                                   trend: "Same weight, \(reps > 0 ? "\(reps) more" : "\(-reps) fewer") \(word)")
        }

        let improved = measure.lowerIsBetter ? change < 0 : change > 0
        let unit: String
        switch measure {
        case .weight, .assisted: unit = "kg"
        case .bodyweight: unit = abs(change) == 1 ? "rep" : "reps"
        case .time: unit = "s"
        }
        let amount = "\(Self.number(abs(change)))\(unit == "s" ? "" : " ")\(unit)"
        return ProgressSummary(headline: headline,
                               trend: "\(improved ? "Up" : "Down") \(amount) on last time")
    }

    private static func number(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : "\(v)"
    }

    // MARK: - What there is to show

    /// Exercises you have actually logged, most recently trained first. An
    /// exercise you have never done has nothing to plot, so it isn't offered.
    var loggedExercises: [Exercise] {
        var seen: [String] = []
        for session in finishedSessions {
            for entry in session.entries where entry.hasWork && !seen.contains(entry.exerciseId) {
                seen.append(entry.exerciseId)
            }
        }
        return seen.compactMap { exercise(id: $0) }
    }

    /// How many calendar weeks to draw: enough to cover your history, never
    /// more than `max`, never fewer than 1. Stops the volume chart showing
    /// eight mostly-empty weeks to someone who started last Tuesday.
    func weeksOfHistory(max limit: Int = 8, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let first = finishedSessions.last?.startedAt,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
              let weeks = calendar.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear
        else { return 1 }
        return Swift.min(limit, Swift.max(1, weeks + 1))
    }

    // MARK: - Weekly volume

    /// Working sets per muscle for the last `weeks` weeks, oldest first, the
    /// current week last. Empty weeks are included so a chart stays continuous.
    func weeklyVolume(weeks: Int, endingAt now: Date = Date(), calendar: Calendar = .current) -> [WeekVolume] {
        guard weeks > 0,
              let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        var starts: [Date] = []
        var cursor = thisWeek.start
        for _ in 0..<weeks {
            starts.insert(cursor, at: 0)
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var buckets = starts.map { WeekVolume(weekStart: $0, sets: [:], unassignedSets: 0) }
        let earliest = starts[0]

        for session in finishedSessions where session.startedAt >= earliest {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: session.startedAt),
                  let index = buckets.firstIndex(where: { $0.weekStart == interval.start }) else { continue }
            for entry in session.entries {
                let count = entry.doneWorkingSets.count
                guard count > 0 else { continue }
                if let muscle = exercise(id: entry.exerciseId)?.muscle {
                    buckets[index].sets[muscle, default: 0] += count
                } else {
                    buckets[index].unassignedSets += count
                }
            }
        }
        return buckets
    }
}
