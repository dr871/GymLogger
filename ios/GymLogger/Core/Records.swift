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
