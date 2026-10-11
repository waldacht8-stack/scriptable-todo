import SwiftUI
import WidgetKit
import AppIntents

// 起床のウィジェット。見た目は Shared/WakeWidgetViews.swift（アプリの見本からも使う）。
// 夜：明日のアラームが入っているか（入っていなければ赤）。スタンバイでは黒地に暗い赤の枕元の時計。
// 朝：見張り中は歩数のリング、チェックイン前は次のアラームと「起きた！」、チェックイン後は出発までのカウントダウン。

struct WakeProvider: TimelineProvider {
    private func entry(at d: Date, watch: WakeWatchFeed, todos: [TodoItem]) -> WakeEntry {
        let tomorrow: Int = DayTodos(todos, now: d).tomorrow.count
        return WakeEntry(date: d, snap: WakeSnapshot.make(now: d), palette: AppTheme.current(),
                         watch: watch, tomorrowTodos: tomorrow)
    }

    func placeholder(in context: Context) -> WakeEntry {
        WakeEntry(date: .now, snap: WakeSnapshot.make(now: .now), palette: AppTheme.current())
    }

    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        completion(entry(at: .now, watch: .load(), todos: TodoData.all()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        // 時間帯が切り替わる時刻（起床の2時間前・各段階・正午・出発・18時・19時の夜）と、
        // 夜の「いま寝ると◯時間」が進むよう 30 分ごとにも描き直す。見張り中は次の見張りの時刻にも
        let now = Date()
        let snap = WakeSnapshot.make(now: now)
        let watch: WakeWatchFeed = .load()
        let todos: [TodoItem] = TodoData.all()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var times: [Date] = [now]
        if let n = snap.next {
            times.append(n.first.addingTimeInterval(-2 * 3600))
            times.append(contentsOf: n.stages.map(\.at))
        }
        if let dep = snap.departure { times.append(dep) }
        if let t = snap.today { times.append(t.last.addingTimeInterval(3600)) }   // 受付の終わり
        for h in [4, 12, 18, 19, 24, 28] {
            if let d = cal.date(byAdding: .hour, value: h, to: today) { times.append(d) }
        }
        if let w = watch.nextWatchAt { times.append(w) }
        if let w = watch.lastWatchAt { times.append(w.addingTimeInterval(60)) }
        let halfHour: TimeInterval = 30 * 60
        let slot: Double = (now.timeIntervalSinceReferenceDate / halfHour).rounded(.up) * halfHour
        let firstSlot: Date = Date(timeIntervalSinceReferenceDate: slot)
        for i in 0..<24 { times.append(firstSlot.addingTimeInterval(Double(i) * halfHour)) }
        let limit = now.addingTimeInterval(12 * 3600)
        let sorted = Array(Set(times.filter { $0 >= now && $0 <= limit })).sorted()
        let entries: [WakeEntry] = sorted.prefix(48).map { entry(at: $0, watch: watch, todos: todos) }
        let refresh: Date = watch.isWatching(now) ? now.addingTimeInterval(5 * 60) : now.addingTimeInterval(60 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct WakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WakeWidget", provider: WakeProvider()) { entry in
            WakeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette) }
        }
        .configurationDisplayName("起床")
        .description("夜は明日のアラームの確認、見張り中は歩数、朝は「起きた！」と出発までの時間。スタンバイでは枕元の時計に。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
