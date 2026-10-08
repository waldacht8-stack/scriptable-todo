import SwiftUI
import WidgetKit

// 起床のウィジェット（エージェント1の担当）

struct WakeEntry: TimelineEntry {
    let date: Date
    let state: WakeState
}

struct WakeProvider: TimelineProvider {
    func placeholder(in context: Context) -> WakeEntry { WakeEntry(date: .now, state: WakeState()) }

    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        completion(WakeEntry(date: .now, state: WakeData.state()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        let e = WakeEntry(date: .now, state: WakeData.state())
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct WakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WakeWidget", provider: WakeProvider()) { entry in
            WakeWidgetView(state: entry.state)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("起床")
        .description("起床チェックインと出発までの時間。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
