import SwiftUI
import WidgetKit
import AppIntents

// 習慣のウィジェット（ホーム画面の小・中、ロック画面の丸・四角）。ボタンでチェックできる。見た目は Shared/HabitWidgetViews.swift。

struct HabitEntry: TimelineEntry {
    let date: Date
    let data: HabitWidgetData
}

struct HabitProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitEntry {
        var d = HabitWidgetData.load()
        if d.rows.isEmpty {
            d.rows = [HabitWidgetRow(habit: Habit(name: "水を飲む", icon: "drop.fill", color: .sky, target: 8, unit: "杯"), count: 3)]
        }
        return HabitEntry(date: .now, data: d)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : HabitEntry(date: .now, data: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        // 日付が変わったら描き直す
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now.addingTimeInterval(3600)
        let refresh = min(tomorrow.addingTimeInterval(5), .now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [HabitEntry(date: .now, data: .load())], policy: .after(refresh)))
    }
}

struct HabitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HabitWidget", provider: HabitProvider()) { entry in
            HabitWidgetView(data: entry.data)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.data.palette) }
        }
        .configurationDisplayName("習慣")
        .description("今日の習慣の進み具合。ボタンでそのままチェックできます。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
