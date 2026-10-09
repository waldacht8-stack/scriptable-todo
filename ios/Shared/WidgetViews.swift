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
    var doneItems: [TodoItem] = []  // 今日の完了（ながれ構成で使う）
    var showDone = false            // 今日の完了も出す（アプリの目のボタン。チェックリストで使う）

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
            groupOK: SharedStore.isGroupAvailable,
            doneItems: all.filter { $0.done && ($0.doneAt.map { Calendar.current.isDateInToday($0) } ?? false) },
            showDone: s.showDone
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
                    case .kanban: kanban
                    case .checklist: checklist
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
                    .contentTransition(.numericText())
                    .widgetAccentable()
                Text("件").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                Spacer()
                if data.overdue > 0 {
                    Text("期限切れ \(data.overdue)").font(.caption2.weight(.bold)).foregroundStyle(p.overdue)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            if let first = data.items.first {
                // 完了すると、この1件が上へ抜けて次の1件が下から入る
                VStack(alignment: .leading, spacing: 6) {
                    Text(DueText.label(first)).font(.caption.weight(.bold))
                        .foregroundStyle(first.isOverdue() ? p.overdue : p.accent)
                        .widgetAccentable()
                    Text(first.title).font(.system(size: family == .systemSmall ? 20 : 24, weight: .bold, design: p.fontDesign))
                        .foregroundStyle(p.text).lineLimit(2).minimumScaleFactor(0.7)
                }
                .id(first.id)
                .transition(.push(from: .bottom))
                Spacer(minLength: 0)
                Button(intent: ToggleTodoIntent(id: first.id)) {
                    Label("完了", systemImage: "checkmark").font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(p.accent, in: RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous))
                        .foregroundStyle(p.onAccent)
                        .invalidatableContent()
                }
                .buttonStyle(.plain)
            } else {
                Text("全部終わりました").font(.headline).foregroundStyle(p.text)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: グループ（期限ごとの見出し）

    /// 小：期限切れ・今日・明日の件数。中・大：色帯の見出しつきで期限ごとの一覧
    @ViewBuilder private var board: some View {
        if family == .systemSmall {
            groupCounts
        } else {
            groupList
        }
    }

    private var groupCounts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("のこり \(data.items.count) 件").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                .contentTransition(.numericText())
            countRow(.overdue)
            countRow(.today)
            countRow(.tomorrow)
            Spacer(minLength: 0)
        }
    }

    private func countRow(_ g: WGroup) -> some View {
        let n: Int = data.items.filter { WGroup.of($0) == g }.count
        let barColor: Color = g.color(p)
        let numberColor: Color = n > 0 ? barColor : p.sub
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 10), style: .continuous)
        return HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(barColor).frame(width: 4, height: 20)
            Text(g.name).font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(n)").font(.system(size: 22, weight: .heavy, design: p.fontDesign)).foregroundStyle(numberColor)
                .contentTransition(.numericText())
                .widgetAccentable()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(p.card, in: shape)
    }

    private var groupRows: [WGroupRow] {
        let budget: Int = family == .systemLarge ? 13 : 5
        var rows: [WGroupRow] = []
        for g in WGroup.allCases {
            let items: [TodoItem] = data.items.filter { WGroup.of($0) == g }
            if items.isEmpty || rows.count + 2 > budget { continue }
            rows.append(WGroupRow(id: "group-\(g.rawValue)", group: g, count: items.count, item: nil))
            for item in items where rows.count < budget {
                rows.append(WGroupRow(id: item.id, group: g, count: 0, item: item))
            }
        }
        return rows
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groupRows) { row in
                if let item = row.item {
                    itemLine(item, color: row.group.color(p))
                } else {
                    sectionBar(row.group.name, row.count, row.group.color(p))
                }
            }
            if data.items.isEmpty { emptyText("やることはありません") }
            Spacer(minLength: 0)
        }
    }

    private func sectionBar(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 14)
            Text(title).font(.caption.weight(.heavy)).foregroundStyle(p.text)
            Text("\(count)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
    }

    /// 行の出入り：完了した行は右へ抜け、新しい行は下から入る（ボタンを押したあとの描き直しで動く）
    static let rowTransition: AnyTransition = .asymmetric(
        insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
        removal: AnyTransition.move(edge: .trailing).combined(with: .opacity)
    )

    /// 丸の印：押すと処理中は薄くなり（invalidatableContent）、描き直しで印が入れ替わる
    private func checkIcon(_ symbol: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .invalidatableContent()
            .widgetAccentable()
    }

    /// 1行：丸を押すと完了（どの構成でも共通）
    private func itemLine(_ item: TodoItem, color: Color) -> some View {
        let clock: String = JP.clock(item, none: "")
        let small: Bool = family == .systemSmall
        let clockFont: Font = small ? Font.system(size: 10, weight: .bold).monospacedDigit() : Font.caption2.weight(.semibold).monospacedDigit()
        let titleFont: Font = small ? Font.system(size: 12, weight: .semibold) : Font.caption.weight(.semibold)
        let circleSize: CGFloat = small ? 11 : 13
        return Button(intent: ToggleTodoIntent(id: item.id)) {
            HStack(alignment: .firstTextBaseline, spacing: small ? 4 : 6) {
                checkIcon("circle", size: circleSize, color: color)
                if small && !clock.isEmpty {
                    // 小さいサイズは時刻を左に（折り返さない）
                    Text(clock).font(clockFont).foregroundStyle(color).lineLimit(1).fixedSize()
                }
                Text(item.title).font(titleFont).foregroundStyle(p.text).lineLimit(small ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true) // 縦につぶさない（入らない行は FitList が省く）
                Spacer(minLength: 0)
                if !small && !clock.isEmpty {
                    Text(clock).font(clockFont).foregroundStyle(p.sub).lineLimit(1).fixedSize()
                }
            }
        }
        .buttonStyle(.plain)
        .transition(Self.rowTransition)
    }

    private func emptyText(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
    }

    // MARK: 週間（7日の帯と今日のやること）

    private static let weekdaySymbols: [String] = ["日", "月", "火", "水", "木", "金", "土"]

    private var thumb: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let todays: [TodoItem] = todayItems
        let limit: Int = family == .systemLarge ? 9 : 3
        let chipGap: CGFloat = family == .systemSmall ? 2 : 4
        let gap: CGFloat = family == .systemSmall ? 4 : 5
        return VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: chipGap) {
                ForEach(0..<7, id: \.self) { i in
                    dayChip(cal.date(byAdding: .day, value: i, to: today) ?? today, selected: i == 0)
                }
            }
            if family != .systemSmall {
                Text("今日のやること \(todays.count)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    .contentTransition(.numericText())
            }
            if todays.isEmpty {
                emptyText("今日のやることはありません")
                Spacer(minLength: 0)
            } else {
                // 入るだけ並べ、入らない分は「ほか n 件」（題名を縦につぶして途中で切らない）
                FitList(items: todays, maxCount: limit, spacing: gap, moreColor: p.sub) { item in
                    itemLine(item, color: item.isOverdue() ? p.overdue : p.accent)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// 期限切れと今日の期限のもの
    private var todayItems: [TodoItem] {
        let cal = Calendar.current
        return data.items.filter { item in
            guard let due = item.due else { return false }
            return item.isOverdue() || cal.isDateInToday(due)
        }
    }

    private func dayChip(_ d: Date, selected: Bool) -> some View {
        let cal = Calendar.current
        let small: Bool = family == .systemSmall
        let has: Bool = data.items.contains { item in item.due.map { cal.isDate($0, inSameDayAs: d) } ?? false }
        let fg: Color = selected ? p.onAccent : p.text
        let bg: Color = selected ? p.accent : p.card
        let dot: Color = has ? (selected ? p.onAccent : p.accent) : Color.clear
        let wd: String = Self.weekdaySymbols[cal.component(.weekday, from: d) - 1]
        let wdSize: CGFloat = small ? 8 : 10
        let daySize: CGFloat = small ? 11 : 15
        let shape = RoundedRectangle(cornerRadius: small ? 6 : 9, style: .continuous)
        return VStack(spacing: 1) {
            Text(wd).font(.system(size: wdSize, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(cal.component(.day, from: d))").font(.system(size: daySize, weight: .heavy).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
            Circle().fill(dot).frame(width: 4, height: 4)
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity)
        .padding(.vertical, small ? 3 : 5)
        .background(bg, in: shape)
    }

    // MARK: ながれ（1本の線と「いま」の印）

    /// 時刻の列の幅（「00:00」が入る幅。文字は fixedSize で折り返さない）
    private var flowTimeWidth: CGFloat { family == .systemSmall ? 30 : 38 }

    private var timeline: some View {
        let now = Date.now
        let entries: [TodoItem] = flowEntries
        let nowIndex: Int = entries.firstIndex { !$0.done && ($0.due ?? .distantFuture) > now } ?? entries.count
        let maxRows: Int = family == .systemLarge ? 10 : (family == .systemMedium ? 4 : 3)
        let before: Int = family == .systemLarge ? 3 : 1
        let start: Int = max(0, min(nowIndex - before, entries.count - maxRows))
        let shown: [TodoItem] = Array(entries.dropFirst(start).prefix(maxRows))
        let markerAt: Int = nowIndex - start
        let lineX: CGFloat = flowTimeWidth + 6 + 6
        return VStack(alignment: .leading, spacing: 5) {
            if family != .systemSmall {
                Text("のこり \(data.items.count) 件 ・ 完了 \(data.doneToday)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    .contentTransition(.numericText())
            }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(p.sub.opacity(0.35)).frame(width: 2).padding(.leading, lineX).padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { pair in
                        if pair.offset == markerAt { nowMarker }
                        flowRow(pair.element)
                    }
                    if markerAt >= shown.count { nowMarker }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if entries.isEmpty { emptyText("やることはありません") }
            Spacer(minLength: 0)
        }
    }

    /// 今日の完了＋期限つきの未完了を時刻順に
    private var flowEntries: [TodoItem] {
        let list: [TodoItem] = data.doneItems + data.items.filter { $0.due != nil }
        return list.sorted { flowKey($0) < flowKey($1) }
    }

    private func flowKey(_ t: TodoItem) -> Date { t.due ?? t.doneAt ?? .now }

    private func flowTime(_ t: TodoItem) -> String {
        let cal = Calendar.current
        let d: Date = flowKey(t)
        if cal.isDateInToday(d) { return t.isAllDay ? "終日" : JP.time(d) }
        if cal.isDateInTomorrow(d) { return "明日" }
        if cal.isDateInYesterday(d) { return "昨日" }
        return "\(cal.component(.month, from: d))/\(cal.component(.day, from: d))"
    }

    @ViewBuilder private func flowRow(_ item: TodoItem) -> some View {
        if item.done {
            flowRowBody(item)
        } else {
            Button(intent: ToggleTodoIntent(id: item.id)) { flowRowBody(item) }
                .buttonStyle(.plain)
                .transition(Self.rowTransition)
        }
    }

    private func flowRowBody(_ item: TodoItem) -> some View {
        let color: Color = item.isOverdue() ? p.overdue : p.accent
        let timeColor: Color = item.done ? p.sub : color
        let titleColor: Color = item.done ? p.sub : p.text
        let symbol: String = item.done ? "checkmark.circle.fill" : "circle"
        let dotBack: Color = p.background.first ?? p.card
        let small: Bool = family == .systemSmall
        let timeFont: Font = small ? Font.system(size: 10, weight: .bold).monospacedDigit() : Font.caption2.weight(.bold).monospacedDigit()
        let titleFont: Font = small ? Font.system(size: 12, weight: .semibold) : Font.caption.weight(.semibold)
        return HStack(alignment: .top, spacing: 6) {
            Text(flowTime(item)).font(timeFont).foregroundStyle(timeColor)
                .lineLimit(1).fixedSize()
                .frame(width: flowTimeWidth, alignment: .leading)
                .padding(.top, 1)
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(timeColor)
                .contentTransition(.symbolEffect(.replace)).invalidatableContent()
                .frame(width: 14, height: 14)
                .background(Circle().fill(dotBack))
            Text(item.title).strikethrough(item.done).font(titleFont).foregroundStyle(titleColor)
                .lineLimit(small ? 2 : 1)
            Spacer(minLength: 0)
        }
    }

    private var nowMarker: some View {
        HStack(spacing: 6) {
            Text("いま").font(.caption2.weight(.heavy)).foregroundStyle(p.overdue)
                .lineLimit(1).fixedSize()
                .frame(width: flowTimeWidth, alignment: .leading)
            Circle().fill(p.overdue).frame(width: 8, height: 8).frame(width: 14)
            Rectangle().fill(p.overdue).frame(height: 1.5)
        }
    }

    // MARK: かんばん（今日・明日・あとで の列）

    private func kanbanItems(_ c: WColumn) -> [TodoItem] { data.items.filter { WColumn.of($0) == c } }

    /// 小：今日の列だけ（ほかの列は件数）。中・大：3列を並べる
    @ViewBuilder private var kanban: some View {
        if family == .systemSmall {
            let todays: [TodoItem] = kanbanItems(.today)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("今日").font(.caption.weight(.heavy)).foregroundStyle(p.accent)
                    Text("\(todays.count)").font(.system(size: 18, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                        .contentTransition(.numericText()).widgetAccentable()
                    Spacer(minLength: 0)
                    Text("明日 \(kanbanItems(.tomorrow).count)・あとで \(kanbanItems(.later).count)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(p.sub).lineLimit(1).fixedSize()
                }
                if todays.isEmpty {
                    emptyText("今日のTODOはありません")
                    Spacer(minLength: 0)
                } else {
                    FitList(items: todays, maxCount: 3, spacing: 4, moreColor: p.sub) { kanbanCard($0) }
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                ForEach(WColumn.allCases, id: \.self) { c in kanbanColumn(c) }
            }
        }
    }

    private func kanbanColumn(_ c: WColumn) -> some View {
        let items: [TodoItem] = kanbanItems(c)
        let maxCount: Int = family == .systemLarge ? 7 : 3
        let headColor: Color = c == .today ? p.accent : p.sub
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(c.name).font(.caption.weight(.heavy)).foregroundStyle(headColor)
                Text("\(items.count)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            if items.isEmpty {
                Text("なし").font(.caption2.weight(.semibold)).foregroundStyle(p.sub.opacity(0.7))
                Spacer(minLength: 0)
            } else {
                FitList(items: items, maxCount: maxCount, spacing: 4, moreColor: p.sub) { kanbanCard($0) }
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kanbanCard(_ item: TodoItem) -> some View {
        let color: Color = item.isOverdue() ? p.overdue : p.accent
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 9), style: .continuous)
        let titleFont: Font = Font.system(size: 11, weight: .semibold)
        return Button(intent: ToggleTodoIntent(id: item.id)) {
            HStack(alignment: .top, spacing: 4) {
                checkIcon("circle", size: 10, color: color)
                    .padding(.top, 1)
                Text(item.title).font(titleFont).foregroundStyle(p.text).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: shape)
        }
        .buttonStyle(.plain)
        .transition(Self.rowTransition)
    }

    // MARK: チェックリスト（紙のリスト）

    private var checklist: some View {
        let rows: [TodoItem] = data.items + (data.showDone ? data.doneItems : [])
        let maxCount: Int = family == .systemLarge ? 13 : (family == .systemMedium ? 5 : 5)
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous)
        let marginX: CGFloat = family == .systemSmall ? 20 : 22
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("のこり \(data.items.count) 件").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if data.doneToday > 0 {
                    Text("完了 \(data.doneToday)").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                }
            }
            Group {
                if rows.isEmpty {
                    emptyText("やることはありません").padding(8)
                    Spacer(minLength: 0)
                } else {
                    FitList(items: rows, maxCount: maxCount, spacing: 0, moreColor: p.sub, moreIndent: marginX + 6) { checkRow($0) }
                        .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(alignment: .leading) {
                Rectangle().fill(p.overdue.opacity(0.3)).frame(width: 1).padding(.leading, marginX)
            }
            .background(p.card, in: shape)
            .clipShape(shape)
        }
    }

    @ViewBuilder private func checkRow(_ item: TodoItem) -> some View {
        if item.done {
            checkRowBody(item)
        } else {
            Button(intent: ToggleTodoIntent(id: item.id)) { checkRowBody(item) }
                .buttonStyle(.plain)
                .transition(Self.rowTransition)
        }
    }

    private func checkRowBody(_ item: TodoItem) -> some View {
        let small: Bool = family == .systemSmall
        let overdue: Bool = item.isOverdue()
        let boxColor: Color = item.done ? p.sub : (overdue ? p.overdue : p.text.opacity(0.7))
        let symbol: String = item.done ? "checkmark.square.fill" : "square"
        let titleFont: Font = small ? Font.system(size: 12, weight: .semibold) : Font.caption.weight(.semibold)
        let clock: String = item.done ? "" : JP.clock(item, none: "")
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: small ? 8 : 10) {
                Image(systemName: symbol).font(.system(size: small ? 13 : 14, weight: .semibold)).foregroundStyle(boxColor)
                    .contentTransition(.symbolEffect(.replace)).invalidatableContent()
                Text(item.title).strikethrough(item.done, color: p.sub).font(titleFont)
                    .foregroundStyle(item.done ? p.sub : p.text)
                    .lineLimit(small ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !small && !clock.isEmpty {
                    Text(clock).font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(overdue ? p.overdue : p.sub).lineLimit(1).fixedSize()
                }
            }
            .padding(.leading, small ? 5 : 6).padding(.trailing, 6).padding(.vertical, small ? 3 : 4)
            Rectangle().fill(p.sub.opacity(0.18)).frame(height: 0.5)
        }
        .opacity(item.done ? 0.6 : 1)
    }

    private var noShare: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("TODO", systemImage: "checklist").font(.headline).foregroundStyle(p.text)
            Text("アプリとデータを共有できません。アプリの「設定」→「状態」を確認してください。")
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
                    .contentTransition(.numericText())
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

// MARK: - グループ構成の区分（アプリの DueGroup と同じ考え方。ウィジェットからはアプリの型が見えないため別に持つ）

private enum WGroup: Int, CaseIterable {
    case overdue, today, tomorrow, later, noDue

    var name: String {
        switch self {
        case .overdue: return "期限切れ"
        case .today: return "今日"
        case .tomorrow: return "明日"
        case .later: return "これから"
        case .noDue: return "期限なし"
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .overdue: return p.overdue
        case .today: return p.accent
        case .tomorrow: return p.accent.opacity(0.6)
        case .later, .noDue: return p.sub
        }
    }

    static func of(_ item: TodoItem, now: Date = .now) -> WGroup {
        guard let due = item.due else { return .noDue }
        if item.isOverdue(now) { return .overdue }
        let cal = Calendar.current
        let days: Int = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        if days <= 0 { return .today }
        if days == 1 { return .tomorrow }
        return .later
    }
}

private struct WGroupRow: Identifiable {
    let id: String
    let group: WGroup
    let count: Int
    let item: TodoItem?
}

// MARK: - かんばんの列（アプリの KanbanColumn と同じ考え方）

private enum WColumn: Int, CaseIterable {
    case today, tomorrow, later

    var name: String {
        switch self {
        case .today: return "今日"
        case .tomorrow: return "明日"
        case .later: return "あとで"
        }
    }

    static func of(_ item: TodoItem, now: Date = .now) -> WColumn {
        guard let due = item.due else { return .later }
        let cal = Calendar.current
        let days: Int = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        if days <= 0 { return .today }
        if days == 1 { return .tomorrow }
        return .later
    }
}

// MARK: - 入るだけ並べる一覧

/// 行を入るだけ並べ、入らない分は「ほか n 件」にする（ViewThatFits で多い順に試す）。
/// 行の文字は縦につぶさない（fixedSize）ので、題名が途中で切れて「…」になるのを防げる
struct FitList<Row: View>: View {
    let items: [TodoItem]
    let maxCount: Int
    var spacing: CGFloat = 4
    var moreColor: Color = .secondary
    var moreIndent: CGFloat = 2
    @ViewBuilder let row: (TodoItem) -> Row

    var body: some View {
        let top: Int = min(maxCount, items.count)
        let counts: [Int] = top > 0 ? Array((1...top).reversed()) : []
        ViewThatFits(in: .vertical) {
            ForEach(counts, id: \.self) { n in
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(items.prefix(n)) { item in row(item) }
                    if items.count > n {
                        Text("ほか \(items.count - n) 件").font(.system(size: 10, weight: .bold)).foregroundStyle(moreColor)
                            .padding(.leading, moreIndent)
                    }
                }
            }
        }
    }
}
