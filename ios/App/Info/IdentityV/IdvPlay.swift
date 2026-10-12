import Foundation

// MARK: - 第五人格：遊ぶときに要る情報（ランクマッチ・対戦情報・アプリの版・第五録の新着）
// 読むもの：
// - 公式サイトのアップデートのお知らせの本文（IdvSchedule.swift で読んだもの）から、
//   「娯楽モード」「大会」「ショップ」などの見出しと「イベント期間：…」の行を組にして期間にする（IdvArticle）
//   ランク戦の開放時間・メンテナンス中の封鎖・段位継承などの文も、公式の本文にあるときだけ出す（IdvRank）
// - App Store の公開 API（itunes.apple.com/lookup）で、アプリの版・公開日・更新内容（IdvAppStore）
// - 第五録（daigoroku.com。ファンの攻略サイト）の「最新アップデート情報」の一覧から、見出しと日付だけ（IdvDaigoroku）
//   第五録は私的利用の範囲を超える転載を禁止しているので、本文・画像は読まない・残さない・出さない。
//   読むのは数時間に1回まで、端末に残して使い回す
// 分からないことは推測せず、画面に「公式で確認」と出してリンクを付ける

// MARK: 期間（公式の本文から）

struct IdvPeriod: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case mode, tournament, collab, gacha, shop, event

        var label: String {
            switch self {
            case .mode: return "モード"
            case .tournament: return "大会"
            case .collab: return "コラボ"
            case .gacha: return "ガチャ"
            case .shop: return "ショップ"
            case .event: return "イベント"
            }
        }
    }

    var kind: Kind
    var section: String
    var title: String
    var start: Date?
    var end: Date
    var link: String

    var id: String { "\(link)#\(kind.rawValue)#\(title)" }

    var asEvent: IdvEvent {
        IdvEvent(id: "official-" + id, title: title, end: end, link: link, start: start,
                 tag: kind == .collab ? "コラボ" : (kind == .gacha ? "ガチャ" : nil))
    }
}

enum IdvArticle {
    /// 公式のお知らせの区切り（この行だけの見出し）
    static let sections: Set<String> = [
        "新シーズン", "新キャラ", "ショップ", "バージョンイベント", "娯楽モード", "大会", "シーズン真髄", "手記の加筆",
        "ゲームの改善", "不具合修正", "キャラ調整", "バランス調整", "新マップ", "システム", "イベント",
    ]
    private static let skipSections: Set<String> = ["ゲームの改善", "不具合修正", "キャラ調整", "バランス調整"]

    private static func re(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }
    private static let dateOnlyRE = re("^(?:(\\d{4})年)?(\\d{1,2})月(\\d{1,2})日(?:\\s*[（(][^）)]{1,3}[）)])?$")
    private static let periodRE = re("期間|開放時間は|開催時間|開催日|開放されます")

    private static func has(_ re: NSRegularExpression?, _ s: String) -> Bool {
        guard let re else { return false }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// 記事の HTML を行に分ける（script・style は捨てる）
    static func lines(fromHTML html: String) -> [String] {
        var s = html
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<!--[\\s\\S]*?-->"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<(br|/p|/div|/li|/h\\d|/tr|/dd|/dt)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        s = InfoFeedParser.unescape(s.replacingOccurrences(of: "&amp;nbsp;", with: " "))
        return s.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[\\s\\x{00A0}\\x{3000}]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 見出しらしい行（短く、句点も「：」もない）
    static func isHeading(_ l: String) -> Bool {
        guard l.count <= 40, !l.contains("。"), !l.contains("："), !l.contains(":") else { return false }
        if l.range(of: "\\bvs\\b|VS", options: [.regularExpression, .caseInsensitive]) != nil { return false }
        return true
    }

    static func kind(section: String, group: String, title: String) -> IdvPeriod.Kind {
        let t = title.uppercased()
        if ["IJL", "IVC", "COA", "IVL", "大会"].contains(where: { t.contains($0) }) { return .tournament }
        if title.contains("コラボ") || group.contains("コラボ") { return .collab }
        if section == "大会" { return .tournament }
        if section == "娯楽モード" || ["モード", "2V8", "1V4", "闘争"].contains(where: { t.contains($0) }) { return .mode }
        if section == "シーズン真髄" || ["ガチャ", "真髄", "推理の径", "宝探し", "秘宝", "ダイス"].contains(where: { title.contains($0) }) { return .gacha }
        if section == "ショップ" || title.contains("ショップ") || title.contains("パック") { return .shop }
        return .event
    }

    /// 本文の行から期間を拾う。見出し → 説明 → 「イベント期間：…」の並びを1組とする
    /// 「大会」の区切りでは、日付だけの行（試合の日）を集めて、最初の日〜最後の日にする
    static func periods(lines: [String], link: String, reference: Date) -> [IdvPeriod] {
        var out: [IdvPeriod] = []
        var section = ""
        var title = ""
        var group = ""
        var matchDays: [Date] = []

        func flushMatches() {
            defer { matchDays = [] }
            guard section == "大会", let first = matchDays.min(), let last = matchDays.max(), !title.isEmpty else { return }
            out.append(IdvPeriod(kind: .tournament, section: section, title: title, start: first, end: last, link: link))
        }

        for raw in lines {
            let n = IdvDates.normalize(raw)
            if sections.contains(n) {
                flushMatches()
                section = n
                title = n
                group = ""
                continue
            }
            if skipSections.contains(section) { continue }
            if let re = dateOnlyRE, let m = re.firstMatch(in: n, range: NSRange(location: 0, length: (n as NSString).length)) {
                let ns = n as NSString
                func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
                if section == "大会", let d = IdvDates.day(Int(g(1)), Int(g(2)) ?? 0, Int(g(3)) ?? 0, reference: reference) {
                    matchDays.append(d)
                }
                continue
            }
            if isHeading(n) {
                flushMatches()
                title = n
                if n.contains("コラボ") { group = n }
                continue
            }
            guard has(periodRE, n), !title.isEmpty, let r = IdvDates.range(in: n, reference: reference) else { continue }
            let k: IdvPeriod.Kind = kind(section: section, group: group, title: title)
            out.append(IdvPeriod(kind: k, section: section, title: title, start: r.start, end: r.end, link: link))
        }
        flushMatches()
        // 同じ見出しは最初の期間だけ
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// まだ終わっていないものを、終わる日の近い順に（同じ見出しは1つ）
    static func current(_ all: [IdvPeriod], now: Date = .now) -> [IdvPeriod] {
        var seen = Set<String>()
        return all.filter { IdvDates.daysLeft($0.end, now: now) >= 0 }
            .sorted { $0.end < $1.end }
            .filter { seen.insert("\($0.kind.rawValue)#\($0.title)").inserted }
    }
}

// MARK: ランクマッチ（開放時間・封鎖・継承の文）

struct IdvRankWindow: Codable, Equatable {
    var label: String
    /// 日本時間の 0:00 からの分（end は 24:00 = 1440 まで。日をまたぐときは start > end）
    var start: Int
    var end: Int

    func contains(minute m: Int) -> Bool {
        start <= end ? (m >= start && m < end) : (m >= start || m < end)
    }

    static func hm(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 25, m % 60) }
    var text: String { "\(Self.hm(start))〜\(Self.hm(end))" }
}

struct IdvRankInfo: Codable, Equatable {
    var windows: [IdvRankWindow] = []
    /// 「ランク戦モードはサーバー維持メンテナンスの間封鎖されます」と公式にあるか
    var closedDuringMaintenance = false
    /// 段位継承・リセットについての公式の文（1文ずつ）
    var notes: [String] = []
    var link: String? = nil

    private static func minute(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// いま開いているもの（開放時間が分かるときだけ）
    func openWindow(now: Date = .now) -> IdvRankWindow? {
        let m = Self.minute(now)
        return windows.first { $0.contains(minute: m) }
    }

    /// 次に開く時刻（いま閉じているとき）
    func nextOpen(now: Date = .now) -> Date? {
        guard !windows.isEmpty, openWindow(now: now) == nil else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let m = Self.minute(now)
        let starts: [Int] = windows.map(\.start).sorted()
        if let s = starts.first(where: { $0 > m }) { return today.addingTimeInterval(Double(s) * 60) }
        guard let first = starts.first, let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return nil }
        return tomorrow.addingTimeInterval(Double(first) * 60)
    }
}

enum IdvRank {
    private static let windowRE = try? NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})\\s*[～〜~\\-－–—]\\s*(\\d{1,2}):(\\d{2})")

    /// 「ランク戦の開放時間：12:00～14:00、19:00～24:00」のような行から時間帯を読む（UTC+8 とあれば1時間足す）
    static func windows(in text: String) -> [IdvRankWindow] {
        guard let re = windowRE else { return [] }
        var out: [IdvRankWindow] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = IdvDates.normalize(raw)
            guard line.contains("ランク"), line.contains("開放") || line.contains("時間") else { continue }
            let shift: Int = line.contains("UTC+8") ? 60 : 0
            let label: String = line.contains("五人") || line.contains("5人") ? "5人ランク" : "ランク戦"
            let ns = line as NSString
            for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let v: [Int] = (1...4).map { Int(ns.substring(with: m.range(at: $0))) ?? 0 }
                guard v[0] <= 24, v[2] <= 24, v[1] < 60, v[3] < 60 else { continue }
                let s = (v[0] * 60 + v[1] + shift) % 1440
                var e = v[2] * 60 + v[3] + shift
                if e > 1440 { e -= 1440 }
                out.append(IdvRankWindow(label: label, start: s, end: e))
            }
        }
        return out
    }

    /// 段位継承・リセットの文（「。」までの1文、最大3つ）
    static func notes(in text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let isRank = line.contains("段位継承") || (line.contains("リセット") && (line.contains("推理の径") || line.contains("段位")))
            guard isRank else { continue }
            var first = line.components(separatedBy: "。").first ?? line
            if first.count > 90 { first = String(first.prefix(89)) + "…" }
            first += first.hasSuffix("…") ? "" : "。"
            if !out.contains(first) { out.append(first) }
            if out.count >= 3 { break }
        }
        return out
    }

    /// 公式のアップデートのお知らせ（新しい順に見る）からまとめる
    static func info(updates: [IdvNews], articles: [String: String]) -> IdvRankInfo {
        var r = IdvRankInfo()
        let sorted = updates.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        for u in sorted {
            guard let text = articles[u.link] else { continue }
            if r.windows.isEmpty {
                let w = windows(in: text)
                if !w.isEmpty { r.windows = w; r.link = r.link ?? u.link }
            }
            if !r.closedDuringMaintenance, IdvDates.normalize(text).contains("ランク戦モードはサーバー維持メンテナンスの間封鎖") {
                r.closedDuringMaintenance = true
            }
            if r.notes.isEmpty, IdvSeasonParser.started(in: text) != nil {
                r.notes = notes(in: text)
                r.link = u.link
            }
        }
        return r
    }
}

// MARK: アプリの版（App Store）

struct IdvAppVersion: Codable, Equatable {
    var version: String
    var released: Date?
    /// 更新内容の頭（最大3行・120字）
    var notes: String
    var url: String
}

enum IdvAppStore {
    /// 日本の App Store の『Identity V』（NetEase）
    static let appID = "1347780764"
    static let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=\(appID)&country=jp")
    static let pageURL = "https://apps.apple.com/jp/app/id\(appID)"

    private struct Response: Decodable {
        struct Item: Decodable {
            let version: String?
            let currentVersionReleaseDate: String?
            let releaseNotes: String?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    static func summary(_ notes: String) -> String {
        let lines: [String] = notes.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "—―-－・*• ").union(.whitespaces)) }
            .filter { !$0.isEmpty }
        var s = lines.prefix(3).joined(separator: "\n")
        if s.count > 120 { s = String(s.prefix(119)) + "…" }
        return s
    }

    static func parse(_ data: Data) -> IdvAppVersion? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data), let item = r.results.first,
              let v = item.version, !v.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        let date: Date? = item.currentVersionReleaseDate.flatMap { iso.date(from: $0) }
        var url: String = item.trackViewUrl ?? pageURL
        if !url.hasPrefix("https://") { url = pageURL }
        return IdvAppVersion(version: v, released: date, notes: summary(item.releaseNotes ?? ""), url: url)
    }
}

// MARK: 第五録の新着（見出しと日付だけ）

struct IdvHeadline: Codable, Identifiable, Equatable {
    var title: String
    var date: Date?
    var link: String

    var id: String { link + "#" + title }
    var url: URL? {
        guard let u = URL(string: link), u.scheme == "https" else { return nil }
        return u
    }
}

enum IdvDaigoroku {
    static let name = "第五録"
    static let topURL = "https://daigoroku.com/"
    /// 「最新アップデート情報」の一覧（週ごとに「2026.9.30現在」と見出しが並ぶ）
    static let listURL = URL(string: "https://daigoroku.com/honntai/saisinn/saisinn.html")
    /// 読むのは6時間に1回まで（引っぱって更新しても）
    static let minInterval: TimeInterval = 6 * 3600
    static let userAgent = "Hiyori/0.3 (iOS personal app; reads headlines and dates only, at most every 6 hours)"

    private static func re(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    private static let blockRE = re("<article[^>]*update-item[^>]*>([\\s\\S]*?)</article>")
    private static let dateRE = re("<h3[^>]*>\\s*(\\d{4})[.．/年](\\d{1,2})[.．/月](\\d{1,2})")
    private static let h2RE = re("<h2[^>]*>([\\s\\S]*?)</h2>")
    private static let hrefRE = re("<a[^>]*href=\"([^\"]+)\"")

    static func due(lastFetch: Date?, now: Date = .now) -> Bool {
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= minInterval
    }

    /// 一覧の HTML から見出しと日付だけを取り出す（本文・画像は取らない）。最大 limit 件
    static func parseListing(_ html: String, base: URL, limit: Int = 15) -> [IdvHeadline] {
        guard let blockRE, let dateRE, let h2RE, let hrefRE else { return [] }
        let ns = html as NSString
        let f = Calendar.current
        var out: [IdvHeadline] = []
        for b in blockRE.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let block = ns.substring(with: b.range(at: 1))
            let bns = block as NSString
            let all = NSRange(location: 0, length: bns.length)
            var date: Date? = nil
            if let d = dateRE.firstMatch(in: block, range: all) {
                let y = Int(bns.substring(with: d.range(at: 1))) ?? 0
                let m = Int(bns.substring(with: d.range(at: 2))) ?? 0
                let day = Int(bns.substring(with: d.range(at: 3))) ?? 0
                date = f.date(from: DateComponents(year: y, month: m, day: day))
            }
            let heads = h2RE.matches(in: block, range: all)
            for (i, h) in heads.enumerated() {
                var title = bns.substring(with: h.range(at: 1))
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                title = InfoFeedParser.unescape(title)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                if title.count > 80 { title = String(title.prefix(79)) + "…" }
                // 次の見出しまでにある最初のリンク（サイトの中のものだけ）。無ければ一覧のページ
                let from = h.range.location + h.range.length
                let to = i + 1 < heads.count ? heads[i + 1].range.location : bns.length
                var link = base.absoluteString
                if let a = hrefRE.firstMatch(in: block, range: NSRange(location: from, length: max(0, to - from))) {
                    let href = bns.substring(with: a.range(at: 1))
                    if let u = URL(string: href, relativeTo: base)?.absoluteURL, u.scheme == "https", u.host == base.host {
                        link = u.absoluteString
                    }
                }
                out.append(IdvHeadline(title: title, date: date, link: link))
                if out.count >= limit { return out }
            }
        }
        return out
    }
}

// MARK: 取得の時刻（「公式・3時間前」）

enum IdvFresh {
    static func ago(_ d: Date, now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 60 { return "たった今" }
        if s < 3600 { return "\(s / 60)分前" }
        if s < 86400 { return "\(s / 3600)時間前" }
        return "\(s / 86400)日前"
    }

    /// 「公式・3時間前」。読めなかったときは「・更新できませんでした」を足す
    static func label(_ source: String, _ at: Date?, failed: Bool = false, now: Date = .now) -> String {
        var s = source + "・" + (at.map { ago($0, now: now) } ?? "未取得")
        if failed { s += "・更新できませんでした" }
        return s
    }
}

// MARK: 残り時間（期限のバッジ）

enum IdvCountdown {
    /// 終わる日の 23:59 まで。1日を切ったら「残り◯時間」、明日までなら「残り1日」
    static func text(end: Date, now: Date = .now) -> String {
        let n = IdvDates.daysLeft(end, now: now)
        if n < 0 { return "終了" }
        if n == 0 {
            let cal = Calendar.current
            let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end
            let h = Int(dayEnd.timeIntervalSince(now) / 3600)
            return h >= 1 ? "残り\(h)時間" : "まもなく終了"
        }
        if n == 1 { return "残り1日" }
        return "あと\(n)日"
    }

    /// 赤く強調するか（残り1日まで）
    static func isLastDay(end: Date, now: Date = .now) -> Bool {
        let n = IdvDates.daysLeft(end, now: now)
        return n >= 0 && n <= 1
    }
}

// MARK: 大会の配信（公式 YouTube の題名から）

enum IdvMatches {
    static let channelURL = "https://www.youtube.com/@identityvjp"
    private static let words = ["IJL", "IVC", "COA", "IVL", "大会", "決勝"]

    static func isTournament(_ title: String) -> Bool {
        let t = IdvDates.normalize(title).uppercased()
        return words.contains { t.contains($0) }
    }

    /// 公式チャンネルの動画のうち大会のもの（新しい順・最大3件）
    static func broadcasts(_ news: [IdvNews]) -> [IdvNews] {
        Array(news.filter { $0.kind == .video && isTournament($0.title) }.prefix(3))
    }
}
