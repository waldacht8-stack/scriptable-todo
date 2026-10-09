import SwiftUI

/// 「今日」タブ。設定の構成（TodayLayout）で画面の作りとボタンの位置が変わる。色は palette に従う。
struct HomeView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @State private var addDraft: AddDraft?
    @State private var shotArgsApplied = false
    // 起動引数 -donelist で完了済みの一覧を開いた状態にする（スクリーンショット用）
    @State private var listTab: ListTab? = ProcessInfo.processInfo.arguments.contains("-donelist") ? .done : nil

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("-todowidgets") {
                TodoWidgetGallery() // 新しい構成のウィジェットの見本（スクリーンショット用）
            } else {
                switch store.layout {
                case .focus: FocusHome(onAdd: { addDraft = AddDraft() })
                case .board: GroupHome(onAdd: { addDraft = AddDraft() })
                case .thumb: WeekHome(onAdd: { addDraft = $0 })
                case .timeline: FlowHome(onAdd: { addDraft = AddDraft() })
                case .kanban: KanbanHome(onAdd: { addDraft = $0 })
                case .checklist: ChecklistHome(onAdd: { addDraft = AddDraft() })
                }
            }
        }
        .environment(\.editTodo, EditTodoAction { addDraft = AddDraft(item: $0) })
        .environment(\.openList, OpenListAction { listTab = $0 })
        .overlay(alignment: .top) { UndoToast() }
        .task {
            // スクリーンショット用：-shotundo で「元に戻す」、-shotedit で先頭のTODOの編集画面、-shotadd で追加画面を出す
            guard !shotArgsApplied else { return }
            shotArgsApplied = true
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("-shotedit") || args.contains("-shotundo") || args.contains("-shotadd") else { return }
            try? await Task.sleep(for: .seconds(1))
            if args.contains("-shotedit"), let first = store.open.first { addDraft = AddDraft(item: first) }
            if args.contains("-shotundo"), let first = store.open.first { store.complete(first) }
            if args.contains("-shotadd") { addDraft = AddDraft(title: "明日15時 美容院を予約") }
        }
        .sheet(item: $addDraft) { draft in
            AddSheet(draft: draft)
                .environmentObject(store)
                .environment(\.palette, p)
                .environment(\.motion, motion)
                .preferredColorScheme(p.scheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $listTab) { tab in
            TodoListSheet(tab: tab).environment(\.palette, p).environment(\.motion, motion).environmentObject(store)
        }
    }
}

/// 追加・編集の画面に最初から入れておく値（item があれば編集）
struct AddDraft: Identifiable {
    let id = UUID()
    /// 最初に選んでおく期限（週間で明日以降を選んでいるときはその日の9時、かんばんの列なら その日の終日）
    var due: Date? = nil
    var allDay = false
    var item: TodoItem? = nil
    /// 最初に入れておく題名（スクリーンショット用）
    var title: String? = nil
}

// MARK: - 編集・一覧を開く（どの構成の行からでも呼べるように環境で渡す）

struct EditTodoAction {
    var run: (TodoItem) -> Void = { _ in }
    func callAsFunction(_ item: TodoItem) { run(item) }
}

enum ListTab: Int, Identifiable {
    case open, done
    var id: Int { rawValue }
}

struct OpenListAction {
    var run: (ListTab) -> Void = { _ in }
    func callAsFunction(_ tab: ListTab) { run(tab) }
}

private struct EditTodoKey: EnvironmentKey { static let defaultValue = EditTodoAction() }
private struct OpenListKey: EnvironmentKey { static let defaultValue = OpenListAction() }

extension EnvironmentValues {
    var editTodo: EditTodoAction {
        get { self[EditTodoKey.self] }
        set { self[EditTodoKey.self] = newValue }
    }
    var openList: OpenListAction {
        get { self[OpenListKey.self] }
        set { self[OpenListKey.self] = newValue }
    }
}

// MARK: - 元に戻す

/// 完了・削除・延期のあと、しばらく上に出る「元に戻す」
struct UndoToast: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            if let u = store.undo {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.accent)
                    Text(u.message).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(motion.change(reduce: reduce)) { store.undoLast() }
                    } label: {
                        Text("元に戻す").font(.subheadline.weight(.bold)).foregroundStyle(p.onAccent)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(p.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
                .background(Color.black.opacity(0.85), in: Capsule())
                .padding(.horizontal, 16).padding(.top, 6)
                .transition(reduce ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: u.id) {
                    try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("-shotundo") ? 120 : UndoInfo.seconds))
                    if store.undo?.id == u.id { withAnimation(motion.change(reduce: reduce)) { store.undo = nil } }
                }
            }
        }
        .animation(motion.change(reduce: reduce), value: store.undo?.id)
    }
}

// MARK: - 一覧（やること・完了済み）

struct TodoListSheet: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion
    @State var tab: ListTab
    @State private var editing: AddDraft?

    var body: some View {
        NavigationStack {
            List {
                if tab == .open {
                    ForEach(store.open) { TodoLine(item: $0) }.listRowBackground(p.card)
                    if store.open.isEmpty {
                        TodoEmptyState(title: "やることはありません").listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(doneDays, id: \.self) { day in
                        Section {
                            ForEach(doneItems(on: day)) { TodoLine(item: $0) }
                        } header: {
                            Text(dayTitle(day)).font(.subheadline.weight(.bold)).foregroundStyle(p.text).textCase(nil)
                        }
                        .listRowBackground(p.card)
                    }
                    if doneDays.isEmpty {
                        TodoEmptyState(icon: "checkmark.circle", title: "完了したTODOはまだありません")
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .safeAreaInset(edge: .top) {
                Picker("表示", selection: $tab) {
                    Text("やること \(store.open.count)").tag(ListTab.open)
                    Text("完了済み \(store.items.filter(\.done).count)").tag(ListTab.done)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
            .navigationTitle("TODOの一覧").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .environment(\.editTodo, EditTodoAction { editing = AddDraft(item: $0) })
        .overlay(alignment: .top) { UndoToast() }
        .sheet(item: $editing) { draft in
            AddSheet(draft: draft)
                .environmentObject(store)
                .environment(\.palette, p)
                .environment(\.motion, motion)
                .preferredColorScheme(p.scheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .presentationDetents([.large])
    }

    /// 完了した日（新しい順）
    private var doneDays: [Date] {
        let cal = Calendar.current
        let days = Set(store.items.filter(\.done).map { cal.startOfDay(for: $0.doneAt ?? $0.due ?? .now) })
        return days.sorted(by: >)
    }

    private func doneItems(on day: Date) -> [TodoItem] {
        let cal = Calendar.current
        return store.items
            .filter { $0.done && cal.isDate($0.doneAt ?? $0.due ?? .now, inSameDayAs: day) }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "今日" }
        if cal.isDateInYesterday(day) { return "昨日" }
        return JP.date(day)
    }
}

// MARK: - 共通部品

/// チェックの印（デザインの角の丸みが小さいときは四角）
struct CheckMark: View {
    @Environment(\.palette) private var p
    let done: Bool
    var color: Color? = nil
    var size: CGFloat = 28
    /// true なら丸みに関係なく四角（チェックリスト）
    var square = false

    var body: some View {
        let c = color ?? p.accent
        let r = square || p.radius < 18 ? size * 0.26 : size / 2
        // 中の塗りと印は常に置いておき、done で大きさ・濃さを変える（完了の瞬間にふくらんで弾む）
        ZStack {
            RoundedRectangle(cornerRadius: r).strokeBorder(c, lineWidth: 2.5)
            RoundedRectangle(cornerRadius: r).fill(c)
                .scaleEffect(done ? 1 : (reduce ? 1 : 0.3))
                .opacity(done ? 1 : 0)
            Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(p.onAccent)
                .opacity(done ? 1 : 0)
                .symbolEffect(.bounce, value: done)
                .symbolEffectsRemoved(reduce)
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }

    @Environment(\.accessibilityReduceMotion) private var reduce
}

/// 長押しメニュー（編集・完了・重要・期限の移動・削除）
struct TodoMenu: ViewModifier {
    @EnvironmentObject var store: TodoStore
    @Environment(\.editTodo) private var editTodo
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let item: TodoItem

    private func run(_ action: @escaping () -> Void) {
        withAnimation(motion.change(reduce: reduce)) { action() }
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { editTodo(item) } label: { Label("編集", systemImage: "pencil") }
            if item.done {
                Button { run { store.uncomplete(item) } } label: { Label("未完了に戻す", systemImage: "arrow.uturn.backward") }
            } else {
                Button { run { store.complete(item) } } label: { Label("完了にする", systemImage: "checkmark") }
            }
            Button { run { store.toggleImportant(item) } } label: {
                Label(item.isImportant ? "重要を外す" : "重要にする", systemImage: item.isImportant ? "star.slash" : "star")
            }
            if !item.done {
                Button { run { store.postpone(item) } } label: { Label("明日に延期", systemImage: "arrow.turn.up.right") }
                Menu {
                    Button { run { store.move(item, to: .today) } } label: { Label("今日", systemImage: "sun.max") }
                    Button { run { store.move(item, to: .tomorrow) } } label: { Label("明日", systemImage: "sunrise") }
                    Button { run { store.move(item, to: .nextWeek) } } label: { Label("来週の月曜", systemImage: "calendar") }
                    Button { run { store.move(item, to: .noDue) } } label: { Label("期限なし", systemImage: "tray") }
                } label: {
                    Label("期限を移す", systemImage: "calendar.badge.clock")
                }
            }
            Button(role: .destructive) { run { store.delete(item) } } label: { Label("削除", systemImage: "trash") }
        }
    }
}

extension View {
    func todoMenu(_ item: TodoItem) -> some View { modifier(TodoMenu(item: item)) }

    /// 一覧の行のスワイプ（右へ：完了／戻す、左へ：明日へ・削除）
    func todoSwipes(_ item: TodoItem, store: TodoStore, animation: Animation = .default) -> some View {
        self
            .swipeActions(edge: .leading) {
                if item.done {
                    Button { withAnimation(animation) { store.uncomplete(item) } } label: {
                        Label("戻す", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.gray)
                } else {
                    Button { withAnimation(animation) { store.complete(item) } } label: { Label("完了", systemImage: "checkmark") }
                        .tint(.green)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { withAnimation(animation) { store.delete(item) } } label: {
                    Label("削除", systemImage: "trash")
                }
                if !item.done {
                    Button { withAnimation(animation) { store.postpone(item) } } label: {
                        Label("明日へ", systemImage: "arrow.turn.up.right")
                    }
                    .tint(.orange)
                }
            }
    }
}

/// 一覧の1行（グループ・週間・一覧シートで使う）。完了したものは線を引いて薄く。
/// 完了にするときは題名に左から線を引いてから消える
struct TodoLine: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.editTodo) private var editTodo
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let item: TodoItem
    var large = false
    /// false なら行のスワイプ操作をつけない（週間は横スワイプで日を移るため）
    var swipes = true
    @State private var sweeping = false

    var body: some View {
        let overdue: Bool = item.isOverdue()
        let shownDone: Bool = item.done || sweeping
        let titleFont: Font = large ? Font.title3.weight(.semibold) : Font.body.weight(.semibold)
        HStack(spacing: 14) {
            Button {
                CompleteMotion.toggle(item, store: store, motion: motion, reduce: reduce, sweeping: $sweeping)
            } label: {
                CheckMark(done: shownDone, color: item.done ? p.sub : (overdue ? p.overdue : p.accent), size: large ? 32 : 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "未完了に戻す" : "完了にする")
            .sensoryFeedback(.success, trigger: sweeping) { _, new in new }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if item.isImportant && !item.done { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    Text(item.title).font(titleFont)
                        .strikethrough(item.done, color: p.sub).foregroundStyle(shownDone ? p.sub : p.text).lineLimit(2)
                        .sweepLine(sweeping && !item.done, color: p.sub)
                }
                TodoMeta(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, large ? 14 : 9)
        .opacity(item.done ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editTodo(item) }   // 行をタップで編集
        .modifier(OptionalSwipes(item: item, enabled: swipes, animation: motion.change(reduce: reduce)))
        .todoMenu(item)
    }
}

/// スワイプ操作をつける・つけない
private struct OptionalSwipes: ViewModifier {
    @EnvironmentObject var store: TodoStore
    let item: TodoItem
    let enabled: Bool
    let animation: Animation

    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.todoSwipes(item, store: store, animation: animation) } else { content }
    }
}

/// 行の下の小さな情報（期限・繰り返し・カレンダー・メモ）
struct TodoMeta: View {
    @Environment(\.palette) private var p
    let item: TodoItem

    var body: some View {
        let overdue: Bool = item.isOverdue()
        HStack(spacing: 6) {
            if item.done, let at = item.doneAt {
                Text("\(JP.time(at)) に完了").foregroundStyle(p.sub)
            } else {
                Text(DueText.label(item)).foregroundStyle(overdue ? p.overdue : p.sub)
                    .lineLimit(1).fixedSize()
            }
            if item.repeatRule != nil { Image(systemName: "repeat").foregroundStyle(p.sub) }
            if item.isCalendar { Image(systemName: "calendar").foregroundStyle(p.sub) }
            if let note = item.note, !note.isEmpty {
                Image(systemName: "note.text").foregroundStyle(p.sub)
            }
        }
        .font(.caption.weight(.medium))
    }
}

/// 一覧の見出し（色の帯・名前・件数）
struct SectionBar: View {
    @Environment(\.palette) private var p
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 18)
            Text(title).font(.headline.weight(.bold)).foregroundStyle(p.text)
            Text("\(count)").font(.subheadline.weight(.bold)).foregroundStyle(p.sub).monospacedDigit()
                .contentTransition(.numericText())
        }
        .textCase(nil)
    }
}

/// 見出しの2段目に出す件数（のこり・今日の完了）
func countLine(open: Int, done: Int) -> String {
    done > 0 ? "のこり \(open) 件・今日の完了 \(done) 件" : "のこり \(open) 件"
}

// MARK: - ① フォーカス：1件ずつ大きなカード。右スワイプで完了、左で明日へ。右下の＋で追加

struct FocusHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: () -> Void
    @State private var drag: CGSize = .zero
    @State private var feedback = 0
    @Environment(\.openList) private var openList
    @Environment(\.editTodo) private var editTodo
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// 完了したときの大きなチェックの合図
    @State private var celebrate = 0
    /// 飛んでいく向き（完了は右、明日へは左）
    @State private var flyDir: CGFloat = 1
    /// いま指で動かしているカード
    @State private var dragID: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 14) {
                TodoHeader(leading: AnyView(HeaderChip(title: "一覧", icon: "list.bullet") { openList(.open) })) {
                    BigCount(prefix: "あと", value: store.open.count, suffix: "件")
                }
                .padding(.horizontal, 24).padding(.top, 16)
                if !store.shownDone.isEmpty { doneStrip }
                ZStack {
                    if store.open.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(p.accent)
                            Text("全部終わりました").font(.title2.bold()).foregroundStyle(p.text)
                            Text(store.doneToday.isEmpty ? "＋ から追加できます" : "今日は \(store.doneToday.count) 件 完了しました")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                        }
                    }
                    ForEach(Array(store.open.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                        FocusCard(item: item, index: index, drag: index == 0 && item.id == dragID ? drag : .zero)
                            .onTapGesture { editTodo(item) }
                            .gesture(swipe(item), including: index == 0 ? .all : .none)
                            .todoMenu(item)
                            .transition(cardTransition)
                    }
                }
                .overlay { celebration }
                .padding(.bottom, 30) // 後ろのカードがのぞく分
                .frame(maxHeight: .infinity)
                if !store.open.isEmpty {
                    HStack {
                        Label("明日へ", systemImage: "arrow.left").foregroundStyle(p.overdue)
                        Spacer()
                        Label("完了", systemImage: "arrow.right").labelStyle(TrailingIcon()).foregroundStyle(p.accent)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 32)
                }
                Color.clear.frame(height: 72) // 右下の＋の分
            }
            AddButton(action: onAdd).padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .sensoryFeedback(.success, trigger: feedback)
    }

    /// 今日の完了（目のボタンがオンのとき）。線を引いて薄く、横にスクロール
    private var doneStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.shownDone) { item in
                    Button { editTodo(item) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(p.accent)
                            Text(item.title).strikethrough(true, color: p.sub).foregroundStyle(p.sub).lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(p.card.opacity(0.7), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .todoMenu(item)
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }

    /// 山札のカード：後ろから出てきて、完了・延期では飛んでいく
    private var cardTransition: AnyTransition {
        let fly: AnyTransition = AnyTransition.offset(x: flyDir * 600).combined(with: .opacity)
        return .asymmetric(insertion: motion.appear(reduce: reduce), removal: reduce ? AnyTransition.opacity : fly)
    }

    /// 完了したとき、山札の上に大きなチェックがふくらんで消える
    private var celebration: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 96, weight: .bold))
            .foregroundStyle(p.accent)
            .allowsHitTesting(false)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: celebrate) { view, v in
                view.scaleEffect(reduce ? 1 : 0.6 + 0.5 * v).opacity(Double(v))
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(CGFloat(1), duration: 0.25)
                    LinearKeyframe(CGFloat(1), duration: 0.15)
                    LinearKeyframe(CGFloat(0), duration: 0.3)
                }
            }
    }

    /// 飛んでいったカードが消えてから戻す（先に戻すと、消える前に真ん中へ戻って見える）
    private func resetDrag() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(motion.tap(reduce: reduce)) { drag = .zero }
            dragID = nil
        }
    }

    private func swipe(_ item: TodoItem) -> some Gesture {
        DragGesture()
            .onChanged { dragID = item.id; drag = $0.translation }
            .onEnded { v in
                if v.translation.width > 120 {
                    flyDir = 1
                    withAnimation(motion.tap(reduce: reduce)) { drag = CGSize(width: 600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(motion.change(reduce: reduce)) { store.complete(item) } // 次のカードがせり上がる
                        feedback += 1
                        celebrate += 1
                        resetDrag()
                    }
                } else if v.translation.width < -120 {
                    flyDir = -1
                    withAnimation(motion.tap(reduce: reduce)) { drag = CGSize(width: -600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(motion.change(reduce: reduce)) { store.postpone(item) }
                        resetDrag()
                    }
                } else {
                    withAnimation(motion.tap(reduce: reduce)) { drag = .zero }
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
            HStack(spacing: 8) {
                Text(item.isOverdue() ? "期限切れ・" + DueText.label(item) : DueText.label(item)).font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tag.opacity(0.14), in: Capsule()).foregroundStyle(tag)
                if item.repeatRule != nil { Image(systemName: "repeat").foregroundStyle(p.sub) }
                if item.isCalendar { Image(systemName: "calendar").foregroundStyle(p.sub) }
                Spacer()
                if item.isImportant { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            Spacer(minLength: 0)
            Text(item.title).font(.system(size: 34, weight: .bold, design: p.fontDesign)).foregroundStyle(p.text)
                .lineLimit(3).minimumScaleFactor(0.6)
            if let note = item.note, !note.isEmpty { Text(note).font(.callout).foregroundStyle(p.sub).lineLimit(2) }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200, maxHeight: 360)
        .background(RoundedRectangle(cornerRadius: p.radius + 4, style: .continuous).fill(p.card)
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8))
        .overlay(alignment: .topTrailing) {
            if drag.width > 30 { stamp("完了", p.accent) } else if drag.width < -30 { stamp("明日へ", p.overdue) }
        }
        .padding(.horizontal, 24)
        .scaleEffect(1 - CGFloat(index) * 0.05)
        .offset(x: drag.width, y: CGFloat(index) * 16 + drag.height * 0.1)
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
        case .later: "それより先"
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

    /// 完了したものは期限切れにならない（期限が過ぎていれば「今日」に入る）
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
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let onAdd: () -> Void
    @State private var draft = ""
    /// たたんでいる見出し（見出しを押して開け閉め）
    @State private var collapsed: Set<Int> = []

    var body: some View {
        let open: [TodoItem] = store.open
        let done: [TodoItem] = store.shownDone
        VStack(spacing: 0) {
            List {
                Section {
                    TodoHeader(subtitle: countLine(open: open.count, done: store.doneToday.count)) {
                        HeaderTitle(text: JP.date(.now))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
                }
                ForEach(DueGroup.allCases, id: \.self) { g in
                    let items: [TodoItem] = open.filter { DueGroup.of($0) == g }
                    let finished: [TodoItem] = done.filter { DueGroup.of($0) == g }
                    if !items.isEmpty || !finished.isEmpty {
                        Section {
                            if !collapsed.contains(g.rawValue) {
                                ForEach(items) { TodoLine(item: $0) }
                                ForEach(finished) { TodoLine(item: $0) }
                            }
                        } header: {
                            groupHeader(g, count: items.count)
                        }
                        .listRowBackground(p.card)
                    }
                }
                if open.isEmpty {
                    TodoEmptyState(title: "やることはありません", message: "下の欄に書いて、確定で追加できます")
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .listSectionSpacing(.compact)
            inputBar
        }
        .paletteBackground(p)
    }

    /// 見出し：押すとたたむ・開く（右の矢印が回る）
    private func groupHeader(_ g: DueGroup, count: Int) -> some View {
        let isCollapsed: Bool = collapsed.contains(g.rawValue)
        return Button {
            withAnimation(motion.change(reduce: reduce)) {
                if isCollapsed { collapsed.remove(g.rawValue) } else { collapsed.insert(g.rawValue) }
            }
        } label: {
            HStack(spacing: 8) {
                SectionBar(title: g.name, count: count, color: g.color(p))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "\(g.name)を開く" : "\(g.name)をたたむ")
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("何をする？（例：明日15時 買い物）", text: $draft)
                .submitLabel(.done)
                .onSubmit {
                    let q = QuickParse.parse(draft)
                    withAnimation(motion.change(reduce: reduce)) {
                        store.add(q.title, due: q.due, allDay: q.allDay, repeatRule: q.repeatRule)
                    }
                    draft = ""
                }
                .foregroundStyle(p.text)
                .padding(.horizontal, 16).frame(height: 46)
                .background(p.card, in: Capsule())
            AddButton(size: 46, action: onAdd)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - ③ 週間：上の日付ボタンで期限の日を選び、その日が期限のTODOを一覧。一覧を横にスワイプでも日を移る。右下の＋で追加

struct WeekHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let onAdd: (AddDraft) -> Void
    @State private var offset = 0   // 今日から何日後を見ているか
    /// 日を移った向き（一覧が押し出される向き）
    @State private var forward = true
    @Namespace private var pill

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let day = cal.date(byAdding: .day, value: offset, to: today) ?? today
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TodoHeader(subtitle: countLine(open: store.open.count, done: store.doneToday.count)) {
                    HeaderTitle(text: JP.date(day)).contentTransition(.numericText())
                }
                .padding(.horizontal, 16).padding(.top, 12)
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let d = cal.date(byAdding: .day, value: i, to: today) ?? today
                        Button { select(i) } label: { chip(d, selected: i == offset) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
                dayList(day)
                    .id(offset)
                    .transition(listTransition)
                    .simultaneousGesture(daySwipe)
            }
            AddButton {
                onAdd(AddDraft(due: offset == 0 ? nil : cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)))
            }
            .padding(22)
        }
        .clipped()
        .paletteBackground(p)
        .sensoryFeedback(.selection, trigger: offset)
    }

    private func dayList(_ day: Date) -> some View {
        let dayItems: [TodoItem] = items(on: day)
        let dayDone: [TodoItem] = doneItems(on: day)
        let undated: [TodoItem] = store.open.filter { $0.due == nil }
        return List {
            if offset == 0 && !store.overdue.isEmpty {
                Section {
                    ForEach(store.overdue) { TodoLine(item: $0, swipes: false) }
                } header: { SectionBar(title: "期限切れ", count: store.overdue.count, color: p.overdue) }
                .listRowBackground(p.card)
            }
            Section {
                ForEach(dayItems) { TodoLine(item: $0, swipes: false) }
                ForEach(dayDone) { TodoLine(item: $0, swipes: false) }
                if dayItems.isEmpty && dayDone.isEmpty {
                    Text(offset == 0 ? "今日が期限のTODOはありません" : "この日が期限のTODOはありません")
                        .font(.subheadline).foregroundStyle(p.sub).padding(.vertical, 6)
                }
            } header: {
                SectionBar(title: offset == 0 ? "今日" : (offset == 1 ? "明日" : JP.date(day)), count: dayItems.count, color: p.accent)
            }
            .listRowBackground(p.card)
            if offset == 0 && !undated.isEmpty {
                Section {
                    ForEach(undated) { TodoLine(item: $0, swipes: false) }
                } header: { SectionBar(title: "期限なし", count: undated.count, color: p.sub) }
                .listRowBackground(p.card)
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(.compact)
        .contentMargins(.bottom, 80, for: .scrollContent)
    }

    /// 日を移すと、一覧が横に押し出される（視差効果を減らす ならフェード）
    private var listTransition: AnyTransition {
        if reduce { return .opacity }
        return .push(from: forward ? .trailing : .leading)
    }

    /// 一覧を横にスワイプ：左へで次の日、右へで前の日
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                let dx: CGFloat = v.translation.width
                guard abs(dx) > 70, abs(dx) > abs(v.translation.height) * 1.5 else { return }
                select(dx < 0 ? min(offset + 1, 6) : max(offset - 1, 0))
            }
    }

    private func select(_ i: Int) {
        guard i != offset else { return }
        forward = i > offset
        withAnimation(motion.change(reduce: reduce)) { offset = i }
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

    /// その日の今日の完了（目のボタンがオンのとき）。今日を見ているときは、期限が過ぎたもの・期限なしも今日に出す
    private func doneItems(on day: Date) -> [TodoItem] {
        let cal = Calendar.current
        let isToday: Bool = cal.isDateInToday(day)
        return store.shownDone.filter { item in
            guard let due = item.due else { return isToday }
            if cal.isDate(due, inSameDayAs: day) { return true }
            return isToday && due < day
        }
    }

    /// 日付のボタン。選んだ日の色の札は matchedGeometryEffect で横にすべって移る
    private func chip(_ d: Date, selected: Bool) -> some View {
        let cal = Calendar.current
        let n = items(on: d).count
        let isWeekend: Bool = cal.isDateInWeekend(d)
        let weekdayColor: Color = selected ? p.onAccent : (isWeekend ? p.overdue : p.sub)
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous)
        return VStack(spacing: 3) {
            Text(Self.weekdays[cal.component(.weekday, from: d) - 1]).font(.caption2.weight(.bold)).foregroundStyle(weekdayColor)
            Text("\(cal.component(.day, from: d))").font(.title3.weight(.heavy)).monospacedDigit()
            Circle().fill(n > 0 ? (selected ? p.onAccent : p.accent) : Color.clear).frame(width: 6, height: 6)
        }
        .foregroundStyle(selected ? p.onAccent : p.text)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background {
            ZStack {
                shape.fill(p.card)
                if selected { shape.fill(p.accent).matchedGeometryEffect(id: "pill", in: pill) }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - ④ ながれ：今日の完了から先の期限まで1本の線でつないだTODO。「いま」の位置に印。右上の＋で追加

struct FlowHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let onAdd: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = ctx.date
            let entries: [TodoItem] = timeline
            let nowIndex: Int = entries.firstIndex { !$0.done && ($0.due ?? .distantFuture) > now } ?? entries.count
            let undated: [TodoItem] = store.open.filter { $0.due == nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TodoHeader(subtitle: countLine(open: store.open.count, done: store.doneToday.count),
                               trailing: AnyView(AddButton(size: 44, action: onAdd))) {
                        HeaderTitle(text: JP.date(now))
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, item in
                        if i == nowIndex { NowMarker(now: now) }
                        if i == 0 || !sameDay(entries[i - 1], item) { dayLabel(item) }
                        FlowRow(item: item)
                    }
                    if nowIndex == entries.count && !entries.isEmpty { NowMarker(now: now) }

                    if !undated.isEmpty {
                        Text("期限なし").font(.headline.weight(.bold)).foregroundStyle(p.text)
                            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
                        ForEach(undated) { FlowRow(item: $0) }
                    }
                    if entries.isEmpty && undated.isEmpty {
                        TodoEmptyState(title: "やることはありません", message: "右上の ＋ から追加できます")
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .paletteBackground(p)
    }

    /// 今日の完了（目のボタンがオンのとき）＋期限つきの未完了を時刻順に
    private var timeline: [TodoItem] {
        let list: [TodoItem] = store.shownDone + store.open.filter { $0.due != nil }
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
}

/// 「いま」の印。丸のまわりに輪がゆっくり広がる（視差効果を減らす ならじっとしている）
struct NowMarker: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduce
    let now: Date
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Text("いま \(JP.time(now))").font(.caption.monospacedDigit().weight(.heavy)).foregroundStyle(p.overdue)
                .lineLimit(1).fixedSize()
                .contentTransition(.numericText())
                .frame(width: 70, alignment: .trailing)
            Circle().fill(p.overdue).frame(width: 10, height: 10)
                .background {
                    Circle().fill(p.overdue.opacity(0.35))
                        .scaleEffect(pulse ? 2.6 : 1)
                        .opacity(pulse ? 0 : 1)
                }
            Rectangle().fill(p.overdue).frame(height: 2)
        }
        .padding(.trailing, 20).padding(.vertical, 6)
        .onAppear {
            guard !reduce else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// ながれの1行：左に時刻、中央に線と丸、右にカード。完了にすると丸から輪が広がる
struct FlowRow: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.editTodo) private var editTodo
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let item: TodoItem
    @State private var sweeping = false
    @State private var ripple = 0

    var body: some View {
        let shownDone: Bool = item.done || sweeping
        let color = item.done ? p.sub : (item.isOverdue() ? p.overdue : p.accent)
        HStack(alignment: .center, spacing: 10) {
            Text(timeText)
                .font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 62, alignment: .trailing)
            Button {
                if !item.done { ripple += 1 }
                CompleteMotion.toggle(item, store: store, motion: motion, reduce: reduce, sweeping: $sweeping)
            } label: {
                CheckMark(done: shownDone, color: color, size: 24)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 8))
                    .rippleRing(ripple, color: p.accent, enabled: !reduce)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: ripple)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.isImportant && !item.done { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(shownDone ? p.sub : p.text)
                        .strikethrough(item.done, color: p.sub).lineLimit(2)
                        .sweepLine(sweeping && !item.done, color: p.sub)
                    if item.repeatRule != nil { Image(systemName: "repeat").font(.caption).foregroundStyle(p.sub) }
                }
                if item.isOverdue() {
                    Text("期限切れ・" + DueText.label(item)).font(.caption.weight(.semibold)).foregroundStyle(p.overdue)
                } else if let note = item.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card, in: RoundedRectangle(cornerRadius: min(p.radius, 16), style: .continuous))
            .opacity(item.done ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture { editTodo(item) }
        }
        .padding(.leading, 10).padding(.trailing, 16).padding(.vertical, 5)
        // 丸の中心を通る縦線（行の高さいっぱい）
        .background(alignment: .leading) {
            Rectangle().fill(p.sub.opacity(0.25)).frame(width: 2).padding(.leading, 10 + 62 + 10 + 11)
        }
        .transition(motion.appear(reduce: reduce))
        .todoMenu(item)
    }

    /// 時刻の列：今日の時刻・終日。期限なしの完了は完了した時刻
    private var timeText: String {
        if item.due == nil, item.done, let at = item.doneAt { return JP.time(at) }
        return JP.clock(item, none: "")
    }
}
