import WidgetKit
import SwiftUI

@main
struct ConnectHSWidgetBundle: WidgetBundle {
    var body: some Widget {
        ConnectHSWidget()
    }
}

struct ConnectHSWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedKeys.widgetKind, provider: LatestPostProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("connecths")
        .description("see the latest moment from your group")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LatestPostEntry: TimelineEntry {
    let date: Date
    let payload: LatestPostPayload?
}

/// Reads `LatestPostPayload` out of the App Group container on every snapshot
/// and timeline request. The app calls `WidgetCenter.reloadAllTimelines()`
/// when a new post arrives so the widget sees fresh data within seconds; the
/// 30-minute fallback policy below is just a safety net for cases where the
/// app hasn't been foregrounded recently.
struct LatestPostProvider: TimelineProvider {

    func placeholder(in context: Context) -> LatestPostEntry {
        LatestPostEntry(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestPostEntry) -> Void) {
        completion(LatestPostEntry(date: Date(), payload: LatestPostPayload.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestPostEntry>) -> Void) {
        let entry = LatestPostEntry(date: Date(), payload: LatestPostPayload.read())
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
