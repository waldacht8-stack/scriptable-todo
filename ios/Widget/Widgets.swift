import SwiftUI
import WidgetKit

// 1つのアプリに複数のウィジェット。ホーム画面でウィジェットを追加するとき「TODO」「起床」などを選べる。
// 各担当は自分のウィジェット・ライブアクティビティをこの一覧に1行ずつ足す（開発規約 1章）。
@main
struct AppWidgets: WidgetBundle {
    var body: some Widget {
        TodoWidget()
        WakeWidget()
        HabitWidget()
        FocusTimerLiveActivity()
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
        // 期限切れへの切り替わりを反映するため、次の期限の直後にも描き直す
        let data = TodoWidgetData.load()
        let next = data.next?.due.map { $0.addingTimeInterval(1) }
        let refresh = min(next ?? .distantFuture, .now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: [TodoEntry(date: .now, data: data)], policy: .after(refresh)))
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoWidget", provider: TodoProvider()) { entry in
            TodoWidgetView(data: entry.data)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.data.palette) }
        }
        .configurationDisplayName("TODO")
        .description("期限が近いTODO。アプリと同じ構成・色合いで表示し、ボタンで完了にできます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
