import SwiftUI

/// 「家計簿」タブ：いまの周期（給料日から次の給料日の前の日まで）の支出・収入・残り、目標貯金、使い道。
/// ホームは大事な数字だけ。カードをタップすると、くわしく（分類の全部・記録の一覧・目標の中身）を開く。
/// 記録はおもに「明細を取り込む」から。現金の支払いは記録の一覧の「手で足す」から
struct KakeiboRootView: View {
    @StateObject private var store = KakeiboStore()
    @ObservedObject private var inbox = KakeiboInbox.shared
    @ObservedObject private var importLink = KakeiboImportLink.shared
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.scenePhase) private var scene
    @State private var cycleOffset = 0
    @State private var sheet: KakeiboSheet?
    @State private var path: [KakeiboRoute] = []

    private var cycle: KakeiboCycle.Period { store.cycle(offset: cycleOffset) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    let summary: KakeiboSummary = store.summary(cycle)
                    KakeiboSummaryCard(summary: summary, offset: $cycleOffset,
                                       onOpen: { open(.records) }, onSettings: { path.append(.settings) })
                    KakeiboImportStatus(dues: store.importDues) { sheet = .importer(.preset($0)) }
                    goalCard
                    KakeiboCategoryCard(summary: summary) { open(.categories) }
                    KakeiboLinkRow(icon: "list.bullet.rectangle", title: "記録を見る", detail: recordsDetail(summary)) {
                        open(.records)
                    }
                    KakeiboLinkRow(icon: "slider.horizontal.3", title: "家計簿の設定", detail: settingsDetail) {
                        path.append(.settings)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            // 左右にスライドで周期を切り替える（左へ＝次、右へ＝前。いまの周期より先には行かない）
            .simultaneousGesture(cycleSwipe)
            .paletteBackground(p)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: KakeiboRoute.self) { route in
                switch route {
                case .detail(let offset, let focus):
                    KakeiboDetailView(store: store, offset: offset, focus: focus,
                                      onEdit: { sheet = .entry($0) }, onAdd: { sheet = .entry(nil) },
                                      onSettings: { path.append(.settings) })
                case .settings: KakeiboSettingsView(store: store)
                }
            }
        }
        .sheet(item: $sheet) { s in sheetContent(s) }
        .onAppear {
            store.reload()
            openPendingImport()
        }
        .onChange(of: importLink.pending) { _, _ in openPendingImport() }
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

    /// 取り込みのお知らせ・hiyori://kakeibo?import=… で来たら、その銀行・カードの取り込みを開く
    private func openPendingImport() {
        guard let i = importLink.pending else { return }
        importLink.pending = nil
        path = []
        sheet = .importer(.preset(i))
    }

    private func open(_ focus: KakeiboDetailFocus) {
        path.append(.detail(cycleOffset, focus))
    }

    private func recordsDetail(_ s: KakeiboSummary) -> String {
        let n: Int = store.entries(in: s.cycle).count
        return "\(s.cycle.title) \(n)件 ・ 現金の支払いは一覧の「手で足す」から"
    }

    private var settingsDetail: String {
        let s = store.settings
        let pay: String = s.payday.map { $0 >= 31 ? "給料日 月末" : "給料日 \($0)日" } ?? "給料日 未設定"
        let from: String = s.employer.isEmpty ? "振り込み元 未設定" : "振り込み元 \(s.employer)"
        return "\(pay) ・ \(from)"
    }

    // MARK: 見出し

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cycle.longTitle) ・ \(cycle.rangeText)").font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
                    .lineLimit(1).minimumScaleFactor(0.8)
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

    /// いちばんの入口：明細を取り込む
    private var importLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.and.arrow.down")
            Text("明細を取り込む")
        }
        .font(.subheadline.weight(.heavy))
        .foregroundStyle(p.onAccent)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(p.accent, in: Capsule())
        .contentShape(Capsule())
    }

    // MARK: 周期の切り替え（スライド）

    private var cycleSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                let dx: CGFloat = v.translation.width
                let dy: CGFloat = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                if dx < 0 {
                    guard cycleOffset < 0 else { return }
                    withAnimation(motion.change) { cycleOffset += 1 }
                } else {
                    withAnimation(motion.change) { cycleOffset -= 1 }
                }
            }
    }

    // MARK: 目標貯金

    @ViewBuilder private var goalCard: some View {
        if let goal = store.settings.savingsGoal, let g = store.savingsProgress {
            KakeiboGoalCard(goal: goal, progress: g, cycle: store.cycle(offset: 0)) { path.append(.detail(0, .goal)) }
        } else {
            KakeiboLinkRow(icon: "flag.checkered", title: "目標貯金を決める",
                           detail: "「来年3月までに50万円」のように決めると、月にいくら残せばよいか出します") {
                path.append(.settings)
            }
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
        }
    }

    private func openManualAfterImport() {
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sheet = .entry(nil) }
    }

    /// 画面写真用の起動引数：-kakeiboentry / -kakeiboimport [source|pick|mapping|preview|done|help|jcb|mufg] /
    /// -kakeiboall / -kakeibodetail [categories|goal|records] / -kakeibosettings
    private func openForScreenshot() async {
        guard let target = KakeiboLaunch.target else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        switch target {
        case .entry: sheet = .entry(nil)
        case .importer(let step): sheet = .importer(.demo(step))
        case .detail(let focus): path = [.detail(0, focus)]
        case .settings: path = [.settings]
        }
    }
}

/// くわしくの画面で最初に見せるところ
enum KakeiboDetailFocus: String, Hashable {
    case summary, categories, goal, records
}

enum KakeiboRoute: Hashable {
    case detail(Int, KakeiboDetailFocus)
    case settings
}

enum KakeiboSheet: Identifiable {
    case entry(KakeiboEntry?)
    case importer(KakeiboImportStart)

    var id: String {
        switch self {
        case .entry(let e): return "entry-\(e?.id ?? "new")"
        case .importer: return "import"
        }
    }
}

/// 起動引数（画面写真用）
enum KakeiboLaunch {
    enum Target { case entry, importer(String), detail(KakeiboDetailFocus), settings }

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, !args[i + 1].hasPrefix("-") else { return nil }
        return args[i + 1]
    }

    static var target: Target? {
        if args.contains("-kakeiboentry") { return .entry }
        if args.contains("-kakeiboimport") { return .importer(value(after: "-kakeiboimport") ?? "source") }
        if args.contains("-kakeiboall") { return .detail(.records) }
        if args.contains("-kakeibodetail") {
            return .detail(value(after: "-kakeibodetail").flatMap(KakeiboDetailFocus.init(rawValue:)) ?? .summary)
        }
        if args.contains("-kakeibosettings") { return .settings }
        return nil
    }
}

// MARK: - 1件の行

struct KakeiboEntryRow: View {
    let entry: KakeiboEntry
    @Environment(\.palette) private var p

    var body: some View {
        let title: String = entry.memo.isEmpty ? entry.category : entry.memo
        let what: String = entry.excludeLabel ?? entry.category
        let meta: String = "\(what) ・ \(KakeiboStyle.dayLabel(entry.date))"
        HStack(spacing: 10) {
            Circle().fill(KakeiboStyle.color(entry.category).opacity(entry.isExcluded ? 0.35 : 1)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                HStack(spacing: 6) {
                    KakeiboSourceTag(entry: entry)
                    if entry.isSalary { salaryTag }
                    Text(meta).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            amountText
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .opacity(entry.isExcluded || entry.isTest == true ? 0.5 : 1)
    }

    private var salaryTag: some View {
        Text("給料").font(.caption2.weight(.bold)).foregroundStyle(p.onAccent)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(KakeiboStyle.color(KakeiboCategories.salary), in: Capsule())
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

/// 下の方の入口の行（記録・目標・設定）
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
