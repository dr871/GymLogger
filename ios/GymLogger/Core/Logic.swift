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
    /// Best estimated one-rep max across the session's working sets.
    var bestEstimatedMax: Double?
    var setCount: Int

    /// What to plot. Weighted work plots the estimated max, so the line moves
    /// while reps climb at one weight rather than only when the weight does.
    var value: Double? {
        switch measure {
        case .weight: return bestEstimatedMax
        case .assisted: return topWeight
        case .bodyweight, .time: return topReps.map(Double.init)
        }
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
        // Warm-ups are logged but never judged.
        let done = entry.doneWorkingSets
        let allSetsDone = !done.isEmpty && done.count == entry.workingSets.count
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
        let last = lastEntry(for: exerciseId)?.entry.workingSets
        let measure = exercise(id: exerciseId)?.measure ?? .weight

        // Prefilled so repeating, or taking the bump, needs no typing. A bump
        // sets every set the same; otherwise it's last time, set for set; and a
        // first session starts at the bottom of the range.
        let sets = (0..<max(1, setCount)).map { i -> SetEntry in
            let reps: Int?
            if let bumped = suggestion.reps {
                reps = bumped
            } else if let last, let previous = (last.indices.contains(i) ? last[i].reps : nil) ?? suggestion.lastReps {
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

    /// Copies a workout, named "X copy" (then "X copy 2"…), right after it.
    @discardableResult
    mutating func duplicateTemplate(id: String) -> String? {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return nil }
        let original = templates[index]
        var name = "\(original.name) copy"
        var n = 2
        while templates.contains(where: { $0.name == name }) { name = "\(original.name) copy \(n)"; n += 1 }
        let copy = WorkoutTemplate(name: name, items: original.items)
        templates.insert(copy, at: index + 1)
        return copy.id
    }

    func templateContains(templateId: String, exerciseId: String) -> Bool {
        template(id: templateId)?.items.contains { $0.exerciseId == exerciseId } ?? false
    }

    /// Appends an exercise to a workout with its measure's default range.
    /// Returns false if the workout already has it, or doesn't exist.
    @discardableResult
    mutating func addToTemplate(templateId: String, exerciseId: String) -> Bool {
        guard let t = templates.firstIndex(where: { $0.id == templateId }),
              !templateContains(templateId: templateId, exerciseId: exerciseId) else { return false }
        let range = (exercise(id: exerciseId)?.measure ?? .weight).defaultTarget
        templates[t].items.append(TemplateItem(exerciseId: exerciseId, sets: 3, targetMin: range.min, targetMax: range.max))
        return true
    }

    // MARK: - Which workout next

    /// When a workout was last finished; nil if never.
    func lastFinished(templateId: String) -> Date? {
        finishedSessions.first { $0.templateId == templateId }?.startedAt
    }

    /// The workout that has waited longest: never-done first, then least
    /// recently finished, ties in template order. With one workout, that one.
    var nextTemplateId: String? {
        var best: (id: String, last: Date?)?
        for template in templates {
            let last = lastFinished(templateId: template.id)
            guard let current = best else { best = (template.id, last); continue }
            switch (current.last, last) {
            case (nil, _): continue                       // a never-done one already leads
            case (_, nil): best = (template.id, nil)      // this one has never been done
            case let (a?, b?): if b < a { best = (template.id, last) }
            }
        }
        return best?.id
    }

    // MARK: - In-session edits

    /// Inserts a warm-up at the top of an entry: roughly half the working
    /// weight, rounded to the increment, reps at the bottom of the range.
    mutating func addWarmup(sessionIndex s: Int, entryIndex e: Int) {
        guard sessions.indices.contains(s), sessions[s].entries.indices.contains(e) else { return }
        let entry = sessions[s].entries[e]
        var weight: Double?
        if entry.measure.usesWeight, let working = entry.workingSets.first?.weight, working > 0 {
            let step = increment(for: entry.exerciseId)
            weight = step > 0 ? (working / 2 / step).rounded() * step : working / 2
        }
        let reps = entry.targetMin ?? entry.workingSets.first?.reps
        sessions[s].entries[e].sets.insert(SetEntry(weight: weight, reps: reps, done: false, warmup: true), at: 0)
    }

    /// ± the increment on every set not yet ticked, never below zero.
    mutating func adjustWeight(sessionIndex s: Int, entryIndex e: Int, by delta: Double) {
        guard sessions.indices.contains(s), sessions[s].entries.indices.contains(e) else { return }
        for i in sessions[s].entries[e].sets.indices where !sessions[s].entries[e].sets[i].done {
            let current = sessions[s].entries[e].sets[i].weight ?? 0
            sessions[s].entries[e].sets[i].weight = round2(max(0, current + delta))
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
            let done = entry.doneWorkingSets
            let weights = done.compactMap(\.weight)
            let estimates = done.compactMap { set -> Double? in
                guard let w = set.weight, w > 0, let r = set.reps, r > 0 else { return nil }
                return AppData.estimatedMax(weight: w, reps: r)
            }
            return ProgressPoint(
                id: session.id,
                date: session.startedAt,
                measure: entry.measure,
                topWeight: entry.measure == .assisted ? weights.min() : weights.max(),
                topReps: done.compactMap(\.reps).max(),
                bestEstimatedMax: estimates.max(),
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
