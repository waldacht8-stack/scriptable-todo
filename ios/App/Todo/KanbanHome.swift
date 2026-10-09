import SwiftUI

// MARK: - ⑤ かんばん：今日・明日・あとで の3列。横にめくって列を切り替え、上の見出しでも選べる

/// かんばんの列
enum KanbanColumn: Int, CaseIterable, Identifiable, Hashable {
    case today, tomorrow, later

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .today: "今日"
        case .tomorrow: "明日"
        case .later: "あとで"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .tomorrow: "sunrise.fill"
        case .later: "tray.full.fill"
        }
    }

    /// 今日＝期限切れと今日まで、明日、あとで＝明後日以降と期限なし
    static func of(_ item: TodoItem, now: Date = .now) -> KanbanColumn {
        guard let due = item.due else { return .later }
        let cal = Calendar.current
        let days: Int = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        if days <= 0 { return .today }
        if days == 1 { return .tomorrow }
        return .later
    }

    /// この列で＋を押したときの期限（今日・明日は終日、あとでは期限なし）
    func draft(now: Date = .now) -> AddDraft {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch self {
        case .today: return AddDraft(due: today, allDay: true)
        case .tomorrow: return AddDraft(due: cal.date(byAdding: .day, value: 1, to: today), allDay: true)
        case .later: return AddDraft()
        }
    }
}


/// かんばん：上の見出し（色の札がすべって移る）と、横にめくる3列。
/// カードは完了で右へ抜け、列を移すと移った列のほうへすべる
struct KanbanHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let onAdd: (AddDraft) -> Void
    @State private var column: KanbanColumn? = .today
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 0) {
            TodoHeader(subtitle: countLine(open: store.open.count, done: store.doneToday.count)) {
                HeaderTitle(text: JP.date(.now))
            }
            .padding(.horizontal, 16).padding(.top, 12)
            tabs
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(KanbanColumn.allCases) { col in
                        KanbanColumnView(column: col, onAdd: { onAdd(col.draft()) })
                            .containerRelativeFrame(.horizontal)
                            .id(col)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $column)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .animation(motion.change(reduce: reduce), value: column)
        .sensoryFeedback(.selection, trigger: column)
    }

    /// 上の見出し：列の名前と件数。押すとその列へ
    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(KanbanColumn.allCases) { col in
                let selected: Bool = (column ?? .today) == col
                let n: Int = store.open.filter { KanbanColumn.of($0) == col }.count
                Button { withAnimation(motion.change(reduce: reduce)) { column = col } } label: {
                    HStack(spacing: 5) {
                        Text(col.name).font(.subheadline.weight(.bold))
                        Text("\(n)").font(.caption.weight(.heavy)).monospacedDigit()
                            .contentTransition(.numericText())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background((selected ? p.onAccent : p.sub).opacity(0.2), in: Capsule())
                    }
                    .foregroundStyle(selected ? p.onAccent : p.text)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background {
                        ZStack {
                            Capsule().fill(p.card)
                            if selected { Capsule().fill(p.accent).matchedGeometryEffect(id: "tab", in: pill) }
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 1つの列（縦にスクロール）
struct KanbanColumnView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let column: KanbanColumn
    let onAdd: () -> Void

    var body: some View {
        let items: [TodoItem] = store.open.filter { KanbanColumn.of($0) == column }
        let done: [TodoItem] = store.shownDone.filter { KanbanColumn.of($0) == column }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { KanbanCard(item: $0, column: column) }
                if items.isEmpty {
                    TodoEmptyState(icon: column.icon, title: emptyTitle, message: emptyMessage)
                }
                addButton
                if !done.isEmpty {
                    Text("今日の完了").font(.footnote.weight(.bold)).foregroundStyle(p.sub).padding(.top, 6).padding(.leading, 4)
                    ForEach(done) { KanbanCard(item: $0, column: column) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
    }

    private var emptyTitle: String {
        switch column {
        case .today: "今日のTODOはありません"
        case .tomorrow: "明日のTODOはありません"
        case .later: "あとでやることはありません"
        }
    }

    private var emptyMessage: String? {
        column == .today ? "カードの ⇄ で、ほかの列から移せます" : nil
    }

    private var addButton: some View {
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 16), style: .continuous)
        return Button(action: onAdd) {
            Label("\(column.name)に追加", systemImage: "plus").font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(shape.strokeBorder(p.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

/// かんばんのカード：左にチェック、右に列を移すボタン
struct KanbanCard: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.editTodo) private var editTodo
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let item: TodoItem
    let column: KanbanColumn
    @State private var sweeping = false
    /// 移す先の向き（右の列へなら右へ、左の列へなら左へ抜ける）
    @State private var exitEdge: Edge = .trailing

    var body: some View {
        let overdue: Bool = item.isOverdue()
        let shownDone: Bool = item.done || sweeping
        let tint: Color = item.done ? p.sub : (overdue ? p.overdue : p.accent)
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 20), style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            Button {
                exitEdge = .trailing
                CompleteMotion.toggle(item, store: store, motion: motion, reduce: reduce, sweeping: $sweeping)
            } label: {
                CheckMark(done: shownDone, color: tint, size: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "未完了に戻す" : "完了にする")
            .sensoryFeedback(.success, trigger: sweeping) { _, new in new }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.body.weight(.semibold)).foregroundStyle(shownDone ? p.sub : p.text)
                    .strikethrough(item.done, color: p.sub)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .sweepLine(sweeping && !item.done, color: p.sub)
                HStack(spacing: 6) {
                    if item.isImportant && !item.done {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                    TodoMeta(item: item)
                }
            }
            Spacer(minLength: 0)
            if !item.done { moveMenu }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(p.card).shadow(color: .black.opacity(p.scheme == .dark ? 0 : 0.05), radius: 8, y: 3))
        .overlay(alignment: .leading) {
            if overdue { Capsule().fill(p.overdue).frame(width: 4).padding(.vertical, 14) }
        }
        .opacity(item.done ? 0.6 : 1)
        .scaleEffect(sweeping && !reduce ? 0.97 : 1)
        .contentShape(shape)
        .onTapGesture { editTodo(item) }
        .todoMenu(item)
        .transition(cardTransition)
    }

    private var cardTransition: AnyTransition {
        if reduce { return .opacity }
        let out: AnyTransition = AnyTransition.move(edge: exitEdge).combined(with: .opacity)
        return .asymmetric(insertion: motion.appear, removal: out)
    }

    private func move(_ target: TodoStore.DueMove, edge: Edge) {
        exitEdge = edge
        withAnimation(motion.change(reduce: reduce)) { store.move(item, to: target) }
    }

    /// ほかの列へ移す
    private var moveMenu: some View {
        Menu {
            if column != .today {
                Button { move(.today, edge: .leading) } label: { Label("今日へ", systemImage: "sun.max") }
            }
            if column != .tomorrow {
                Button { move(.tomorrow, edge: column == .today ? .trailing : .leading) } label: {
                    Label("明日へ", systemImage: "sunrise")
                }
            }
            if column != .later || item.due != nil {
                Button { move(.nextWeek, edge: .trailing) } label: { Label("来週の月曜へ", systemImage: "calendar") }
                Button { move(.noDue, edge: .trailing) } label: { Label("期限なしにする", systemImage: "tray") }
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                .frame(width: 32, height: 32)
                .background(p.sub.opacity(0.12), in: Circle())
        }
        .accessibilityLabel("ほかの列へ移す")
    }
}
