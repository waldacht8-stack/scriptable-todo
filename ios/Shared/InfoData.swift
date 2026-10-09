import Foundation

// MARK: - 「情報」タブのデータ（話題・記事・あとで読む・おすすめの好み）
// 通信と XML の読み取りは App/Info に置き、ここには型と保存だけを置く（ウィジェットにも入るため）。
// 保存は info-*.json。ウィジェットの再読み込みを起こさないよう SharedStore.save は使わず直接書く。

/// 記事・投稿を集める元（キー不要・無料のもの）
enum InfoSource: String, Codable, CaseIterable, Identifiable {
    case googleNews      // Google ニュース（日本語）
    case hatena          // はてなブックマーク
    case googleNewsEN    // Google News（英語）
    case hackerNews      // Hacker News（Algolia）
    case bluesky         // Bluesky の公開投稿
    case reddit          // Reddit（つながれば）
    case fivech          // 5ch のスレッド（題名だけ。本文は公式の Web ページをアプリ内で開く）

    var id: String { rawValue }

    var name: String {
        switch self {
        case .googleNews: "Google ニュース"
        case .hatena: "はてなブックマーク"
        case .googleNewsEN: "Google News（英語）"
        case .hackerNews: "Hacker News"
        case .bluesky: "Bluesky"
        case .reddit: "Reddit"
        case .fivech: "5ch"
        }
    }

    /// カードに出す短い名前
    var short: String {
        switch self {
        case .googleNews: "Google ニュース"
        case .hatena: "はてブ"
        case .googleNewsEN: "Google News"
        case .hackerNews: "Hacker News"
        case .bluesky: "Bluesky"
        case .reddit: "Reddit"
        case .fivech: "5ch"
        }
    }

    var summary: String {
        switch self {
        case .googleNews: "国内のニュース記事"
        case .hatena: "話題になっている記事・ブログ"
        case .googleNewsEN: "海外のニュース（日本語に翻訳）"
        case .hackerNews: "海外の技術系の話題（日本語に翻訳）"
        case .bluesky: "日本語の公開投稿"
        case .reddit: "海外の掲示板（つながるときだけ）"
        case .fivech: "5ch のスレッド（題名で検索・アプリ内で開く）"
        }
    }

    var symbol: String {
        switch self {
        case .googleNews, .googleNewsEN: "newspaper"
        case .hatena: "bookmark"
        case .hackerNews: "chevron.left.forwardslash.chevron.right"
        case .bluesky: "bubble.left.and.bubble.right"
        case .reddit: "text.bubble"
        case .fivech: "list.bullet.rectangle"
        }
    }

    static let defaults: [InfoSource] = [.googleNews, .hatena, .bluesky]

    /// どの話題でも必ず検索する元
    var isAlwaysOn: Bool { self == .bluesky }
}

/// 好きな話題（キーワードと、どこから集めるか）
struct InfoTopic: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var keyword: String
    var color: Int = 0                 // InfoTopicColor の番号（0 はデザインの強調色）
    var sourceIDs: [String] = InfoSource.defaults.map(\.rawValue)
    var notify: Bool? = nil            // 新着を通知（準備中。設定だけ保存する）
    var createdAt: Date = .now

    /// 知らない元（新しい版で増えたもの）は読み飛ばす
    var sources: [InfoSource] {
        let picked = sourceIDs.compactMap(InfoSource.init(rawValue:)).filter { !$0.isAlwaysOn }
        return picked + InfoSource.allCases.filter(\.isAlwaysOn)
    }

    /// X（旧 Twitter）の検索。自動では集めず、アプリ内のブラウザで開くだけ
    var xSearchURL: URL? { InfoText.xSearchURL(keyword) }
}

/// 1件の記事・投稿
struct InfoArticle: Codable, Identifiable, Hashable {
    var id: String { link }
    var title: String
    var link: String
    var source: String                 // InfoSource の rawValue、または "hot"（はてブ人気）・"top"（主要ニュース）
    var site: String? = nil            // 媒体・投稿者の名前
    var feedKey: String = ""           // どの話題から来たか（InfoTopic.id。おすすめ用は "_hot"・"_top"）
    var published: Date? = nil
    var image: String? = nil
    var summary: String? = nil
    // Bluesky の投稿だけが持つ項目
    var author: String? = nil          // 表示名
    var handle: String? = nil          // @ハンドル
    var likes: Int? = nil
    var reposts: Int? = nil

    var isPost: Bool { source == InfoSource.bluesky.rawValue }

    var sourceName: String {
        if let s = InfoSource(rawValue: source) { return s.short }
        switch source {
        case "hot": return "はてブ 人気"
        case "top": return "主要ニュース"
        default: return source
        }
    }

    /// 日本語でない見出し（翻訳の対象）：かな・漢字を含まず、英字が多いもの
    var isForeign: Bool { InfoText.isForeign(title) }
}

enum InfoText {
    static func isForeign(_ s: String) -> Bool {
        var latin = 0
        for u in s.unicodeScalars {
            switch u.value {
            case 0x3040...0x30FF, 0x4E00...0x9FFF, 0xFF66...0xFF9F: return false
            case 0x41...0x5A, 0x61...0x7A: latin += 1
            default: break
            }
        }
        return latin >= 3
    }

    /// URL のクエリに入れる文字だけを残して符号化する（「&」「+」「/」なども符号化）
    static func encode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func xSearchURL(_ keyword: String) -> URL? {
        URL(string: "https://x.com/search?q=\(encode(keyword))&f=live")
    }

    /// 「3分前」「2時間前」「昨日」「10/3」
    static func ago(_ d: Date?, now: Date = .now) -> String {
        guard let d else { return "" }
        let s = max(0, now.timeIntervalSince(d))
        if s < 60 { return "たった今" }
        if s < 3600 { return "\(Int(s / 60))分前" }
        if s < 86400 { return "\(Int(s / 3600))時間前" }
        if s < 86400 * 2 { return "昨日" }
        if s < 86400 * 7 { return "\(Int(s / 86400))日前" }
        return JP.shortDate(d)
    }
}

/// 1つの取得元から集めた結果
struct InfoFeedCache: Codable {
    var fetchedAt: Date
    var items: [InfoArticle]
    var failed: Bool? = nil
}

/// おすすめの好み（スワイプ・開いた・読んだ時間から学ぶ。端末の中だけに保存）
struct InfoPrefs: Codable {
    var tokens: [String: Double] = [:]
    var sources: [String: Double] = [:]
    var updatedAt: Date? = nil
}

enum InfoData {
    static let topicsFile = "info-topics.json"
    static let cacheFile = "info-cache.json"
    static let readFile = "info-read.json"
    static let savedFile = "info-saved.json"
    static let prefsFile = "info-prefs.json"
    static let translationsFile = "info-translations.json"

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? { SharedStore.load(type, from: name) }

    /// ウィジェットを再読み込みさせずに書く（情報タブのデータはウィジェットで使わない）
    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder.iso.encode(value) else { return }
        try? data.write(to: SharedStore.url(name), options: .atomic)
    }

    /// 話題を追加するときの候補
    static let suggestions = ["猫", "iPhone", "キャンプ", "料理", "ゲーム", "宇宙", "カメラ", "サッカー"]
}

// MARK: - 見本（起動引数 -demo。通信せずに表示する架空の内容）

enum InfoDemo {
    static let topics: [InfoTopic] = [
        InfoTopic(id: "demo-cat", keyword: "猫", color: 0, sourceIDs: ["googleNews", "hatena", "bluesky", "fivech"]),
        InfoTopic(id: "demo-phone", keyword: "iPhone", color: 1, sourceIDs: ["googleNews", "hatena", "googleNewsEN", "hackerNews"]),
        InfoTopic(id: "demo-camp", keyword: "キャンプ", color: 3, sourceIDs: ["googleNews", "hatena"]),
    ]

    /// 架空の記事（実在の記事・人物ではない）
    static let fixedNow = Date()

    static func articles(now: Date = InfoDemo.fixedNow) -> [InfoArticle] {
        var n = 0
        func ago(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        func a(_ title: String, _ key: String, _ src: String, _ site: String, _ min: Double, _ summary: String? = nil) -> InfoArticle {
            n += 1
            return InfoArticle(title: title, link: "https://example.com/demo/\(key)/\(n)", source: src, site: site,
                        feedKey: key, published: ago(min), summary: summary)
        }
        func post(_ text: String, _ key: String, _ name: String, _ handle: String, _ min: Double, _ likes: Int, _ reposts: Int) -> InfoArticle {
            var x = a(text, key, "bluesky", name, min)
            x.author = name
            x.handle = handle
            x.likes = likes
            x.reposts = reposts
            return x
        }
        return [
            a("New study suggests cats recognize their names even from strangers", "demo-cat", "googleNewsEN", "Sample Science", 14),
            a("保護猫の譲渡会、週末に駅前ひろばで開催へ　初めての人向けの相談コーナーも", "demo-cat", "googleNews", "みほん新聞", 25,
              "地域のボランティア団体が主催。飼う前に知っておきたいことを相談できるコーナーを設ける。"),
            a("【見本】猫と暮らしてる人、朝のルーティン教えて", "demo-cat", "fivech", "5ch・見本板", 40),
            a("スマホの写真を整理するコツ　アルバム分けは「月ごと」が続けやすい", "demo-phone", "hatena", "サンプル技術ブログ", 48),
            a("Developers share tips for longer battery life on older phones", "demo-phone", "hackerNews", "Hacker News", 70),
            a("初心者向けキャンプ道具、最初にそろえるべき5つ", "demo-camp", "hatena", "みほんアウトドア", 95,
              "テント・寝袋・ライト・椅子・調理道具。レンタルから始めるのもおすすめ。"),
            a("猫が快適に過ごせる部屋の温度は？　季節ごとの目安まとめ", "demo-cat", "hatena", "ねこ暮らし（見本）", 130),
            a("スマートフォンの新しいカメラ機能、夜景の撮り方が変わる", "demo-phone", "googleNews", "サンプル通信", 180),
            a("秋の星空キャンプ、冷え込み対策は「足元」から", "demo-camp", "googleNews", "みほん新聞", 240),
            post("近所の猫カフェに新しい子猫が仲間入り。まだ小さくて、ずっと毛布の上で寝ています", "demo-cat", "みほんのねこ", "demo.example", 300, 42, 6),
            a("週末は晴れの予報、紅葉の名所がにぎわいそう", "_top", "top", "みほん新聞", 35),
            a("「毎日5分」の片づけ習慣が続く仕組みの作り方", "_hot", "hot", "サンプル暮らしブログ", 60),
        ]
    }

    /// 見本の翻訳（実機では端末の翻訳機能で作る）
    static let translations: [String: String] = {
        var t: [String: String] = [:]
        for a in articles() where a.isForeign {
            if a.title.hasPrefix("New study") { t[a.id] = "猫は知らない人に呼ばれても自分の名前がわかる、との新しい研究" }
            if a.title.hasPrefix("Developers") { t[a.id] = "古いスマホの電池を長持ちさせるコツを開発者たちが紹介" }
        }
        return t
    }()

    static let prefs = InfoPrefs(tokens: ["猫": 2.5, "写真": 1.2, "キャンプ": 0.8], sources: ["hatena": 0.6])
}
