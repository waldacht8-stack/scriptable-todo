import SwiftUI
import WidgetKit
import AppIntents

// TODO ウィジェットの見た目。設定の「構成」と「色合い」に合わせて描き分ける。

struct TodoWidgetData {
    var items: [TodoItem]          // 未完了（期限切れ → 近い順、重要が先頭）
    var overdue: Int
    var doneToday: Int
    var next: TodoItem?            // 時刻つきで、まだ来ていない一番近いもの
    var layout: TodayLayout
    var palette: Palette
    var groupOK: Bool

    static func load(now: Date = .now) -> TodoWidgetData {
        let all = TodoData.all()
        let open = TodoData.sorted(all.filter { !$0.done })
        let s = SettingsData.load()
        return TodoWidgetData(
            items: open,
            overdue: open.filter { $0.isOverdue(now) }.count,
            doneToday: all.filter { $0.done && ($0.doneAt.map { Calendar.current.isDateInToday($0) } ?? false) }.count,
            next: open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > now }.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) },
            layout: TodayLayout.from(s.layout),
            palette: AppTheme.from(s.theme).palette,
            groupOK: SharedStore.isGroupAvailable
        )
    }
}

/// ウィジェットの背景（色合いに合わせる）
struct WidgetPaletteBackground: View {
    let p: Palette
    var body: some View {
        LinearGradient(colors: p.background.count > 1 ? p.background : [p.background[0], p.background[0]],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let data: TodoWidgetData
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }

    /// familyOverride はアプリ内の見本画面用（環境の widgetFamily は書き換えられないため）
    init(data: TodoWidgetData, familyOverride: WidgetFamily? = nil) {
        self.data = data
        self.familyOverride = familyOverride
    }
    private var p: Palette { data.palette }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default:
                if !data.groupOK {
                    noShare
                } else {
                    switch data.layout {
                    case .focus: focus
                    case .board: board
                    case .thumb: thumb
                    case .timeline: timeline
                    }
                }
            }
        }
        .fontDesign(p.fontDesign)
    }

    // MARK: ホーム画面

    /// フォーカス：一番近い1件を大きく。丸を押すと完了
    private var focus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("あと").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                Text("\(data.items.count)").font(.system(size: 22, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                Text("件").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                Spacer()
                if data.overdue > 0 { Text("期限切れ \(data.overdue)").font(.caption2.weight(.bold)).foregroundStyle(p.overdue) }
            }
            Spacer(minLength: 0)
            if let first = data.items.first {
                Text(DueText.label(first)).font(.caption.weight(.bold))
                    .foregroundStyle(first.isOverdue() ? p.overdue : p.accent)
                Text(first.title).font(.system(size: family == .systemSmall ? 20 : 24, weight: .bold, design: p.fontDesign))
                    .foregroundStyle(p.text).lineLimit(2).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Button(intent: ToggleTodoIntent(id: first.id)) {
                    Label("完了", systemImage: "checkmark").font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(p.accent, in: RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous))
                        .foregroundStyle(p.onAccent)
                }
                .buttonStyle(.plain)
            } else {
                Text("全部終わりました").font(.headline).foregroundStyle(p.text)
                Spacer(minLength: 0)
            }
        }
    }

    /// ボード：タイルで全体を一目で
    private var board: some View {
        let cols = family == .systemSmall ? 1 : 2
        return VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
                tile("のこり", "\(data.items.count)", p.accent)
                if cols == 2 {
                    nextTile
                    tile("期限切れ", "\(data.overdue)", data.overdue > 0 ? p.overdue : p.sub)
                    tile("今日の完了", "\(data.doneToday)", p.text)
                }
            }
            if family == .systemLarge {
                lines(Array(data.items.prefix(5)), large: false)
            }
            if cols == 1, let first = data.items.first {
                Text(first.title).font(.caption.weight(.semibold)).foregroundStyle(p.text).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    /// 片手：大きなチェック付きの一覧
    private var thumb: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("のこり \(data.items.count) 件").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            lines(Array(data.items.prefix(family == .systemLarge ? 6 : (family == .systemMedium ? 3 : 2))), large: true)
            Spacer(minLength: 0)
        }
    }

    /// タイムライン：時刻の色帯つき
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(JP.date(.now)).font(.caption.weight(.bold)).foregroundStyle(p.sub)
            ForEach(data.items.prefix(family == .systemLarge ? 7 : (family == .systemMedium ? 3 : 2))) { item in
                let color = item.isOverdue() ? p.overdue : p.accent
                Button(intent: ToggleTodoIntent(id: item.id)) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
                        Text(JP.clock(item, none: "―")).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(color)
                            .frame(width: 38, alignment: .leading)
                        Text(item.title).font(.caption.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5).padding(.trailing, 6)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func lines(_ items: [TodoItem], large: Bool) -> some View {
        VStack(alignment: .leading, spacing: large ? 7 : 5) {
            ForEach(items) { item in
                Button(intent: ToggleTodoIntent(id: item.id)) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle").font(large ? .title3 : .body)
                            .foregroundStyle(item.isOverdue() ? p.overdue : p.accent)
                        Text(item.title).font(large ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                            .foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(DueText.label(item)).font(.caption2.weight(.semibold))
                            .foregroundStyle(item.isOverdue() ? p.overdue : p.sub)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
            Text(value).font(.system(size: 24, weight: .heavy, design: p.fontDesign)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(p.card, in: RoundedRectangle(cornerRadius: min(p.radius, 14), style: .continuous))
    }

    private var nextTile: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("次の予定").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
            if let due = data.next?.due {
                Text(due, style: .timer).font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(p.accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text("なし").font(.system(size: 18, weight: .heavy)).foregroundStyle(p.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(p.card, in: RoundedRectangle(cornerRadius: min(p.radius, 14), style: .continuous))
    }

    private var noShare: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("TODO", systemImage: "checklist").font(.headline).foregroundStyle(p.text)
            Text("アプリとデータを共有できません。アプリの設定 → 状態 を確認してください。")
                .font(.caption).foregroundStyle(p.sub)
            Spacer(minLength: 0)
        }
    }

    // MARK: ロック画面（単色で表示される）

    private var inline: some View {
        let first = data.items.first
        return Text(first.map { "\(JP.clock($0, none: "")) \($0.title)" } ?? "やることはありません")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(data.items.count)").font(.title2.weight(.heavy))
                Text("のこり").font(.system(size: 9, weight: .semibold))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("次のTODO" + (data.overdue > 0 ? "・期限切れ\(data.overdue)" : "")).font(.caption2.weight(.semibold))
            ForEach(data.items.prefix(2)) { item in
                Text("\(JP.clock(item, none: "―")) \(item.title)").font(.caption.weight(.bold)).lineLimit(1)
            }
            if data.items.isEmpty { Text("やることはありません").font(.caption.weight(.bold)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
