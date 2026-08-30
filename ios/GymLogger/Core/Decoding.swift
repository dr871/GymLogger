import Foundation

// Swift's synthesized Codable init throws when a key is missing — it does *not*
// fall back to the property's default value. For a single local file that is the
// only copy of someone's training history, that is the wrong trade: one absent
// or malformed field would fail the whole decode and lose everything. These
// helpers make every non-essential field forgiving instead.

extension KeyedDecodingContainer {
    /// Missing or malformed → the fallback, never a thrown error.
    func or<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// Missing or malformed → nil.
    func maybe<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

// Explicit keys: declaring `init(from:)` below suppresses the synthesized
// CodingKeys, and encoding still uses these so the two stay in step.

extension Settings {
    enum CodingKeys: String, CodingKey { case defaultRestSec, defaultIncrement }
}

extension Exercise {
    enum CodingKeys: String, CodingKey { case id, name, notes, restSec, increment }
}

extension TemplateItem {
    enum CodingKeys: String, CodingKey { case exerciseId, sets, target }
}

extension WorkoutTemplate {
    enum CodingKeys: String, CodingKey { case id, name, items }
}

extension SetEntry {
    enum CodingKeys: String, CodingKey { case id, weight, reps, done }
}

extension SessionEntry {
    enum CodingKeys: String, CodingKey { case id, exerciseId, name, target, note, sets, suggested }
}

extension Session {
    enum CodingKeys: String, CodingKey { case id, templateId, name, startedAt, finishedAt, entries }
}

extension RestTimerState {
    enum CodingKeys: String, CodingKey { case exerciseId, label, endsAt, durationSec, notificationId }
}

extension AppData {
    enum CodingKeys: String, CodingKey {
        case version, settings, exercises, templates, sessions, activeSessionId, timer
    }
}

extension Settings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            defaultRestSec: c.or(.defaultRestSec, 90),
            defaultIncrement: c.or(.defaultIncrement, 2.5)
        )
    }
}

extension Exercise {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.or(.id, newID("ex")),
            name: c.or(.name, "Exercise"),
            notes: c.or(.notes, ""),
            restSec: c.maybe(.restSec),
            increment: c.maybe(.increment)
        )
    }
}

extension TemplateItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exerciseId: c.or(.exerciseId, ""),
            sets: c.or(.sets, 3),
            target: c.maybe(.target)
        )
    }
}

extension WorkoutTemplate {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.or(.id, newID("tpl")),
            name: c.or(.name, "Workout"),
            items: c.or(.items, [])
        )
    }
}

extension SetEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.or(.id, newID("set")),
            weight: c.maybe(.weight),
            reps: c.maybe(.reps),
            done: c.or(.done, false)
        )
    }
}

extension SessionEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.or(.id, newID("en")),
            exerciseId: c.or(.exerciseId, ""),
            name: c.or(.name, "Exercise"),
            target: c.maybe(.target),
            note: c.or(.note, ""),
            sets: c.or(.sets, []),
            suggested: c.or(.suggested, false)
        )
    }
}

extension Session {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.or(.id, newID("s")),
            templateId: c.or(.templateId, ""),
            name: c.or(.name, "Workout"),
            startedAt: c.or(.startedAt, Date()),
            finishedAt: c.maybe(.finishedAt),
            entries: c.or(.entries, [])
        )
    }
}

extension RestTimerState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exerciseId: c.or(.exerciseId, ""),
            label: c.or(.label, ""),
            endsAt: c.or(.endsAt, Date()),
            durationSec: c.or(.durationSec, 90),
            notificationId: c.or(.notificationId, UUID().uuidString)
        )
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: c.or(.version, 1),
            settings: c.or(.settings, Settings()),
            exercises: c.or(.exercises, []),
            templates: c.or(.templates, []),
            sessions: c.or(.sessions, []),
            activeSessionId: c.maybe(.activeSessionId),
            timer: c.maybe(.timer)
        )
    }
}
