import Foundation
import UserNotifications

// MARK: - 第五人格（公式のお知らせ・イベントやシーズンの期限）
// 公式のお知らせ：
// - 公式サイト（identityv.jp）のお知らせ一覧は静的な HTML で、2023年から更新が止まっている（RSS・JSON もない）ので使わない
// - 代わりに公式 YouTube チャンネル（@identityvjp）の RSS と、運営（NetEase Games）の PR TIMES のプレスリリース RSS を読む
//   PR TIMES は会社のすべてのゲームが入るので、題名に「第五人格」「Identity」があるものだけ残す
// - いまの公式サイト（identityvgame.com/jp）のアップデート情報の一覧も読む（予定・シーズン。IdvSchedule.swift）
// 期限：自分で足したもの（題名と終わる日）と、お知らせの題名・説明文・本文にある「開催期間」や日付の範囲から見つけたもの
// 通知：設定でオンにしたときだけ（既定はオフ）。メンテナンスの前の日の 19:00、期限の残り1日、シーズン終了の3日前（どれも idv- で始まる）
// ランクマッチ・対戦情報・アプリの版・第五録の新着は IdvPlay.swift
// 戦績は扱わない（決定済み）。起動引数 -demo では通信せず、架空のお知らせを出す

struct IdvNews: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case video, press, official }

    var title: String
    var link: String
    var date: Date?
    var kind: Kind
    var image: String?
    /// RSS の説明文（PR TIMES は120字ほどで切れている）
    var summary: String? = nil

    var id: String { link }
    var url: URL? {
        guard let u = URL(string: link), u.scheme == "https" else { return nil }
        return u
    }
}

struct IdvEvent: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var end: Date                   // 終わる日（その日の終わりまで）
    var link: String?
    /// 始まる日（コラボ・ガチャ。分かるときだけ）
    var start: Date? = nil
    /// 「コラボ」「ガチャ」（題名から）
    var tag: String? = nil

    var label: String { tag == nil ? IdvDates.label(end) : IdvCollab.label(start: start, end: end) }
}

enum IdvFeed {
    /// 公式 YouTube チャンネル（『IdentityV 第五人格』公式チャンネル @identityvjp）
    static let youtubeChannelID = "UCo5pHsgk0RaUek1ORd0PyXA"
    static var youtubeURL: URL? { URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(youtubeChannelID)") }
    /// 運営のプレスリリース（PR TIMES・NetEase Games）
    static let pressURL = URL(string: "https://prtimes.jp/companyrdf.php?company_id=71247")
    /// 公式 X アカウントの投稿の検索
    static let xURL = URL(string: "https://x.com/search?q=from%3AIdentityVJP&f=live")

    static let keywords = ["第五人格", "identity v", "identityv", "identityｖ", "ｉｄｅｎｔｉｔｙ"]

    static func isIdentityV(_ title: String) -> Bool {
        let t = title.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        if t.contains("第五人格") { return true }
        return t.contains("identityv") || t.contains("identityⅴ") || t.contains("identityｖ") || t.contains("ｉｄｅｎｔｉｔｙ")
    }

    /// RSS／Atom を読んで、お知らせにする（press は第五人格のものだけ）
    static func parse(_ data: Data, kind: IdvNews.Kind) -> [IdvNews] {
        let items = InfoFeedParser.parse(data, source: kind.rawValue)
        return items.compactMap { a in
            guard a.link.hasPrefix("https://") else { return nil }
            if kind == .press && !isIdentityV(a.title) { return nil }
            var image: String? = a.image
            if kind == .video, image == nil, let vid = videoID(a.link) {
                image = "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg"
            }
            return IdvNews(title: a.title, link: a.link, date: a.published, kind: kind, image: image, summary: a.summary)
        }
    }

    static func videoID(_ link: String) -> String? {
        guard let c = URLComponents(string: link) else { return nil }
        return c.queryItems?.first { $0.name == "v" }?.value
    }

    /// 読めなかった元は failed に名前（"video"・"press"）を入れる
    static func fetchAll() async -> (news: [IdvNews], failed: [String]) {
        var out: [IdvNews] = []
        var failed: [String] = []
        let sources: [(URL?, IdvNews.Kind)] = [(youtubeURL, .video), (pressURL, .press)]
        for (u, kind) in sources {
            guard let u else { continue }
            do {
                let data = try await InfoFetcher.get(u)
                out += parse(data, kind: kind)
            } catch {
                failed.append(kind.rawValue)
            }
        }
        return (out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }, failed)
    }
}

// MARK: - 題名から期間を見つける

enum IdvDates {
    struct Range: Equatable {
        var start: Date?
        var end: Date
    }

    /// 全角の数字・記号を半角に
    static func normalize(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch.value {
            case 0xFF10...0xFF19: out.unicodeScalars.append(Unicode.Scalar(ch.value - 0xFF10 + 0x30)!)
            case 0xFF0F: out += "/"
            case 0xFF1A: out += ":"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    private static let tilde = "[～〜~\\-－–—]"
    /// 「9月3日メンテナンス後から9月10日メンテナンス前まで」のような「から」も、月日の形のときだけ範囲とみなす
    private static let tildeJP = "(?:[～〜~\\-－–—]|から)"

    /// 年のない月日は reference の年（月がずっと前なら翌年）
    static func day(_ y: Int?, _ m: Int, _ d: Int, reference: Date) -> Date? {
        let cal = Calendar.current
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        var year = y ?? cal.component(.year, from: reference)
        if y == nil && m < cal.component(.month, from: reference) - 6 { year += 1 }
        return cal.date(from: DateComponents(year: year, month: m, day: d))
    }

    /// 例：「10月10日（金）～10月24日（金）」「10/10～10/24」「開催期間：10月24日まで」
    /// reference（お知らせの日付）の年を使い、月がずっと前なら翌年とみなす
    static func range(in title: String, reference: Date) -> Range? {
        let t = normalize(title)
        let cal = Calendar.current
        let refYear = cal.component(.year, from: reference)
        let refMonth = cal.component(.month, from: reference)

        func make(_ y: Int?, _ m: Int, _ d: Int, after: Date? = nil) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            var year = y ?? refYear
            if y == nil && m < refMonth - 6 { year += 1 }
            guard var date = cal.date(from: DateComponents(year: year, month: m, day: d)) else { return nil }
            if let a = after, date < a, y == nil, let next = cal.date(byAdding: .year, value: 1, to: date) { date = next }
            return date
        }

        let patterns: [String] = [
            "(?:(\\d{4})年)?(\\d{1,2})月(\\d{1,2})日[^～〜~\\-－–—]{0,14}?\(tildeJP)\\s*(?:(\\d{4})年)?(?:(\\d{1,2})月)?(\\d{1,2})日(?!間)",
            "(?:(\\d{4})/)?(\\d{1,2})/(\\d{1,2})[^～〜~\\-－–—/\\d]{0,14}?\(tilde)\\s*(?:(\\d{4})/)?(?:(\\d{1,2})/)?(\\d{1,2})(?!\\d)",
        ]
        for p in patterns {
            guard let g = groups(p, t) else { continue }
            let sy = Int(g[0]), sm = Int(g[1]) ?? 0, sd = Int(g[2]) ?? 0
            let ey = Int(g[3]), em = Int(g[4]) ?? sm, ed = Int(g[5]) ?? 0
            guard let s = make(sy, sm, sd), let e = make(ey ?? sy, em, ed, after: s) else { continue }
            return Range(start: s, end: e)
        }
        // 「開催期間」や「まで」：いちばん最後の日付を終わりの日とする
        guard t.contains("開催期間") || t.contains("まで") else { return nil }
        let single = "(?:(\\d{4})年)?(\\d{1,2})月(\\d{1,2})日|(?:(\\d{4})/)?(\\d{1,2})/(\\d{1,2})"
        guard let re = try? NSRegularExpression(pattern: single) else { return nil }
        let ns = t as NSString
        guard let m = re.matches(in: t, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        func part(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        let jp = !part(2).isEmpty
        let y = Int(jp ? part(1) : part(4))
        let mo = Int(jp ? part(2) : part(5)) ?? 0
        let d = Int(jp ? part(3) : part(6)) ?? 0
        guard let e = make(y, mo, d) else { return nil }
        return Range(start: nil, end: e)
    }

    /// 最初に合ったものの各グループ（無いグループは ""）
    private static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i))
        }
    }

    /// 終わる日まで、あと何日か（今日が終わる日なら 0、過ぎていればマイナス）
    static func daysLeft(_ end: Date, now: Date = .now) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day ?? 0
    }

    static func label(_ end: Date, now: Date = .now) -> String {
        let n = daysLeft(end, now: now)
        if n < 0 { return "終了" }
        if n == 0 { return "今日まで" }
        return "あと\(n)日"
    }

    /// ニュースから見つけた期限（まだ終わっていないもの）
    /// 題名に期間がなければ、説明文・読んだ本文（articles）の「期間」から探す。コラボ・ガチャは題名で印を付け、始まる日も持つ
    static func candidates(_ news: [IdvNews], articles: [String: String] = [:], now: Date = .now) -> [IdvEvent] {
        news.compactMap { n in
            guard n.kind != .official else { return nil }
            let ref = n.date ?? now
            var r = range(in: n.title, reference: ref)
            if r == nil, let s = n.summary { r = IdvCollab.periodRange(in: s, reference: ref) }
            if r == nil, let a = articles[n.link] { r = IdvCollab.periodRange(in: a, reference: ref) }
            guard let r, daysLeft(r.end, now: now) >= 0 else { return nil }
            return IdvEvent(id: "news-" + n.link, title: n.title, end: r.end, link: n.link, start: r.start, tag: IdvCollab.tag(n.title))
        }
    }
}

// MARK: - 通知（idv-。設定でオンにしたときだけ。既定はオフ）
// - メンテナンスの前の日の 19:00
// - ガチャ・コラボ・登録した期限の「残り1日」（終わる日の前日 19:00）
// - ランクマッチのシーズン終了の3日前 19:00

enum IdvReminder {
    /// 通知を使うか（設定のスイッチ。既定はオフ）
    static let enabledKey = "idvNotify"

    /// 終わる日の前日 19:00（過ぎていれば出さない）
    static func fireDate(_ end: Date, now: Date = .now) -> Date? {
        fireDate(end, daysBefore: 1, now: now)
    }

    /// 終わる日の daysBefore 日前の 19:00
    static func fireDate(_ end: Date, daysBefore: Int, now: Date = .now) -> Date? {
        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -daysBefore, to: cal.startOfDay(for: end)),
              let at = cal.date(bySettingHour: 19, minute: 0, second: 0, of: dayBefore), at > now else { return nil }
        return at
    }

    /// メンテナンスの前の日の 19:00
    static func maintenanceFireDate(_ s: IdvScheduleItem, now: Date = .now) -> Date? {
        guard s.kind == .maintenance, !s.isPast(now: now) else { return nil }
        return fireDate(s.start, daysBefore: 1, now: now)
    }

    struct Planned: Equatable {
        var id: String
        var title: String
        var body: String
        var at: Date
    }

    /// 出す通知の一覧（テストしやすいように、組み立てだけ分ける）
    /// events：登録した期限、periods：公式の本文から見つけた期間（ガチャ・コラボだけ使う）
    static func plan(events: [IdvEvent], periods: [IdvPeriod] = [], schedule: [IdvScheduleItem], season: IdvSeason?,
                     now: Date = .now) -> [Planned] {
        var out: [Planned] = []
        var titles = Set<String>()
        let fromOfficial: [IdvEvent] = periods.filter { $0.kind == .gacha || $0.kind == .collab }.map(\.asEvent)
        let deadlines: [IdvEvent] = (events + fromOfficial).filter { titles.insert($0.title).inserted }
        for e in deadlines.sorted(by: { $0.end < $1.end }) {
            guard out.count < 10, let at = fireDate(e.end, now: now) else { continue }
            out.append(Planned(id: "idv-\(e.id)", title: "残り1日：\(e.title)", body: "第五人格：\(JP.date(e.end))で終わります", at: at))
        }
        var maintenance = 0
        for s in schedule.sorted(by: { $0.start < $1.start }) {
            guard maintenance < 3, let at = maintenanceFireDate(s, now: now) else { continue }
            maintenance += 1
            let time: String = s.hasTime ? " \(JP.time(s.start))から" : ""
            out.append(Planned(id: "idv-mnt-\(Int(s.start.timeIntervalSince1970))", title: "明日はメンテナンス",
                               body: "第五人格：\(JP.date(s.start))\(time)（\(s.title)）", at: at))
        }
        if let season, let end = season.end, let at = fireDate(end, daysBefore: 3, now: now) {
            out.append(Planned(id: "idv-season-3", title: "ランクマ \(season.title) 終了まであと3日",
                               body: "\(JP.date(end))でランクマッチのシーズンが終わります", at: at))
        }
        return out
    }

    /// idv- の通知を消してから、オンのときだけ組み直す
    static func reschedule(enabled: Bool, events: [IdvEvent], periods: [IdvPeriod], schedule: [IdvScheduleItem],
                           season: IdvSeason?) async {
        guard !LaunchArguments.isScripted else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("idv-") })
        guard enabled else { return }
        for p in plan(events: events, periods: periods, schedule: schedule, season: season) {
            let c = UNMutableNotificationContent()
            c.title = p.title
            c.body = p.body
            c.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.at)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - 状態

/// App Store・第五録の結果と、元ごとの取得時刻（idv-play.json）
struct IdvPlayCache: Codable, Equatable {
    var app: IdvAppVersion? = nil
    var headlines: [IdvHeadline] = []
    /// 元（IdvSource）→ 最後に読めた時刻
    var fetchedAt: [String: Date] = [:]
    /// 元 → 最後に読みに行った時刻（読めなくても。第五録・App Store を何度も読みに行かないため）
    var triedAt: [String: Date] = [:]
    /// 最後に読みに行って、読めなかった元
    var failed: [String] = []
}

enum IdvSource {
    static let official = "official"
    static let video = "video"
    static let press = "press"
    static let app = "app"
    static let daigoroku = "daigoroku"
}

@MainActor
final class IdvStore: ObservableObject {
    static let shared = IdvStore()
    private static let eventsFile = "idv-events.json"
    private static let newsFile = "idv-news.json"
    private static let officialFile = "idv-official.json"
    /// 見出しの行も読むようにしたので、前の版（idv-articles.json）は読み直す
    private static let articlesFile = "idv-articles-v2.json"
    private static let periodsFile = "idv-periods.json"
    private static let seasonFile = "idv-season.json"
    private static let playFile = "idv-play.json"

    @Published private(set) var news: [IdvNews] = []
    /// 公式サイトのアップデート情報（一覧）
    @Published private(set) var official: [IdvNews] = []
    /// 読んだ記事の本文（リンク → 日付のある行だけ）
    @Published private(set) var articles: [String: String] = [:]
    /// 公式の本文から見つけた期間（リンク → 期間）
    @Published private(set) var periods: [String: [IdvPeriod]] = [:]
    @Published private(set) var events: [IdvEvent] = []
    @Published private(set) var schedule: [IdvScheduleItem] = []
    @Published private(set) var detectedSeason: IdvSeason? = nil
    @Published private(set) var seasonOverride = IdvSeasonOverride()
    @Published private(set) var rank = IdvRankInfo()
    @Published private(set) var play = IdvPlayCache()
    @Published private(set) var notifyEnabled: Bool = false
    @Published private(set) var loading = false
    @Published private(set) var error: String? = nil
    @Published private(set) var updatedAt: Date? = nil

    let isDemo = InfoLaunch.isDemo

    private init() {
        if isDemo {
            news = IdvDemo.news()
            events = IdvDemo.events()
            schedule = IdvDemo.schedule()
            detectedSeason = IdvDemo.season()
            periods = ["demo": IdvDemo.periods()]
            rank = IdvDemo.rank()
            play = IdvDemo.play()
            updatedAt = .now
        } else {
            news = SplatFiles.load([IdvNews].self, Self.newsFile) ?? []
            official = SplatFiles.load([IdvNews].self, Self.officialFile) ?? []
            articles = SplatFiles.load([String: String].self, Self.articlesFile) ?? [:]
            periods = SplatFiles.load([String: [IdvPeriod]].self, Self.periodsFile) ?? [:]
            events = SplatFiles.load([IdvEvent].self, Self.eventsFile) ?? []
            seasonOverride = SplatFiles.load(IdvSeasonOverride.self, Self.seasonFile) ?? IdvSeasonOverride()
            play = SplatFiles.load(IdvPlayCache.self, Self.playFile) ?? IdvPlayCache()
            notifyEnabled = UserDefaults.standard.bool(forKey: IdvReminder.enabledKey)
            recompute()
        }
    }

    /// 今のシーズン（手動の上書きがあればそれ）
    var season: IdvSeason? { seasonOverride.season ?? detectedSeason }

    /// まだ終わっていない公式の期間
    var currentPeriods: [IdvPeriod] { IdvArticle.current(periods.values.flatMap { $0 }) }
    var modes: [IdvPeriod] { currentPeriods.filter { $0.kind == .mode } }
    /// 大会は終わって7日までのものも出す
    var tournaments: [IdvPeriod] {
        let all: [IdvPeriod] = periods.values.flatMap { $0 }.filter { $0.kind == .tournament && IdvDates.daysLeft($0.end) >= -7 }
        var seen = Set<String>()
        return all.sorted { $0.end > $1.end }.filter { seen.insert($0.title).inserted }
    }
    var broadcasts: [IdvNews] { IdvMatches.broadcasts(news) }
    var nextMaintenance: IdvScheduleItem? { IdvSchedule.nextMaintenanceItem(schedule) }
    /// いちばん新しい公式のアップデートのお知らせ
    var latestOfficial: IdvNews? { official.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) } }

    /// 「公式・3時間前」（読めなかったら「・更新できませんでした」）
    func fresh(_ source: String) -> String {
        let name: String
        switch source {
        case IdvSource.app: name = "App Store"
        case IdvSource.daigoroku: name = IdvDaigoroku.name
        case IdvSource.video: name = "公式YouTube"
        default: name = "公式"
        }
        return IdvFresh.label(name, play.fetchedAt[source], failed: play.failed.contains(source))
    }

    /// 期限の近い順（終わったものは後ろ）
    var sortedEvents: [IdvEvent] {
        events.sorted { a, b in
            let da = IdvDates.daysLeft(a.end), db = IdvDates.daysLeft(b.end)
            if (da < 0) != (db < 0) { return da >= 0 }
            return a.end < b.end
        }
    }

    /// ニュースと公式の本文から見つけたもの（まだ足していないもの）
    var suggestions: [IdvEvent] {
        let haveLinks = Set(events.compactMap(\.link))
        var haveTitles = Set(events.map(\.title))
        let fromNews: [IdvEvent] = IdvDates.candidates(news, articles: articles).filter { !haveLinks.contains($0.link ?? "") }
        for e in fromNews { haveTitles.insert(e.title) }
        let fromOfficial: [IdvEvent] = currentPeriods.filter { $0.kind == .gacha || $0.kind == .collab }.map(\.asEvent)
            .filter { haveTitles.insert($0.title).inserted }
        return (fromNews + fromOfficial).sorted { $0.end < $1.end }
    }

    var nextEvent: IdvEvent? { sortedEvents.first { IdvDates.daysLeft($0.end) >= 0 } }

    func refreshIfNeeded() async {
        guard !isDemo else { return }
        if let u = updatedAt, Date.now.timeIntervalSince(u) < 1800 { return }
        await refresh()
    }

    private func due(_ source: String, every interval: TimeInterval) -> Bool {
        guard let t = play.triedAt[source] else { return true }
        return Date.now.timeIntervalSince(t) >= interval
    }

    func refresh() async {
        guard !isDemo, !loading else { return }
        loading = true
        defer { loading = false }
        var tried = Set<String>()
        var failed = Set<String>()
        func mark(_ source: String, ok: Bool) {
            tried.insert(source)
            play.triedAt[source] = .now
            if ok { play.fetchedAt[source] = .now } else { failed.insert(source) }
        }

        let r = await IdvFeed.fetchAll()
        mark(IdvSource.video, ok: !r.failed.contains(IdvSource.video))
        mark(IdvSource.press, ok: !r.failed.contains(IdvSource.press))
        if !r.news.isEmpty {
            news = Array(r.news.prefix(40))
            SplatFiles.save(news, Self.newsFile)
        }
        // 公式サイトの一覧は1時間に1回まで
        if due(IdvSource.official, every: 3600) {
            if let u = IdvOfficial.updateListURL, let data = try? await InfoFetcher.get(u) {
                let list = IdvOfficial.parseList(String(decoding: data, as: UTF8.self))
                if !list.isEmpty {
                    official = Array(list.prefix(20))
                    SplatFiles.save(official, Self.officialFile)
                }
                mark(IdvSource.official, ok: !list.isEmpty)
            } else {
                mark(IdvSource.official, ok: false)
            }
        }
        await fetchArticles()
        // App Store は6時間に1回まで
        if due(IdvSource.app, every: 6 * 3600), let u = IdvAppStore.lookupURL {
            let data: Data? = try? await InfoFetcher.get(u)
            let v: IdvAppVersion? = data.flatMap { IdvAppStore.parse($0) }
            if let v { play.app = v }
            mark(IdvSource.app, ok: v != nil)
        }
        // 第五録は6時間に1回まで（見出しと日付だけ）
        if due(IdvSource.daigoroku, every: IdvDaigoroku.minInterval), let u = IdvDaigoroku.listURL {
            let data: Data? = try? await InfoFetcher.get(u, userAgent: IdvDaigoroku.userAgent)
            let list: [IdvHeadline] = data.map { IdvDaigoroku.parseListing(String(decoding: $0, as: UTF8.self), base: u) } ?? []
            if !list.isEmpty { play.headlines = list }
            mark(IdvSource.daigoroku, ok: !list.isEmpty)
        }
        // 今回読みに行かなかった元は、前の結果のまま
        play.failed = Array(Set(play.failed).subtracting(tried).union(failed)).sorted()
        SplatFiles.save(play, Self.playFile)

        let feedFailed: Int = [IdvSource.video, IdvSource.press, IdvSource.official].filter { failed.contains($0) }.count
        error = feedFailed >= 3 ? "お知らせを更新できませんでした。前に読んだものを表示しています。"
            : (feedFailed > 0 ? "一部のお知らせを更新できませんでした。" : nil)
        updatedAt = .now
        recompute()
        await reschedule()
    }

    /// 本文が要るものだけ記事を読む（1回の更新で最大5件。読んだものは残す）
    /// 公式のお知らせは、見出しと期間の組（periods）も作る
    private func fetchArticles() async {
        let all: [IdvNews] = official + news
        let cached = Set(articles.keys.filter { link in
            all.first { $0.link == link }?.kind != .official || periods[link] != nil
        })
        let todo = IdvOfficial.articlesToFetch(news: all, cached: cached)
        guard !todo.isEmpty else { return }
        for n in todo {
            guard let u = n.url, let data = try? await InfoFetcher.get(u) else { continue }
            let lines: [String] = IdvArticle.lines(fromHTML: String(decoding: data, as: UTF8.self))
            articles[n.link] = IdvOfficial.text(lines: lines)
            if n.kind == .official {
                periods[n.link] = IdvArticle.periods(lines: lines, link: n.link, reference: n.date ?? .now)
            }
        }
        // 今の一覧にないものは捨てる
        let keep = Set(all.map(\.link))
        articles = articles.filter { keep.contains($0.key) }
        periods = periods.filter { keep.contains($0.key) }
        SplatFiles.save(articles, Self.articlesFile)
        SplatFiles.save(periods, Self.periodsFile)
    }

    private func recompute() {
        schedule = IdvSchedule.items(news: official + news, articles: articles)
        detectedSeason = IdvSeasonParser.resolve(updates: official, articles: articles, news: news)
        rank = IdvRank.info(updates: official, articles: articles)
    }

    func setOverride(_ o: IdvSeasonOverride) {
        seasonOverride = o
        guard !isDemo else { return }
        SplatFiles.save(o, Self.seasonFile)
        rescheduleAll()
    }

    func add(_ e: IdvEvent) {
        events.removeAll { $0.id == e.id }
        events.append(e)
        persist()
    }

    func remove(_ e: IdvEvent) {
        events.removeAll { $0.id == e.id }
        persist()
    }

    /// 設定のスイッチ。オンにしたときだけ通知の許可を聞く
    func setNotify(_ on: Bool) {
        notifyEnabled = on
        guard !isDemo else { return }
        UserDefaults.standard.set(on, forKey: IdvReminder.enabledKey)
        Task {
            if on, !LaunchArguments.isScripted {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
            await reschedule()
        }
    }

    /// 画面を開いたとき：通知を組み直す（オフなら idv- を消すだけ。許可はスイッチを入れたときに聞く）
    func prepareNotifications() async {
        guard !isDemo, !LaunchArguments.isScripted else { return }
        await reschedule()
    }

    private func reschedule() async {
        guard !isDemo else { return }
        await IdvReminder.reschedule(enabled: notifyEnabled, events: events, periods: currentPeriods, schedule: schedule, season: season)
    }

    private func persist() {
        guard !isDemo else { return }
        SplatFiles.save(events, Self.eventsFile)
        rescheduleAll()
    }

    private func rescheduleAll() {
        guard !isDemo else { return }
        Task { await reschedule() }
    }
}

// MARK: - 見本（-demo。架空のお知らせ・予定・シーズン）

enum IdvDemo {
    private static func md(_ days: Int, _ now: Date) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: days, to: now) ?? now
        return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日"
    }

    static func news(now: Date = .now) -> [IdvNews] {
        func md(_ days: Int) -> String { Self.md(days, now) }
        return [
            IdvNews(title: "（見本）秋の特別イベント「月夜の舞踏会」開催期間：\(md(-3))～\(md(9))", link: "https://www.identityv.jp/",
                    date: now.addingTimeInterval(-3600 * 5), kind: .video, image: nil),
            IdvNews(title: "（見本）架空の物語とのコラボ 開催期間：\(md(5))～\(md(26))", link: "https://www.identityv.jp/#news4",
                    date: now.addingTimeInterval(-3600 * 9), kind: .press, image: nil),
            IdvNews(title: "（見本）新衣装の紹介映像を公開しました", link: "https://www.identityv.jp/#news1",
                    date: now.addingTimeInterval(-86400), kind: .video, image: nil),
            IdvNews(title: "（見本）復刻ガチャ「夜想の仮面」\(md(-2))～\(md(6))", link: "https://www.identityv.jp/#news2",
                    date: now.addingTimeInterval(-86400 * 2), kind: .press, image: nil),
            IdvNews(title: "（見本）期間限定ショップ \(md(-1))～\(md(4))", link: "https://www.identityv.jp/#news3",
                    date: now.addingTimeInterval(-86400 * 3), kind: .press, image: nil),
        ]
    }

    static func events(now: Date = .now) -> [IdvEvent] {
        let cal = Calendar.current
        return [
            IdvEvent(id: "demo-2", title: "（見本）推理の径 第3章", end: cal.date(byAdding: .day, value: 16, to: now) ?? now, link: nil, tag: "ガチャ"),
            IdvEvent(id: "demo-3", title: "（見本）衣装の人気投票", end: cal.date(byAdding: .day, value: 2, to: now) ?? now, link: nil),
        ]
    }

    static func schedule(now: Date = .now) -> [IdvScheduleItem] {
        let cal = Calendar.current
        func at(_ days: Int, _ h: Int, _ m: Int = 0) -> Date {
            let d = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
            return cal.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
        }
        let items: [IdvScheduleItem] = [
            IdvScheduleItem(id: "demo-m1", kind: .maintenance, title: "（見本）定期メンテナンス", start: at(2, 9), end: at(2, 13),
                            hasTime: true, link: nil),
            IdvScheduleItem(id: "demo-u1", kind: .update, title: "（見本）バージョン更新：新しい荘園マップ", start: at(9, 9), end: nil,
                            hasTime: true, link: nil),
            IdvScheduleItem(id: "demo-m2", kind: .maintenance, title: "（見本）臨時メンテナンス", start: at(16, 0), end: nil,
                            hasTime: false, link: nil),
            IdvScheduleItem(id: "demo-m0", kind: .maintenance, title: "（見本）定期メンテナンス", start: at(-5, 9), end: at(-5, 12, 30),
                            hasTime: true, link: nil),
        ]
        return IdvSchedule.sorted(items, now: now)
    }

    static func season(now: Date = .now) -> IdvSeason {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -44, to: cal.startOfDay(for: now)) ?? now
        let end = cal.date(byAdding: .day, value: 19, to: cal.startOfDay(for: now)) ?? now
        return IdvSeason(number: 12, name: "シーズン12", start: start, end: end, source: "見本", link: nil)
    }

    static func periods(now: Date = .now) -> [IdvPeriod] {
        let cal = Calendar.current
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now)) ?? now }
        let link = "https://www.identityvgame.com/jp/news/update/"
        return [
            IdvPeriod(kind: .mode, section: "娯楽モード", title: "（見本）期間限定モード 2V8", start: day(-4), end: day(10), link: link),
            IdvPeriod(kind: .mode, section: "娯楽モード", title: "（見本）闘争の部屋", start: day(-1), end: day(1), link: link),
            IdvPeriod(kind: .tournament, section: "大会", title: "（見本）秋季大会 決勝戦", start: day(5), end: day(6), link: link),
            IdvPeriod(kind: .gacha, section: "シーズン真髄", title: "（見本）シーズン真髄2", start: day(-13), end: day(1), link: link),
            IdvPeriod(kind: .collab, section: "ショップ", title: "（見本）架空の物語コラボ衣装", start: day(-6), end: day(17), link: link),
        ]
    }

    static func rank() -> IdvRankInfo {
        IdvRankInfo(windows: [IdvRankWindow(label: "ランク戦", start: 12 * 60, end: 14 * 60),
                              IdvRankWindow(label: "ランク戦", start: 19 * 60, end: 24 * 60)],
                    closedDuringMaintenance: true,
                    notes: ["（見本）新しいシーズンが始まると、前のシーズンの最終段位をもとに段位が継承されます。"],
                    link: nil)
    }

    static func play(now: Date = .now) -> IdvPlayCache {
        let cal = Calendar.current
        func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
        let listing = "https://daigoroku.com/"
        let days: [Date] = [0, 7, 14].map { cal.date(byAdding: .day, value: -($0 + 2), to: cal.startOfDay(for: now)) ?? now }
        let heads: [IdvHeadline] = [
            IdvHeadline(title: "（見本）新しいサバイバーが登場", date: days[0], link: listing),
            IdvHeadline(title: "（見本）シーズン真髄の新衣装まとめ", date: days[0], link: listing),
            IdvHeadline(title: "（見本）秋のバージョンイベント開催", date: days[1], link: listing),
            IdvHeadline(title: "（見本）キャラ調整の内容", date: days[2], link: listing),
        ]
        let app = IdvAppVersion(version: "1.0.0（見本）", released: cal.date(byAdding: .day, value: -5, to: now),
                                notes: "（見本）一部の不具合を修正しました", url: IdvAppStore.pageURL)
        return IdvPlayCache(app: app, headlines: heads,
                            fetchedAt: [IdvSource.official: ago(3), IdvSource.video: ago(3), IdvSource.press: ago(3),
                                        IdvSource.app: ago(2), IdvSource.daigoroku: ago(26)],
                            triedAt: [:], failed: [])
    }
}
