import SwiftUI
import Charts

// 家計簿のホームのカード：いまの周期の支出・収入・残り／目標貯金／使い道。
// どれもタップでくわしく（KakeiboDetailView）を開く。中のボタン（周期の切り替えなど）は、そのボタンの動きが先

// MARK: - 支出・収入・残り

struct KakeiboSummaryCard: View {
    let summary: KakeiboSummary
    @Binding var offset: Int
    let onOpen: () -> Void
    let onSettings: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion

    var body: some View {
        let atLatest: Bool = offset >= 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(summary.cycle.title + "の支出").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                Spacer()
                cycleButton("chevron.left", label: "前の周期") { offset -= 1 }
                Text(summary.cycle.title).font(.subheadline.weight(.bold)).foregroundStyle(p.text).frame(minWidth: 52)
                cycleButton("chevron.right", label: "次の周期") { offset += 1 }
                    .disabled(atLatest)
                    .opacity(atLatest ? 0.35 : 1)
            }
            KakeiboBigYen(value: summary.spent)
                .animation(motion.change, value: summary.spent)
            HStack(spacing: 10) {
                figure("収入", summary.income, color: KakeiboStyle.color(KakeiboCategories.income))
                figure("残り（収入 − 支出）", summary.left, color: summary.left < 0 ? p.overdue : p.accent)
            }
            paydayLine
        }
        .paletteCard(p, padding: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "くわしく見る", onOpen)
    }

    private func figure(_ title: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(KakeiboFormat.signedYen(value)).font(.title3.weight(.heavy)).foregroundStyle(color)
                    .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                Text("円").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(p.sub.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var paydayLine: some View {
        if summary.payday == nil {
            Button(action: onSettings) {
                Label("給料日を決めると、給料日から次の給料日の前の日までで数えます ›", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.bold)).foregroundStyle(p.accent).multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                Text(paydayText)
                Spacer(minLength: 4)
                Text("くわしく ›").foregroundStyle(p.sub)
            }
            .font(.caption.weight(.bold)).foregroundStyle(p.accent)
        }
    }

    private var paydayText: String {
        guard let d = summary.daysToPayday else { return summary.cycle.rangeText }
        return d == 0 ? "今日は給料日" : "次の給料日まであと\(d)日"
    }

    private func cycleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion.change) { action() } } label: {
            Image(systemName: icon).font(.footnote.weight(.heavy)).foregroundStyle(p.text)
                .frame(width: 36, height: 36)
                .background(p.sub.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 目標貯金

struct KakeiboGoalCard: View {
    let goal: KakeiboSavingsGoal
    let progress: KakeiboSavings.Progress
    let cycle: KakeiboCycle.Period
    let onOpen: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: progress.reached ? "flag.checkered.circle.fill" : "flag.checkered")
                    .foregroundStyle(p.accent)
                Text("目標貯金").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                Spacer(minLength: 4)
                Text(KakeiboGoalText.title(goal)).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if progress.reached {
                Text("目標に届きました").font(.title3.weight(.heavy)).foregroundStyle(p.accent)
            } else if progress.monthsLeft == 0 {
                Text("期限を過ぎました・あと \(KakeiboFormat.yen(progress.remaining)) 円").font(.headline.weight(.heavy))
                    .foregroundStyle(p.overdue)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("月に").font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                    Text(KakeiboFormat.yen(progress.perMonth)).font(.title.weight(.heavy)).monospacedDigit().foregroundStyle(p.text)
                    Text("円 残せば届きます").font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                }
                cycleLine
            }
            GeometryReader { geo in
                let w: CGFloat = geo.size.width * CGFloat(progress.ratio)
                ZStack(alignment: .leading) {
                    Capsule().fill(p.accent.opacity(0.15))
                    Capsule().fill(p.accent).frame(width: max(progress.ratio > 0 ? 12 : 0, w))
                }
            }
            .frame(height: 10)
            .animation(motion.change, value: progress.ratio)
            Text("これまでに \(KakeiboFormat.signedYen(progress.saved)) 円 ・ あと \(progress.monthsLeft)か月")
                .font(.caption).foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "くわしく見る", onOpen)
    }

    /// 今の周期：残せた額と必要額、届いているか
    private var cycleLine: some View {
        let ok: Bool = progress.onTrack
        let short: Int = max(0, progress.needThisCycle - progress.savedThisCycle)
        return HStack(spacing: 8) {
            Text("\(cycle.title)：残せた \(KakeiboFormat.signedYen(progress.savedThisCycle)) / 必要 \(KakeiboFormat.yen(progress.needThisCycle)) 円")
                .font(.caption.weight(.bold)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(ok ? "順調" : "あと \(KakeiboFormat.yen(short)) 円")
                .font(.caption2.weight(.heavy)).foregroundStyle(ok ? p.onAccent : p.overdue)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(ok ? p.accent : p.overdue.opacity(0.14), in: Capsule())
        }
    }
}

enum KakeiboGoalText {
    /// 「2027年3月分までに 300,000 円」
    static func title(_ goal: KakeiboSavingsGoal) -> String {
        let cal = Calendar.current
        let y: Int = cal.component(.year, from: goal.deadline)
        let m: Int = cal.component(.month, from: goal.deadline)
        return "\(y)年\(m)月分までに \(KakeiboFormat.yen(goal.amount)) 円"
    }
}

// MARK: - 使い道（分類別の円グラフ）

struct KakeiboCategoryCard: View {
    let summary: KakeiboSummary
    let onOpen: () -> Void
    @Environment(\.palette) private var p

    struct Slice: Identifiable {
        var id: String { category }
        let category: String
        let amount: Int
        let color: Color
    }

    private var slices: [Slice] {
        let all = summary.categories
        var out: [Slice] = all.prefix(3).map { Slice(category: $0.name, amount: $0.amount, color: KakeiboStyle.color($0.name)) }
        let rest: Int = all.dropFirst(3).reduce(0) { $0 + $1.amount }
        if rest > 0 { out.append(Slice(category: "ほか", amount: rest, color: p.sub.opacity(0.45))) }
        return out
    }

    var body: some View {
        let list = slices
        let total: Int = list.reduce(0) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("使い道").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                Spacer()
                Text("くわしく ›").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            }
            HStack(spacing: 16) {
                KakeiboDonut(slices: list)
                    .frame(width: 96, height: 96)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText(list, total))
                VStack(alignment: .leading, spacing: 6) {
                    if list.isEmpty {
                        Text("この周期の支出はまだありません。明細を取り込むと、取引先から自動で分けます")
                            .font(.subheadline).foregroundStyle(p.sub)
                    }
                    ForEach(list) { s in legendRow(s, total) }
                }
            }
        }
        .paletteCard(p, padding: 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "くわしく見る", onOpen)
    }

    private func legendRow(_ s: Slice, _ total: Int) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 10, height: 10)
            Text(s.category).font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(KakeiboFormat.yen(s.amount)) 円").font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                .monospacedDigit()
        }
    }

    private func accessibilityText(_ list: [Slice], _ total: Int) -> String {
        guard total > 0 else { return "分類別の支出：なし" }
        let parts: [String] = list.map { "\($0.category) \($0.amount * 100 / total)％" }
        return "分類別の支出：" + parts.joined(separator: "、")
    }
}

/// 円グラフ
struct KakeiboDonut: View {
    let slices: [KakeiboCategoryCard.Slice]
    @Environment(\.palette) private var p

    var body: some View {
        if slices.isEmpty {
            Circle().stroke(p.accent.opacity(0.15), lineWidth: 16).padding(8)
        } else {
            Chart(slices) { s in
                SectorMark(angle: .value("金額", s.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(s.color)
                    .cornerRadius(3)
            }
            .chartLegend(.hidden)
        }
    }
}

// MARK: - 最後の取り込み（取り込み忘れを防ぐ1行）

/// 「十六銀行 3日前・JCB 28日前」。期限を過ぎた銀行・カードは注意の色と「取り込む」
struct KakeiboImportStatus: View {
    let dues: [KakeiboReminders.Due]
    let onImport: (KakeiboInstitution) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        if !dues.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                KakeiboFlowLayout(spacing: 6) {
                    ForEach(dues) { d in item(d) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("最後の取り込み")
        }
    }

    private func ago(_ d: KakeiboReminders.Due) -> String {
        let n: Int = d.daysSince()
        return n == 0 ? "今日" : "\(n)日前"
    }

    @ViewBuilder private func item(_ d: KakeiboReminders.Due) -> some View {
        let late: Bool = d.isOverdue()
        if late {
            Button { onImport(d.institution) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("\(d.institution.name) \(ago(d))")
                    Text("取り込む").foregroundStyle(p.onAccent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(p.overdue, in: Capsule())
                }
                .font(.caption.weight(.heavy)).foregroundStyle(p.overdue)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(d.institution.name) \(ago(d))。明細の取り込みがまだです。取り込む")
        } else {
            Text("\(d.institution.name) \(ago(d))").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                .frame(minHeight: 32)
        }
    }
}
