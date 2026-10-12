import SwiftUI

/// くわしく：周期のまとめ・分類の全部・目標貯金の中身・記録の一覧（「手で足す」もここ）
struct KakeiboDetailView: View {
    @ObservedObject var store: KakeiboStore
    let offset: Int
    let focus: KakeiboDetailFocus
    let onEdit: (KakeiboEntry) -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    @Environment(\.palette) private var p
    @State private var scrolled = false

    private var cycle: KakeiboCycle.Period { store.cycle(offset: offset) }

    private struct Day: Identifiable {
        var id: Date { day }
        let day: Date
        let items: [KakeiboEntry]
    }

    private func days(_ list: [KakeiboEntry]) -> [Day] {
        let cal = Calendar.current
        let groups: [Date: [KakeiboEntry]] = Dictionary(grouping: list) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { Day(day: $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        let summary: KakeiboSummary = store.summary(cycle)
        let list: [KakeiboEntry] = store.entries(in: cycle)
        ScrollViewReader { proxy in
            List {
                summarySection(summary)
                categorySection(summary)
                goalSection
                Section {
                    Button(action: onAdd) {
                        Label("手で足す（現金の支払いなど）", systemImage: "plus.circle")
                            .font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .listRowBackground(p.card)
                    .id(KakeiboDetailFocus.records)
                    if list.isEmpty {
                        Text("この周期の記録はありません。「明細を取り込む」から入れられます").font(.subheadline).foregroundStyle(p.sub)
                            .listRowBackground(p.card)
                    }
                } header: {
                    header("記録 \(list.count)件")
                }
                ForEach(days(list)) { d in
                    Section {
                        ForEach(d.items) { e in row(e) }
                    } header: {
                        Text(JP.date(d.day)).font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                    }
                }
                Section {
                    Text("行をタップすると、分類を直せます（次から同じお店はその分類に）。左へ払うと消せます。うすい行は合計に入れていない記録です（カードの引き落としはカードの明細で1件ずつ数えます）")
                        .font(.caption).foregroundStyle(p.sub)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle(cycle.longTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .onAppear {
                guard !scrolled, focus != .summary else { return }
                scrolled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { proxy.scrollTo(focus, anchor: .top) }
            }
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.bold)).foregroundStyle(p.sub)
    }

    // MARK: まとめ

    private func summarySection(_ s: KakeiboSummary) -> some View {
        Section {
            line("支出", KakeiboFormat.yen(s.spent) + " 円", p.text)
            line("収入", KakeiboFormat.yen(s.income) + " 円", KakeiboStyle.color(KakeiboCategories.income))
            line("残り（収入 − 支出）", KakeiboFormat.signedYen(s.left) + " 円", s.left < 0 ? p.overdue : p.accent)
            if let d = s.daysToPayday {
                line("次の給料日", d == 0 ? "今日" : "あと\(d)日", p.text)
            } else if s.payday == nil {
                Button("給料日を決める ›", action: onSettings).foregroundStyle(p.accent).listRowBackground(p.card)
            }
        } header: {
            header("\(s.cycle.title) ・ \(s.cycle.rangeText)")
        }
    }

    private func line(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(p.text)
            Spacer()
            Text(value).font(.body.weight(.heavy)).monospacedDigit().foregroundStyle(color)
        }
        .listRowBackground(p.card)
        .accessibilityElement(children: .combine)
    }

    // MARK: 分類別（全部）

    private func categorySection(_ s: KakeiboSummary) -> some View {
        let total: Int = max(1, s.spent)
        let top: Int = max(1, s.categories.first?.amount ?? 1)
        return Section {
            line("支出の合計", KakeiboFormat.yen(s.spent) + " 円", p.text).id(KakeiboDetailFocus.categories)
            if s.categories.isEmpty {
                Text("支出はまだありません").foregroundStyle(p.sub).listRowBackground(p.card)
            }
            ForEach(s.categories, id: \.name) { c in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(KakeiboStyle.color(c.name)).frame(width: 10, height: 10)
                        Text(c.name).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                        Spacer()
                        Text("\(c.amount * 100 / total)%").font(.caption.weight(.bold)).foregroundStyle(p.sub).monospacedDigit()
                        Text("\(KakeiboFormat.yen(c.amount)) 円").font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                            .monospacedDigit()
                    }
                    GeometryReader { g in
                        Capsule().fill(KakeiboStyle.color(c.name).opacity(0.75))
                            .frame(width: max(6, g.size.width * Double(c.amount) / Double(top)))
                    }
                    .frame(height: 5)
                }
                .padding(.vertical, 2)
                .listRowBackground(p.card)
                .accessibilityElement(children: .combine)
            }
        } header: {
            header("使い道（分類は取引先から自動で決めます）")
        }
    }

    // MARK: 目標貯金

    private func goalNote(_ g: KakeiboSavings.Progress, _ now: KakeiboCycle.Period) -> String {
        if g.reached { return "目標に届きました" }
        if g.onTrack { return "\(now.title)は目標どおりです" }
        let short: Int = max(0, g.needThisCycle - g.savedThisCycle)
        return "\(now.title)は、あと \(KakeiboFormat.yen(short)) 円残すと目標どおりです"
    }

    @ViewBuilder private var goalSection: some View {
        if let goal = store.settings.savingsGoal, let g = store.savingsProgress {
            let now: KakeiboCycle.Period = store.cycle(offset: 0)
            Section {
                line("目標", KakeiboGoalText.title(goal), p.text).id(KakeiboDetailFocus.goal)
                line("これまでに残せた額", KakeiboFormat.signedYen(g.saved) + " 円", p.text)
                line("目標まであと", KakeiboFormat.yen(g.remaining) + " 円", p.text)
                line("期限まで（今の周期を含む）", "\(g.monthsLeft)か月", p.text)
                line("月あたり必要な額", KakeiboFormat.yen(g.perMonth) + " 円", p.accent)
                line("\(now.title)に残せた額", KakeiboFormat.signedYen(g.savedThisCycle) + " 円",
                     g.onTrack ? p.accent : p.overdue)
                Text(goalNote(g, now))
                    .font(.footnote.weight(.bold)).foregroundStyle(g.onTrack ? p.accent : p.overdue)
                    .listRowBackground(p.card)
                Button("目標を変える ›", action: onSettings).foregroundStyle(p.accent).listRowBackground(p.card)
            } header: {
                header("目標貯金")
            } footer: {
                Text("給料日から次の給料日の前の日までを1か月として、「収入 − 支出」を積み上げます。必要な額は、前の周期までに残せた分から決めます")
                    .font(.caption).foregroundStyle(p.sub)
            }
        } else {
            Section {
                Button("目標貯金を決める ›", action: onSettings).foregroundStyle(p.accent).listRowBackground(p.card)
                    .id(KakeiboDetailFocus.goal)
            } header: {
                header("目標貯金")
            }
        }
    }

    // MARK: 記録の行

    private func row(_ e: KakeiboEntry) -> some View {
        Button { onEdit(e) } label: { KakeiboEntryRow(entry: e) }
            .buttonStyle(.plain)
            .listRowBackground(p.card)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { store.delete([e.id]) } label: { Label("消す", systemImage: "trash") }
            }
    }
}
