import SwiftUI
import WidgetKit
import AppIntents

// 習慣のウィジェット（ホーム画面の小・中、ロック画面の丸・四角）。ボタンでチェックできる。

struct HabitWidgetRow: Identifiable {
    let habit: Habit
    let count: Int
    var id: String { habit.id }
    var done: Bool { count >= habit.target }
}

struct HabitWidgetData {
    var rows: [HabitWidgetRow]
    var progress: Double
    var palette: Palette

    var doneCount: Int { rows.filter(\.done).count }
    var next: HabitWidgetRow? { rows.first { !$0.done } }

    static func load(now: Date = .now) -> HabitWidgetData {
        let habits = HabitData.habits()
        let log = HabitData.log()
        let rows = habits.filter { $0.isActive(on: now) }.map { HabitWidgetRow(habit: $0, count: HabitData.count(log, $0, now)) }
        return HabitWidgetData(rows: rows, progress: HabitData.dayProgress(habits, log, on: now),
                               palette: AppTheme.from(SettingsData.load().theme).palette)
    }
}

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

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let data: HabitWidgetData
    private var p: Palette { data.palette }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .fontDesign(p.fontDesign)
    }

    // MARK: ホーム画面

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ring(size: 30, line: 5)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(data.doneCount)").font(.system(size: 22, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    Text("/\(data.rows.count)").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                }
                Spacer(minLength: 0)
            }
            if data.rows.isEmpty { emptyText }
            ForEach(data.rows.prefix(3)) { row in rowButton(row, compact: true) }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                ZStack {
                    ring(size: 76, line: 9)
                    VStack(spacing: 0) {
                        Text("\(data.doneCount)").font(.system(size: 26, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                        Text("/ \(data.rows.count)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    }
                }
                Text("今日の習慣").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
            }
            VStack(alignment: .leading, spacing: 5) {
                if data.rows.isEmpty { emptyText }
                ForEach(data.rows.prefix(4)) { row in rowButton(row, compact: false) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyText: some View {
        Text("アプリで習慣を追加してください").font(.caption).foregroundStyle(p.sub)
    }

    private func ring(size: CGFloat, line: CGFloat) -> some View {
        HabitRing(fraction: data.progress, color: p.accent, lineWidth: line).frame(width: size, height: size)
    }

    private func rowButton(_ row: HabitWidgetRow, compact: Bool) -> some View {
        let c = row.habit.tint.color(p)
        return Button(intent: CheckHabitIntent(id: row.habit.id)) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(row.done ? c : c.opacity(0.18))
                    Image(systemName: row.done ? "checkmark" : row.habit.icon)
                        .font(.system(size: compact ? 10 : 11, weight: .bold))
                        .foregroundStyle(row.done ? row.habit.tint.onColor(p) : c)
                }
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                Text(row.habit.name).font(.caption.weight(.semibold))
                    .foregroundStyle(row.done ? p.sub : p.text).lineLimit(1)
                Spacer(minLength: 0)
                if row.habit.isCount {
                    Text("\(row.count)/\(row.habit.target)").font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(row.done ? c : p.sub)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: ロック画面

    @ViewBuilder
    private var circular: some View {
        if let next = data.next {
            Button(intent: CheckHabitIntent(id: next.habit.id)) {
                Gauge(value: data.progress) {
                    Image(systemName: next.habit.icon)
                } currentValueLabel: {
                    Text("\(data.doneCount)/\(data.rows.count)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
            .buttonStyle(.plain)
        } else {
            Gauge(value: data.rows.isEmpty ? 0 : 1) {
                Image(systemName: "leaf.fill")
            } currentValueLabel: {
                Image(systemName: data.rows.isEmpty ? "leaf" : "checkmark")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("習慣 \(data.doneCount)/\(data.rows.count) 達成").font(.caption2.weight(.semibold))
            if let next = data.next {
                Button(intent: CheckHabitIntent(id: next.habit.id)) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle")
                        Text(next.habit.name).lineLimit(1)
                        if next.habit.isCount { Text("\(next.count)/\(next.habit.target)") }
                    }
                    .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
            } else {
                Text(data.rows.isEmpty ? "習慣はありません" : "すべて達成！").font(.caption.weight(.bold))
            }
            ProgressView(value: data.progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
