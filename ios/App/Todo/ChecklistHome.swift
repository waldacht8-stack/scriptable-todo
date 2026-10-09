import SwiftUI

// MARK: - ⑥ チェックリスト：紙のリストのように詰めて並べ、大きな四角のチェック欄で消していく。最後の行に書き足す

struct ChecklistHome: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let onAdd: () -> Void
    @State private var draft = ""
    @FocusState private var writing: Bool
    @State private var feedback = 0

    var body: some View {
        let open: [TodoItem] = store.open
        let done: [TodoItem] = store.shownDone
        List {
            Section {
                TodoHeader(subtitle: countLine(open: open.count, done: store.doneToday.count),
                           trailing: AnyView(AddButton(size: 44, action: onAdd))) {
                    HeaderTitle(text: JP.date(.now))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            }
            Section {
                ForEach(open) { item in
                    ChecklistRow(item: item, feedback: $feedback).listRowBackground(paper)
                }
                ForEach(done) { item in
                    ChecklistRow(item: item, feedback: $feedback).listRowBackground(paper)
                }
                writeRow.listRowBackground(paper)
            } footer: {
                if open.isEmpty {
                    Text("やることはありません。最後の行に書き足せます。")
                        .font(.footnote).foregroundStyle(p.sub)
                }
            }
            .listRowSeparatorTint(p.sub.opacity(0.25))
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 46)
        .scrollDismissesKeyboard(.interactively)
        .paletteBackground(p)
        .sensoryFeedback(.success, trigger: feedback)
    }

    /// 紙：カードの色に、チェック欄の右に赤い縦線（ノートの余白線）
    private var paper: some View {
        p.card.overlay(alignment: .leading) {
            Rectangle().fill(p.overdue.opacity(0.28)).frame(width: 1.5).padding(.leading, 58)
        }
    }

    /// 最後の行：書いて確定すると追加（続けて書ける）
    private var writeRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(p.accent)
                .frame(width: 30, height: 30)
            TextField("書き足す（例：明日10時 電話）", text: $draft)
                .font(.body.weight(.semibold))
                .foregroundStyle(p.text)
                .focused($writing)
                .submitLabel(.next)
                .onSubmit {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { writing = false; return }
                    let q = QuickParse.parse(text)
                    withAnimation(motion.change(reduce: reduce)) { store.add(q.title, due: q.due, allDay: q.allDay, repeatRule: q.repeatRule) }
                    draft = ""
                    writing = true
                }
        }
        .padding(.vertical, 4)
    }
}

/// チェックリストの1行：大きな四角、題名、右に期限
struct ChecklistRow: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.editTodo) private var editTodo
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var sweeping = false
    let item: TodoItem
    @Binding var feedback: Int

    var body: some View {
        let overdue: Bool = item.isOverdue()
        let boxColor: Color = item.done ? p.sub : (overdue ? p.overdue : p.text.opacity(0.75))
        HStack(alignment: .center, spacing: 14) {
            Button {
                // 赤ペンで線を引くように消してから完了
                if !item.done { feedback += 1 }
                CompleteMotion.toggle(item, store: store, motion: motion, reduce: reduce, sweeping: $sweeping)
            } label: {
                CheckMark(done: item.done || sweeping, color: boxColor, size: 30, square: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? "未完了に戻す" : "完了にする")
            HStack(spacing: 4) {
                if item.isImportant && !item.done {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
                Text(item.title)
                    .font(.system(.body, design: p.fontDesign).weight(.semibold))
                    .foregroundStyle(item.done ? p.sub : p.text)
                    .strikethrough(item.done, color: p.sub)
                    .lineLimit(2)
                    .sweepLine(sweeping && !item.done, color: p.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing(overdue: overdue)
        }
        .padding(.vertical, 2)
        .opacity(item.done ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editTodo(item) }
        .todoSwipes(item, store: store, animation: motion.change(reduce: reduce))
        .todoMenu(item)
    }

    /// 右の小さな期限（今日は時刻だけ、終日は「終日」、期限なしは出さない）
    @ViewBuilder private func trailing(overdue: Bool) -> some View {
        if item.done, let at = item.doneAt {
            Text(JP.time(at)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(p.sub)
        } else if item.due != nil {
            HStack(spacing: 3) {
                if item.repeatRule != nil { Image(systemName: "repeat").font(.caption2) }
                Text(DueText.label(item)).font(.caption.weight(.bold).monospacedDigit()).lineLimit(1)
            }
            .foregroundStyle(overdue ? p.overdue : p.sub)
            .fixedSize()
        }
    }
}
