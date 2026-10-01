import Foundation

/// The small amount the home screen needs, written to the shared container by
/// the app and read by the widget.
///
/// A snapshot rather than the whole store: a widget has a tight memory budget
/// and no business decoding a year of sessions to work out one number. It also
/// means the widget never touches the live data file, so it cannot be the thing
/// that corrupts it.
struct WidgetSnapshot: Codable, Equatable {
    var workoutName: String?
    var lastFinished: Date?
    var setsThisWeek: Int
    var generatedAt: Date

    /// Whole days between the two calendar days, so a session at 9pm and a
    /// glance at 8am the next morning reads as "Yesterday", not "today".
    func daysSince(_ now: Date, calendar: Calendar = .current) -> Int? {
        guard let lastFinished else { return nil }
        let from = calendar.startOfDay(for: lastFinished)
        let to = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: from, to: to).day else { return nil }
        return max(0, days)
    }

    /// The line the widget leads with. Short: it has to fit a lock-screen
    /// circle as well as a home-screen square.
    func headline(now: Date, calendar: Calendar = .current) -> String {
        guard let days = daysSince(now, calendar: calendar) else { return "—" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days"
        }
    }

    /// What the headline means, for the families with room to say it.
    func caption(now: Date, calendar: Calendar = .current) -> String {
        guard daysSince(now, calendar: calendar) != nil else {
            return "No workouts logged yet"
        }
        return workoutName.map { "since \($0)" } ?? "since your last workout"
    }

    /// The tiny lock-screen families get one glyph-sized string.
    func compact(now: Date, calendar: Calendar = .current) -> String {
        guard let days = daysSince(now, calendar: calendar) else { return "—" }
        return "\(days)d"
    }

    // Its own coder: the widget compiles this one file, without the rest of
    // the data model, so it can't borrow AppData's.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
