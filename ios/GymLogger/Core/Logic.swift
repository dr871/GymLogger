import Foundation

/// What last session says about what to load today.
struct Suggestion: Equatable {
    /// What to prefill: last session's top weight, or that plus the increment
    /// when the bump was earned. nil when there is nothing to go on.
    var weight: Double?
    /// Last session's top weight, for the "keep it here" escape hatch.
    var lastWeight: Double?
    /// True when every set hit the target last time and an increase is proposed.
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
    var topWeight: Double?
    var topReps: Int?
    var setCount: Int
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

    func suggestion(for exerciseId: String, excluding sessionId: String? = nil) -> Suggestion {
        guard let last = lastEntry(for: exerciseId, excluding: sessionId) else { return .none }

        let done = last.entry.doneSets
        let weights = done.compactMap(\.weight)
        let topWeight = weights.max()

        // Earned only when every set was ticked off AND hit the target. No
        // weight logged (bodyweight work) means there is nothing to bump.
        let allSetsDone = !done.isEmpty && done.count == last.entry.sets.count
        let hitTarget = last.entry.target.map { target in
            done.allSatisfy { ($0.reps ?? 0) >= target }
        } ?? false

        let earned = allSetsDone && hitTarget && topWeight != nil

        var suggested = topWeight
        if earned, let top = topWeight {
            suggested = ((top + increment(for: exerciseId)) * 100).rounded() / 100
        }

        return Suggestion(weight: suggested, lastWeight: topWeight, earned: earned)
    }

    // MARK: - Building

    func buildEntry(exerciseId: String, sets setCount: Int, target: Int?) -> SessionEntry {
        let suggestion = suggestion(for: exerciseId)
        // Prefilled with the suggestion so repeating or bumping needs no typing.
        let sets = (0..<max(1, setCount)).map { _ in
            SetEntry(weight: suggestion.weight, reps: target, done: false)
        }
        return SessionEntry(
            exerciseId: exerciseId,
            name: exercise(id: exerciseId)?.name ?? "Exercise",
            target: target,
            note: exercise(id: exerciseId)?.notes ?? "",
            sets: sets,
            suggested: suggestion.earned
        )
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
                buildEntry(exerciseId: $0.exerciseId, sets: $0.sets, target: $0.target)
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

    // MARK: - Progress

    /// Oldest first, for charting.
    func progressSeries(for exerciseId: String) -> [ProgressPoint] {
        finishedSessions.reversed().compactMap { session in
            guard let entry = session.entries.first(where: { $0.exerciseId == exerciseId }),
                  entry.hasWork else { return nil }
            let done = entry.doneSets
            return ProgressPoint(
                id: session.id,
                date: session.startedAt,
                topWeight: done.compactMap(\.weight).max(),
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
