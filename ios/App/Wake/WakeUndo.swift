import SwiftUI

// 誤タップ対策：受付時間外の「起きた！」は押せないようにし、チェックインは取り消せるようにする

/// 受付時間の外で、次のアラームのカードの下に出す「押せない起きた！」と理由
struct WakeLockedCheckIn: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        if model.checkInAt == nil && !model.canCheckIn, let from = model.checkInFrom {
            let reason: String = "\(WakeLogic.dayLabel(from, now: model.now)) \(JP.time(from))から押せます"
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(Font.caption.weight(.bold))
                        Text("起きた！").font(Font.subheadline.weight(.heavy))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(p.sub)
                    .overlay(Capsule().strokeBorder(p.sub.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    // 押し間違い防止のため、最初のアラームの2時間前から（説明は「アラームの詳細」に）
                    Text(reason).font(Font.footnote.weight(.bold)).foregroundStyle(p.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

/// チェックイン後、その日のあいだ出す「起きたを取り消す」（確認つき）。起床タブのホームの行の1つ
struct WakeUndoRow: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            WakeRowLabel(icon: "arrow.uturn.backward", title: "起きたを取り消す",
                         detail: "押し間違えたときに。今日のアラームを予約し直します", tint: p.overdue)
        }
        .buttonStyle(.plain)
        .confirmationDialog("起きたを取り消しますか？", isPresented: $confirm, titleVisibility: .visible) {
            Button("取り消す", role: .destructive) { model.undoCheckIn() }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("今日の起床の記録を消し、これから鳴るはずだった今日のアラームを予約し直します。")
        }
    }
}

/// チェックイン直後に約10秒出す「取り消す」
struct WakeUndoToast: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(Font.title3).foregroundStyle(p.onAccent)
            Text("起床を記録しました").font(Font.subheadline.weight(.bold)).foregroundStyle(p.onAccent)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button { model.undoCheckIn() } label: {
                Text("取り消す").font(Font.subheadline.weight(.heavy))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(p.onAccent.opacity(0.2), in: Capsule())
                    .foregroundStyle(p.onAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(p.accent, in: RoundedRectangle(cornerRadius: min(p.radius, 20), style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 20).padding(.bottom, 12)
    }
}
