import Foundation

extension AppData {
    /// Built from the same helpers the Home screen uses, so the widget can
    /// never quietly disagree with the app.
    func widgetSnapshot(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let name = nextTemplateId.flatMap { template(id: $0)?.name }
            ?? templates.first?.name
        let thisWeek = weeklyVolume(weeks: 1, endingAt: now, calendar: calendar).last
        return WidgetSnapshot(
            workoutName: name,
            lastFinished: finishedSessions.compactMap(\.finishedAt).max(),
            setsThisWeek: thisWeek?.totalSets ?? 0,
            generatedAt: now
        )
    }
}
