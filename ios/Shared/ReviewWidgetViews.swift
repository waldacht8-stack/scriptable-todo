import SwiftUI
import WidgetKit

// MARK: - 見返し（ウィジェット・中 / 大。案A「3つの丸」）
// 朝・昼・夜の見返しが済んだかを3つの丸で。右に「次の見返しまで◯時間」と、まだ見ていない数。
// 押すと見返しの画面（hiyori://review。アプリがまだ受けていなければアプリが開くだけ）。
// 大は、できなかった（期限切れの）TODO と明日の分も出す。丸を押すと完了。

/// 朝・昼・夜の3つの印（済みは塗り＋チェック、未は輪。次の分の名前は強調色）。今日のまとめでも使う
struct ReviewSlotsView: View {
    let p: Palette
    let done: [Bool]
    var size: CGFloat = 32
    var showLabels: Bool = true
    var spacing: CGFloat = 8

    static let names: [String] = ["朝", "昼", "夜"]

    var body: some View {
        let current: Int? = done.firstIndex(of: false)
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                let isDone: Bool = i < done.count ? done[i] : false
                VStack(spacing: 4) {
                    ReviewSlotMark(p: p, done: isDone, size: size)
                    if showLabels {
                        Text(Self.names[i]).font(.system(size: max(9, size * 0.32), weight: .bold))
                            .foregroundStyle(i == current ? p.accent : p.sub)
                    }
                }
            }
        }
    }
}

/// 1つの印。ブルータルは四角に黒枠とずらした影、クレイはぷっくり、オーロラは光る
struct ReviewSlotMark: View {
    let p: Palette
    let done: Bool
    var size: CGFloat = 32

    var body: some View {
        let line: CGFloat = max(2, size * 0.09)
        let check: Font = Font.system(size: size * 0.48, weight: .black)
        ZStack {
            switch p.world {
            case .brutal:
                let shape = RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                if done { shape.fill(Color.black).offset(x: 2, y: 2) }
                shape.fill(done ? p.accent : p.card)
                shape.strokeBorder(Color.black, lineWidth: max(2, line))
            case .clay:
                if done {
                    let puffy = p.accent
                        .shadow(.inner(color: Color.white.opacity(0.45), radius: 2, x: 1.5, y: 1.5))
                        .shadow(.inner(color: Color.black.opacity(0.18), radius: 2, x: -1.5, y: -2))
                    Circle().fill(puffy).shadow(color: p.accent.opacity(0.35), radius: 3, x: 1, y: 2)
                } else {
                    Circle().strokeBorder(p.accent.opacity(0.85), lineWidth: line)
                }
            case .aurora:
                if done {
                    Circle().fill(p.accent).shadow(color: p.accent.opacity(0.6), radius: 4)
                } else {
                    Circle().strokeBorder(p.accent, lineWidth: line).shadow(color: p.accent.opacity(0.4), radius: 3)
                }
            case .swiss:
                if done {
                    Circle().fill(p.accent)
                } else {
                    Circle().strokeBorder(p.text, lineWidth: max(1, line * 0.5))
                }
            default:
                if done {
                    Circle().fill(p.accent)
                } else {
                    Circle().strokeBorder(p.accent, lineWidth: line)
                }
            }
            if done {
                Image(systemName: "checkmark").font(check).foregroundStyle(p.onAccent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .widgetAccentable()
    }
}

struct ReviewWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: DayWidgetEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { entry.palette }
    private var review: ReviewFeed { entry.review }
    private var done: [Bool] { review.done(entry.date) }

    init(entry: DayWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            if family == .systemLarge { large } else { medium }
        }
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: done.map { $0 ? 1 : 0 } + [review.unreviewedCount ?? 0])
        .widgetURL(WidgetLinks.review)
    }

    /// 次の見返しの名前（朝・昼・夜）
    private var nextName: String {
        guard let t = review.next(after: entry.date) else { return "次の見返し" }
        let h: Int = Calendar.current.component(.hour, from: t)
        let name: String = h < 11 ? "朝" : (h < 17 ? "昼" : "夜")
        let day: String = Calendar.current.isDate(t, inSameDayAs: entry.date) ? "" : "明日の"
        return "次は\(day)\(name)の見返し \(JP.time(t))"
    }

    private var untilText: String {
        guard let t = review.next(after: entry.date) else { return done.allSatisfy { $0 } ? "今日は完了" : "いま見返せます" }
        return WidgetFeedDay.untilText(t, from: entry.date)
    }

    private var unreviewed: Int { review.unreviewedCount ?? 0 }

    // MARK: 中

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("今日の見返し").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    if review.isSample { WidgetSampleBadge(color: p.sub) }
                }
                Spacer(minLength: 0)
                ReviewSlotsView(p: p, done: done, size: 32)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("連続").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
                    WidgetCount(p: p, text: "\(review.streak ?? 0)", value: Double(review.streak ?? 0), size: 13, color: p.text)
                    Text("日").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
                }
            }
            .frame(width: 122, alignment: .leading)
            Rectangle().fill(p.sub.opacity(0.25)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(nextName).font(.caption2.weight(.bold)).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                WidgetCount(p: p, text: untilText, size: 26)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                unreviewedLine.font(.footnote.weight(.bold))
                Spacer(minLength: 0)
                reviewButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unreviewedLine: some View {
        let color: Color = unreviewed > 0 ? p.overdue : p.sub
        let text: String = unreviewed > 0 ? "まだ見ていない \(unreviewed)件" : "全部見ました"
        return Text(text).foregroundStyle(color).lineLimit(1)
            .contentTransition(.numericText(value: Double(unreviewed)))
    }

    private var reviewButton: some View {
        Link(destination: WidgetLinks.review) {
            Text("いま見返す").font(.caption.weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(p.onAccent)
                .widgetButton(p, radius: 14)
        }
    }

    // MARK: 大

    private var large: some View {
        let day: DayTodos = entry.day
        let missed: [TodoItem] = day.open.filter { $0.isOverdue(entry.date) }
        let tomorrow: [TodoItem] = day.tomorrow
        let current: Int? = done.firstIndex(of: false)
        let title: String = current.map { "今日の見返し・\(ReviewSlotsView.names[$0])" } ?? "今日の見返し・完了"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                if review.isSample { WidgetSampleBadge(color: p.sub) }
                Spacer(minLength: 0)
                ReviewSlotsView(p: p, done: done, size: 18, showLabels: false, spacing: 6)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(nextName).font(.caption.weight(.bold)).foregroundStyle(p.sub).lineLimit(1)
                Spacer(minLength: 0)
                Text(untilText).font(.caption.weight(.heavy)).foregroundStyle(p.accent).lineLimit(1)
                    .contentTransition(.numericText())
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(missed.isEmpty ? "できなかったものはありません" : "できなかった").font(.title3.weight(.heavy)).foregroundStyle(p.text)
                if !missed.isEmpty {
                    WidgetCount(p: p, text: "\(missed.count)", value: Double(missed.count), size: 22)
                    Text("件").font(.title3.weight(.heavy)).foregroundStyle(p.text)
                }
                Spacer(minLength: 0)
                unreviewedLine.font(.caption.weight(.bold))
            }
            VStack(spacing: 6) {
                ForEach(missed.prefix(3)) { item in missedRow(item, day: day) }
            }
            Text("明日の分（先に見ておく）").font(.caption.weight(.bold)).foregroundStyle(p.sub).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(tomorrow.prefix(missed.count > 2 ? 2 : 3)) { item in
                    HStack {
                        Text(item.title).font(.subheadline).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(JP.clock(item, none: "")).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(p.sub)
                    }
                    .transition(p.world.widgetRowTransition(p))
                }
                if tomorrow.isEmpty {
                    Text("明日の予定はありません").font(.subheadline).foregroundStyle(p.sub)
                } else if tomorrow.count > 3 {
                    Text("ほか \(tomorrow.count - 3)件").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// できなかった1件（丸を押すと完了）
    private func missedRow(_ item: TodoItem, day: DayTodos) -> some View {
        Button(intent: ToggleTodoIntent(id: item.id)) {
            HStack(spacing: 10) {
                Image(systemName: p.world.widgetCheckSymbol(done: false))
                    .font(.system(size: 16, weight: p.world.widgetCheckWeight)).foregroundStyle(p.overdue)
                    .contentTransition(p.world.widgetSymbolTransition)
                    .invalidatableContent()
                Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                Spacer(minLength: 0)
                Text(day.shortClock(item)).font(.caption.weight(.bold)).foregroundStyle(p.overdue).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .widgetCard(p, radius: 14)
        }
        .buttonStyle(.plain)
        .transition(p.world.widgetRowTransition(p))
    }
}
