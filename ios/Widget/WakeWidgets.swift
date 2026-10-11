import SwiftUI
import WidgetKit
import AppIntents

// 起床のウィジェット（エージェント1の担当）。見た目は Shared/WakeWidgetViews.swift（アプリの見本からも使う）。
// チェックイン前：次のアラームと「起きた！」ボタン。チェックイン後：出発までのカウントダウンと次のルーティン。

struct WakeProvider: TimelineProvider {
    private func entry(at d: Date) -> WakeEntry {
        WakeEntry(date: d, snap: WakeSnapshot.make(now: d), palette: AppTheme.current())
    }

    func placeholder(in context: Context) -> WakeEntry { entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        // 時間帯が切り替わる時刻（起床の2時間前・各段階・正午・出発・18時）にも描き直す
        let now = Date()
        let snap = WakeSnapshot.make(now: now)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var times: [Date] = [now]
        if let n = snap.next {
            times.append(n.first.addingTimeInterval(-2 * 3600))
            times.append(contentsOf: n.stages.map(\.at))
        }
        if let dep = snap.departure { times.append(dep) }
        if let t = snap.today { times.append(t.last.addingTimeInterval(3600)) }   // 受付の終わり
        for h in [12, 18, 24] {
            if let d = cal.date(byAdding: .hour, value: h, to: today) { times.append(d) }
        }
        let limit = now.addingTimeInterval(24 * 3600)
        let sorted = Array(Set(times.filter { $0 >= now && $0 <= limit })).sorted()
        let entries: [WakeEntry] = sorted.prefix(20).map { entry(at: $0) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct WakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WakeWidget", provider: WakeProvider()) { entry in
            WakeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette) }
        }
        .configurationDisplayName("起床")
        .description("次のアラームと「起きた！」ボタン。起きた後は出発までの時間と次のルーティン。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
