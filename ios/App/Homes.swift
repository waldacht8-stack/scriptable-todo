import SwiftUI

/// 「今日」タブ。設定の構成（TodayLayout）で画面の作りとボタンの位置が変わる。色は palette に従う。
struct HomeView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @State private var addDraft: AddDraft?

    var body: some View {
        Group {
            switch store.layout {
            case .focus: FocusHome(onAdd: { addDraft = AddDraft() })
            case .board: GroupHome(onAdd: { addDraft = AddDraft() })
            case .thumb: WeekHome(onAdd: { addDraft = $0 })
            case .timeline: FlowHome(onAdd: { addDraft = AddDraft() })
            }
        }
        .sheet(item: $addDraft) { draft in
            AddSheet(draft: draft).environmentObject(store).presentationDetents([.medium, .large])
        }
    }
}

/// 追加画面に最初から入れておく値（週間で明日以降を選んでいるときはその日の9時）
struct AddDraft: Identifiable {
    let id = UUID()
    var due: Date? = nil
}

// MARK: - 共通部品

/// チェックの印（デザインの角の丸みが小さいときは四角）
struct CheckMark: View {
    @Environment(\.palette) private var p
    let done: Bool
    var color: Color? = nil
    var size: CGFloat = 28

    var body: some View {
        let c = color ?? p.accent
        let r = p.radius < 18 ? size * 0.28 : size / 2
        ZStack {
            RoundedRectangle(cornerRadius: r).strokeBorder(c, lineWidth: 2.5)
            if done {
                RoundedRectangle(cornerRadius: r).fill(c)
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(p.onAccent)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }
}

/// 長押しメニュー（重要・明日へ・削除）
struct TodoMenu: ViewModifier {
    @EnvironmentObject var store: TodoStore
    let item: TodoItem
    func body(content: Content) -> some View {
        content.contextMenu {
            Button { store.toggleImportant(item) } label: {
                Label(item.isImportant ? "重要を外す" : "重要にする", systemImage: item.isImportant ? "star.slash" : "star")
            }
            Button { store.postpone(item) } label: { Label("明日へ延期", systemImage: "arrow.turn.up.right") }
            Button(role: .destructive) { store.delete(item) } label: { Label("削除", systemImage: "trash") }
        }
    }
}

extension View {
    func todoMenu(_ item: TodoItem) -> some View { modifier(TodoMenu(item: item)) }
}

/// 一覧の1行（グループ・一覧シートで使う）
struct TodoLine: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let item: TodoItem
    var large = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if item.done { store.uncomplete(item) } else { store.complete(item) }
            } label: {
                CheckMark(done: item.done, color: item.isOverdue() ? p.overdue : p.accent, size: large ? 32 : 26)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if item.isImportant { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    Text(item.title).font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
                        .strikethrough(item.done).foregroundStyle(item.done ? p.sub : p.text).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(DueText.label(item)).foregroundStyle(item.isOverdue() ? p.overdue : p.sub)
                    if item.repeatRule != nil { Image(systemName: "repeat").foregroundStyle(p.sub) }
                    if item.isCalendar { Image(systemName: "calendar").foregroundStyle(p.sub) }
                }
                .font(.caption.weight(.medium))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, large ? 14 : 10)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            Button { store.complete(item) } label: { Label("完了", systemImage: "checkmark") }.tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button { store.postpone(item) } label: { Label("明日へ", systemImage: "arrow.turn.up.right") }.tint(.orange)
            Button(role: .destructive) { store.delete(item) } label: { Label("削除", systemImage: "trash") }
        }
        .todoMenu(item)
    }
}

// MARK: - ① フォーカス：1件ずつ大きなカード。右スワイプで完了、左で明日へ。右下の＋で追加

struct FocusHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: () -> Void
    @State private var drag: CGSize = .zero
    @State private var feedback = 0
    @State private var showAll = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    BigCount(prefix: "あと", value: store.open.count, suffix: "件")
                    Button { showAll = true } label: {
                        Label("一覧", systemImage: "list.bullet").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(p.card, in: Capsule())
                    }
                    .foregroundStyle(p.text)
                }
                .padding(.horizontal, 24).padding(.top, 24)
                ZStack {
                    if store.open.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(p.accent)
                            Text("全部終わりました").font(.title2.bold()).foregroundStyle(p.text)
                        }
                    }
                    ForEach(Array(store.open.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                        FocusCard(item: item, index: index, drag: index == 0 ? drag : .zero)
                            .gesture(swipe(item), including: index == 0 ? .all : .none)
                            .todoMenu(item)
                    }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    Label("明日へ", systemImage: "arrow.left").foregroundStyle(p.overdue)
                    Spacer()
                    Label("完了", systemImage: "arrow.right").labelStyle(TrailingIcon()).foregroundStyle(p.accent)
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 32).padding(.bottom, 96)
            }
            Button(action: onAdd) {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 60, height: 60)
                    .foregroundStyle(p.onAccent).background(p.accent, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .padding(22)
            .accessibilityLabel("TODOを追加")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(isPresented: $showAll) {
            NavigationStack {
                List { ForEach(store.open) { TodoLine(item: $0) }.listRowBackground(p.card) }
                    .scrollContentBackground(.hidden).paletteBackground(p)
                    .navigationTitle("すべてのTODO").navigationBarTitleDisplayMode(.inline)
            }
            .environment(\.palette, p)
            .environmentObject(store)
            .presentationDetents([.large])
        }
    }

    private func swipe(_ item: TodoItem) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if v.translation.width > 120 {
                    withAnimation(.spring(duration: 0.35)) { drag = CGSize(width: 600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { store.complete(item); drag = .zero; feedback += 1 }
                } else if v.translation.width < -120 {
                    withAnimation(.spring(duration: 0.35)) { drag = CGSize(width: -600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { store.postpone(item); drag = .zero }
                } else {
                    withAnimation(.spring(duration: 0.35)) { drag = .zero }
                }
            }
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

struct FocusCard: View {
    @Environment(\.palette) private var p
    let item: TodoItem
    let index: Int
    let drag: CGSize

    var body: some View {
        let tag = item.isOverdue() ? p.overdue : p.accent
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(DueText.label(item)).font(.subheadline.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tag.opacity(0.14), in: Capsule()).foregroundStyle(tag)
                if item.repeatRule != nil { Image(systemName: "repeat").foregroundStyle(p.sub) }
                Spacer()
                if item.isImportant { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            Spacer()
            Text(item.title).font(.system(size: 34, weight: .bold, design: p.fontDesign)).foregroundStyle(p.text)
                .lineLimit(3).minimumScaleFactor(0.6)
            if let note = item.note, !note.isEmpty { Text(note).font(.callout).foregroundStyle(p.sub).lineLimit(2) }
            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .background(RoundedRectangle(cornerRadius: p.radius + 4, style: .continuous).fill(p.card)
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8))
        .overlay(alignment: .topTrailing) {
            if drag.width > 30 { stamp("完了", p.accent) } else if drag.width < -30 { stamp("明日へ", p.overdue) }
        }
        .padding(.horizontal, 24)
        .scaleEffect(1 - CGFloat(index) * 0.05)
        .offset(x: drag.width, y: CGFloat(index) * 18 + drag.height * 0.1)
        .rotationEffect(.degrees(Double(drag.width) / 20))
    }

    private func stamp(_ text: String, _ color: Color) -> some View {
        // 型を明示（Xcode 26.3 では1つの式のままだと font があいまいになる）
        let label: Text = Text(verbatim: text).font(Font.title2.weight(.bold))
        let angle: Double = drag.width > 0 ? -12 : 12
        let fade: Double = Double(min(1, abs(drag.width) / 120))
        return label.foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
            .padding(22)
            .opacity(fade)
    }
}

// MARK: - ② グループ：期限ごとに見出しで分けた一覧。下の入力欄で打ってすぐ追加

/// 期限の区分（グループ構成の見出し）
enum DueGroup: Int, CaseIterable {
    case overdue, today, tomorrow, week, later, noDue

    var name: String {
        switch self {
        case .overdue: "期限切れ"
        case .today: "今日"
        case .tomorrow: "明日"
        case .week: "7日以内"
        case .later: "それ以降"
        case .noDue: "期限なし"
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .overdue: p.overdue
        case .today: p.accent
        case .tomorrow: p.accent.opacity(0.6)
        default: p.sub
        }
    }

    static func of(_ item: TodoItem, now: Date = .now) -> DueGroup {
        guard let due = item.due else { return .noDue }
        if item.isOverdue(now) { return .overdue }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .tomorrow
        case 2...7: return .week
        default: return .later
        }
    }
}

struct GroupHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: () -> Void
    @State private var draft = ""

    var body: some View {
        let open = store.open
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(JP.date(.now)).font(.title2.weight(.heavy)).foregroundStyle(p.text)
                        Text("のこり \(open.count) 件 ・ 今日の完了 \(store.doneToday.count) 件")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                }
                ForEach(DueGroup.allCases, id: \.self) { g in
                    let items = open.filter { DueGroup.of($0) == g }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { TodoLine(item: $0) }
                        } header: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(g.color(p)).frame(width: 4, height: 18)
                                Text(g.name).font(.headline.weight(.bold)).foregroundStyle(p.text)
                                Text("\(items.count)").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                            }
                            .textCase(nil)
                        }
                        .listRowBackground(p.card)
                    }
                }
                if open.isEmpty {
                    Section { Text("やることはありません").foregroundStyle(p.sub) }.listRowBackground(p.card)
                }
            }
            .scrollContentBackground(.hidden)
            HStack(spacing: 10) {
                TextField("何をする？（入力して確定で追加）", text: $draft)
                    .submitLabel(.done)
                    .onSubmit { store.add(draft); draft = "" }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(p.card, in: Capsule())
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.title3.bold()).frame(width: 46, height: 46)
                        .foregroundStyle(p.onAccent).background(p.accent, in: Circle())
                }
                .accessibilityLabel("TODOを追加")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .paletteBackground(p)
    }
}

// MARK: - ③ 週間：上の日付ボタンで日を選び、その日の予定を時刻つきで。右下の＋で追加

struct WeekHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: (AddDraft) -> Void
    @State private var offset = 0   // 今日から何日後を見ているか

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let day = cal.date(byAdding: .day, value: offset, to: today) ?? today
        let dayItems = items(on: day)
        let undated = store.open.filter { $0.due == nil }
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let d = cal.date(byAdding: .day, value: i, to: today) ?? today
                        Button { withAnimation(.snappy) { offset = i } } label: { chip(d, selected: i == offset) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
                List {
                    if offset == 0 && !store.overdue.isEmpty {
                        Section {
                            ForEach(store.overdue) { AgendaRow(item: $0) }
                        } header: { header("期限切れ", store.overdue.count, p.overdue) }
                        .listRowBackground(p.card)
                    }
                    Section {
                        ForEach(dayItems) { AgendaRow(item: $0) }
                        if dayItems.isEmpty { Text("予定はありません").foregroundStyle(p.sub) }
                    } header: { header(offset == 0 ? "今日" : JP.date(day), dayItems.count, p.accent) }
                    .listRowBackground(p.card)
                    if offset == 0 && !undated.isEmpty {
                        Section {
                            ForEach(undated) { AgendaRow(item: $0) }
                        } header: { header("期限なし", undated.count, p.sub) }
                        .listRowBackground(p.card)
                    }
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 80, for: .scrollContent)
            }
            Button { onAdd(AddDraft(due: offset == 0 ? nil : cal.date(bySettingHour: 9, minute: 0, second: 0, of: day))) } label: {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 60, height: 60)
                    .foregroundStyle(p.onAccent).background(p.accent, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .padding(22)
            .accessibilityLabel("TODOを追加")
        }
        .paletteBackground(p)
    }

    /// その日の未完了（終日が先、あとは時刻順。期限切れは別の見出し）
    private func items(on day: Date) -> [TodoItem] {
        let cal = Calendar.current
        return store.open
            .filter { item in
                guard let due = item.due, cal.isDate(due, inSameDayAs: day) else { return false }
                return !item.isOverdue()
            }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
            }
    }

    private func chip(_ d: Date, selected: Bool) -> some View {
        let cal = Calendar.current
        let n = items(on: d).count
        return VStack(spacing: 3) {
            Text(Self.weekdays[cal.component(.weekday, from: d) - 1]).font(.caption2.weight(.bold))
            Text("\(cal.component(.day, from: d))").font(.title3.weight(.heavy)).monospacedDigit()
            Circle().fill(n > 0 ? (selected ? p.onAccent : p.accent) : Color.clear).frame(width: 6, height: 6)
        }
        .foregroundStyle(selected ? p.onAccent : p.text)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(selected ? p.accent : p.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func header(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 18)
            Text(title).font(.headline.weight(.bold)).foregroundStyle(p.text)
            Text("\(count)").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
        }
        .textCase(nil)
    }
}

/// 週間の1行：左に時刻、中央にやること、右に完了の印
struct AgendaRow: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let item: TodoItem

    var body: some View {
        let color = item.isOverdue() ? p.overdue : p.accent
        HStack(spacing: 12) {
            Text(item.isOverdue() ? DueText.label(item) : JP.clock(item, none: "—"))
                .font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.isImportant { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(2)
                }
                if let note = item.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { store.complete(item) } label: { CheckMark(done: false, color: color, size: 26) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            Button { store.complete(item) } label: { Label("完了", systemImage: "checkmark") }.tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button { store.postpone(item) } label: { Label("明日へ", systemImage: "arrow.turn.up.right") }.tint(.orange)
            Button(role: .destructive) { store.delete(item) } label: { Label("削除", systemImage: "trash") }
        }
        .todoMenu(item)
    }
}

// MARK: - ④ ながれ：今日の完了から先の予定まで1本の線でつないだ時系列。「いま」の位置に印。右上の＋で追加

struct FlowHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let entries = timeline
            let nowIndex = entries.firstIndex { !$0.done && ($0.due ?? .distantFuture) > now } ?? entries.count
            let undated = store.open.filter { $0.due == nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(JP.date(now)).font(.title2.weight(.heavy)).foregroundStyle(p.text)
                            Text("のこり \(store.open.count) 件 ・ 今日の完了 \(store.doneToday.count) 件")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                        }
                        Spacer()
                        Button(action: onAdd) {
                            Image(systemName: "plus").font(.title3.bold()).frame(width: 44, height: 44)
                                .foregroundStyle(p.onAccent).background(p.accent, in: Circle())
                        }
                        .accessibilityLabel("TODOを追加")
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, item in
                        if i == nowIndex { nowMarker(now) }
                        if i == 0 || !sameDay(entries[i - 1], item) { dayLabel(item) }
                        FlowRow(item: item)
                    }
                    if nowIndex == entries.count { nowMarker(now) }

                    if !undated.isEmpty {
                        Text("期限なし").font(.headline.weight(.bold)).foregroundStyle(p.text)
                            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
                        ForEach(undated) { FlowRow(item: $0) }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .paletteBackground(p)
    }

    /// 今日の完了＋期限つきの未完了を時刻順に
    private var timeline: [TodoItem] {
        let list = store.doneToday + store.open.filter { $0.due != nil }
        return list.sorted { key($0) < key($1) }
    }

    private func key(_ t: TodoItem) -> Date { t.due ?? t.doneAt ?? .now }

    private func sameDay(_ a: TodoItem, _ b: TodoItem) -> Bool {
        Calendar.current.isDate(key(a), inSameDayAs: key(b))
    }

    private func dayLabel(_ item: TodoItem) -> some View {
        let d = key(item)
        let cal = Calendar.current
        let title = cal.isDateInToday(d) ? "今日" : cal.isDateInTomorrow(d) ? "明日" : cal.isDateInYesterday(d) ? "昨日" : JP.date(d)
        return Text(title).font(.headline.weight(.bold)).foregroundStyle(p.text)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
    }

    private func nowMarker(_ now: Date) -> some View {
        HStack(spacing: 8) {
            Text("いま \(JP.time(now))").font(.caption.monospacedDigit().weight(.heavy)).foregroundStyle(p.overdue)
                .frame(width: 70, alignment: .trailing)
            Circle().fill(p.overdue).frame(width: 10, height: 10)
            Rectangle().fill(p.overdue).frame(height: 2)
        }
        .padding(.trailing, 20).padding(.vertical, 6)
    }
}

/// ながれの1行：左に時刻、中央に線と丸、右にカード
struct FlowRow: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let item: TodoItem

    var body: some View {
        let color = item.done ? p.sub : (item.isOverdue() ? p.overdue : p.accent)
        HStack(alignment: .center, spacing: 10) {
            Text(JP.clock(item, none: ""))
                .font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(color)
                .frame(width: 62, alignment: .trailing)
            Button { item.done ? store.uncomplete(item) : store.complete(item) } label: {
                CheckMark(done: item.done, color: color, size: 24)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.isImportant { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(item.done ? p.sub : p.text)
                        .strikethrough(item.done).lineLimit(2)
                }
                if item.isOverdue() {
                    Text(DueText.label(item)).font(.caption.weight(.semibold)).foregroundStyle(p.overdue)
                } else if let note = item.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: min(p.radius, 16), style: .continuous))
            .opacity(item.done ? 0.6 : 1)
        }
        .padding(.leading, 10).padding(.trailing, 16).padding(.vertical, 5)
        // 丸の中心を通る縦線（行の高さいっぱい）
        .background(alignment: .leading) {
            Rectangle().fill(p.sub.opacity(0.25)).frame(width: 2).padding(.leading, 10 + 62 + 10 + 11)
        }
        .todoMenu(item)
    }
}
