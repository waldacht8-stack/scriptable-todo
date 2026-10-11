import SwiftUI
import WidgetKit

/// 家計簿の画面が使う記録と設定。書き込むたびに共有フォルダのファイルから読み直す（ショートカットが同時に書いても失わない）
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

    func save(_ e: KakeiboEntry, learnFrom old: KakeiboEntry? = nil) {
        var e = e
        e.dedupeKey = KakeiboDedupe.key(date: e.date, amount: e.amount, kind: e.kind, text: e.memo)
        if e.amount > 0 { e.needsAmount = nil }
        KakeiboData.update { list in
            if let i = list.firstIndex(where: { $0.id == e.id }) { list[i] = e } else { list.insert(e, at: 0) }
        }
        if let old, old.category != e.category, !e.memo.isEmpty, e.source != .manual {
            learn(e.memo, category: e.category)
        }
        reload()
    }

    func delete(_ ids: Set<String>) {
        KakeiboData.update { $0.removeAll { ids.contains($0.id) } }
        reload()
    }

    func deleteTests() {
        KakeiboData.update { $0.removeAll { $0.isTest == true } }
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

    func suggest(_ text: String, kind: KakeiboKind) -> String {
        KakeiboRules.suggest(text, kind: kind, settings: settings)
    }

    // MARK: 月

    func entries(in month: Date) -> [KakeiboEntry] {
        entries.filter { KakeiboMonth.contains(month, $0.date) }
    }

    func summary(_ month: Date) -> KakeiboSummary {
        KakeiboSummary.make(entries: entries, budget: settings.budget, month: month)
    }

    /// 手入力のシートの「最近の記録をもう一度」（同じ内容は1つに）
    var recentTemplates: [KakeiboEntry] {
        var seen = Set<String>()
        var out: [KakeiboEntry] = []
        for e in entries where e.kind == .expense && e.amount > 0 && e.isTest != true {
            let key = "\(e.memo)|\(e.amount)"
            if seen.insert(key).inserted { out.append(e) }
            if out.count >= 6 { break }
        }
        return out
    }

    // MARK: 取り込み

    /// 読み取った行に、分類の候補・重複・入れない行の印を付ける
    func prepare(_ rows: [KakeiboDraft], institution: KakeiboInstitution, isCard: Bool, excludeTransfers: Bool) -> [KakeiboDraft] {
        let existing = entries
        let hasCardStatements = existing.contains { $0.source.isCard }
        var out: [KakeiboDraft] = []
        for var r in rows {
            r.category = suggest(r.text, kind: r.kind)
            r.flag = nil
            r.include = true
            if KakeiboDedupe.isDuplicate(date: r.date, amount: r.amount, kind: r.kind, text: r.text, in: existing)
                || KakeiboDedupe.isDuplicate(date: r.date, amount: r.amount, kind: r.kind, text: r.text, in: out.filter(\.include).map { self.draftEntry($0) }) {
                r.flag = .duplicate
                r.include = false
            } else if !isCard && r.kind == .expense && hasCardStatements && KakeiboText.isJCBWithdrawal(r.text) {
                r.flag = .cardOverlap
                r.include = false
            } else if !isCard && KakeiboText.isTransferLike(r.text) {
                // 切り替え（カード引落・振替を入れない）で入れるか決める
                r.flag = .transfer
                r.include = !excludeTransfers
            }
            out.append(r)
        }
        return out
    }

    private func draftEntry(_ r: KakeiboDraft) -> KakeiboEntry {
        KakeiboEntry(date: r.date, amount: r.amount, kind: r.kind, category: r.category, memo: r.text,
                     source: .manual, dedupeKey: "")
    }

    struct ImportResult: Hashable {
        var batch: String
        var added: Int
        var duplicates: Int
        var excluded: Int
        var overlapsHidden: Int     // カードの明細を入れたので、合計から外した銀行の JCB 引落
        var from: Date?
        var to: Date?
    }

    /// 確認画面の行を記録にする
    func commit(_ rows: [KakeiboDraft], institution: KakeiboInstitution, source: KakeiboSource) -> ImportResult {
        let batch = UUID().uuidString
        let take = rows.filter(\.include)
        let new: [KakeiboEntry] = take.map { r in
            KakeiboEntry(date: r.date, amount: r.amount, kind: r.kind, category: r.category, memo: r.text,
                         source: source, institution: institution.rawValue,
                         dedupeKey: KakeiboDedupe.key(date: r.date, amount: r.amount, kind: r.kind, text: r.text),
                         batch: batch)
        }
        // JCB の明細を入れたら、銀行側の JCB の引落は合計から外す（2回数えない）
        let hidden: Int = KakeiboData.update { list in
            var n = 0
            if source.isCard && institution == .jcb {
                for i in list.indices where list[i].source.isBank && list[i].kind == .expense
                    && !list[i].isExcluded && KakeiboText.isJCBWithdrawal(list[i].memo) {
                    list[i].excluded = true
                    n += 1
                }
            }
            list.insert(contentsOf: new, at: 0)
            return n
        }
        reload()
        let dates = rows.map(\.date)
        return ImportResult(batch: batch, added: new.count,
                            duplicates: rows.filter { $0.flag == .duplicate }.count,
                            excluded: rows.filter { ($0.flag == .transfer || $0.flag == .cardOverlap) && !$0.include }.count,
                            overlapsHidden: hidden, from: dates.min(), to: dates.max())
    }

    func undo(batch: String) {
        KakeiboData.update { $0.removeAll { $0.batch == batch } }
        reload()
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
