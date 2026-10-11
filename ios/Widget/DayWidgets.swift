import SwiftUI
import WidgetKit

// リリース4のウィジェット：太陽と月の一日・見返し・今日のまとめ・ロック画面（時間帯で切り替え）。
// 見た目は Shared/SunMoonWidget.swift・ReviewWidgetViews.swift・SummaryWidgetViews.swift・LockWidgetViews.swift。
// データは Shared/DayWidgetData.swift（TODO・起床）と Shared/WidgetFeeds.swift（見返し・見張り・家計簿の JSON）。

struct DayProvider: TimelineProvider {
    /// 描き直しの間隔（太陽と月は 15 分ごとに少しずつ動かす）
    let step: TimeInterval
    /// 先に用意する時間
    let span: TimeInterval

    func placeholder(in context: Context) -> DayWidgetEntry {
        let now = Date()
        return DayWidgetEntry.load(at: now, todos: TodoData.demo(now: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (DayWidgetEntry) -> Void) {
        let now = Date()
        let todos: [TodoItem] = TodoData.all()
        // ウィジェットを選ぶ画面では、TODO が空なら見本を出す
        let shown: [TodoItem] = context.isPreview && todos.isEmpty ? TodoData.demo(now: now) : todos
        completion(DayWidgetEntry.load(at: now, todos: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayWidgetEntry>) -> Void) {
        let now = Date()
        let todos: [TodoItem] = TodoData.all()
        let end: Date = now.addingTimeInterval(span)
        var times: [Date] = [now]
        let slot: Double = (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        var t: Date = Date(timeIntervalSinceReferenceDate: slot)
        while t <= end {
            times.append(t)
            t = t.addingTimeInterval(step)
        }
        // TODO の期限の直後にも描き直す（済み・期限切れの切り替わり）
        for item in todos where !item.done {
            if let due = item.due, due > now, due < end { times.append(due.addingTimeInterval(1)) }
        }
        let watch: WakeWatchFeed = .load()
        if let w = watch.nextWatchAt, w > now { times.append(w) }
        let sorted: [Date] = Array(Set(times)).sorted()
        let entries: [DayWidgetEntry] = sorted.prefix(60).map { DayWidgetEntry.load(at: $0, todos: todos) }
        let last: Date = sorted.last ?? end
        let refresh: Date = watch.isWatching(now) ? now.addingTimeInterval(5 * 60) : last
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

/// 太陽と月の一日（小・中・大）
struct SunMoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SunMoonWidget", provider: DayProvider(step: 15 * 60, span: 8 * 3600)) { entry in
            SunMoonWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    SunMoonSky(period: SkyPeriod.of(entry.date), world: entry.palette.world, accent: entry.palette.accent)
                }
                .widgetURL(WidgetLinks.todo)
        }
        .configurationDisplayName("太陽と月の一日")
        .description("昼は太陽、夜は月が弧を進みます。弧の上に今日の TODO を時刻の位置に置き、次の1件と残りの数を出します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// 見返し（中・大）
struct ReviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReviewWidget", provider: DayProvider(step: 30 * 60, span: 6 * 3600)) { entry in
            ReviewWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette) }
        }
        .configurationDisplayName("見返し")
        .description("朝・昼・夜の見返しが済んだかと、次の見返しまでの時間。押すと見返しを始めます。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// 今日のまとめ（大）
struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SummaryWidget", provider: DayProvider(step: 30 * 60, span: 6 * 3600)) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette) }
        }
        .configurationDisplayName("今日のまとめ")
        .description("次のアラームか見張りの歩数、今日の TODO の上位3件（丸で完了）、見返し、今月の支出。")
        .supportedFamilies([.systemLarge])
    }
}

/// ロック画面（時間帯で中身が変わる）
struct DayLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayLockWidget", provider: DayProvider(step: 15 * 60, span: 6 * 3600)) { entry in
            DayLockView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("いまの日和")
        .description("ふだんは次の TODO と残りの数、見張り中は歩数、夜は明日のアラーム。時間帯で切り替わります。")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
