import SwiftUI
import WidgetKit

// 1つのアプリに複数のウィジェット。ホーム画面でウィジェットを追加するとき「TODO」「起床」などを選べる。
// 各担当は自分のウィジェット・ライブアクティビティをこの一覧に1行ずつ足す（開発規約 1章）。
@main
struct AppWidgets: WidgetBundle {
    var body: some Widget {
        TodoWidget()
        WakeWidget()
        WakeLiveActivity()
        // リリース4：太陽と月の一日・見返し・今日のまとめ・ロック画面（Widget/DayWidgets.swift）
        SunMoonWidget()
        ReviewWidget()
        SummaryWidget()
        DayLockWidget()
        // タブごと：家計簿・相談・情報（Widget/DayWidgets.swift。この一覧は 10 個まで）
        KakeiboWidget()
        ConsultWidget()
        InfoWidget()
    }
}

struct TodoEntry: TimelineEntry {
    let date: Date
    let data: TodoWidgetData
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        var d = TodoWidgetData.load()
        d.items = [TodoItem(title: "やること")]
        return TodoEntry(date: .now, data: d)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(TodoEntry(date: .now, data: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        // 15分ごとの絵を2時間ぶん先に用意する（読み直しではなく entry で。世界観の住人が少しずつ進む）。
        // 期限切れへの切り替わりを反映するため、その間の期限の直後にも1枚足す
        let now = Date()
        let data = TodoWidgetData.load(now: now)
        let quarter: TimeInterval = 15 * 60
        let slot: Double = (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter
        let first: Date = Date(timeIntervalSinceReferenceDate: slot)
        var times: [Date] = [now]
        for i in 0..<8 { times.append(first.addingTimeInterval(Double(i) * quarter)) }
        let end: Date = times.last ?? now.addingTimeInterval(2 * 3600)
        for item in data.items {
            if let due = item.due, due > now, due < end { times.append(due.addingTimeInterval(1)) }
        }
        let sorted: [Date] = Array(Set(times)).sorted()
        let entries: [TodoEntry] = sorted.prefix(24).map { TodoEntry(date: $0, data: data.at($0)) }
        completion(Timeline(entries: entries, policy: .after(end)))
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoWidget", provider: TodoProvider()) { entry in
            TodoWidgetView(data: entry.data)
                .containerBackground(for: .widget) {
                    WidgetPaletteBackground(p: entry.data.palette, date: entry.date)
                }
        }
        .configurationDisplayName("TODO")
        .description("期限が近いTODO。アプリと同じ構成・色合いで表示し、ボタンで完了にできます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
