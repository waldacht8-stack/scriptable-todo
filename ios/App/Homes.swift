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
            case .board: BoardHome()
            case .thumb: ThumbHome(onAdd: { addDraft = AddDraft() })
            case .timeline: TimelineHome(onAdd: { addDraft = $0 })
            }
        }
        .sheet(item: $addDraft) { draft in
            AddSheet(draft: draft).environmentObject(store).presentationDetents([.medium, .large])
        }
    }
}

/// 追加画面に最初から入れておく値（タイムラインで時間帯をタップしたときは時刻入り）
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

/// 一覧の1行（ボード・片手・一覧シートで使う）
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
        Text(text).font(.title2.bold()).foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(drag.width > 0 ? -12 : 12))
            .padding(22)
            .opacity(min(1, abs(drag.width) / 120))
    }
}

// MARK: - ② ボード：タイルで全体を一目で。上部の入力欄で打ってすぐ追加

struct BoardHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(JP.date(.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(p.accent)
                        TextField("何をする？（入力して確定で追加）", text: $draft)
                            .focused($typing).submitLabel(.done)
                            .onSubmit { store.add(draft); draft = "" }
                    }
                    .padding(14)
                    .background(p.card, in: RoundedRectangle(cornerRadius: p.radius * 0.6, style: .continuous))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        tile("のこり", "\(store.open.count)", "件", p.accent)
                        nextTile
                        tile("期限切れ", "\(store.overdue.count)", "件", store.overdue.isEmpty ? p.sub : p.overdue)
                        tile("今日の完了", "\(store.doneToday.count)", "件", p.text)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(store.open) { TodoLine(item: $0) }
                if store.open.isEmpty { Text("やることはありません").foregroundStyle(p.sub) }
            } header: {
                Text("やること").font(.headline).foregroundStyle(p.text)
            }
            .listRowBackground(p.card)
        }
        .scrollContentBackground(.hidden)
        .paletteBackground(p)
    }

    private func tile(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(color)
                Text(unit).font(.caption).foregroundStyle(p.sub)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(14)
        .background(p.card, in: RoundedRectangle(cornerRadius: p.radius * 0.7, style: .continuous))
    }

    private var nextTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("次の予定").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            if let next = store.nextTimed, let due = next.due {
                Text(due, style: .timer).font(.system(size: 24, weight: .heavy, design: .monospaced)).foregroundStyle(p.accent)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(next.title).font(.caption.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
            } else {
                Text("なし").font(.title2.weight(.heavy)).foregroundStyle(p.sub)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(14)
        .background(p.card, in: RoundedRectangle(cornerRadius: p.radius * 0.7, style: .continuous))
    }
}

// MARK: - ③ 片手：内容を下に寄せ、親指で届く下部の大きなボタンで操作

struct ThumbHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: () -> Void
    @State private var showDone = false
    @State private var feedback = 0

    var body: some View {
        let list = showDone ? store.doneToday : Array(store.open.reversed())
        VStack(spacing: 0) {
            HStack {
                Text(JP.date(.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Spacer()
                Text(showDone ? "今日の完了 \(store.doneToday.count) 件" : "のこり \(store.open.count) 件")
                    .font(.subheadline.weight(.bold)).foregroundStyle(p.text)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            List {
                ForEach(list) { TodoLine(item: $0, large: true) }
                    .listRowBackground(p.card)
                if list.isEmpty {
                    Text(showDone ? "今日完了したものはまだありません" : "やることはありません").foregroundStyle(p.sub)
                        .listRowBackground(p.card)
                }
            }
            .scrollContentBackground(.hidden)
            .defaultScrollAnchor(.bottom)       // 一番近いTODOが親指の近く（下）に来る
            HStack(spacing: 10) {
                bigButton(showDone ? "やること" : "完了済み", showDone ? "list.bullet" : "checkmark.circle", filled: false) { showDone.toggle() }
                bigButton("次を完了", "checkmark", filled: false) {
                    if let first = store.open.first { store.complete(first); feedback += 1 }
                }
                .disabled(store.open.isEmpty)
                bigButton("追加", "plus", filled: true, action: onAdd)
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        }
        .paletteBackground(p)
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func bigButton(_ title: String, _ icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2.weight(.bold))
                Text(title).font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .foregroundStyle(filled ? p.onAccent : p.text)
            .background(filled ? p.accent : p.card, in: RoundedRectangle(cornerRadius: p.radius * 0.7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ④ タイムライン：縦の時間軸。右上の＋、時間帯をタップでその時刻のTODOを追加

struct TimelineHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: (AddDraft) -> Void
    private let hourHeight: CGFloat = 64
    private let startHour = 6

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if !untimed.isEmpty {
                                Text("時間を決めていない・今日以外").font(.caption.weight(.semibold)).foregroundStyle(p.sub).padding(.horizontal, 20)
                                VStack(spacing: 0) { ForEach(untimed) { TodoLine(item: $0).padding(.horizontal, 16) } }
                                    .background(p.card, in: RoundedRectangle(cornerRadius: p.radius * 0.6, style: .continuous))
                                    .padding(.horizontal, 16)
                            }
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(startHour..<24, id: \.self) { h in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(String(format: "%02d:00", h)).font(.caption.monospacedDigit()).foregroundStyle(p.sub)
                                                .frame(width: 44, alignment: .trailing)
                                            Rectangle().fill(p.sub.opacity(0.18)).frame(height: 1).padding(.top, 7)
                                        }
                                        .frame(height: hourHeight, alignment: .top)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onAdd(AddDraft(due: todayAt(h))) }
                                        .id(h)
                                    }
                                }
                                ForEach(timedToday) { item in
                                    TimelineChip(item: item).padding(.leading, 64).padding(.trailing, 16)
                                        .offset(y: offset(for: item.due ?? .now))
                                }
                                if offset(for: ctx.date) >= 0 {
                                    HStack(spacing: 0) {
                                        Circle().fill(p.overdue).frame(width: 9, height: 9)
                                        Rectangle().fill(p.overdue).frame(height: 2)
                                    }
                                    .padding(.leading, 50).offset(y: offset(for: ctx.date) + 3)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .padding(.bottom, 40)
                    }
                    .onAppear { proxy.scrollTo(max(startHour, Calendar.current.component(.hour, from: .now) - 1), anchor: .top) }
                }
            }
            .paletteBackground(p)
            .navigationTitle(JP.date(.now))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onAdd(AddDraft()) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .accessibilityLabel("TODOを追加")
                }
            }
        }
    }

    /// 時刻のない・今日以外の未完了
    private var untimed: [TodoItem] {
        store.open.filter { item in
            guard let due = item.due, !item.isAllDay else { return true }
            return !Calendar.current.isDateInToday(due) || Calendar.current.component(.hour, from: due) < startHour
        }
    }

    /// 今日の時刻つき（完了も含めて時間軸に置く）
    private var timedToday: [TodoItem] {
        store.items.filter { item in
            guard let due = item.due, !item.isAllDay, Calendar.current.isDateInToday(due) else { return false }
            return Calendar.current.component(.hour, from: due) >= startHour
        }
    }

    private func offset(for date: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 - Double(startHour)
        return CGFloat(h) * hourHeight
    }

    private func todayAt(_ h: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now
    }
}

struct TimelineChip: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let item: TodoItem

    var body: some View {
        let color = item.done ? p.sub : (item.isOverdue() ? p.overdue : p.accent)
        HStack(spacing: 10) {
            Button { item.done ? store.uncomplete(item) : store.complete(item) } label: {
                CheckMark(done: item.done, color: color, size: 22)
            }
            .buttonStyle(.plain)
            Text(JP.clock(item)).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(color)
            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(item.done ? p.sub : p.text)
                .strikethrough(item.done).lineLimit(1)
            Spacer(minLength: 0)
            if item.isImportant { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, 6) }
        .todoMenu(item)
    }
}
