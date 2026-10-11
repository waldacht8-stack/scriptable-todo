import Foundation
import WidgetKit

// 家計簿のデータ（アプリ・ウィジェット・ショートカットの App Intent が同じファイルを読み書きする）。
// ファイルは App Group の共有フォルダに kakeibo-entries.json / kakeibo-settings.json として置く。
// 書き込みは SharedStore.url へ直接（SharedStore.save は使わない）。

// MARK: - 記録

enum KakeiboKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var name: String { self == .expense ? "支出" : "収入" }
}

/// 記録の出どころ
enum KakeiboSource: String, Codable, CaseIterable {
    case bankCSV, bankPDF, cardCSV, cardPDF, applePay, manual

    var isCard: Bool { self == .cardCSV || self == .cardPDF }
    var isBank: Bool { self == .bankCSV || self == .bankPDF }
    var isFile: Bool { isCard || isBank }
}

/// 明細を出した銀行・カード会社
enum KakeiboInstitution: String, Codable, CaseIterable, Identifiable {
    case juroku, jcb, mufg, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .juroku: "十六銀行"
        case .jcb: "JCB"
        case .mufg: "MUFG"
        case .other: "その他"
        }
    }

    /// カード会社か（銀行でなければカード）
    var isCard: Bool { self == .jcb }
}

struct KakeiboEntry: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: Date
    var amount: Int                     // 円。常に 0 以上（支出か収入かは kind）
    var kind: KakeiboKind = .expense
    var category: String
    var memo: String                    // お店・摘要・メモ
    var source: KakeiboSource
    var institution: String? = nil      // KakeiboInstitution.rawValue（明細から取り込んだとき）
    var card: String? = nil             // Apple Pay のカード名
    var dedupeKey: String
    var batch: String? = nil            // 取り込みの単位（「今回の取り込みを取り消す」に使う）
    var excluded: Bool? = nil           // 合計に入れない（カードの明細と重なる銀行の引落など）
    var needsAmount: Bool? = nil        // 金額が届かなかった（Apple Pay の iD・QUICPay など）
    var isTest: Bool? = nil             // 「テストで1件送る」で入れた1件
    var createdAt: Date = .now

    var signed: Int { kind == .expense ? -amount : amount }
    var isExcluded: Bool { excluded ?? false }
    var isPending: Bool { needsAmount ?? false }
    var counts: Bool { !isExcluded && !isPending }

    var institutionValue: KakeiboInstitution? { institution.flatMap(KakeiboInstitution.init(rawValue:)) }

    /// 一覧の小さな札に出す名前（十六銀行 / JCB / MUFG / Apple Pay / 手入力）
    var sourceTag: String {
        switch source {
        case .applePay: return "Apple Pay"
        case .manual: return "手入力"
        default:
            let name = institutionValue?.name ?? "明細"
            return institutionValue == .other ? "明細" : name
        }
    }
}

// MARK: - 設定（分類・予算・分類の決まり・列の対応）

/// 分類の決まり：摘要やお店の名前に keyword が入っていれば category にする
struct KakeiboRule: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var keyword: String
    var category: String
    var learned: Bool = false           // 確認画面で直した内容から覚えたもの

    static let defaults: [KakeiboRule] = {
        let table: [(String, [String])] = [
            ("食費", ["スーパー", "コンビニ", "セブン", "ローソン", "ファミリーマート", "ファミマ", "イオン", "バロー", "ベーカリー", "弁当", "マクドナルド", "スターバックス", "食堂", "レストラン", "カフェ"]),
            ("日用品", ["ドラッグ", "薬局", "ダイソー", "セリア", "無印", "ホームセンター", "カインズ", "ニトリ"]),
            ("交通", ["JR", "鉄道", "名鉄", "バス", "タクシー", "SUICA", "PASMO", "TOICA", "MANACA", "ENEOS", "出光", "ガソリン", "駐車", "高速"]),
            ("サブスク", ["NETFLIX", "SPOTIFY", "APPLE.COM", "APPLE COM", "YOUTUBE", "PRIME", "DISNEY", "ICLOUD", "U-NEXT"]),
            ("ゲーム", ["STEAM", "NINTENDO", "任天堂", "PLAYSTATION", "ゲーム"]),
            ("娯楽", ["映画", "シネマ", "カラオケ", "書店", "本屋", "チケット"]),
            ("住まい", ["家賃", "管理費", "不動産"]),
            ("光熱", ["電気", "電力", "ガス", "水道", "デンキ", "スイドウ"]),
            ("通信", ["携帯", "ドコモ", "DOCOMO", "SOFTBANK", "ソフトバンク", "楽天モバイル", "KDDI", "NTT", "プロバイダ"]),
            ("医療", ["病院", "クリニック", "医院", "歯科", "調剤"]),
            ("服", ["ユニクロ", "UNIQLO", "しまむら", "ZARA", "靴"]),
            ("交際", ["プレゼント", "居酒屋", "ギフト"]),
            ("収入", ["給与", "給料", "賞与", "利息", "キュウヨ"]),
        ]
        return table.flatMap { cat, words in words.map { KakeiboRule(keyword: $0, category: cat) } }
    }()
}

/// CSV の列の対応（見出しの名前で覚える。列の順序に頼らない）
struct KakeiboColumnMapping: Codable, Hashable {
    var date: String? = nil
    var amount: String? = nil           // 1列の金額（符号つき、またはカードの利用金額）
    var withdrawal: String? = nil       // 出金・お引出し
    var deposit: String? = nil          // 入金・お預入れ
    var text: String? = nil             // 摘要・内容・ご利用店名
    var balance: String? = nil          // 残高（検算だけに使う）

    var isUsable: Bool { date != nil && (amount != nil || withdrawal != nil || deposit != nil) }

    /// この対応に必要な見出しがすべて揃っているか
    func fits(_ headers: [String]) -> Bool {
        let need = [date, amount, withdrawal, deposit, text, balance].compactMap { $0 }
        return isUsable && need.allSatisfy { headers.contains($0) }
    }
}

struct KakeiboSettings: Codable {
    static let defaultCategories = ["食費", "日用品", "交通", "娯楽", "ゲーム", "サブスク", "住まい", "光熱", "通信", "医療", "服", "交際", "その他", "収入"]

    var categories: [String] = KakeiboSettings.defaultCategories
    var budget: Int = 50_000            // 1か月の予算（円）
    var rules: [KakeiboRule] = KakeiboRule.defaults
    var mappings: [String: KakeiboColumnMapping] = [:]   // 銀行・カードごとの列の対応
    var excludeTransfers: Bool = true   // カード引落・振替を入れない
    var applePayTested: Bool = false    // テストの1件が届いたことがある

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KakeiboSettings()
        categories = (try? c.decodeIfPresent([String].self, forKey: .categories)) ?? d.categories
        budget = (try? c.decodeIfPresent(Int.self, forKey: .budget)) ?? d.budget
        rules = (try? c.decodeIfPresent([KakeiboRule].self, forKey: .rules)) ?? d.rules
        mappings = (try? c.decodeIfPresent([String: KakeiboColumnMapping].self, forKey: .mappings)) ?? d.mappings
        excludeTransfers = (try? c.decodeIfPresent(Bool.self, forKey: .excludeTransfers)) ?? d.excludeTransfers
        applePayTested = (try? c.decodeIfPresent(Bool.self, forKey: .applePayTested)) ?? d.applePayTested
    }

    enum CodingKeys: String, CodingKey {
        case categories, budget, rules, mappings, excludeTransfers, applePayTested
    }
}

// MARK: - 読み書き

enum KakeiboData {
    static let entriesFile = "kakeibo-entries.json"
    static let settingsFile = "kakeibo-settings.json"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: SharedStore.url(name)) else { return nil }
        return try? JSONDecoder.iso.decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: SharedStore.url(name), options: .atomic)
    }

    static func entries() -> [KakeiboEntry] { read([KakeiboEntry].self, entriesFile) ?? [] }

    static func saveEntries(_ list: [KakeiboEntry]) {
        write(list.sorted { $0.date > $1.date }, entriesFile)
        writeSummary(entries: list, budget: settings().budget)
    }

    static func settings() -> KakeiboSettings { read(KakeiboSettings.self, settingsFile) ?? KakeiboSettings() }

    static func saveSettings(_ s: KakeiboSettings) {
        write(s, settingsFile)
        writeSummary(entries: entries(), budget: s.budget)
    }

    /// ウィジェット用の今月のまとめ（kakeibo-summary.json）を書き、ウィジェットを更新する
    static func writeSummary(entries list: [KakeiboEntry], budget: Int, now: Date = .now) {
        write(KakeiboSummary.make(entries: list, budget: budget, month: now, now: now), KakeiboSummary.file)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 読んで、変えて、書く（アプリとショートカットが同時に書いても、直前の中身から変える）
    @discardableResult
    static func update<R>(_ change: (inout [KakeiboEntry]) -> R) -> R {
        var list = entries()
        let r = change(&list)
        saveEntries(list)
        return r
    }
}

// MARK: - 文字の比べ方・分類・重複

enum KakeiboText {
    /// 比べるための形：全角英数・半角カナをそろえ、ひらがなはカタカナに、大文字に、空白や記号・長音を取る
    static func normalize(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping
        let kata = nfkc.applyingTransform(.hiraganaToKatakana, reverse: false) ?? nfkc
        let drop: Set<Character> = [" ", "　", "-", "ー", "‐", "−", "・", ".", ",", "(", ")", "（", "）", "/", "*", "＊", "_", "'", "\""]
        return String(kata.uppercased().filter { !drop.contains($0) })
    }

    /// だいたい同じ文字か（片方が空、どちらかがどちらかを含む、先頭4文字が同じ）
    static func similar(_ a: String, _ b: String) -> Bool {
        let x = normalize(a), y = normalize(b)
        if x.isEmpty || y.isEmpty { return true }
        if x.contains(y) || y.contains(x) { return true }
        let n = min(4, min(x.count, y.count))
        return x.prefix(n) == y.prefix(n)
    }

    private static func containsAny(_ s: String, _ words: [String]) -> Bool {
        let n = normalize(s)
        return words.contains { n.contains(normalize($0)) }
    }

    /// カードの引落・口座の振替らしい行（2回数えないため既定で入れない）
    static func isTransferLike(_ s: String) -> Bool {
        containsAny(s, ["振替", "フリカエ", "引落", "ヒキオトシ", "カード", "クレジット", "JCB", "ジェーシービー", "ジエーシービー", "UFJニコス", "セゾン"])
    }

    /// JCB の引落らしい行（JCB の明細を取り込むと、銀行側のこの行は合計から外す）
    static func isJCBWithdrawal(_ s: String) -> Bool {
        containsAny(s, ["JCB", "ジェーシービー", "ジエーシービー"])
    }

    /// 決まりの言葉にする（確認画面で分類を直したときに覚える）。数字や記号を除いた先頭 12 文字
    static func ruleKeyword(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = nfkc.split(whereSeparator: { $0 == " " || $0 == "　" }).first.map(String.init) ?? nfkc
        let base = first.count >= 2 ? first : nfkc
        return String(base.prefix(12))
    }
}

enum KakeiboRules {
    /// 摘要・お店の名前から分類の候補を決める（覚えた決まりが先、収入は「収入」）
    static func suggest(_ text: String, kind: KakeiboKind, settings: KakeiboSettings) -> String {
        let n = KakeiboText.normalize(text)
        let ordered = settings.rules.filter(\.learned) + settings.rules.filter { !$0.learned }
        if !n.isEmpty {
            for r in ordered {
                let k = KakeiboText.normalize(r.keyword)
                guard !k.isEmpty, n.contains(k) else { continue }
                if kind == .income && r.category != "収入" { continue }
                if kind == .expense && r.category == "収入" { continue }
                if settings.categories.contains(r.category) { return r.category }
            }
        }
        if kind == .income { return settings.categories.contains("収入") ? "収入" : (settings.categories.last ?? "収入") }
        return settings.categories.contains("その他") ? "その他" : (settings.categories.first ?? "その他")
    }

    /// 直した分類を覚える（同じ言葉の決まりがあれば上書き、なければ先頭に足す）
    static func learn(_ text: String, category: String, into s: inout KakeiboSettings) {
        let key = KakeiboText.ruleKeyword(text)
        guard KakeiboText.normalize(key).count >= 2 else { return }
        if let i = s.rules.firstIndex(where: { KakeiboText.normalize($0.keyword) == KakeiboText.normalize(key) }) {
            s.rules[i].category = category
            s.rules[i].learned = true
            let r = s.rules.remove(at: i)
            s.rules.insert(r, at: 0)
        } else {
            s.rules.insert(KakeiboRule(keyword: key, category: category, learned: true), at: 0)
        }
    }
}

enum KakeiboDedupe {
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 重複を見分ける鍵：日付＋支出/収入＋金額＋文字の先頭
    static func key(date: Date, amount: Int, kind: KakeiboKind, text: String) -> String {
        "\(dayFormat.string(from: date))|\(kind == .expense ? "e" : "i")|\(amount)|\(KakeiboText.normalize(text).prefix(12))"
    }

    /// すでにある記録と重なるか：同じ日（Apple Pay とは前後1日）・同じ金額・似た文字
    static func isDuplicate(date: Date, amount: Int, kind: KakeiboKind, text: String, in list: [KakeiboEntry], fromFile: Bool = true) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return list.contains { e in
            guard e.amount == amount, e.kind == kind, e.isTest != true else { return false }
            let other = cal.startOfDay(for: e.date)
            let gap = abs(cal.dateComponents([.day], from: day, to: other).day ?? 99)
            let allowed = (fromFile && e.source == .applePay) ? 1 : 0
            guard gap <= allowed else { return false }
            return KakeiboText.similar(text, e.memo)
        }
    }
}

// MARK: - 月

enum KakeiboMonth {
    static func start(_ d: Date, offset: Int = 0) -> Date {
        let cal = Calendar.current
        let s = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
        return cal.date(byAdding: .month, value: offset, to: s) ?? s
    }

    static func contains(_ month: Date, _ d: Date) -> Bool {
        Calendar.current.isDate(d, equalTo: month, toGranularity: .month)
    }
}

// MARK: - ウィジェット向けの読み出し用（今月の支出・予算・残り）

/// 家計簿の今月のまとめ。ウィジェットは共有フォルダの kakeibo-summary.json を読むだけにする。
/// ファイルの形（名前は固定）：
/// { "month": "2026-10", "spent": 12345, "budget": 50000, "remaining": 37655,
///   "topCategories": [ { "name": "食費", "amount": 4938 }, … 最大3つ ] }
/// budget・remaining は予算なし（0）のとき null。アプリの中だけで使う項目（収入・残り日数など）はファイルに書かない
struct KakeiboSummary: Codable, Hashable {
    static let file = "kakeibo-summary.json"

    var month: Date             // 月の初日
    var spent: Int              // その月の支出（円、プラス）
    var income: Int = 0         // その月の収入（円。ファイルには書かない）
    var budget: Int             // 1か月の予算（円。0 は予算なし）
    var daysLeft: Int = 0       // 月末まであと何日（今日を含む。ファイルには書かない）
    var pendingCount: Int = 0   // 金額の入力待ち（ファイルには書かない）
    var topCategories: [Slice]  // 支出の多い分類（多い順、最大3つ）

    struct Slice: Codable, Hashable {
        var name: String
        var amount: Int
    }

    var remaining: Int { budget - spent }
    /// 予算に対して使った割合（0〜1。予算なしは 0）
    var progress: Double { budget > 0 ? min(1, Double(spent) / Double(budget)) : 0 }
    var isOver: Bool { budget > 0 && spent > budget }

    init(month: Date, spent: Int, income: Int = 0, budget: Int, daysLeft: Int = 0, pendingCount: Int = 0, topCategories: [Slice]) {
        self.month = month
        self.spent = spent
        self.income = income
        self.budget = budget
        self.daysLeft = daysLeft
        self.pendingCount = pendingCount
        self.topCategories = topCategories
    }

    // MARK: ファイルの形（yyyy-MM の月、予算なしは null）

    enum CodingKeys: String, CodingKey {
        case month, spent, budget, remaining, topCategories
    }

    private static let monthFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.monthFormat.string(from: month), forKey: .month)
        try c.encode(spent, forKey: .spent)
        let b: Int? = budget > 0 ? budget : nil
        try c.encode(b, forKey: .budget)
        let r: Int? = budget > 0 ? remaining : nil
        try c.encode(r, forKey: .remaining)
        try c.encode(Array(topCategories.prefix(3)), forKey: .topCategories)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let m = try c.decode(String.self, forKey: .month)
        month = Self.monthFormat.date(from: m) ?? KakeiboMonth.start(.now)
        spent = try c.decode(Int.self, forKey: .spent)
        budget = try c.decodeIfPresent(Int.self, forKey: .budget) ?? 0
        topCategories = try c.decodeIfPresent([Slice].self, forKey: .topCategories) ?? []
    }

    /// 共有フォルダのファイルから今月のまとめを作る（アプリ用。ウィジェットは read() で書かれたものを読む）
    static func current(now: Date = .now) -> KakeiboSummary {
        make(entries: KakeiboData.entries(), budget: KakeiboData.settings().budget, month: now, now: now)
    }

    /// kakeibo-summary.json を読む（なければ nil）
    static func read() -> KakeiboSummary? {
        guard let data = try? Data(contentsOf: SharedStore.url(file)) else { return nil }
        return try? JSONDecoder().decode(KakeiboSummary.self, from: data)
    }

    static func make(entries: [KakeiboEntry], budget: Int, month: Date, now: Date = .now) -> KakeiboSummary {
        let m = KakeiboMonth.start(month)
        let inMonth = entries.filter { KakeiboMonth.contains(m, $0.date) && $0.isTest != true }
        let counted = inMonth.filter(\.counts)
        let spent = counted.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let income = counted.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        var byCat: [String: Int] = [:]
        for e in counted where e.kind == .expense { byCat[e.category, default: 0] += e.amount }
        let top: [Slice] = byCat.sorted { $0.value > $1.value }.prefix(3).map { Slice(name: $0.key, amount: $0.value) }
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: m)?.count ?? 30
        let left: Int
        if KakeiboMonth.contains(m, now) {
            left = days - cal.component(.day, from: now) + 1
        } else {
            left = now < m ? days : 0
        }
        return KakeiboSummary(month: m, spent: spent, income: income, budget: budget, daysLeft: left,
                              pendingCount: inMonth.filter(\.isPending).count, topCategories: top)
    }

    static let placeholder = KakeiboSummary(month: KakeiboMonth.start(.now), spent: 12_345, budget: 50_000, daysLeft: 20,
                                            topCategories: [Slice(name: "食費", amount: 4_938), Slice(name: "日用品", amount: 3_086)])
}

extension Notification.Name {
    /// 家計簿の記録が変わった（同じアプリの中でショートカットから記録したときなど）
    static let kakeiboDataChanged = Notification.Name("kakeiboDataChanged")
}

/// 金額・日付の表示
enum KakeiboFormat {
    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    /// 12,345
    static func yen(_ v: Int) -> String { number.string(from: NSNumber(value: v)) ?? "\(v)" }
}
