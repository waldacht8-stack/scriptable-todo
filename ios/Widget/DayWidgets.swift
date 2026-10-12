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
        let loadTimes: Set<Date> = Set(times)
        // その間にも15分ごとの絵を足す（世界観の住人が少しずつ進む）。読み直さず、直前の中身を時刻だけ変えて使う
        let quarter: TimeInterval = 15 * 60
        if step > quarter {
            let qslot: Double = (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter
            var q: Date = Date(timeIntervalSinceReferenceDate: qslot)
            while q <= end {
                times.append(q)
                q = q.addingTimeInterval(quarter)
            }
        }
        let sorted: [Date] = Array(Set(times)).sorted()
        var entries: [DayWidgetEntry] = []
        for d in sorted.prefix(72) {
            if loadTimes.contains(d) || entries.isEmpty {
                entries.append(DayWidgetEntry.load(at: d, todos: todos))
            } else if let prev = entries.last {
                entries.append(prev.moved(to: d))
            }
        }
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
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette, date: entry.date) }
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
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette, date: entry.date) }
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

// MARK: - タブごと：家計簿・相談・情報

/// 家計簿（今月の支出と予算の残り）
struct KakeiboWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KakeiboWidget", provider: DayProvider(step: 60 * 60, span: 6 * 3600)) { entry in
            KakeiboWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette, date: entry.date) }
        }
        .configurationDisplayName("家計簿")
        .description("今月の支出と予算の残り。中サイズは支出の多い分類も出します。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// 相談（今日の気分をその場で記録・夜は「1日1枚」）
struct ConsultWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ConsultWidget", provider: DayProvider(step: 60 * 60, span: 12 * 3600)) { entry in
            ConsultWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette, date: entry.date) }
        }
        .configurationDisplayName("相談")
        .description("今日の気分を5つのボタンで記録。夜に「1日1枚」がまだなら知らせます。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// 情報（未読の見出し・スプラトゥーンのステージ・Steam のセール）
struct InfoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InfoWidget", provider: DayProvider(step: 30 * 60, span: 6 * 3600)) { entry in
            InfoWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette, date: entry.date) }
        }
        .configurationDisplayName("情報")
        .description("未読の話題の見出し。中・大はスプラトゥーンのいまのステージと Steam のセールも。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
