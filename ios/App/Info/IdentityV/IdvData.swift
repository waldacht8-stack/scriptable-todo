import Foundation
import UserNotifications

// MARK: - 第五人格（公式のお知らせ・イベントやシーズンの期限）
// 公式のお知らせ：
// - 公式サイト（identityv.jp）のお知らせ一覧は静的な HTML で、2023年から更新が止まっている（RSS・JSON もない）ので使わない
// - 代わりに公式 YouTube チャンネル（@identityvjp）の RSS と、運営（NetEase Games）の PR TIMES のプレスリリース RSS を読む
//   PR TIMES は会社のすべてのゲームが入るので、題名に「第五人格」「Identity」があるものだけ残す
// - いまの公式サイト（identityvgame.com/jp）のアップデート情報の一覧も読む（予定・シーズン。IdvSchedule.swift）
// 期限：自分で足したもの（題名と終わる日）と、お知らせの題名・説明文・本文にある「開催期間」や日付の範囲から見つけたもの
// 通知：終わる日の前日 19:00、メンテナンスの1時間前、シーズン終了の3日前と前日の 19:00（どれも idv- で始まる）
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

    static func fetchAll() async -> (news: [IdvNews], failed: Int) {
        var out: [IdvNews] = []
        var failed = 0
        let sources: [(URL?, IdvNews.Kind)] = [(youtubeURL, .video), (pressURL, .press)]
        for (u, kind) in sources {
            guard let u else { continue }
            do {
                let data = try await InfoFetcher.get(u)
                out += parse(data, kind: kind)
            } catch {
                failed += 1
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

// MARK: - 通知（idv-）：期限の前日・メンテナンスの1時間前・シーズン終了の3日前と前日

enum IdvReminder {
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

    /// メンテナンスの始まる1時間前（時刻が分かるメンテナンスだけ）
    static func maintenanceFireDate(_ s: IdvScheduleItem, now: Date = .now) -> Date? {
        guard s.kind == .maintenance, s.hasTime else { return nil }
        let at = s.start.addingTimeInterval(-3600)
        return at > now ? at : nil
    }

    struct Planned: Equatable {
        var id: String
        var title: String
        var body: String
        var at: Date
    }

    /// 出す通知の一覧（テストしやすいように、組み立てだけ分ける）
    static func plan(events: [IdvEvent], schedule: [IdvScheduleItem], season: IdvSeason?, now: Date = .now) -> [Planned] {
        var out: [Planned] = []
        for e in events.sorted(by: { $0.end < $1.end }).prefix(10) {
            guard let at = fireDate(e.end, now: now) else { continue }
            out.append(Planned(id: "idv-\(e.id)", title: "明日まで：\(e.title)", body: "第五人格のイベント・シーズンが明日で終わります", at: at))
        }
        var maintenance = 0
        for s in schedule {
            guard maintenance < 5, let at = maintenanceFireDate(s, now: now) else { continue }
            maintenance += 1
            out.append(Planned(id: "idv-mnt-\(Int(s.start.timeIntervalSince1970))", title: "1時間後にメンテナンス",
                               body: "第五人格：\(JP.time(s.start))から \(s.title)", at: at))
        }
        if let season, let end = season.end {
            for days in [3, 1] {
                guard let at = fireDate(end, daysBefore: days, now: now) else { continue }
                out.append(Planned(id: "idv-season-\(days)", title: "ランクマ \(season.title) 終了まであと\(days)日",
                                   body: "\(JP.date(end))でランクマッチのシーズンが終わります", at: at))
            }
        }
        return out
    }

    static func reschedule(events: [IdvEvent], schedule: [IdvScheduleItem], season: IdvSeason?) async {
        guard !LaunchArguments.isScripted else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("idv-") })
        for p in plan(events: events, schedule: schedule, season: season) {
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

@MainActor
final class IdvStore: ObservableObject {
    static let shared = IdvStore()
    private static let eventsFile = "idv-events.json"
    private static let newsFile = "idv-news.json"
    private static let officialFile = "idv-official.json"
    private static let articlesFile = "idv-articles.json"
    private static let seasonFile = "idv-season.json"

    @Published private(set) var news: [IdvNews] = []
    /// 公式サイトのアップデート情報（一覧）
    @Published private(set) var official: [IdvNews] = []
    /// 読んだ記事の本文（リンク → 日付のある行だけ）
    @Published private(set) var articles: [String: String] = [:]
    @Published private(set) var events: [IdvEvent] = []
    @Published private(set) var schedule: [IdvScheduleItem] = []
    @Published private(set) var detectedSeason: IdvSeason? = nil
    @Published private(set) var seasonOverride = IdvSeasonOverride()
    @Published private(set) var loading = false
    @Published private(set) var error: String? = nil
    @Published private(set) var updatedAt: Date? = nil
    private var officialAt: Date? = nil

    let isDemo = InfoLaunch.isDemo

    private init() {
        if isDemo {
            news = IdvDemo.news()
            events = IdvDemo.events()
            schedule = IdvDemo.schedule()
            detectedSeason = IdvDemo.season()
            updatedAt = .now
        } else {
            news = SplatFiles.load([IdvNews].self, Self.newsFile) ?? []
            official = SplatFiles.load([IdvNews].self, Self.officialFile) ?? []
            articles = SplatFiles.load([String: String].self, Self.articlesFile) ?? [:]
            events = SplatFiles.load([IdvEvent].self, Self.eventsFile) ?? []
            seasonOverride = SplatFiles.load(IdvSeasonOverride.self, Self.seasonFile) ?? IdvSeasonOverride()
            recompute()
        }
    }

    /// 今のシーズン（手動の上書きがあればそれ）
    var season: IdvSeason? { seasonOverride.season ?? detectedSeason }

    /// 期限の近い順（終わったものは後ろ）
    var sortedEvents: [IdvEvent] {
        events.sorted { a, b in
            let da = IdvDates.daysLeft(a.end), db = IdvDates.daysLeft(b.end)
            if (da < 0) != (db < 0) { return da >= 0 }
            return a.end < b.end
        }
    }

    /// ニュースから見つけたもの（まだ足していないもの）
    var suggestions: [IdvEvent] {
        let have = Set(events.compactMap(\.link))
        return IdvDates.candidates(news, articles: articles).filter { !have.contains($0.link ?? "") }
    }

    var nextEvent: IdvEvent? { sortedEvents.first { IdvDates.daysLeft($0.end) >= 0 } }

    func refreshIfNeeded() async {
        guard !isDemo else { return }
        if let u = updatedAt, Date.now.timeIntervalSince(u) < 1800 { return }
        await refresh()
    }

    func refresh() async {
        guard !isDemo, !loading else { return }
        loading = true
        defer { loading = false }
        let r = await IdvFeed.fetchAll()
        var failed = r.failed
        if !r.news.isEmpty {
            news = Array(r.news.prefix(40))
            SplatFiles.save(news, Self.newsFile)
        }
        // 公式サイトの一覧は1時間に1回まで
        let officialDue: Bool = officialAt.map { Date.now.timeIntervalSince($0) > 3600 } ?? true
        if officialDue {
            if let u = IdvOfficial.updateListURL, let data = try? await InfoFetcher.get(u) {
                let list = IdvOfficial.parseList(String(decoding: data, as: UTF8.self))
                if !list.isEmpty {
                    official = Array(list.prefix(20))
                    SplatFiles.save(official, Self.officialFile)
                }
                officialAt = .now
            } else {
                failed += 1
            }
        }
        await fetchArticles()
        error = failed >= 3 ? "お知らせを読み込めませんでした。通信を確認してください。"
            : (failed > 0 ? "一部のお知らせを読み込めませんでした。" : nil)
        updatedAt = .now
        recompute()
        await IdvReminder.reschedule(events: events, schedule: schedule, season: season)
    }

    /// 本文が要るものだけ記事を読む（1回の更新で最大5件。読んだものは残す）
    private func fetchArticles() async {
        let all: [IdvNews] = official + news
        let todo = IdvOfficial.articlesToFetch(news: all, cached: Set(articles.keys))
        guard !todo.isEmpty else { return }
        for n in todo {
            guard let u = n.url, let data = try? await InfoFetcher.get(u) else { continue }
            articles[n.link] = IdvOfficial.text(fromHTML: String(decoding: data, as: UTF8.self))
        }
        // 今の一覧にないものは捨てる
        let keep = Set(all.map(\.link))
        articles = articles.filter { keep.contains($0.key) }
        SplatFiles.save(articles, Self.articlesFile)
    }

    private func recompute() {
        schedule = IdvSchedule.items(news: official + news, articles: articles)
        detectedSeason = IdvSeasonParser.resolve(updates: official, articles: articles, news: news)
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

    /// 画面を開いたとき：通知の許可を聞いて（初回だけ出る）、通知を組み直す
    func prepareNotifications() async {
        guard !isDemo, !LaunchArguments.isScripted else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await IdvReminder.reschedule(events: events, schedule: schedule, season: season)
    }

    private func persist() {
        guard !isDemo else { return }
        SplatFiles.save(events, Self.eventsFile)
        rescheduleAll()
    }

    private func rescheduleAll() {
        guard !isDemo else { return }
        let list = events, sched = schedule, s = season
        Task {
            if !LaunchArguments.isScripted { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            await IdvReminder.reschedule(events: list, schedule: sched, season: s)
        }
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
}
