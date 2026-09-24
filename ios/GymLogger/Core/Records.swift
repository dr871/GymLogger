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
    /// session before it. A first session sets them all — that's the baseline.
    func recordsSet(in sessionId: String) -> [(exerciseId: String, record: PersonalRecord)] {
        guard let session = sessions.first(where: { $0.id == sessionId }), session.isFinished else { return [] }
        let earlier = finishedSessions.filter { $0.startedAt < session.startedAt && $0.id != sessionId }

        var out: [(exerciseId: String, record: PersonalRecord)] = []
        for exerciseId in Set(session.entries.filter(\.hasWork).map(\.exerciseId)) {
            let previous = bestRecords(in: earlier, for: exerciseId)
            for record in bestRecords(in: [session], for: exerciseId) {
                let old = previous.first { $0.kind == record.kind }
                let lowerIsBetter = record.kind == .leastAssistance
                let beaten = old.map { lowerIsBetter ? record.value < $0.value : record.value > $0.value } ?? true
                if beaten { out.append((exerciseId, record)) }
            }
        }
        return out.sorted { $0.record.kind.rawValue < $1.record.kind.rawValue }
    }

    private func bestRecords(in sessions: [Session], for exerciseId: String) -> [PersonalRecord] {
        var best: [RecordKind: PersonalRecord] = [:]

        func consider(_ kind: RecordKind, _ value: Double, reps: Int?, in session: Session, lowerIsBetter: Bool = false) {
            guard let current = best[kind] else {
                best[kind] = PersonalRecord(kind: kind, value: value, reps: reps, date: session.startedAt, sessionId: session.id)
                return
            }
            let better = lowerIsBetter ? value < current.value : value > current.value
            // Ties go to the earlier session: that's when the record was set.
            let sameButEarlier = value == current.value && session.startedAt < current.date
            if better || sameButEarlier {
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
