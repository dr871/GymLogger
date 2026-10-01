import Foundation

/// One thing the app noticed about itself.
///
/// Never workout content — counts and outcomes only, so the report can be sent
/// to someone else without sending a training history with it.
struct DiagnosticEvent: Codable, Equatable, Identifiable {
    enum Level: String, Codable, Equatable {
        case info, warning, error

        /// Padded so the column lines up in a plain-text report.
        var column: String {
            switch self {
            case .info: return "info   "
            case .warning: return "warning"
            case .error: return "error  "
            }
        }
    }

    var id: String = newID("ev")
    var at: Date
    var level: Level
    var message: String
}

/// Facts about one file on disk, gathered for the report. Kept as plain data so
/// the report itself can be generated — and tested — without a file system.
struct FileFact: Equatable {
    var name: String
    var exists: Bool
    var bytes: Int?
    var modified: Date?
}

/// Everything the report says that isn't an event.
struct DiagnosticContext {
    var appVersion: String
    var system: String
    var device: String
    var generatedAt: Date
    var schemaVersion: Int
    var supportedSchemaVersion: Int
    var exercises: Int
    var workouts: Int
    var sessions: Int
    var loggedSets: Int
    var lastSession: Date?
    var lastExported: Date?
    var files: [FileFact] = []
    var timeZone: TimeZone = .current
}

/// A short, bounded record of what went wrong — and of the quiet recoveries
/// that are easy to miss.
///
/// Kept in its own file, deliberately. The events most worth reading are the
/// ones about `data.json` being unreadable, and a log stored inside the file it
/// is describing would be lost exactly when it was needed.
///
/// A reference type because `DataFile` holds one and writes to it from inside
/// a read.
final class DiagnosticLog {
    /// Ordinary activity is kept for a week — long enough to cover the refresh
    /// cycle a sideloaded build lives on, short enough that the file stays
    /// small without anyone thinking about it.
    static let keepRoutineFor: TimeInterval = 7 * 24 * 60 * 60
    /// Problems are kept far longer. They are rare, so they cost nothing to
    /// hold, and they are the reason the log exists: a corruption noticed a
    /// fortnight later is exactly the case a 7-day window would throw away.
    static let keepProblemsFor: TimeInterval = 30 * 24 * 60 * 60
    /// A backstop against something failing in a loop. Age alone doesn't bound
    /// the size if an event fires a thousand times an hour.
    static let limit = 500

    private(set) var events: [DiagnosticEvent]

    init(events: [DiagnosticEvent] = []) {
        self.events = events
    }

    /// Newest last.
    func record(_ level: DiagnosticEvent.Level, _ message: String, at: Date = Date()) {
        events.append(DiagnosticEvent(at: at, level: level, message: message))
        prune(now: at)
    }

    /// Age first, then the hard cap.
    func prune(now: Date) {
        events.removeAll { event in
            let window = event.level == .info ? Self.keepRoutineFor : Self.keepProblemsFor
            return now.timeIntervalSince(event.at) > window
        }
        if events.count > Self.limit {
            events.removeFirst(events.count - Self.limit)
        }
    }

    // MARK: - Persistence

    func load(from url: URL) {
        guard let raw = try? Data(contentsOf: url),
              let decoded = try? AppData.decoder().decode([DiagnosticEvent].self, from: raw)
        else { return }
        events = Array(decoded)
        // A build that sat unopened for a month shouldn't reopen full of
        // events older than the window.
        prune(now: Date())
    }

    /// Best effort by design: failing to write the log must never be the reason
    /// a save fails.
    func save(to url: URL) {
        guard let encoded = try? AppData.encoder().encode(events) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? encoded.write(to: url, options: .atomic)
    }

    // MARK: - The report

    func reportText(context c: DiagnosticContext) -> String {
        func stamp(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB_POSIX")
            f.timeZone = c.timeZone
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.string(from: date)
        }
        func day(_ date: Date?) -> String {
            guard let date else { return "never" }
            return String(stamp(date).prefix(10))
        }
        func size(_ bytes: Int?) -> String {
            guard let bytes else { return "—" }
            return bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
        }

        var out: [String] = []
        out.append("GymLogger diagnostics")
        out.append("Generated:  \(stamp(c.generatedAt))")
        out.append("App:        \(c.appVersion)")
        out.append("System:     \(c.system) · \(c.device)")
        out.append("")

        out.append("Data")
        let schema = c.schemaVersion == c.supportedSchemaVersion
            ? "\(c.schemaVersion)"
            : "\(c.schemaVersion) — this build supports \(c.supportedSchemaVersion)"
        out.append("  Schema:        \(schema)")
        out.append("  Exercises:     \(c.exercises)")
        out.append("  Workouts:      \(c.workouts)")
        out.append("  Sessions:      \(c.sessions) (\(c.loggedSets) sets logged)")
        out.append("  Last session:  \(day(c.lastSession))")
        out.append("  Last exported: \(day(c.lastExported))")
        out.append("")

        if !c.files.isEmpty {
            out.append("Files")
            for f in c.files {
                out.append(f.exists
                    ? "  \(f.name): \(size(f.bytes)), modified \(day(f.modified))"
                    : "  \(f.name): absent")
            }
            out.append("")
        }

        out.append("Events (newest first)")
        if events.isEmpty {
            out.append("  Nothing recorded.")
        } else {
            for e in events.reversed() {
                out.append("  \(stamp(e.at))  \(e.level.column)  \(e.message)")
            }
        }
        out.append("")
        out.append("No workout content is included — counts only.")
        return out.joined(separator: "\n")
    }
}
