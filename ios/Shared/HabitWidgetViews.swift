import SwiftUI
import WidgetKit
import AppIntents

// 習慣のウィジェットの見た目（アプリのウィジェット見本からも使うので Shared に置く。タイムラインは Widget/HabitWidgets.swift）。
// 世界観を選んでいれば、背景・輪・数字・動きを世界観に合わせる（部品は WorldWidget.swift）。

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
    var motion: MotionStyle = .snappy

    var doneCount: Int { rows.filter(\.done).count }
    var next: HabitWidgetRow? { rows.first { !$0.done } }

    static func load(now: Date = .now) -> HabitWidgetData {
        let habits = HabitData.habits()
        let log = HabitData.log()
        let rows = habits.filter { $0.isActive(on: now) }.map { HabitWidgetRow(habit: $0, count: HabitData.count(log, $0, now)) }
        let s: AppSettings = SettingsData.load()
        let theme: AppTheme = AppTheme.from(s.theme)
        // 動き方は世界観が優先（アプリの RootView と同じ）
        let motion: MotionStyle = World.from(s.world).motion ?? MotionStyle.from(theme)
        return HabitWidgetData(rows: rows, progress: HabitData.dayProgress(habits, log, on: now),
                               palette: AppTheme.current(s), motion: motion)
    }
}

struct HabitWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let data: HabitWidgetData
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { data.palette }
    /// 前の表示からの変化の動き（テーマ・世界観に合わせる。「動きを減らす」ではなし）
    private var change: Animation? { data.motion.change(reduced: reduceMotion) }

    /// familyOverride はアプリ内の見本画面用（環境の widgetFamily は書き換えられないため）
    init(data: HabitWidgetData, familyOverride: WidgetFamily? = nil) {
        self.data = data
        self.familyOverride = familyOverride
    }

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
                    WidgetCount(p: p, text: "\(data.doneCount)", value: Double(data.doneCount), size: 22)
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
            ringTile
            VStack(alignment: .leading, spacing: 5) {
                if data.rows.isEmpty { emptyText }
                ForEach(data.rows.prefix(4)) { row in rowButton(row, compact: false) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 中サイズの左：輪と達成数（世界観を選んでいればカードに載せる）
    @ViewBuilder private var ringTile: some View {
        let tile = VStack(spacing: 6) {
            ZStack {
                ring(size: 76, line: 9)
                VStack(spacing: 0) {
                    WidgetCount(p: p, text: "\(data.doneCount)", value: Double(data.doneCount), size: 26)
                    Text("/ \(data.rows.count)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                }
            }
            Text("今日の習慣").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
        }
        if p.world.isOn {
            tile.padding(8).widgetCard(p, radius: 18)
        } else {
            tile
        }
    }

    private var emptyText: some View {
        Text("アプリで習慣を追加してください").font(.caption).foregroundStyle(p.sub)
    }

    private func ring(size: CGFloat, line: CGFloat) -> some View {
        WidgetWorldRing(p: p, fraction: data.progress, lineWidth: line).frame(width: size, height: size)
            .animation(change, value: data.progress)
    }

    private func rowButton(_ row: HabitWidgetRow, compact: Bool) -> some View {
        let c = row.habit.tint.color(p)
        let side: CGFloat = compact ? 22 : 24
        let outline: CGFloat = 0
        let iconWeight: Font.Weight = .bold
        return Button(intent: CheckHabitIntent(id: row.habit.id)) {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(row.done ? c : c.opacity(0.18))
                    Circle().strokeBorder(p.text, lineWidth: outline)
                    Image(systemName: row.done ? "checkmark" : row.habit.icon)
                        .font(.system(size: compact ? 10 : 11, weight: iconWeight))
                        .foregroundStyle(row.done ? row.habit.tint.onColor(p) : c)
                        .contentTransition(p.world.widgetSymbolTransition)
                }
                .frame(width: side, height: side)
                .animation(change, value: row.done)
                Text(row.habit.name).font(.caption.weight(.semibold))
                    .foregroundStyle(row.done ? p.sub : p.text).lineLimit(1)
                Spacer(minLength: 0)
                if row.habit.isCount {
                    Text("\(row.count)/\(row.habit.target)").font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(row.done ? c : p.sub)
                        .contentTransition(.numericText(value: Double(row.count)))
                }
            }
        }
        .buttonStyle(.plain)
        // 押してから描き直されるまでの間、押した行を薄くして「受け付けた」ことを見せる
        .invalidatableContent()
    }

    // MARK: ロック画面（色は使われないので、世界観は文字の太さ・形で出す）

    @ViewBuilder
    private var circular: some View {
        let w: World = p.world
        let valueFont: Font? = w == .none ? nil : w.accessoryNumberFont(15)
        if let next = data.next {
            Button(intent: CheckHabitIntent(id: next.habit.id)) {
                Gauge(value: data.progress) {
                    Image(systemName: next.habit.icon)
                } currentValueLabel: {
                    Text("\(data.doneCount)/\(data.rows.count)")
                        .font(valueFont).tracking(w.accessoryTracking)
                        .contentTransition(.numericText(value: Double(data.doneCount)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
            .buttonStyle(.plain)
            .invalidatableContent()
        } else {
            Gauge(value: data.rows.isEmpty ? 0 : 1) {
                Image(systemName: "leaf.fill")
            } currentValueLabel: {
                Image(systemName: data.rows.isEmpty ? "leaf" : "checkmark")
                    .contentTransition(w.widgetSymbolTransition)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }

    private var rectangular: some View {
        let w: World = p.world
        let head: Font = w == .none ? Font.caption2.weight(.semibold) : w.accessoryFont(.caption2, .semibold)
        let line: Font = w == .none ? Font.caption.weight(.bold) : w.accessoryFont(.caption, .bold)
        return VStack(alignment: .leading, spacing: 2) {
            Text("習慣 \(data.doneCount)/\(data.rows.count) 達成").font(head)
                .contentTransition(.numericText(value: Double(data.doneCount)))
            if let next = data.next {
                Button(intent: CheckHabitIntent(id: next.habit.id)) {
                    HStack(spacing: 4) {
                        Image(systemName: w.widgetCheckSymbol(done: false))
                        Text(next.habit.name).lineLimit(1)
                        if next.habit.isCount { Text("\(next.count)/\(next.habit.target)") }
                    }
                    .font(line)
                }
                .buttonStyle(.plain)
                .invalidatableContent()
            } else {
                Text(data.rows.isEmpty ? "習慣はありません" : "すべて達成！").font(line)
            }
            ProgressView(value: data.progress)
                .animation(change, value: data.progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessoryWorldFrame(w)
    }
}
