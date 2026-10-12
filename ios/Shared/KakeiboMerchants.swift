import Foundation

// 家計簿の自動の分類：取引先（お店・振込元・引落先）の名前から分類を決める。
// 比べるときは KakeiboText.normalize で全角・半角、ひらがな・カタカナ、小さい字、空白や記号をそろえる。
// 合う言葉がいくつもあるときは、いちばん長い言葉を使う（「ガスト」は光熱の「ガス」より先、「楽天モバイル」は買い物の「楽天」より先）。

enum KakeiboCategories {
    static let other = "その他"
    static let salary = "給料"
    static let income = "収入"

    /// 支出の分類（直すときのメニューに出す順）
    static let expense: [String] = ["食費", "日用品", "買い物", "交通", "車・ガソリン", "サブスク", "ゲーム", "娯楽",
                                    "住まい", "光熱", "通信", "医療", "服", "交際", other]
    /// 収入の分類
    static let incomeList: [String] = [salary, income]

    static func list(for kind: KakeiboKind) -> [String] { kind == .income ? incomeList : expense }

    static func isIncomeCategory(_ c: String) -> Bool { incomeList.contains(c) }
}

enum KakeiboMerchants {
    /// 組みこみの辞書（分類 → 取引先の言葉）
    static let table: [(String, [String])] = [
        ("交通", ["ETC", "NEXCO", "ネクスコ", "高速道路", "首都高", "JR", "鉄道", "名鉄", "近鉄", "東急", "小田急", "京王",
                 "京急", "西武鉄道", "東武鉄道", "阪急", "阪神電", "メトロ", "地下鉄", "市営バス", "バス", "タクシー", "SUICA",
                 "PASMO", "TOICA", "MANACA", "ICOCA", "新幹線", "エクスプレス予約"]),
        ("車・ガソリン", ["ENEOS", "エネオス", "出光", "IDEMITSU", "アポロステーション", "コスモ石油", "コスモ", "COSMO",
                       "シェル", "SHELL", "ガソリン", "給油", "駐車", "パーキング", "タイムズ", "TIMES", "オートバックス",
                       "イエローハット", "車検", "洗車"]),
        ("食費", ["コンビニ", "セブンイレブン", "セブン-イレブン", "7-ELEVEN", "SEVEN-ELEVEN", "セブン", "ローソン", "LAWSON",
                 "ファミリーマート", "ファミマ", "FAMILYMART", "ミニストップ", "MINISTOP", "デイリーヤマザキ", "セイコーマート",
                 "スーパー", "イオン", "AEON", "マックスバリュ", "イトーヨーカドー", "西友", "バロー", "業務スーパー",
                 "ベーカリー", "弁当", "マクドナルド", "MCDONALD", "スターバックス", "STARBUCKS", "ドトール", "コメダ",
                 "すき家", "吉野家", "松屋", "ガスト", "サイゼリヤ", "スシロー", "くら寿司", "食堂", "レストラン", "カフェ",
                 "CAFE", "UBER EATS", "出前館"]),
        ("日用品", ["ドラッグ", "薬局", "マツモトキヨシ", "ウエルシア", "スギ薬局", "ツルハ", "ダイソー", "DAISO", "セリア",
                   "キャンドゥ", "無印", "ホームセンター", "カインズ", "コメリ", "ニトリ"]),
        ("買い物", ["AMAZON", "アマゾン", "AMZN", "楽天", "RAKUTEN", "ラクテン", "YAHOO", "ヤフー", "ZOZO", "メルカリ",
                   "ヨドバシ", "ビックカメラ", "ヤマダ電機", "ヤマダデンキ", "ケーズデンキ", "エディオン"]),
        ("サブスク", ["APPLE.COM", "APPLE COM BILL", "ITUNES", "ICLOUD", "NETFLIX", "SPOTIFY", "YOUTUBE", "AMAZON PRIME",
                    "アマゾンプライム", "PRIME VIDEO", "DISNEY", "U-NEXT", "HULU", "DAZN", "ABEMA", "ADOBE", "MICROSOFT",
                    "OPENAI", "サブスク", "月額"]),
        ("ゲーム", ["STEAM", "VALVE", "NINTENDO", "任天堂", "ニンテンドー", "PLAYSTATION", "プレイステーション", "PSN",
                   "XBOX", "ゲーム"]),
        ("娯楽", ["映画", "シネマ", "イオンシネマ", "TOHOシネマズ", "カラオケ", "書店", "本屋", "TSUTAYA", "チケット", "ボウリング"]),
        ("住まい", ["家賃", "ヤチン", "賃料", "管理費", "共益費", "不動産"]),
        ("光熱", ["電気", "電力", "デンキ", "楽天でんき", "ガス", "水道", "スイドウ", "上下水道"]),
        ("通信", ["携帯", "ケイタイ", "ドコモ", "DOCOMO", "SOFTBANK", "ソフトバンク", "ワイモバイル", "Y!MOBILE", "YMOBILE",
                 "楽天モバイル", "KDDI", "UQモバイル", "AHAMO", "アハモ", "POVO", "LINEMO", "NTT", "フレッツ", "プロバイダ",
                 "IIJ", "MINEO", "マイネオ"]),
        ("医療", ["病院", "クリニック", "医院", "歯科", "調剤"]),
        ("服", ["ユニクロ", "UNIQLO", "しまむら", "ZARA", "ワークマン", "靴"]),
        ("交際", ["プレゼント", "居酒屋", "ギフト"]),
    ]

    /// 比べる形にした辞書（長い言葉が先）
    private static let entries: [(key: String, category: String)] = {
        var out: [(key: String, category: String)] = []
        for (cat, words) in table {
            for w in words {
                let k = KakeiboText.normalize(w)
                if !k.isEmpty { out.append((k, cat)) }
            }
        }
        return out.sorted { $0.key.count > $1.key.count }
    }()

    /// 辞書で分類を探す（なければ nil）
    static func category(_ text: String) -> String? {
        let n = KakeiboText.normalize(text)
        guard !n.isEmpty else { return nil }
        return entries.first { n.contains($0.key) }?.category
    }

    // MARK: 給料

    /// 給料らしい言葉（会社名を決めていなくても給料にする）
    static let salaryWords = ["給与", "給料", "賞与", "キュウヨ", "ショウヨ", "キュウリョウ"]

    /// 会社名を比べる形に（「株式会社」「(株)」などを外す）。「、」「,」で区切ると、いくつも書ける
    static func employerKeys(_ employer: String) -> [String] {
        let parts = employer.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { "、,，/\n".contains($0) })
        let drop = ["株式会社", "有限会社", "合同会社", "(株)", "(有)", "(同)", "カブシキガイシャ", "ユウゲンガイシャ"]
        return parts.compactMap { part -> String? in
            var s = String(part)
            for d in drop { s = s.replacingOccurrences(of: d, with: "") }
            let k = KakeiboText.normalize(s)
            return k.count >= 2 ? k : nil
        }
    }

    /// 振り込み元の会社名が入った収入か
    static func isFromEmployer(_ text: String, employer: String) -> Bool {
        let n = KakeiboText.normalize(text)
        guard !n.isEmpty else { return false }
        return employerKeys(employer).contains { n.contains($0) }
    }

    // MARK: カードの引き落とし（銀行の明細の行）

    /// カード会社の名前。銀行の明細にこの名前の引落があれば、カードの明細で1件ずつ数えるので合計に入れない
    static let cardCompanies = ["十六カード", "ジユウロクカード", "ジュウロクカード", "JCB", "ジエーシービー", "ジェーシービー",
                                "三菱UFJニコス", "UFJニコス", "ニコス", "NICOS", "MUFGカード", "DCカード", "セゾン", "SAISON",
                                "楽天カード", "ラクテンカード", "三井住友カード", "ミツイスミトモカード", "SMBC", "イオンカード",
                                "イオンクレジット", "エポス", "EPOS", "オリコ", "ORICO", "アメックス", "AMEX", "アメリカンエキスプレス",
                                "ビューカード", "VIEWCARD", "PAYPAYカード", "ペイペイカード", "Dカード", "AUPAYカード",
                                "エーユーペイカード", "クレジット"]

    private static let cardKeys: [String] = cardCompanies.map(KakeiboText.normalize).filter { !$0.isEmpty }

    /// カードの引き落としらしい行か
    static func isCardSettlement(_ text: String) -> Bool {
        let n = KakeiboText.normalize(text)
        return cardKeys.contains { n.contains($0) }
    }

    /// 自分の口座どうしの振替らしい行か（口座振替＝引落は除く。積立・定期・自分あての振込）
    static func isOwnTransfer(_ text: String) -> Bool {
        let n = KakeiboText.normalize(text)
        guard !n.isEmpty else { return false }
        let debit = ["口座振替", "コウザフリカエ", "自動振替", "ジドウフリカエ"].map(KakeiboText.normalize)
        let own = ["積立", "ツミタテ", "定期預金", "テイキヨキン", "本人", "ホンニン", "自分", "口座間", "振替", "フリカエ"]
            .map(KakeiboText.normalize)
        if debit.contains(where: { n.contains($0) }) {
            // 口座振替でも、積立・定期は自分の口座へ
            return ["積立", "ツミタテ", "定期預金", "テイキヨキン"].map(KakeiboText.normalize).contains { n.contains($0) }
        }
        return own.contains { n.contains($0) }
    }
}
