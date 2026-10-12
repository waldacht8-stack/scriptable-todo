import Foundation

// Steam のデータ（自分のプロフィール・ウィッシュリストのセール・ストアのセール・ゲームのニュース、キーがあれば最近遊んだゲームと実績）
// キーなしで読めるもの：
// - コミュニティの XML（https://steamcommunity.com/profiles/<id>/?xml=1・/id/<名前>/?xml=1）：名前・アイコン・オンライン・プレイ中のゲーム。
//   カスタム URL の名前から SteamID を求めるのにも使う
// - ウィッシュリスト（IWishlistService/GetWishlist）とストアの価格（store.steampowered.com/api/appdetails、日本円）
// - ストアの特集・セール（store.steampowered.com/api/featuredcategories）
// - ゲームのニュース（ISteamNews/GetNewsForApp）
// Web API キーがあるときだけ：最近遊んだゲーム・持っているゲームの数・実績。キーは Keychain にだけ置く
// プロフィール・ゲームの詳細・ウィッシュリストが「公開」でないと、空で返る。
// 読み方はゆるくする：項目はすべて省略可能。1つの取得に失敗しても、ほかは表示する（読めなかった分は前のデータを残す）。

// MARK: - 画面で使う形

struct SteamProfile: Codable, Equatable {
    var steamID: String
    var name: String
    var avatar: String?
    var state: Int          // 0 オフライン・1 オンライン・2 取り込み中・3 離席・4 ねむり …
    var playing: String?    // いま遊んでいるゲーム
    var isPublic: Bool? = nil   // プロフィールが公開か（わからなければ nil）

    var stateText: String {
        if let playing, !playing.isEmpty { return "\(playing) をプレイ中" }
        switch state {
        case 0: return "オフライン"
        case 2: return "取り込み中"
        case 3, 4: return "離席中"
        default: return "オンライン"
        }
    }

    var isOnline: Bool { state != 0 || playing != nil }
}

struct SteamGame: Codable, Identifiable, Equatable {
    var appID: Int
    var name: String
    var minutes2Weeks: Int
    var minutesTotal: Int
    var achieved: Int?
    var achievementsTotal: Int?

    var id: Int { appID }
    var headerURL: URL? { URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg") }
    var storeURL: URL? { URL(string: "https://store.steampowered.com/app/\(appID)/") }
    var hours2Weeks: Double { Double(minutes2Weeks) / 60 }
    var hoursTotal: Double { Double(minutesTotal) / 60 }
}

struct SteamDeal: Codable, Identifiable, Equatable {
    var appID: Int
    var name: String
    var discount: Int
    var finalPrice: String?
    var initialPrice: String?

    var id: Int { appID }
    var storeURL: URL? { URL(string: "https://store.steampowered.com/app/\(appID)/") }
}

/// ストア全体のセール（スペシャル・売上上位・新作のうち割引中のもの）
struct SteamSpecial: Codable, Identifiable, Equatable {
    var appID: Int
    var name: String
    var discount: Int
    var finalYen: Int?
    var originalYen: Int?
    var endsAt: Date?

    var id: Int { appID }
    var storeURL: URL? { URL(string: "https://store.steampowered.com/app/\(appID)/") }
    var finalText: String? { finalYen.map(SteamAPI.yen) }
    var originalText: String? { originalYen.map(SteamAPI.yen) }
}

struct SteamNews: Codable, Identifiable, Equatable {
    var id: String
    var appName: String
    var title: String
    var url: String
    var date: Date
}

struct SteamSnapshot: Codable, Equatable {
    var profile: SteamProfile?
    var recent: [SteamGame] = []
    var ownedCount: Int?
    var deals: [SteamDeal] = []
    var news: [SteamNews] = []
    var fetchedAt: Date = .now
    // あとから足したもの（前の版で保存したデータも読めるよう、省略可能にする）
    var specials: [SteamSpecial]? = nil
    var wishlistHidden: Bool? = nil   // ウィッシュリストが空か非公開で、中身が返らなかった
    var failed: [String]? = nil       // 今回読めなかったもの（その分は前のデータを表示している）

    /// 直近2週間に遊んだ時間（時間）
    var hours2Weeks: Double { recent.reduce(0) { $0 + $1.hours2Weeks } }
    /// 最近のゲームで取った実績の合計
    var achievedSum: Int? {
        let list = recent.compactMap(\.achieved)
        return list.isEmpty ? nil : list.reduce(0, +)
    }
    /// プロフィールかウィッシュリストが非公開らしい
    var looksPrivate: Bool { profile?.isPublic == false || wishlistHidden == true }
}

enum SteamAPIError: Error, Equatable {
    case badKey
    case notFound
    case http(Int)
    case badData
}

// MARK: - コミュニティの XML（キーなしで読めるプロフィール）

struct SteamXMLProfile: Equatable {
    var steamID64: String
    var name: String
    var avatar: String?
    var onlineState: String     // online・offline・in-game
    var stateMessage: String?
    var privacyState: String?   // public・friendsonly・private
    var gameName: String?

    var profile: SteamProfile {
        let msg: String = (stateMessage ?? "").lowercased()
        let online: String = onlineState.lowercased()
        let state: Int
        if online == "offline" { state = 0 }
        else if online == "in-game" { state = 1 }
        else if msg.contains("busy") { state = 2 }
        else if msg.contains("snooze") { state = 4 }
        else if msg.contains("away") { state = 3 }
        else { state = 1 }
        let playing: String? = online == "in-game" ? gameName : nil
        let isPublic: Bool? = privacyState.map { $0.lowercased() == "public" }
        return SteamProfile(steamID: steamID64, name: name, avatar: avatar, state: state, playing: playing, isPublic: isPublic)
    }
}

enum SteamProfileXML {
    /// <profile> の XML を読む。<response><error> や SteamID の無いものは notFound
    static func parse(_ data: Data) throws -> SteamXMLProfile {
        let collector = SteamXMLCollector()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse() else { throw SteamAPIError.badData }
        let f: [String: String] = collector.fields
        if f["response/error"] != nil { throw SteamAPIError.notFound }
        guard let id = f["profile/steamID64"], id.count == 17, id.allSatisfy(\.isNumber) else {
            throw SteamAPIError.notFound
        }
        return SteamXMLProfile(steamID64: id, name: f["profile/steamID"] ?? "Steam", avatar: f["profile/avatarFull"],
                               onlineState: f["profile/onlineState"] ?? "offline", stateMessage: f["profile/stateMessage"],
                               privacyState: f["profile/privacyState"], gameName: f["profile/inGameInfo/gameName"])
    }
}

/// 要素の道筋（"profile/inGameInfo/gameName" など）ごとに、最初の文字を集める
private final class SteamXMLCollector: NSObject, XMLParserDelegate {
    var fields: [String: String] = [:]
    private var path: [String] = []
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        path.append(elementName)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let key: String = path.joined(separator: "/")
        let value: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if fields[key] == nil, !value.isEmpty { fields[key] = value }
        if !path.isEmpty { path.removeLast() }
        text = ""
    }
}

// MARK: - 読み込み

enum SteamAPI {
    static let api = "https://api.steampowered.com/"

    static func get(_ url: URL, accept: String = "application/json") async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, res) = try await URLSession.shared.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 200
        if code == 401 || code == 403 { throw SteamAPIError.badKey }
        if code == 404 { throw SteamAPIError.notFound }
        guard (200..<300).contains(code) else { throw SteamAPIError.http(code) }
        return data
    }

    static func url(_ path: String, _ items: [String: String]) -> URL? {
        var c = URLComponents(string: api + path)
        c?.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c?.url
    }

    /// 日本円の表示（ストアの表示に合わせて「¥ 1,234」）
    static func yen(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US_POSIX")
        let s: String = f.string(from: NSNumber(value: v)) ?? String(v)
        return "¥ \(s)"
    }

    /// 入力（17桁の SteamID・プロフィールの URL・カスタム URL の名前）の種類
    enum IDInput: Equatable {
        case id(String)
        case vanity(String)
    }

    static func classify(_ raw: String) -> IDInput? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count == 17, s.allSatisfy(\.isNumber) { return .id(s) }
        if let r = s.range(of: "/profiles/") {
            let id = s[r.upperBound...].prefix { $0.isNumber }
            if id.count == 17 { return .id(String(id)) }
        }
        var name = s
        if let r = s.range(of: "/id/") {
            name = String(s[r.upperBound...].prefix { $0 != "/" && $0 != "?" })
        }
        guard !name.isEmpty, !name.contains("/"), !name.contains(" ") else { return nil }
        return .vanity(name)
    }

    /// SteamID を求める。カスタム URL の名前はコミュニティの XML で（キーなし）、だめならキーがあれば Web API で
    static func resolveID(_ raw: String, key: String?) async throws -> String {
        guard let input = classify(raw) else { throw SteamAPIError.notFound }
        switch input {
        case .id(let id):
            return id
        case .vanity(let name):
            do {
                return try await fetchXMLProfile(vanity: name).steamID64
            } catch {
                guard let key, !key.isEmpty else { throw error }
                guard let u = url("ISteamUser/ResolveVanityURL/v1/", ["key": key, "vanityurl": name]) else {
                    throw SteamAPIError.notFound
                }
                let root = try JSONDecoder().decode(RawVanityRoot.self, from: try await get(u))
                guard root.response?.success == 1, let id = root.response?.steamid else { throw SteamAPIError.notFound }
                return id
            }
        }
    }

    /// まとめて読む。読めなかったものは previous の分を残し、failed に名前を入れる。
    /// キーなしの3つ（プロフィール・ウィッシュリスト・ストアのセール）がどれも読めなければ失敗する（SteamID の間違いは notFound）
    static func fetchAll(id: String, key: String?, previous: SteamSnapshot?) async throws -> SteamSnapshot {
        let k: String? = (key?.isEmpty ?? true) ? nil : key
        async let profileR: Result<SteamProfile, Error> = profileResult(id: id, key: k)
        async let recentR: Result<[SteamGame], Error>? = recentResult(id: id, key: k)
        async let ownedR: Int? = ownedIfKey(id: id, key: k)
        async let wishR: SteamWishResult? = wishlistOrNil(id: id)
        async let specialsR: [SteamSpecial]? = featuredOrNil()

        let prev: SteamSnapshot? = previous
        var snap = SteamSnapshot()
        var failed: [String] = []

        let profileRes: Result<SteamProfile, Error> = await profileR
        switch profileRes {
        case .success(let p):
            snap.profile = p
        case .failure(let e):
            if prev == nil, (e as? SteamAPIError) == .notFound { throw SteamAPIError.notFound }
            snap.profile = prev?.profile
            failed.append("プロフィール")
        }

        var games: [SteamGame] = []
        let recentRes: Result<[SteamGame], Error>? = await recentR
        let owned: Int? = await ownedR
        if let r = recentRes {
            switch r {
            case .success(let list):
                games = list
            case .failure(let e):
                games = prev?.recent ?? []
                failed.append((e as? SteamAPIError) == .badKey ? "Web API キー" : "最近遊んだゲーム")
            }
            snap.ownedCount = owned ?? prev?.ownedCount
        }

        if let w: SteamWishResult = await wishR {
            snap.deals = w.deals
            snap.wishlistHidden = w.hidden
        } else {
            snap.deals = prev?.deals ?? []
            snap.wishlistHidden = prev?.wishlistHidden
            failed.append("ウィッシュリスト")
        }

        if let sp: [SteamSpecial] = await specialsR {
            snap.specials = sp
        } else {
            snap.specials = prev?.specials
            failed.append("ストアのセール")
        }

        let allFailed: Bool = failed.contains("プロフィール") && failed.contains("ウィッシュリスト") && failed.contains("ストアのセール")
        if allFailed {
            if case .failure(let e) = profileRes { throw e }
            throw SteamAPIError.badData
        }

        // 実績（キーがあるとき、最近の上位3本）
        let top: [SteamGame] = Array(games.prefix(3))
        if let achKey = k {
            await withTaskGroup(of: (Int, Int?, Int?).self) { group in
                for g in top {
                    group.addTask {
                        let ach: (Int, Int)? = try? await fetchAchievements(id: id, key: achKey, appID: g.appID)
                        return (g.appID, ach?.0, ach?.1)
                    }
                }
                for await (appID, got, total) in group {
                    if let i = games.firstIndex(where: { $0.appID == appID }) {
                        games[i].achieved = got
                        games[i].achievementsTotal = total
                    }
                }
            }
        }

        // ニュース：最近のゲーム → ウィッシュリスト → ストアのセールの順に3本
        let newsApps: [SteamNewsApp] = newsTargets(recent: games, deals: snap.deals, specials: snap.specials ?? [])
        let fetchedNews: [SteamNews] = await withTaskGroup(of: [SteamNews].self) { group in
            for a in newsApps {
                group.addTask { (try? await fetchNews(appID: a.appID, appName: a.name)) ?? [] }
            }
            var all: [SteamNews] = []
            for await items in group { all += items }
            return all
        }
        let news: [SteamNews] = Array(fetchedNews.sorted { $0.date > $1.date }.prefix(5))
        snap.news = news.isEmpty ? (prev?.news ?? []) : news
        snap.recent = games
        snap.failed = failed.isEmpty ? nil : failed
        snap.fetchedAt = .now
        return snap
    }

    struct SteamNewsApp: Equatable {
        var appID: Int
        var name: String
    }

    /// ニュースを読むゲーム（同じゲームは1回、多くても limit 本）
    static func newsTargets(recent: [SteamGame], deals: [SteamDeal], specials: [SteamSpecial], limit: Int = 3) -> [SteamNewsApp] {
        let all: [SteamNewsApp] = recent.prefix(3).map { SteamNewsApp(appID: $0.appID, name: $0.name) }
            + deals.map { SteamNewsApp(appID: $0.appID, name: $0.name) }
            + specials.map { SteamNewsApp(appID: $0.appID, name: $0.name) }
        var out: [SteamNewsApp] = []
        for a in all where out.count < limit && !out.contains(where: { $0.appID == a.appID }) {
            out.append(a)
        }
        return out
    }

    private static func profileResult(id: String, key: String?) async -> Result<SteamProfile, Error> {
        do { return .success(try await fetchProfile(id: id, key: key)) } catch { return .failure(error) }
    }

    private static func recentResult(id: String, key: String?) async -> Result<[SteamGame], Error>? {
        guard let key else { return nil }
        do { return .success(try await fetchRecent(id: id, key: key)) } catch { return .failure(error) }
    }

    private static func ownedIfKey(id: String, key: String?) async -> Int? {
        guard let key else { return nil }
        let n: Int?? = try? await fetchOwnedCount(id: id, key: key)
        return n ?? nil
    }

    private static func wishlistOrNil(id: String) async -> SteamWishResult? {
        try? await fetchWishlistDeals(id: id)
    }

    private static func featuredOrNil() async -> [SteamSpecial]? {
        try? await fetchFeatured()
    }

    /// プロフィール：キーがあれば Web API、なければ（または失敗したら）コミュニティの XML
    static func fetchProfile(id: String, key: String?) async throws -> SteamProfile {
        if let key, !key.isEmpty, let p = try? await fetchProfileAPI(id: id, key: key) { return p }
        return try await fetchXMLProfile(id: id).profile
    }

    static func fetchXMLProfile(id: String) async throws -> SteamXMLProfile {
        guard let u = URL(string: "https://steamcommunity.com/profiles/\(id)/?xml=1") else { throw SteamAPIError.badData }
        return try SteamProfileXML.parse(try await get(u, accept: "text/xml"))
    }

    static func fetchXMLProfile(vanity: String) async throws -> SteamXMLProfile {
        let name: String = vanity.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? vanity
        guard let u = URL(string: "https://steamcommunity.com/id/\(name)/?xml=1") else { throw SteamAPIError.badData }
        return try SteamProfileXML.parse(try await get(u, accept: "text/xml"))
    }

    static func fetchProfileAPI(id: String, key: String) async throws -> SteamProfile {
        guard let u = url("ISteamUser/GetPlayerSummaries/v2/", ["key": key, "steamids": id]) else { throw SteamAPIError.badData }
        let root = try JSONDecoder().decode(RawPlayersRoot.self, from: try await get(u))
        guard let p = root.response?.players?.first else { throw SteamAPIError.notFound }
        let isPublic: Bool? = p.communityvisibilitystate.map { $0 == 3 }
        return SteamProfile(steamID: p.steamid ?? id, name: p.personaname ?? "Steam", avatar: p.avatarfull,
                            state: p.personastate ?? 0, playing: p.gameextrainfo, isPublic: isPublic)
    }

    static func fetchRecent(id: String, key: String) async throws -> [SteamGame] {
        guard let u = url("IPlayerService/GetRecentlyPlayedGames/v1/", ["key": key, "steamid": id, "count": "6"]) else {
            throw SteamAPIError.badData
        }
        let root = try JSONDecoder().decode(RawRecentRoot.self, from: try await get(u))
        let list: [RawGame] = root.response?.games ?? []
        return list.compactMap { g in
            guard let appID = g.appid else { return nil }
            return SteamGame(appID: appID, name: g.name ?? "App \(appID)",
                             minutes2Weeks: g.playtime_2weeks ?? 0, minutesTotal: g.playtime_forever ?? 0)
        }
    }

    static func fetchOwnedCount(id: String, key: String) async throws -> Int? {
        guard let u = url("IPlayerService/GetOwnedGames/v1/", ["key": key, "steamid": id, "include_appinfo": "0"]) else {
            throw SteamAPIError.badData
        }
        let root = try JSONDecoder().decode(RawOwnedRoot.self, from: try await get(u))
        return root.response?.game_count
    }

    /// 取った実績の数と全部の数（実績の無いゲームは失敗する）
    static func fetchAchievements(id: String, key: String, appID: Int) async throws -> (Int, Int) {
        guard let u = url("ISteamUserStats/GetPlayerAchievements/v1/", ["key": key, "steamid": id, "appid": String(appID)]) else {
            throw SteamAPIError.badData
        }
        let root = try JSONDecoder().decode(RawAchRoot.self, from: try await get(u))
        let list: [RawAch] = root.playerstats?.achievements ?? []
        guard !list.isEmpty else { throw SteamAPIError.badData }
        return (list.filter { ($0.achieved ?? 0) == 1 }.count, list.count)
    }

    static func fetchNews(appID: Int, appName: String) async throws -> [SteamNews] {
        guard let u = url("ISteamNews/GetNewsForApp/v2/", ["appid": String(appID), "count": "2", "maxlength": "1"]) else {
            throw SteamAPIError.badData
        }
        let root = try JSONDecoder().decode(RawNewsRoot.self, from: try await get(u))
        let items: [RawNewsItem] = root.appnews?.newsitems ?? []
        return items.compactMap { n in
            guard let gid = n.gid, let title = n.title, let link = n.url else { return nil }
            return SteamNews(id: gid, appName: appName, title: title, url: link,
                             date: Date(timeIntervalSince1970: TimeInterval(n.date ?? 0)))
        }
    }

    struct SteamWishResult {
        var deals: [SteamDeal]
        var hidden: Bool
    }

    /// ウィッシュリストのうち、いま割引中のもの（多くても8本の価格を調べる）。
    /// 非公開か空だと {"response":{}} が返る → hidden
    static func fetchWishlistDeals(id: String) async throws -> SteamWishResult {
        guard let u = url("IWishlistService/GetWishlist/v1/", ["steamid": id]) else { throw SteamAPIError.badData }
        let root = try JSONDecoder().decode(RawWishRoot.self, from: try await get(u))
        let raw: [RawWishItem] = root.response?.items ?? []
        if raw.isEmpty { return SteamWishResult(deals: [], hidden: true) }
        let items: [RawWishItem] = raw.sorted { ($0.priority ?? 99) < ($1.priority ?? 99) }
        let ids: [Int] = Array(items.compactMap(\.appid).prefix(8))
        var deals: [SteamDeal] = []
        await withTaskGroup(of: SteamDeal?.self) { group in
            for appID in ids {
                group.addTask { try? await fetchPrice(appID: appID) }
            }
            for await d in group {
                if let d { deals.append(d) }
            }
        }
        let sorted: [SteamDeal] = deals.sorted { $0.discount > $1.discount }
        return SteamWishResult(deals: sorted, hidden: false)
    }

    static func fetchPrice(appID: Int) async throws -> SteamDeal? {
        var c = URLComponents(string: "https://store.steampowered.com/api/appdetails")
        c?.queryItems = [URLQueryItem(name: "appids", value: String(appID)), URLQueryItem(name: "cc", value: "jp"),
                         URLQueryItem(name: "l", value: "japanese")]
        guard let u = c?.url else { throw SteamAPIError.badData }
        let root = try JSONDecoder().decode([String: RawAppDetails].self, from: try await get(u))
        guard let d = root[String(appID)]?.data, let name = d.name else { return nil }
        let price: RawPrice? = d.price_overview
        return SteamDeal(appID: appID, name: name, discount: price?.discount_percent ?? 0,
                         finalPrice: price?.final_formatted, initialPrice: price?.initial_formatted)
    }

    /// ストアの特集・セール（日本円・日本語）
    static func fetchFeatured() async throws -> [SteamSpecial] {
        guard let u = URL(string: "https://store.steampowered.com/api/featuredcategories?cc=jp&l=japanese") else {
            throw SteamAPIError.badData
        }
        return try parseFeatured(try await get(u))
    }

    /// featuredcategories の JSON から割引中のゲームを取り出す（スペシャル → 売上上位 → 新作の順。同じゲームは1回だけ）。
    /// 価格は 100 倍の整数で来る（319500 → ¥ 3,195）
    static func parseFeatured(_ data: Data, limit: Int = 8) throws -> [SteamSpecial] {
        let root = try JSONDecoder().decode(RawFeaturedRoot.self, from: data)
        let groups: [[RawFeaturedItem]] = [root.specials?.items ?? [], root.top_sellers?.items ?? [], root.new_releases?.items ?? []]
        var out: [SteamSpecial] = []
        var seen: Set<Int> = []
        for item in groups.joined() {
            if out.count >= limit { break }
            guard let appID = item.id, let name = item.name, (item.type ?? 0) == 0 else { continue }
            let discount: Int = item.discount_percent ?? 0
            let discounted: Bool = item.discounted ?? true
            if discount <= 0 || !discounted || seen.contains(appID) { continue }
            seen.insert(appID)
            let finalYen: Int? = item.final_price.map { $0 / 100 }
            let originalYen: Int? = item.original_price.map { $0 / 100 }
            var ends: Date? = nil
            if let t = item.discount_expiration, t > 0 { ends = Date(timeIntervalSince1970: TimeInterval(t)) }
            out.append(SteamSpecial(appID: appID, name: name, discount: discount, finalYen: finalYen,
                                    originalYen: originalYen, endsAt: ends))
        }
        return out
    }
}

// MARK: - 生の JSON（すべて省略可能）

private struct RawVanityRoot: Decodable { let response: RawVanity? }
private struct RawVanity: Decodable { let success: Int?; let steamid: String? }

private struct RawPlayersRoot: Decodable { let response: RawPlayers? }
private struct RawPlayers: Decodable { let players: [RawPlayer]? }
private struct RawPlayer: Decodable {
    let steamid: String?
    let personaname: String?
    let avatarfull: String?
    let personastate: Int?
    let gameextrainfo: String?
    let communityvisibilitystate: Int?
}

private struct RawRecentRoot: Decodable { let response: RawRecent? }
private struct RawRecent: Decodable { let games: [RawGame]? }
private struct RawGame: Decodable {
    let appid: Int?
    let name: String?
    let playtime_2weeks: Int?
    let playtime_forever: Int?
}

private struct RawOwnedRoot: Decodable { let response: RawOwned? }
private struct RawOwned: Decodable { let game_count: Int? }

private struct RawAchRoot: Decodable { let playerstats: RawAchStats? }
private struct RawAchStats: Decodable { let achievements: [RawAch]? }
private struct RawAch: Decodable { let achieved: Int? }

private struct RawNewsRoot: Decodable { let appnews: RawNews? }
private struct RawNews: Decodable { let newsitems: [RawNewsItem]? }
private struct RawNewsItem: Decodable {
    let gid: String?
    let title: String?
    let url: String?
    let date: Int?
}

private struct RawWishRoot: Decodable { let response: RawWish? }
private struct RawWish: Decodable { let items: [RawWishItem]? }
private struct RawWishItem: Decodable { let appid: Int?; let priority: Int? }

private struct RawAppDetails: Decodable { let data: RawAppData? }
private struct RawAppData: Decodable { let name: String?; let price_overview: RawPrice? }
private struct RawPrice: Decodable {
    let discount_percent: Int?
    let initial_formatted: String?
    let final_formatted: String?
}

private struct RawFeaturedRoot: Decodable {
    let specials: RawFeaturedGroup?
    let top_sellers: RawFeaturedGroup?
    let new_releases: RawFeaturedGroup?
}
private struct RawFeaturedGroup: Decodable { let items: [RawFeaturedItem]? }
private struct RawFeaturedItem: Decodable {
    let id: Int?
    let type: Int?
    let name: String?
    let discounted: Bool?
    let discount_percent: Int?
    let original_price: Int?
    let final_price: Int?
    let discount_expiration: Int?
}
