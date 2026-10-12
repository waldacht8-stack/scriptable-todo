import SwiftUI
import WidgetKit

/// 家計簿の画面が使う記録と設定。書き込むたびに共有フォルダのファイルから読み直す
@MainActor
final class KakeiboStore: ObservableObject {
    @Published private(set) var entries: [KakeiboEntry] = []
    @Published private(set) var settings = KakeiboSettings()

    init() {
        if ProcessInfo.processInfo.arguments.contains("-demo") { KakeiboDemo.install() }
        reload()
    }

    func reload() {
        entries = KakeiboData.entries().sorted { $0.date > $1.date }
        settings = KakeiboData.settings()
    }

    // MARK: 記録

    func add(_ e: KakeiboEntry) {
        KakeiboData.update { $0.insert(e, at: 0) }
        reload()
    }

    /// 1件を保存する。分類を直したら、その記録に手で直した印を付け、同じお店を次から同じ分類にする
    func save(_ e: KakeiboEntry, learnFrom old: KakeiboEntry? = nil) {
        var e = e
        e.dedupeKey = KakeiboDedupe.key(date: e.date, amount: e.amount, kind: e.kind, text: e.memo)
        if e.amount > 0 { e.needsAmount = nil }
        if let old, old.category != e.category {
            e.categoryFixed = true
            e.salary = e.category == KakeiboCategories.salary ? true : nil
            if !e.memo.isEmpty { learn(e.memo, category: e.category) }
        }
        KakeiboData.update { list in
            if let i = list.firstIndex(where: { $0.id == e.id }) { list[i] = e } else { list.insert(e, at: 0) }
        }
        reload()
    }

    func delete(_ ids: Set<String>) {
        KakeiboData.update { $0.removeAll { ids.contains($0.id) } }
        reload()
    }

    // MARK: 設定

    func updateSettings(_ change: (inout KakeiboSettings) -> Void) {
        var s = KakeiboData.settings()
        change(&s)
        KakeiboData.saveSettings(s)
        settings = s
        WidgetCenter.shared.reloadAllTimelines()
    }

    func learn(_ text: String, category: String) {
        updateSettings { KakeiboRules.learn(text, category: category, into: &$0) }
    }

    func classify(_ text: String, kind: KakeiboKind) -> KakeiboRules.Result {
        KakeiboRules.classify(text, kind: kind, settings: settings)
    }

    func suggest(_ text: String, kind: KakeiboKind) -> String {
        classify(text, kind: kind).category
    }

    /// 振り込み元を決めたとき：すでにある収入の記録も、会社名が合えば給料にする（手で直した記録は変えない）
    func applyEmployer() {
        let s = settings
        KakeiboData.update { list in
            for i in list.indices where list[i].kind == .income && list[i].categoryFixed != true {
                if KakeiboMerchants.isFromEmployer(list[i].memo, employer: s.employer) {
                    list[i].category = KakeiboCategories.salary
                    list[i].salary = true
                }
            }
        }
        reload()
    }

    /// 分類を直すメニューに出す分類（組みこみの分類と、覚えた・使った分類）
    func categoryChoices(for kind: KakeiboKind) -> [String] {
        var out: [String] = KakeiboCategories.list(for: kind)
        let used: [String] = settings.rules.map(\.category) + entries.filter { $0.kind == kind }.map(\.category)
        for c in used where !out.contains(c) && KakeiboCategories.isIncomeCategory(c) == (kind == .income) {
            out.append(c)
        }
        return out
    }

    // MARK: 周期（給料日から次の給料日の前の日まで）

    func cycle(offset: Int, now: Date = .now) -> KakeiboCycle.Period {
        settings.cycle(now, offset: offset)
    }

    func entries(in cycle: KakeiboCycle.Period) -> [KakeiboEntry] {
        KakeiboSummary.entries(entries, in: cycle)
    }

    func summary(_ cycle: KakeiboCycle.Period, now: Date = .now) -> KakeiboSummary {
        KakeiboSummary.make(entries: entries, cycle: cycle, payday: settings.payday, now: now)
    }

    /// 目標貯金の進み具合（決めていなければ nil）
    var savingsProgress: KakeiboSavings.Progress? {
        settings.savingsGoal.map { KakeiboSavings.progress($0, entries: entries, payday: settings.payday) }
    }

    /// 手入力のシートの「最近の記録をもう一度」（同じ内容は1つに）
    var recentTemplates: [KakeiboEntry] {
        var seen = Set<String>()
        var out: [KakeiboEntry] = []
        for e in entries where e.kind == .expense && e.amount > 0 && e.isTest != true && !e.isExcluded {
            let key = "\(e.memo)|\(e.amount)"
            if seen.insert(key).inserted { out.append(e) }
            if out.count >= 6 { break }
        }
        return out
    }

    // MARK: 取り込み

    /// 読み取った行に、分類・重複・合計に入れない行の印を付ける
    func prepare(_ rows: [KakeiboDraft], institution: KakeiboInstitution, isCard: Bool, excludeTransfers: Bool) -> [KakeiboDraft] {
        KakeiboImportRules.prepare(rows, existing: entries, settings: settings, institution: institution,
                                   isCard: isCard, excludeTransfers: excludeTransfers)
    }

    /// カードの引き落としの行があるのに、その前のカードの明細をまだ取り込んでいないか
    func missingCardStatement(_ rows: [KakeiboDraft]) -> Bool {
        KakeiboImportRules.missingCardStatement(rows, existing: entries)
    }

    struct ImportResult: Hashable {
        var batch: String
        var added: Int
        var duplicates: Int
        var excluded: Int           // 合計に入れない記録として入れた（カードの引き落とし・口座間の振替）
        var overlapsHidden: Int     // カードの明細を入れたので、合計から外した銀行の JCB 引落
        var from: Date?
        var to: Date?
    }

    /// 確認画面の行を記録にする
    func commit(_ rows: [KakeiboDraft], institution: KakeiboInstitution, source: KakeiboSource) -> ImportResult {
        let batch = UUID().uuidString
        let new: [KakeiboEntry] = KakeiboImportRules.entries(rows, institution: institution, source: source, batch: batch)
        // JCB の明細を入れたら、銀行側の JCB の引落（前の版で入れたもの）は合計から外す（2回数えない）
        let hidden: Int = KakeiboData.update { list in
            var n = 0
            if source.isCard && institution == .jcb {
                for i in list.indices where list[i].source.isBank && list[i].kind == .expense
                    && !list[i].isExcluded && list[i].excludeReason == nil && KakeiboText.isJCBWithdrawal(list[i].memo) {
                    list[i].excluded = true
                    list[i].excludeReason = .cardSettlement
                    n += 1
                }
            }
            list.insert(contentsOf: new, at: 0)
            return n
        }
        reload()
        let dates: [Date] = rows.map(\.date)
        return ImportResult(batch: batch, added: new.filter { !$0.isExcluded }.count,
                            duplicates: rows.filter { $0.flag == .duplicate && !$0.include }.count,
                            excluded: new.filter(\.isExcluded).count,
                            overlapsHidden: hidden, from: dates.min(), to: dates.max())
    }

    func undo(batch: String) {
        KakeiboData.update { $0.removeAll { $0.batch == batch } }
        reload()
    }
}

/// 取り込みの決まり（画面から切り離して確かめられるように）
enum KakeiboImportRules {
    /// 分類・給料・重複・合計に入れない行の印を付ける
    static func prepare(_ rows: [KakeiboDraft], existing: [KakeiboEntry], settings: KakeiboSettings,
                        institution: KakeiboInstitution, isCard: Bool, excludeTransfers: Bool) -> [KakeiboDraft] {
        var out: [KakeiboDraft] = []
        for var r in rows {
            let c: KakeiboRules.Result = KakeiboRules.classify(r.text, kind: r.kind, settings: settings)
            r.category = c.category
            r.salary = c.salary
            r.flag = nil
            r.include = true
            let taken: [KakeiboEntry] = out.filter(\.include).map(draftEntry)
            let dupe: Bool = KakeiboDedupe.isDuplicate(date: r.date, amount: r.amount, kind: r.kind, text: r.text,
                                                       institution: institution.rawValue, in: existing)
                || KakeiboDedupe.isDuplicate(date: r.date, amount: r.amount, kind: r.kind, text: r.text, in: taken, fromFile: false)
            if dupe {
                r.flag = .duplicate
                r.include = false
            } else if !c.salary, let reason = KakeiboRules.excludeReason(r.text, kind: r.kind, isCard: isCard) {
                let flag: KakeiboDraft.Flag = reason == .cardSettlement ? .cardSettlement : .ownTransfer
                r.flag = flag
                r.include = !excludeTransfers
            }
            out.append(r)
        }
        return out
    }

    private static func draftEntry(_ r: KakeiboDraft) -> KakeiboEntry {
        KakeiboEntry(date: r.date, amount: r.amount, kind: r.kind, category: r.category, memo: r.text,
                     source: .manual, dedupeKey: "")
    }

    /// 確認画面の行から記録を作る。入れる行はそのまま、カードの引き落とし・振替で外した行は「合計に入れない記録」として残す。
    /// 重複・手で外した行は入れない
    static func entries(_ rows: [KakeiboDraft], institution: KakeiboInstitution, source: KakeiboSource, batch: String) -> [KakeiboEntry] {
        rows.compactMap { r -> KakeiboEntry? in
            let keepExcluded: Bool = !r.include && (r.flag == .cardSettlement || r.flag == .ownTransfer)
            guard r.include || keepExcluded else { return nil }
            var e = KakeiboEntry(date: r.date, amount: r.amount, kind: r.kind, category: r.category, memo: r.text,
                                 source: source, institution: institution.rawValue,
                                 dedupeKey: KakeiboDedupe.key(date: r.date, amount: r.amount, kind: r.kind, text: r.text),
                                 batch: batch)
            if r.salary { e.salary = true }
            if keepExcluded {
                e.excluded = true
                let reason: KakeiboExcludeReason = r.flag == .cardSettlement ? .cardSettlement : .ownTransfer
                e.excludeReason = reason
            }
            return e
        }
    }

    /// カードの引き落としの行があるのに、その前 45 日のカードの明細がまだないか
    static func missingCardStatement(_ rows: [KakeiboDraft], existing: [KakeiboEntry]) -> Bool {
        let settlements: [KakeiboDraft] = rows.filter { $0.flag == .cardSettlement }
        guard !settlements.isEmpty else { return false }
        let cards: [KakeiboEntry] = existing.filter { $0.source.isCard }
        return settlements.contains { r in
            let from: Date = r.date.addingTimeInterval(-45 * 86_400)
            return !cards.contains { $0.date >= from && $0.date <= r.date }
        }
    }
}

// MARK: - 共有で受け取ったファイル（「日和」で開く・共有シートから）

/// 受け取ったファイルを家計簿の取り込みへ渡す
@MainActor
final class KakeiboInbox: ObservableObject {
    static let shared = KakeiboInbox()
    @Published var pending: KakeiboIncomingFile?
    private var lastURL: URL?
    private var lastAt = Date.distantPast

    struct KakeiboIncomingFile: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let data: Data
    }

    /// CSV か PDF なら受け取って true（同じファイルが続けて届いたときは1回だけ）
    @discardableResult
    func receive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard url.isFileURL, ["csv", "pdf", "txt"].contains(ext) else { return false }
        if url == lastURL && Date().timeIntervalSince(lastAt) < 3 { return true }
        lastURL = url
        lastAt = Date()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return false }
        pending = KakeiboIncomingFile(name: url.lastPathComponent, data: data)
        return true
    }
}

extension View {
    /// RootView に1行足すと、共有で受け取った CSV・PDF で家計簿タブを開く：`.kakeiboOpenURL { tab = 2 }`
    func kakeiboOpenURL(_ showTab: @escaping () -> Void) -> some View {
        onOpenURL { url in
            if KakeiboInbox.shared.receive(url) { showTab() }
        }
    }
}
