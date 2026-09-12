import Foundation

/// What last session says about what to do today. Double progression: climb
/// the rep range at one weight, and once every set reaches the top, move the
/// weight and drop back to the bottom of the range.
struct Suggestion: Equatable {
    /// What to prefill as the weight (for assisted work, the assistance): last
    /// session's best, or that moved by the increment when the bump was earned.
    /// nil when there is nothing to go on, or the measure has no weight.
    var weight: Double?
    /// Last session's best weight, for the "keep it here" escape hatch.
    var lastWeight: Double?
    /// What to prefill as reps (seconds for timed work) when earned; nil means
    /// repeat last session set for set.
    var reps: Int? = nil
    /// Last session's best rep count.
    var lastReps: Int? = nil
    /// True when an increase is proposed.
    var earned: Bool

    static let none = Suggestion(weight: nil, lastWeight: nil, earned: false)
}

struct LastEntry: Equatable {
    var entry: SessionEntry
    var session: Session
}

struct ProgressPoint: Identifiable, Equatable {
    var id: String
    var date: Date
    var measure: Measure
    /// The heaviest set — or, for assisted work, the one with the least help.
    var topWeight: Double?
    var topReps: Int?
    var setCount: Int

    /// What to plot: weight where there is one, otherwise reps or seconds.
    var value: Double? {
        measure.usesWeight ? topWeight : topReps.map(Double.init)
    }
}

extension AppData {

    // MARK: - Lookups

    func exercise(id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func template(id: String) -> WorkoutTemplate? {
        templates.first { $0.id == id }
    }

    func restSec(for exerciseId: String) -> Int {
        exercise(id: exerciseId)?.restSec ?? settings.defaultRestSec
    }

    func increment(for exerciseId: String) -> Double {
        exercise(id: exerciseId)?.increment ?? settings.defaultIncrement
    }

    var activeSession: Session? {
        guard let id = activeSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    var activeSessionIndex: Int? {
        guard let id = activeSessionId else { return nil }
        return sessions.firstIndex { $0.id == id }
    }

    /// Newest first.
    var finishedSessions: [Session] {
        sessions.filter(\.isFinished).sorted { $0.startedAt > $1.startedAt }
    }

    /// The most recent finished session that actually logged *this movement* —
    /// per-exercise, not per-session, so skipping a machine or running a
    /// different template still shows the right target.
    func lastEntry(for exerciseId: String, excluding sessionId: String? = nil) -> LastEntry? {
        for session in finishedSessions where session.id != sessionId {
            if let entry = session.entries.first(where: { $0.exerciseId == exerciseId && $0.hasWork }) {
                return LastEntry(entry: entry, session: session)
            }
        }
        return nil
    }

    /// `targetMin`/`targetMax` are today's range, used for where reps land
    /// after a bump and for capping rep-only progress. "Did they hit the top"
    /// is judged against the range the last session was actually aiming at.
    func suggestion(for exerciseId: String, excluding sessionId: String? = nil,
                    targetMin: Int? = nil, targetMax: Int? = nil) -> Suggestion {
        guard let last = lastEntry(for: exerciseId, excluding: sessionId) else { return .none }

        let entry = last.entry
        let measure = exercise(id: exerciseId)?.measure ?? entry.measure
        let done = entry.doneSets
        let allSetsDone = !done.isEmpty && done.count == entry.sets.count
        let topReps = done.compactMap(\.reps).max()
        let bottomToday = targetMin ?? entry.targetMin
        let step = increment(for: exerciseId)

        // Every set ticked, every set at or above the top of the range.
        let top = entry.targetMax ?? targetMax
        let hitTop = top.map { t in done.allSatisfy { ($0.reps ?? 0) >= t } } ?? false

        switch measure {
        case .weight:
            let best = done.compactMap(\.weight).max()
            let earned = allSetsDone && hitTop && best != nil
            return Suggestion(
                weight: earned ? best.map { round2($0 + step) } : best,
                lastWeight: best,
                reps: earned ? (bottomToday ?? topReps) : nil,
                lastReps: topReps,
                earned: earned
            )

        case .assisted:
            // The best set is the one that needed the least help.
            let best = done.compactMap(\.weight).min()
            var earned = allSetsDone && hitTop && best != nil
            var next = best
            if earned, let best {
                let less = round2(max(0, best - step))
                if less < best { next = less } else { earned = false }   // already unassisted
            }
            return Suggestion(
                weight: next,
                lastWeight: best,
                reps: earned ? (bottomToday ?? topReps) : nil,
                lastReps: topReps,
                earned: earned
            )

        case .bodyweight, .time:
            // No weight to move, so the reps themselves climb: once every set
            // matches the best, ask for one more (five more seconds), and stop
            // at the top of the range.
            guard let best = topReps else { return .none }
            let uniform = allSetsDone && done.allSatisfy { ($0.reps ?? 0) >= best }
            var next = best + (measure == .time ? 5 : 1)
            if let cap = targetMax ?? entry.targetMax { next = min(next, cap) }
            let earned = uniform && next > best
            return Suggestion(
                weight: nil,
                lastWeight: nil,
                reps: earned ? next : nil,
                lastReps: best,
                earned: earned
            )
        }
    }

    private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    // MARK: - Building

    func buildEntry(exerciseId: String, sets setCount: Int, targetMin: Int?, targetMax: Int?) -> SessionEntry {
        let suggestion = suggestion(for: exerciseId, targetMin: targetMin, targetMax: targetMax)
        let last = lastEntry(for: exerciseId)?.entry
        let measure = exercise(id: exerciseId)?.measure ?? .weight

        // Prefilled so repeating, or taking the bump, needs no typing. A bump
        // sets every set the same; otherwise it's last time, set for set; and a
        // first session starts at the bottom of the range.
        let sets = (0..<max(1, setCount)).map { i -> SetEntry in
            let reps: Int?
            if let bumped = suggestion.reps {
                reps = bumped
            } else if let last, let previous = (last.sets.indices.contains(i) ? last.sets[i].reps : nil) ?? suggestion.lastReps {
                reps = previous
            } else {
                reps = targetMin ?? targetMax
            }
            return SetEntry(weight: measure.usesWeight ? suggestion.weight : nil, reps: reps, done: false)
        }

        return SessionEntry(
            exerciseId: exerciseId,
            name: exercise(id: exerciseId)?.name ?? "Exercise",
            targetMin: targetMin,
            targetMax: targetMax,
            note: exercise(id: exerciseId)?.notes ?? "",
            sets: sets,
            suggested: suggestion.earned,
            measure: measure
        )
    }

    /// A fixed target: both ends of the range are the same number.
    func buildEntry(exerciseId: String, sets setCount: Int, target: Int?) -> SessionEntry {
        buildEntry(exerciseId: exerciseId, sets: setCount, targetMin: target, targetMax: target)
    }

    // MARK: - Session lifecycle

    @discardableResult
    mutating func startSession(templateId: String) -> String? {
        guard let template = template(id: templateId) else { return nil }

        let session = Session(
            templateId: templateId,
            name: template.name,
            startedAt: Date(),
            finishedAt: nil,
            entries: template.items.map {
                buildEntry(exerciseId: $0.exerciseId, sets: $0.sets, targetMin: $0.targetMin, targetMax: $0.targetMax)
            }
        )

        sessions.append(session)
        activeSessionId = session.id
        return session.id
    }

    mutating func finishSession(at date: Date = Date()) {
        guard let index = activeSessionIndex else { return }
        sessions[index].finishedAt = date
        activeSessionId = nil
        timer = nil
    }

    mutating func discardSession() {
        guard let id = activeSessionId else { return }
        sessions.removeAll { $0.id == id }
        activeSessionId = nil
        timer = nil
    }

    mutating func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        if activeSessionId == id {
            activeSessionId = nil
            timer = nil
        }
    }

    /// Editing a note updates the exercise — so it follows you into every future
    /// session — and the current entry, which is the historical snapshot.
    mutating func setNote(_ note: String, exerciseId: String, sessionIndex: Int?, entryIndex: Int?) {
        if let i = exercises.firstIndex(where: { $0.id == exerciseId }) {
            exercises[i].notes = note
        }
        if let s = sessionIndex, let e = entryIndex,
           sessions.indices.contains(s), sessions[s].entries.indices.contains(e) {
            sessions[s].entries[e].note = note
        }
    }

    // MARK: - Library

    /// Removes an exercise from the library and from every workout template.
    /// Sessions are untouched: they carry their own name snapshot, and the
    /// per-exercise history lookup keeps working on the id.
    mutating func deleteExercise(id: String) {
        exercises.removeAll { $0.id == id }
        for i in templates.indices {
            templates[i].items.removeAll { $0.exerciseId == id }
        }
    }

    // MARK: - Housekeeping

    /// A rest that ended while the app was away has already notified; carrying
    /// it back in as a permanent "Rest done" bar helps nobody.
    mutating func pruneExpiredTimer(at now: Date = Date()) {
        if let timer, timer.isDone(at: now) { self.timer = nil }
    }

    // MARK: - Progress

    /// Oldest first, for charting.
    func progressSeries(for exerciseId: String) -> [ProgressPoint] {
        finishedSessions.reversed().compactMap { session in
            guard let entry = session.entries.first(where: { $0.exerciseId == exerciseId }),
                  entry.hasWork else { return nil }
            let done = entry.doneSets
            let weights = done.compactMap(\.weight)
            return ProgressPoint(
                id: session.id,
                date: session.startedAt,
                measure: entry.measure,
                topWeight: entry.measure == .assisted ? weights.min() : weights.max(),
                topReps: done.compactMap(\.reps).max(),
                setCount: done.count
            )
        }
    }

    /// Exercises in the order they appear across templates, then any strays.
    var orderedExercises: [Exercise] {
        var seen = Set<String>()
        var out: [Exercise] = []
        for template in templates {
            for item in template.items where !seen.contains(item.exerciseId) {
                if let ex = exercise(id: item.exerciseId) {
                    out.append(ex)
                    seen.insert(ex.id)
                }
            }
        }
        out.append(contentsOf: exercises.filter { !seen.contains($0.id) })
        return out
    }

    // MARK: - Persistence

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func exportJSON() throws -> Data {
        try AppData.encoder().encode(self)
    }
}

// MARK: - Restore

struct RestorePreview: Equatable {
    var exerciseCount: Int
    var templateCount: Int
    var sessionCount: Int
    var firstSession: Date?
    var lastSession: Date?
    var hasActiveSession: Bool
}

enum RestoreError: Error, Equatable {
    /// Not JSON this app wrote, or not JSON at all.
    case unreadable
    /// Decoded, but there is nothing in it — restoring would only wipe.
    case empty
}

extension AppData {
    var preview: RestorePreview {
        let finished = finishedSessions
        return RestorePreview(
            exerciseCount: exercises.count,
            templateCount: templates.count,
            sessionCount: finished.count,
            firstSession: finished.last?.startedAt,
            lastSession: finished.first?.startedAt,
            hasActiveSession: activeSession != nil
        )
    }

    /// Parses a backup file into a store ready to replace the current one.
    /// Refuses anything that would leave the user with less than they had.
    static func restore(from raw: Data, now: Date = Date()) throws -> AppData {
        guard var decoded = try? decoder().decode(AppData.self, from: raw) else {
            throw RestoreError.unreadable
        }
        guard !decoded.exercises.isEmpty || !decoded.sessions.isEmpty else {
            throw RestoreError.empty
        }
        // A session id that points at nothing is a leftover, not state.
        if decoded.activeSession == nil { decoded.activeSessionId = nil }
        decoded.pruneExpiredTimer(at: now)
        return decoded
    }
}
