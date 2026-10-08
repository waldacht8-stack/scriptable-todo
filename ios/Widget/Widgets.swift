import SwiftUI
import WidgetKit

// 1つのアプリに2種類のウィジェット。ホーム画面でウィジェットを追加するとき「TODO」「起床」を選べる。
@main
struct AppWidgets: WidgetBundle {
    var body: some Widget {
        TodoWidget()
        WakeWidget()
    }
}

struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [TodoItem]
    let groupOK: Bool
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(date: .now, items: [TodoItem(title: "TODO")], groupOK: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> TodoEntry {
        TodoEntry(date: .now, items: TodoData.all(), groupOK: SharedStore.isGroupAvailable)
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodoWidget", provider: TodoProvider()) { entry in
            TodoWidgetView(items: entry.items, groupOK: entry.groupOK)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("TODO")
        .description("期限が近いTODO。ボタンで完了にできます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

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
