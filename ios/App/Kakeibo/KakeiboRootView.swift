import SwiftUI
import Charts

/// 「家計簿」タブ：今月の支出（大きく）・予算の残り・分類の円グラフ・最近の記録・取り込みと手入力
struct KakeiboRootView: View {
    @StateObject private var store = KakeiboStore()
    @ObservedObject private var inbox = KakeiboInbox.shared
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.scenePhase) private var scene
    @State private var monthOffset = 0
    @State private var sheet: KakeiboSheet?
    @State private var path: [KakeiboRoute] = []
    @State private var showAddChoices = false

    private var month: Date { KakeiboMonth.start(.now, offset: monthOffset) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    KakeiboSpendCard(summary: store.summary(month), monthOffset: $monthOffset)
                    goalCard
                    pendingCard
                    KakeiboCategoryCard(entries: store.entries(in: month))
                    recentSection
                    KakeiboLinkRow(icon: "wave.3.right.circle.fill", title: "Apple Pay を自動で記録",
                                   detail: applePayDetail) {
                        sheet = .applePay
                    }
                    KakeiboLinkRow(icon: "slider.horizontal.3", title: "家計簿の設定", detail: settingsDetail) {
                        path.append(.settings)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            // 左右にスライドで月を切り替える（左へ＝次の月、右へ＝前の月。今月より先には行かない）
            .simultaneousGesture(monthSwipe)
            .paletteBackground(p)
            .overlay(alignment: .bottomTrailing) { addButton }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: KakeiboRoute.self) { route in
                switch route {
                case .all: KakeiboAllView(store: store, month: month) { sheet = .entry($0) }
                case .settings: KakeiboSettingsView(store: store)
                }
            }
        }
        .sheet(item: $sheet) { s in sheetContent(s) }
        .onAppear { store.reload() }
        .onChange(of: scene) { _, s in if s == .active { store.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .kakeiboDataChanged)) { _ in store.reload() }
        .onOpenURL { url in inbox.receive(url) }
        .onChange(of: inbox.pending) { _, f in
            guard let f else { return }
            inbox.pending = nil
            sheet = .importer(.file(name: f.name, data: f.data))
        }
        .task { await openForScreenshot() }
    }

    private var applePayDetail: String {
        store.settings.applePayTested ? "テストの1件が届いています" : "払うたびにショートカットが日和へ送ります"
    }

    private var settingsDetail: String {
        let s = store.settings
        return "予算 \(KakeiboFormat.yen(s.budget)) 円 ・ 分類 \(s.categories.count) ・ 決まり \(s.rules.count)"
    }

    // MARK: 見出し

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(KakeiboStyle.monthTitle(month)).font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
                Text("家計簿").font(.largeTitle.weight(.heavy)).foregroundStyle(p.text)
            }
            Spacer(minLength: 4)
            Button { sheet = .importer(.fresh) } label: { importLabel }
                .buttonStyle(.plain)
            SettingsButton()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private var importLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.and.arrow.down")
            Text("明細を取り込む")
        }
        .font(.subheadline.weight(.heavy))
        .foregroundStyle(p.accent)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(Capsule().strokeBorder(p.accent, lineWidth: 1.5))
        .contentShape(Capsule())
    }

    // MARK: 月の切り替え（スライド）

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                let dx: CGFloat = v.translation.width
                let dy: CGFloat = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                if dx < 0 {
                    guard monthOffset < 0 else { return }
                    withAnimation(motion.change) { monthOffset += 1 }
                } else {
                    withAnimation(motion.change) { monthOffset -= 1 }
                }
            }
    }

    // MARK: 目標貯金

    @ViewBuilder private var goalCard: some View {
        if let goal = store.settings.savingsGoal, let g = store.savingsProgress {
            Button { path.append(.settings) } label: { KakeiboGoalCard(goal: goal, progress: g) }
                .buttonStyle(.plain)
        } else {
            KakeiboLinkRow(icon: "flag.checkered", title: "目標貯金を決める",
                           detail: "「来年3月までに50万円」のように、総額と期限で決めます") {
                path.append(.settings)
            }
        }
    }

    // MARK: 金額の入力待ち（Apple Pay で金額が届かなかった）

    @ViewBuilder private var pendingCard: some View {
        let pending: [KakeiboEntry] = store.entries.filter(\.isPending)
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("金額の入力待ち \(pending.count)件", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.heavy)).foregroundStyle(p.overdue)
                ForEach(pending.prefix(3)) { e in
                    // 右下の ＋ ボタンに「金額を入力」が隠れないよう、右を空ける
                    Button { sheet = .entry(e) } label: { KakeiboEntryRow(entry: e).padding(.trailing, 52) }.buttonStyle(.plain)
                }
            }
            .paletteCard(p, padding: 14)
        }
    }

    // MARK: 最近の記録

    private var recentSection: some View {
        let recent: [KakeiboEntry] = Array(store.entries(in: month).filter { !$0.isPending }.prefix(5))
        let title: String = monthOffset == 0 ? "最近の記録" : "\(Calendar.current.component(.month, from: month))月の記録"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline.weight(.heavy)).foregroundStyle(p.text)
                Spacer()
                Button("すべて見る ›") { path.append(.all) }
                    .font(.footnote.weight(.bold)).foregroundStyle(p.accent)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            KakeiboRecentList(entries: recent) { sheet = .entry($0) }
                .paletteCard(p, padding: 14)
                .animation(motion.change, value: recent.map(\.id))
        }
    }

    private var addButton: some View {
        Button { showAddChoices = true } label: {
            Image(systemName: "plus").font(.title2.weight(.heavy)).foregroundStyle(p.onAccent)
                .frame(width: 60, height: 60)
                .background(p.accent, in: Circle())
                .shadow(color: p.accent.opacity(0.35), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("記録する・明細を取り込む")
        .confirmationDialog("記録のしかた", isPresented: $showAddChoices, titleVisibility: .visible) {
            Button("手入力で記録") { sheet = .entry(nil) }
            Button("明細を取り込む") { sheet = .importer(.fresh) }
            Button("Apple Pay の自動記録") { sheet = .applePay }
            Button("やめる", role: .cancel) {}
        }
    }

    // MARK: シート

    @ViewBuilder private func sheetContent(_ s: KakeiboSheet) -> some View {
        switch s {
        case .entry(let e):
            KakeiboEntrySheet(store: store, editing: e)
                .environment(\.palette, p)
                .environment(\.motion, motion)
        case .importer(let start):
            KakeiboImportView(store: store, start: start, onManual: openManualAfterImport)
                .environment(\.palette, p)
                .environment(\.motion, motion)
        case .applePay:
            KakeiboApplePayGuide(store: store, startPage: KakeiboLaunch.applePayPage)
                .environment(\.palette, p)
                .environment(\.motion, motion)
        }
    }

    private func openManualAfterImport() {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sheet = .entry(nil) }
    }

    /// 画面写真用の起動引数：-kakeiboentry / -kakeiboimport [source|pick|mapping|preview|done|help] / -kakeiboapplepay [1|2|3] / -kakeiboall / -kakeibosettings
    private func openForScreenshot() async {
        guard let target = KakeiboLaunch.target else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        switch target {
        case .entry: sheet = .entry(nil)
        case .addMenu: showAddChoices = true
        case .importer(let step): sheet = .importer(.demo(step))
        case .applePay: sheet = .applePay
        case .all: path = [.all]
        case .settings: path = [.settings]
        }
    }
}

enum KakeiboRoute: Hashable {
    case all, settings
}

enum KakeiboSheet: Identifiable {
    case entry(KakeiboEntry?)
    case importer(KakeiboImportStart)
    case applePay

    var id: String {
        switch self {
        case .entry(let e): return "entry-\(e?.id ?? "new")"
        case .importer: return "import"
        case .applePay: return "applepay"
        }
    }
}

/// 起動引数（画面写真用）
enum KakeiboLaunch {
    enum Target { case entry, addMenu, importer(String), applePay, all, settings }

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, !args[i + 1].hasPrefix("-") else { return nil }
        return args[i + 1]
    }

    static var target: Target? {
        if args.contains("-kakeiboentry") { return .entry }
        if args.contains("-kakeiboadd") { return .addMenu }
        if args.contains("-kakeiboimport") { return .importer(value(after: "-kakeiboimport") ?? "source") }
        if args.contains("-kakeiboapplepay") { return .applePay }
        if args.contains("-kakeiboall") { return .all }
        if args.contains("-kakeibosettings") { return .settings }
        return nil
    }

    static var applePayPage: Int {
        guard let v = value(after: "-kakeiboapplepay"), let n = Int(v) else { return 0 }
        return max(0, min(2, n - 1))
    }
}

// MARK: - 今月の支出

struct KakeiboSpendCard: View {
    let summary: KakeiboSummary
    @Binding var monthOffset: Int
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion

    var body: some View {
        let month: Int = Calendar.current.component(.month, from: summary.month)
        let title: String = monthOffset == 0 ? "今月の支出" : "\(month)月の支出"
        let atLatest: Bool = monthOffset >= 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                Spacer()
                monthButton("chevron.left", label: "前の月") { monthOffset -= 1 }
                Text("\(month)月").font(.subheadline.weight(.bold)).foregroundStyle(p.text).frame(minWidth: 40)
                monthButton("chevron.right", label: "次の月") { monthOffset += 1 }
                    .disabled(atLatest)
                    .opacity(atLatest ? 0.35 : 1)
            }
            KakeiboBigYen(value: summary.spent)
                .animation(motion.change, value: summary.spent)
            KakeiboBudgetBar(summary: summary)
            if summary.income > 0 {
                Text("収入 \(KakeiboFormat.yen(summary.income)) 円").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p, padding: 16)
    }

    private func monthButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion.change) { action() } } label: {
            Image(systemName: icon).font(.footnote.weight(.heavy)).foregroundStyle(p.text)
                .frame(width: 36, height: 36)
                .background(p.sub.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 分類別（円グラフ）

struct KakeiboCategoryCard: View {
    let entries: [KakeiboEntry]
    @Environment(\.palette) private var p

    struct Slice: Identifiable {
        var id: String { category }
        let category: String
        let amount: Int
        let color: Color
    }

    private var slices: [Slice] {
        var by: [String: Int] = [:]
        for e in entries where e.counts && e.kind == .expense && e.isTest != true {
            by[e.category, default: 0] += e.amount
        }
        let sorted = by.sorted { $0.value > $1.value }
        var out: [Slice] = sorted.prefix(4).map { Slice(category: $0.key, amount: $0.value, color: KakeiboStyle.color($0.key)) }
        let rest: Int = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
        if rest > 0 { out.append(Slice(category: "ほか", amount: rest, color: p.sub.opacity(0.45))) }
        return out
    }

    var body: some View {
        let list = slices
        let total: Int = list.reduce(0) { $0 + $1.amount }
        HStack(spacing: 16) {
            donut(list)
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(list, total))
            VStack(alignment: .leading, spacing: 6) {
                if list.isEmpty {
                    Text("この月の支出はまだありません").font(.subheadline).foregroundStyle(p.sub)
                }
                ForEach(list) { s in legendRow(s) }
                    .padding(.trailing, 44)   // 右下の＋ボタンに金額が隠れないように
            }
        }
        .paletteCard(p, padding: 14)
    }

    @ViewBuilder private func donut(_ list: [Slice]) -> some View {
        if list.isEmpty {
            Circle().stroke(p.accent.opacity(0.15), lineWidth: 16).padding(8)
        } else {
            Chart(list) { s in
                SectorMark(angle: .value("金額", s.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(s.color)
                    .cornerRadius(3)
            }
            .chartLegend(.hidden)
        }
    }

    private func legendRow(_ s: Slice) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 10, height: 10)
            Text(s.category).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
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

// MARK: - 最近の記録の一覧

struct KakeiboRecentList: View {
    let entries: [KakeiboEntry]
    let onTap: (KakeiboEntry) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text("まだ記録がありません。右下の ＋ か「明細を取り込む」から始めましょう")
                    .font(.subheadline).foregroundStyle(p.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                Button { onTap(e) } label: { KakeiboEntryRow(entry: e) }.buttonStyle(.plain)
                if i < entries.count - 1 { Divider().overlay(p.sub.opacity(0.2)) }
            }
        }
    }
}

// MARK: - 1件の行

struct KakeiboEntryRow: View {
    let entry: KakeiboEntry
    @Environment(\.palette) private var p

    var body: some View {
        let title: String = entry.memo.isEmpty ? entry.category : entry.memo
        let meta: String = "\(entry.category) ・ \(KakeiboStyle.dayLabel(entry.date))"
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                HStack(spacing: 6) {
                    KakeiboSourceTag(entry: entry)
                    if entry.isTest == true { testTag }
                    Text(meta).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            amountText
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .opacity(entry.isExcluded ? 0.5 : 1)
    }

    private var testTag: some View {
        Text("テスト").font(.caption2.weight(.bold)).foregroundStyle(p.onAccent)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(p.accent, in: Capsule())
    }

    @ViewBuilder private var amountText: some View {
        if entry.isPending {
            Text("金額を入れる ›").font(.footnote.weight(.heavy)).foregroundStyle(p.overdue)
        } else {
            let sign: String = entry.kind == .expense ? "−" : "+"
            let color: Color = entry.kind == .income ? KakeiboStyle.color("収入") : p.text
            Text("\(sign)\(KakeiboFormat.yen(entry.amount))")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(color)
                .strikethrough(entry.isExcluded)
                .monospacedDigit()
        }
    }
}

/// 下の方の入口の行（Apple Pay・設定）
struct KakeiboLinkRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(p.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                    Text(detail).font(.caption).foregroundStyle(p.sub).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(p.sub)
            }
            .contentShape(Rectangle())
            .paletteCard(p, padding: 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - すべての記録（月ごと）

struct KakeiboAllView: View {
    @ObservedObject var store: KakeiboStore
    let month: Date
    let onEdit: (KakeiboEntry) -> Void
    @Environment(\.palette) private var p

    private struct Day: Identifiable {
        var id: Date { day }
        let day: Date
        let items: [KakeiboEntry]
    }

    private var days: [Day] {
        let cal = Calendar.current
        let groups: [Date: [KakeiboEntry]] = Dictionary(grouping: store.entries(in: month)) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { Day(day: $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if days.isEmpty {
                Text("この月の記録はありません").foregroundStyle(p.sub).listRowBackground(p.card)
            }
            ForEach(days) { d in
                Section {
                    ForEach(d.items) { e in row(e) }
                } header: {
                    Text(JP.date(d.day)).font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                }
            }
            Section {
                Text("左へ払うと消せます。うすい行は、カードの明細と重なるので合計に入れていない記録です")
                    .font(.caption).foregroundStyle(p.sub)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .paletteBackground(p)
        .navigationTitle(KakeiboStyle.monthTitle(month) + "の記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func row(_ e: KakeiboEntry) -> some View {
        Button { onEdit(e) } label: { KakeiboEntryRow(entry: e) }
            .buttonStyle(.plain)
            .listRowBackground(p.card)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { store.delete([e.id]) } label: { Label("消す", systemImage: "trash") }
            }
    }
}
