import WidgetKit
import SwiftUI

/// One number: how long since you last trained.
///
/// It is the only thing on a home screen that changes what you do — the rest of
/// what the app knows is worth looking at in the app, at the gym, not here.
struct Entry: TimelineEntry {
    let date: Date
    /// nil when the shared container isn't reachable, which on a sideloaded
    /// build means the app group wasn't granted. Say so plainly rather than
    /// showing a confident zero.
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: WidgetSnapshot(workoutName: "Full Body",
                                                     lastFinished: Date().addingTimeInterval(-2 * 86_400),
                                                     setsThisWeek: 24,
                                                     generatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: AppGroup.readSnapshot()))
    }

    /// The number only changes when the day does, so refresh at each midnight
    /// rather than on a timer. The app also reloads the timeline the moment a
    /// session is finished, which covers the case that actually matters.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = AppGroup.readSnapshot()
        let calendar = Calendar.current

        var entries = [Entry(date: now, snapshot: snapshot)]
        for day in 1...3 {
            if let midnight = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now)) {
                entries.append(Entry(date: midnight, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct GymLoggerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(compact).font(.system(.title3, design: .rounded).weight(.bold))
                Text("since").font(.system(.caption2))
            }
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(.headline, design: .rounded))
                Text(caption).font(.system(.caption)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST WORKOUT")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(headline)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let snapshot = entry.snapshot, snapshot.lastFinished != nil {
                    Spacer(minLength: 0)
                    Text("\(snapshot.setsThisWeek) sets this week")
                        .font(.system(.caption2))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Strings

    /// No snapshot means no shared container. The widget can't fix that, but it
    /// can avoid pretending it knows something.
    private var headline: String {
        guard let snapshot = entry.snapshot else { return "—" }
        return snapshot.headline(now: entry.date)
    }

    private var caption: String {
        guard let snapshot = entry.snapshot else { return "Open GymLogger" }
        return snapshot.caption(now: entry.date)
    }

    private var compact: String {
        guard let snapshot = entry.snapshot else { return "—" }
        return snapshot.compact(now: entry.date)
    }

    private var inlineText: String {
        guard let snapshot = entry.snapshot else { return "GymLogger" }
        guard snapshot.lastFinished != nil else { return "No workouts yet" }
        return "\(snapshot.headline(now: entry.date)) since \(snapshot.workoutName ?? "last workout")"
    }
}

struct GymLoggerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymLoggerLastWorkout", provider: Provider()) { entry in
            GymLoggerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last workout")
        .description("How long since you last trained.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct GymLoggerWidgetBundle: WidgetBundle {
    var body: some Widget {
        GymLoggerWidget()
    }
}
