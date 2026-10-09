import SwiftUI

// 「今日」の各構成と追加画面で共通に使う部品（見出し・完了の表示切り替え・空の表示・チップ）

// MARK: - 見出し

/// 各構成の見出し。1段目：題名と右上の歯車（＋ trailing）、2段目：件数と「完了済み｜目」のボタン（＋ leading）
struct TodoHeader<Title: View>: View {
    @Environment(\.palette) private var p
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    var leading: AnyView? = nil
    @ViewBuilder let title: () -> Title

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                title()
                Spacer(minLength: 8)
                if let trailing { trailing }
                SettingsButton()
            }
            HStack(alignment: .center, spacing: 8) {
                if let leading { leading }
                if let subtitle {
                    Text(subtitle).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                DoneControls()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 見出しの大きな題名（日付など）
struct HeaderTitle: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        Text(text).font(.system(size: 26, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// 「完了済み（一覧を開く）」と「目（今日の完了を表示・非表示）」をひとつのカプセルに
struct DoneControls: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.openList) private var openList
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let on: Bool = store.showDone
        let count: Int = store.doneToday.count
        HStack(spacing: 0) {
            Button { openList(.done) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle")
                        .symbolEffect(.bounce, value: count)
                        .symbolEffectsRemoved(reduce)
                    Text("完了済み")
                    if count > 0 {
                        Text("\(count)").monospacedDigit().foregroundStyle(p.sub)
                            .contentTransition(.numericText())
                    }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
                .lineLimit(1).fixedSize()
                .padding(.leading, 12).padding(.trailing, 10).frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完了済みの一覧")
            Rectangle().fill(p.sub.opacity(0.3)).frame(width: 1, height: 18)
            Button { withAnimation(motion.change(reduce: reduce)) { store.setShowDone(!on) } } label: {
                Image(systemName: on ? "eye.fill" : "eye.slash")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(on ? p.accent : p.sub)
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? "今日の完了を隠す" : "今日の完了を表示")
        }
        .background(p.card, in: Capsule())
        .sensoryFeedback(.selection, trigger: on)
    }
}

/// 構成の見出しの横に置く小さなボタン（一覧など）
struct HeaderChip: View {
    @Environment(\.palette) private var p
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).frame(height: 36)
                .background(p.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 丸い＋ボタン（右下に浮かべる・見出しに置く）
struct AddButton: View {
    @Environment(\.palette) private var p
    var size: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(size > 50 ? .title2.bold() : .title3.bold())
                .frame(width: size, height: size)
                .foregroundStyle(p.onAccent).background(p.accent, in: Circle())
                .shadow(color: .black.opacity(size > 50 ? 0.2 : 0), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("TODOを追加")
    }
}

// MARK: - 空のとき

struct TodoEmptyState: View {
    @Environment(\.palette) private var p
    var icon: String = "checkmark.seal.fill"
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 44, weight: .semibold)).foregroundStyle(p.accent.opacity(0.85))
            Text(title).font(.headline.weight(.bold)).foregroundStyle(p.text)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(p.sub).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - チップ（追加画面・かんばん）

struct ChoiceChip: View {
    @Environment(\.palette) private var p
    let title: String
    var icon: String? = nil
    var selected = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        let c: Color = tint ?? p.accent
        let fg: Color = selected ? p.onAccent : p.text
        let bg: Color = selected ? c : p.card
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.footnote.weight(.bold)) }
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 13).frame(height: 36)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(p.sub.opacity(selected ? 0 : 0.18), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 折り返して並べる（チップ用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = arrange(width: width, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width = r.indices.isEmpty ? size.width : r.width + spacing + size.width
            r.height = max(r.height, size.height)
            r.indices.append(i)
            rows[rows.count - 1] = r
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - 期限の選び方（追加画面のチップ・期限の移動）

enum DueChoice: String, CaseIterable, Identifiable {
    case today, tonight, tomorrow, weekend, nextWeek

    var id: String { rawValue }

    var name: String {
        switch self {
        case .today: "今日"
        case .tonight: "今夜"
        case .tomorrow: "明日"
        case .weekend: "週末"
        case .nextWeek: "来週"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .tonight: "moon"
        case .tomorrow: "sunrise"
        case .weekend: "beach.umbrella"
        case .nextWeek: "calendar"
        }
    }

    /// 選んだときの日（その日の 0 時）と時刻（nil は終日）
    func resolve(now: Date = .now) -> (day: Date, time: DateComponents?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        switch self {
        case .today: return (today, nil)
        case .tonight:
            // 20 時を過ぎていたら、いまから1時間後（0時を越えない）
            let h = cal.component(.hour, from: now)
            return (today, DateComponents(hour: h >= 20 ? min(h + 1, 23) : 20, minute: 0))
        case .tomorrow: return (cal.date(byAdding: .day, value: 1, to: today) ?? today, nil)
        case .weekend: return (Self.weekend(from: today), nil)
        case .nextWeek: return (Self.nextMonday(from: today), nil)
        }
    }

    /// 次の土曜（今日が土・日なら今日）
    static func weekend(from today: Date) -> Date {
        let cal = Calendar.current
        let w = cal.component(.weekday, from: today) // 日曜 = 1 … 土曜 = 7
        if w == 7 || w == 1 { return today }
        return cal.date(byAdding: .day, value: 7 - w, to: today) ?? today
    }

    /// 来週の月曜
    static func nextMonday(from today: Date) -> Date {
        let cal = Calendar.current
        let w = cal.component(.weekday, from: today)
        let ahead = w == 1 ? 1 : 9 - w
        return cal.date(byAdding: .day, value: ahead, to: today) ?? today
    }
}

/// 時刻の選び方（追加画面のチップ）
enum TimeChoice: String, CaseIterable, Identifiable {
    case allDay, morning, noon, evening, night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .allDay: "終日"
        case .morning: "朝 9:00"
        case .noon: "昼 12:00"
        case .evening: "夕方 18:00"
        case .night: "夜 21:00"
        }
    }

    var time: DateComponents? {
        switch self {
        case .allDay: nil
        case .morning: DateComponents(hour: 9, minute: 0)
        case .noon: DateComponents(hour: 12, minute: 0)
        case .evening: DateComponents(hour: 18, minute: 0)
        case .night: DateComponents(hour: 21, minute: 0)
        }
    }
}

// MARK: - 動き（テーマの MotionStyle。「視差効果を減らす」がオンなら短いフェードだけ）

extension MotionStyle {
    func tap(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.2) : tap }
    func change(reduce: Bool) -> Animation { reduce ? .easeInOut(duration: 0.25) : change }
    func appear(reduce: Bool) -> AnyTransition { reduce ? .opacity : appear }
}

/// 完了にするとき、題名に左から線を引く（引き終わってから完了にする）
struct SweepLine: ViewModifier {
    let on: Bool
    let color: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            Rectangle().fill(color).frame(height: 1.5)
                .scaleEffect(x: on ? 1 : 0, anchor: .leading)
                .opacity(on ? 1 : 0)
        }
    }
}

extension View {
    func sweepLine(_ on: Bool, color: Color) -> some View { modifier(SweepLine(on: on, color: color)) }
}

/// 完了の操作をそろえる：線を引く → 少し待って完了（行が消える・薄くなる）。戻すときはすぐ
@MainActor
enum CompleteMotion {
    static func toggle(_ item: TodoItem, store: TodoStore, motion: MotionStyle, reduce: Bool,
                       sweeping: Binding<Bool>, onDone: @escaping () -> Void = {}) {
        if item.done {
            withAnimation(motion.change(reduce: reduce)) { store.uncomplete(item) }
            return
        }
        if reduce {
            withAnimation(motion.change(reduce: true)) { store.complete(item) }
            onDone()
            return
        }
        withAnimation(.easeOut(duration: 0.28)) { sweeping.wrappedValue = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(motion.change) { store.complete(item) }
            sweeping.wrappedValue = false
            onDone()
        }
    }
}

/// 完了したときに広がる輪（ながれの丸など）
struct RippleRing: ViewModifier {
    let trigger: Int
    let color: Color
    let enabled: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, v in
            view.overlay {
                Circle().stroke(color, lineWidth: 2)
                    .scaleEffect(1 + v * 1.6)
                    .opacity(enabled && v > 0 ? Double(1 - v) : 0)
            }
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(CGFloat(1), duration: 0.55)
                LinearKeyframe(CGFloat(0), duration: 0.01)
            }
        }
    }
}

extension View {
    func rippleRing(_ trigger: Int, color: Color, enabled: Bool = true) -> some View {
        modifier(RippleRing(trigger: trigger, color: color, enabled: enabled))
    }
}
