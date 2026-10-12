import Foundation
import WidgetKit

// 家計簿のデータ（アプリとウィジェットが同じファイルを読み書きする）。
// ファイルは App Group の共有フォルダに kakeibo-entries.json / kakeibo-settings.json として置く。
// 書き込みは SharedStore.url へ直接（SharedStore.save は使わない）。
// 「月」は給料の周期（KakeiboCycle.swift）。給料日を決めていなければ暦の月。

// MARK: - 記録

enum KakeiboKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var name: String { self == .expense ? "支出" : "収入" }
}

/// 記録の出どころ（applePay は前の版の自動記録。記録はそのまま残す）
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

/// 合計に入れない理由
enum KakeiboExcludeReason: String, Codable, Hashable {
    case cardSettlement     // 銀行の明細にあるカードの引き落とし（カードの明細で1件ずつ数える）
    case ownTransfer        // 自分の口座どうしの振替・積立

    var label: String {
        switch self {
        case .cardSettlement: "カードの引き落とし（明細で計上）"
        case .ownTransfer: "口座間の振替（合計に入れない）"
        }
    }
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
    var card: String? = nil             // 前の版の Apple Pay のカード名
    var dedupeKey: String
    var batch: String? = nil            // 取り込みの単位（「今回の取り込みを取り消す」に使う）
    var excluded: Bool? = nil           // 合計に入れない（カードの引き落とし・口座間の振替）
    var excludeReason: KakeiboExcludeReason? = nil
    var needsAmount: Bool? = nil        // 金額が届かなかった（前の版の Apple Pay の iD・QUICPay など）
    var isTest: Bool? = nil             // 前の版の「テストで1件送る」で入れた1件
    var salary: Bool? = nil             // 給料（振り込み元の会社名などで見つけた）
    var categoryFixed: Bool? = nil      // 分類を手で直した（自動の分類で上書きしない）
    var createdAt: Date = .now

    var signed: Int { kind == .expense ? -amount : amount }
    var isExcluded: Bool { excluded ?? false }
    var isPending: Bool { needsAmount ?? false }
    var isSalary: Bool { salary ?? false }
    var counts: Bool { !isExcluded && !isPending && isTest != true }

    var institutionValue: KakeiboInstitution? { institution.flatMap(KakeiboInstitution.init(rawValue:)) }

    /// 合計に入れない理由の文（前の版で外した JCB の引落は「カードの引き落とし」）
    var excludeLabel: String? {
        guard isExcluded else { return nil }
        return (excludeReason ?? .cardSettlement).label
    }

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

// MARK: - 設定（給料日・振り込み元・覚えた分類・列の対応・目標貯金）

/// 分類の決まり：摘要やお店の名前に keyword が入っていれば category にする（記録の分類を直したときに覚える）
struct KakeiboRule: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var keyword: String
    var category: String
    var learned: Bool = true            // 直した内容から覚えたもの（前の版の組みこみの決まりは false。読むときに捨てる）
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

/// 家計簿の設定。前の版の「予算」「分類の一覧」「Apple Pay」は読み捨てる（ファイルに残っていても使わない）
struct KakeiboSettings: Codable {
    var payday: Int? = nil              // 給料日（1〜31。31 は月末）。nil は暦の月で数える
    var employer: String = ""           // 振り込み元（会社名）。明細の収入の行と比べて給料を見つける
    var rules: [KakeiboRule] = []       // 覚えた分類（新しいものが先）
    var mappings: [String: KakeiboColumnMapping] = [:]   // 銀行・カードごとの列の対応
    var excludeTransfers: Bool = true   // カードの引き落とし・口座間の振替を合計に入れない
    var savingsGoal: KakeiboSavingsGoal? = nil   // 目標貯金（期限つきの総額）
    var lastImports: [String: Date] = [:]        // 銀行・カードごとの最後の取り込み（KakeiboInstitution.rawValue → 日時）
    var reminder = KakeiboReminderSettings()     // 取り込みのお知らせ

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KakeiboSettings()
        let day: Int? = (try? c.decodeIfPresent(Int.self, forKey: .payday)) ?? nil
        payday = KakeiboCycle.validDay(day)
        employer = ((try? c.decodeIfPresent(String.self, forKey: .employer)) ?? nil) ?? d.employer
        // 前の版の組みこみの決まり（learned でないもの）は辞書に移ったので捨てる
        let saved: [KakeiboRule] = ((try? c.decodeIfPresent([KakeiboRule].self, forKey: .rules)) ?? nil) ?? d.rules
        rules = saved.filter(\.learned)
        mappings = ((try? c.decodeIfPresent([String: KakeiboColumnMapping].self, forKey: .mappings)) ?? nil) ?? d.mappings
        excludeTransfers = ((try? c.decodeIfPresent(Bool.self, forKey: .excludeTransfers)) ?? nil) ?? d.excludeTransfers
        savingsGoal = (try? c.decodeIfPresent(KakeiboSavingsGoal.self, forKey: .savingsGoal)) ?? nil
        lastImports = ((try? c.decodeIfPresent([String: Date].self, forKey: .lastImports)) ?? nil) ?? d.lastImports
        reminder = ((try? c.decodeIfPresent(KakeiboReminderSettings.self, forKey: .reminder)) ?? nil) ?? d.reminder
    }

    enum CodingKeys: String, CodingKey {
        case payday, employer, rules, mappings, excludeTransfers, savingsGoal, lastImports, reminder
    }

    /// d を含む周期（offset で前後へ）
    func cycle(_ d: Date = .now, offset: Int = 0) -> KakeiboCycle.Period {
        KakeiboCycle.period(containing: d, payday: payday, offset: offset)
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
        writeSummary(entries: list, settings: settings())
    }

    static func settings() -> KakeiboSettings { read(KakeiboSettings.self, settingsFile) ?? KakeiboSettings() }

    static func saveSettings(_ s: KakeiboSettings) {
        write(s, settingsFile)
        writeSummary(entries: entries(), settings: s)
    }

    /// ウィジェット用のいまの周期のまとめ（kakeibo-summary.json）を書き、ウィジェットを更新する
    static func writeSummary(entries list: [KakeiboEntry], settings s: KakeiboSettings, now: Date = .now) {
        var sum = KakeiboSummary.make(entries: list, cycle: s.cycle(now), payday: s.payday, now: now)
        sum.importDue = s.reminder.enabled ? KakeiboReminders.dues(settings: s, entries: list).map { $0.due }.min() : nil
        write(sum, KakeiboSummary.file)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 読んで、変えて、書く（直前の中身から変える）
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
    private static let smallKana: [Character: Character] = [
        "ァ": "ア", "ィ": "イ", "ゥ": "ウ", "ェ": "エ", "ォ": "オ", "ャ": "ヤ", "ュ": "ユ", "ョ": "ヨ", "ッ": "ツ", "ヮ": "ワ", "ヵ": "カ", "ヶ": "ケ",
    ]

    /// 比べるための形：全角英数・半角カナをそろえ、ひらがなはカタカナに、小さい字は大きく、大文字に、空白や記号・長音を取る
    /// （銀行の半角カナは小さい字を使えないので「ｼﾞｴｰｼｰﾋﾞｰ」と「ジェーシービー」を同じにする）
    static func normalize(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping
        let kata = nfkc.applyingTransform(.hiraganaToKatakana, reverse: false) ?? nfkc
        let drop: Set<Character> = [" ", "　", "-", "ー", "‐", "−", "・", ".", ",", "(", ")", "（", "）", "/", "*", "＊", "_", "'", "\"", "!"]
        let chars: [Character] = kata.uppercased().compactMap { ch -> Character? in
            if drop.contains(ch) { return nil }
            return smallKana[ch] ?? ch
        }
        return String(chars)
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

    /// カードの引き落とし・口座の振替らしい行（2回数えないため既定で入れない）
    static func isTransferLike(_ s: String) -> Bool {
        if KakeiboMerchants.isCardSettlement(s) || KakeiboMerchants.isOwnTransfer(s) { return true }
        return containsAny(s, ["引落", "ヒキオトシ", "カード"]) && !containsAny(s, ["口座振替", "コウザフリカエ"])
    }

    /// JCB の引落らしい行
    static func isJCBWithdrawal(_ s: String) -> Bool {
        containsAny(s, ["JCB", "ジェーシービー", "ジエーシービー"])
    }

    /// 決まりの言葉にする（分類を直したときに覚える）。数字や記号を除いた先頭 12 文字
    static func ruleKeyword(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = nfkc.split(whereSeparator: { $0 == " " || $0 == "　" }).first.map(String.init) ?? nfkc
        let base = first.count >= 2 ? first : nfkc
        return String(base.prefix(12))
    }
}

enum KakeiboRules {
    struct Result: Hashable {
        var category: String
        var salary: Bool
    }

    /// 摘要・お店の名前から分類を決める。
    /// 収入：振り込み元の会社名 → 覚えた分類 → 給料らしい言葉 → 「収入」。
    /// 支出：覚えた分類 → 組みこみの辞書 → 「その他」
    static func classify(_ text: String, kind: KakeiboKind, settings: KakeiboSettings) -> Result {
        let n = KakeiboText.normalize(text)
        if kind == .income && KakeiboMerchants.isFromEmployer(text, employer: settings.employer) {
            return Result(category: KakeiboCategories.salary, salary: true)
        }
        if !n.isEmpty {
            for r in settings.rules where r.learned {
                let k = KakeiboText.normalize(r.keyword)
                guard !k.isEmpty, n.contains(k) else { continue }
                let isIncome: Bool = KakeiboCategories.isIncomeCategory(r.category)
                if (kind == .income) != isIncome { continue }
                return Result(category: r.category, salary: r.category == KakeiboCategories.salary)
            }
        }
        if kind == .income {
            let words: [String] = KakeiboMerchants.salaryWords.map(KakeiboText.normalize)
            if words.contains(where: { n.contains($0) }) { return Result(category: KakeiboCategories.salary, salary: true) }
            return Result(category: KakeiboCategories.income, salary: false)
        }
        return Result(category: KakeiboMerchants.category(text) ?? KakeiboCategories.other, salary: false)
    }

    /// 分類だけ
    static func suggest(_ text: String, kind: KakeiboKind, settings: KakeiboSettings) -> String {
        classify(text, kind: kind, settings: settings).category
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

    /// 銀行の明細の行が、合計に入れない行か（カードの明細の行は見ない）
    static func excludeReason(_ text: String, kind: KakeiboKind, isCard: Bool) -> KakeiboExcludeReason? {
        guard !isCard else { return nil }
        if kind == .expense && KakeiboMerchants.isCardSettlement(text) { return .cardSettlement }
        if KakeiboMerchants.isOwnTransfer(text) { return .ownTransfer }
        return nil
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

    /// すでにある記録と重なる1件（なければ nil）：同じ金額・似た文字で、日付が前後1日まで。
    /// 同じ銀行・カードの明細どうしは同じ日だけ（2回取り込んだ明細は日付も同じ。翌日の同じ買い物は別の1件）
    static func match(date: Date, amount: Int, kind: KakeiboKind, text: String, institution: String? = nil,
                      in list: [KakeiboEntry], fromFile: Bool = true) -> KakeiboEntry? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return list.first { e in
            guard e.amount == amount, e.kind == kind, e.isTest != true else { return false }
            let other = cal.startOfDay(for: e.date)
            let gap: Int = abs(cal.dateComponents([.day], from: day, to: other).day ?? 99)
            let sameStatement: Bool = institution != nil && e.institution == institution && e.source.isFile
            let allowed: Int = fromFile && !sameStatement ? 1 : 0
            guard gap <= allowed else { return false }
            return KakeiboText.similar(text, e.memo)
        }
    }

    static func isDuplicate(date: Date, amount: Int, kind: KakeiboKind, text: String, institution: String? = nil,
                            in list: [KakeiboEntry], fromFile: Bool = true) -> Bool {
        match(date: date, amount: amount, kind: kind, text: text, institution: institution, in: list, fromFile: fromFile) != nil
    }
}

// MARK: - 暦の月（目標の期限の選び方などに使う）

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

// MARK: - 周期のまとめ（ホーム・ウィジェット）

/// 家計簿の周期のまとめ。ウィジェットは共有フォルダの kakeibo-summary.json を読むだけにする。
/// ファイルの形（名前は固定）：
/// { "month": "2026-10", "spent": 12345, "income": 210000,
///   "cycleStart": "2026-09-25", "cycleEnd": "2026-10-22", "payday": 25, "importDue": "2026-10-24",
///   "topCategories": [ { "name": "食費", "amount": 4938 }, … 最大3つ ] }
/// month は周期の呼び名の月（「10月分」）。cycleEnd は周期の最後の日（含む）。payday は給料日なしなら null。
/// importDue はいちばん早い明細の取り込みの期限（この日から「明細の取り込みがまだです」。お知らせを切っていれば null）
struct KakeiboSummary: Codable, Hashable {
    static let file = "kakeibo-summary.json"

    var cycle: KakeiboCycle.Period
    var spent: Int              // その周期の支出（円、プラス）
    var income: Int             // その周期の収入
    var payday: Int?            // 給料日（ファイルに書く。ウィジェットが「あと何日」を出す）
    var daysToPayday: Int? = nil    // 次の給料日まであと何日（いまの周期のときだけ。ファイルには書かない）
    var pendingCount: Int = 0   // 金額の入力待ち（ファイルには書かない）
    var categories: [Slice]     // 支出の分類（多い順。ファイルには上位3つ）
    var importDue: Date? = nil  // いちばん早い取り込みの期限（お知らせを切っていれば nil。ファイルに書く）

    struct Slice: Codable, Hashable {
        var name: String
        var amount: Int
    }

    /// 残り（収入 − 支出）
    var left: Int { income - spent }
    var topCategories: [Slice] { Array(categories.prefix(3)) }

    init(cycle: KakeiboCycle.Period, spent: Int, income: Int, payday: Int?, daysToPayday: Int? = nil,
         pendingCount: Int = 0, categories: [Slice]) {
        self.cycle = cycle
        self.spent = spent
        self.income = income
        self.payday = payday
        self.daysToPayday = daysToPayday
        self.pendingCount = pendingCount
        self.categories = categories
    }

    // MARK: ファイルの形

    enum CodingKeys: String, CodingKey {
        case month, spent, income, cycleStart, cycleEnd, payday, topCategories, importDue
    }

    private static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.calendar = Calendar(identifier: .gregorian)
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = TimeZone.current
        d.dateFormat = f
        return d
    }

    private static let monthFormat: DateFormatter = formatter("yyyy-MM")
    private static let dayFormat: DateFormatter = formatter("yyyy-MM-dd")

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.monthFormat.string(from: cycle.label), forKey: .month)
        try c.encode(spent, forKey: .spent)
        try c.encode(income, forKey: .income)
        try c.encode(Self.dayFormat.string(from: cycle.start), forKey: .cycleStart)
        try c.encode(Self.dayFormat.string(from: cycle.lastDay), forKey: .cycleEnd)
        try c.encode(payday, forKey: .payday)
        try c.encode(topCategories, forKey: .topCategories)
        try c.encode(importDue.map { Self.dayFormat.string(from: $0) }, forKey: .importDue)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cal = Calendar.current
        let m: String = try c.decode(String.self, forKey: .month)
        let label: Date = Self.monthFormat.date(from: m) ?? KakeiboMonth.start(.now)
        let day: Int? = try c.decodeIfPresent(Int.self, forKey: .payday)
        payday = KakeiboCycle.validDay(day)
        let fallback: KakeiboCycle.Period = KakeiboCycle.period(label: label, payday: payday)
        let startText: String? = try c.decodeIfPresent(String.self, forKey: .cycleStart)
        let lastText: String? = try c.decodeIfPresent(String.self, forKey: .cycleEnd)
        let start: Date = startText.flatMap { Self.dayFormat.date(from: $0) } ?? fallback.start
        let last: Date? = lastText.flatMap { Self.dayFormat.date(from: $0) }
        let end: Date = last.flatMap { cal.date(byAdding: .day, value: 1, to: $0) } ?? fallback.end
        cycle = KakeiboCycle.Period(start: start, end: end, label: label, usesPayday: payday != nil)
        spent = try c.decode(Int.self, forKey: .spent)
        income = try c.decodeIfPresent(Int.self, forKey: .income) ?? 0
        categories = try c.decodeIfPresent([Slice].self, forKey: .topCategories) ?? []
        let dueText: String? = try c.decodeIfPresent(String.self, forKey: .importDue)
        importDue = dueText.flatMap { Self.dayFormat.date(from: $0) }
    }

    /// kakeibo-summary.json を読む（なければ nil）
    static func read() -> KakeiboSummary? {
        guard let data = try? Data(contentsOf: SharedStore.url(file)) else { return nil }
        return try? JSONDecoder().decode(KakeiboSummary.self, from: data)
    }

    /// 周期の記録だけ
    static func entries(_ list: [KakeiboEntry], in cycle: KakeiboCycle.Period) -> [KakeiboEntry] {
        list.filter { cycle.contains($0.date) }
    }

    static func make(entries: [KakeiboEntry], cycle: KakeiboCycle.Period, payday: Int?, now: Date = .now) -> KakeiboSummary {
        let inCycle: [KakeiboEntry] = Self.entries(entries, in: cycle).filter { $0.isTest != true }
        let counted: [KakeiboEntry] = inCycle.filter(\.counts)
        let spent: Int = counted.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let income: Int = counted.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        var byCat: [String: Int] = [:]
        for e in counted where e.kind == .expense { byCat[e.category, default: 0] += e.amount }
        let sorted = byCat.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let slices: [Slice] = sorted.map { Slice(name: $0.key, amount: $0.value) }
        let days: Int? = cycle.contains(now) ? KakeiboCycle.daysToPayday(now: now, payday: payday) : nil
        return KakeiboSummary(cycle: cycle, spent: spent, income: income, payday: payday, daysToPayday: days,
                              pendingCount: inCycle.filter(\.isPending).count, categories: slices)
    }
}

extension Notification.Name {
    /// 家計簿の記録が変わった
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

    /// −12,345 / 12,345（マイナスは「−」）
    static func signedYen(_ v: Int) -> String { v < 0 ? "−" + yen(-v) : yen(v) }
}

// MARK: - 目標貯金（期限つきの総額）

/// 「2027年3月分までに50万円」。数えはじめの周期から、周期ごとの「収入 − 支出」を積み上げる
struct KakeiboSavingsGoal: Codable, Hashable {
    var amount: Int         // 目標の総額（円）
    var deadline: Date      // この月分（周期の呼び名の月）の終わりまで
    var start: Date         // 数えはじめる日（この日を含む周期から）
}

enum KakeiboSavings {
    struct Progress: Hashable {
        var saved: Int          // いままでに残せた額（今の周期の分も含む。マイナスもある）
        var savedThisCycle: Int // 今の周期に残せた額（収入 − 支出）
        var needThisCycle: Int  // 今の周期に残す必要がある額（前の周期までの分から割った、月あたりの額）
        var remaining: Int      // 目標まであと（0 以上）
        var monthsLeft: Int     // 今の周期を含めて、期限の周期まであといくつ（過ぎたら 0）
        var ratio: Double       // 0〜1
        var reached: Bool { remaining == 0 }
        /// 月あたりあと何円残せばよいか（＝今の周期の必要額）
        var perMonth: Int { needThisCycle }
        /// 今の周期は目標どおりか（残せた額が必要額に届いている）
        var onTrack: Bool { reached || savedThisCycle >= needThisCycle }
    }

    static func progress(_ goal: KakeiboSavingsGoal, entries: [KakeiboEntry], payday: Int?, now: Date = .now) -> Progress {
        let first: KakeiboCycle.Period = KakeiboCycle.period(containing: goal.start, payday: payday)
        let last: KakeiboCycle.Period = KakeiboCycle.period(label: KakeiboMonth.start(goal.deadline), payday: payday)
        let current: KakeiboCycle.Period = KakeiboCycle.period(containing: now, payday: payday)
        var before = 0
        var this = 0
        for e in entries where e.counts && e.date >= first.start && e.date < last.end {
            if current.contains(e.date) {
                this += e.signed
            } else if e.date < current.start {
                before += e.signed
            }
        }
        let saved: Int = before + this
        let remaining: Int = max(0, goal.amount - saved)
        let diff: Int = KakeiboCycle.distance(from: current, to: last)
        let monthsLeft: Int = max(0, diff + 1)
        // 今の周期の必要額は、前の周期までに残せた分から決める（今の周期の中で使っても、必要額は動かない）
        let restAtStart: Int = max(0, goal.amount - before)
        let need: Int = monthsLeft > 0 ? (restAtStart + monthsLeft - 1) / monthsLeft : remaining
        let ratio: Double = goal.amount > 0 ? min(1, max(0, Double(saved) / Double(goal.amount))) : 0
        return Progress(saved: saved, savedThisCycle: this, needThisCycle: need, remaining: remaining,
                        monthsLeft: monthsLeft, ratio: ratio)
    }
}
