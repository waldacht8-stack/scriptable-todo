import Foundation

// Steam のデータ（自分のプロフィール・最近遊んだゲーム・実績・ウィッシュリストのセール・ゲームのニュース）
// - Steam Web API（https://api.steampowered.com）：Web API キーと SteamID が要る。キーは Keychain にだけ置く
// - ストア（https://store.steampowered.com/api/appdetails）：価格と割引（日本円）
// プロフィールとゲームの詳細が「公開」でないと、最近遊んだゲームなどは空で返る。
// 読み方はゆるくする：項目はすべて省略可能。1つの取得に失敗しても、ほかは表示する。

// MARK: - 画面で使う形

struct SteamProfile: Codable, Equatable {
    var steamID: String
    var name: String
    var avatar: String?
    var state: Int          // 0 オフライン・1 オンライン・2 取り込み中・3 離席・4 ねむり …
    var playing: String?    // いま遊んでいるゲーム

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

    /// 直近2週間に遊んだ時間（時間）
    var hours2Weeks: Double { recent.reduce(0) { $0 + $1.hours2Weeks } }
    /// 最近のゲームで取った実績の合計
    var achievedSum: Int? {
        let list = recent.compactMap(\.achieved)
        return list.isEmpty ? nil : list.reduce(0, +)
    }
}

enum SteamAPIError: Error {
    case badKey
    case notFound
    case http(Int)
    case badData
}

// MARK: - 読み込み

enum SteamAPI {
    static let api = "https://api.steampowered.com/"

    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
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

    /// 入力（17桁の SteamID・プロフィールの URL・カスタム URL の名前）から SteamID を求める
    static func resolveID(_ raw: String, key: String) async throws -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count == 17, s.allSatisfy(\.isNumber) { return s }
        var name = s
        if let r = s.range(of: "/profiles/") {
            let id = s[r.upperBound...].prefix { $0.isNumber }
            if id.count == 17 { return String(id) }
        }
        if let r = s.range(of: "/id/") {
            name = String(s[r.upperBound...].prefix { $0 != "/" })
        }
        guard !name.isEmpty, let u = url("ISteamUser/ResolveVanityURL/v1/", ["key": key, "vanityurl": name]) else {
            throw SteamAPIError.notFound
        }
        let root = try JSONDecoder().decode(RawVanityRoot.self, from: try await get(u))
        guard root.response?.success == 1, let id = root.response?.steamid else { throw SteamAPIError.notFound }
        return id
    }

    /// まとめて読む（プロフィールが読めなければ失敗。ほかは読めた分だけ）
    static func fetchAll(id: String, key: String) async throws -> SteamSnapshot {
        async let profile = fetchProfile(id: id, key: key)
        async let recent = try? fetchRecent(id: id, key: key)
        async let owned = try? fetchOwnedCount(id: id, key: key)
        async let wishlist = try? fetchWishlistDeals(id: id)
        var snap = SteamSnapshot()
        snap.profile = try await profile
        var games: [SteamGame] = await recent ?? []
        snap.ownedCount = await owned
        snap.deals = await wishlist ?? []
        // 上位3本の実績とニュース
        let top: [SteamGame] = Array(games.prefix(3))
        await withTaskGroup(of: (Int, Int?, Int?, [SteamNews]).self) { group in
            for g in top {
                group.addTask {
                    let ach = try? await fetchAchievements(id: id, key: key, appID: g.appID)
                    let news = (try? await fetchNews(appID: g.appID, appName: g.name)) ?? []
                    return (g.appID, ach?.0, ach?.1, news)
                }
            }
            var news: [SteamNews] = []
            for await (appID, got, total, items) in group {
                if let i = games.firstIndex(where: { $0.appID == appID }) {
                    games[i].achieved = got
                    games[i].achievementsTotal = total
                }
                news += items
            }
            snap.news = Array(news.sorted { $0.date > $1.date }.prefix(5))
        }
        snap.recent = games
        snap.fetchedAt = .now
        return snap
    }

    static func fetchProfile(id: String, key: String) async throws -> SteamProfile {
        guard let u = url("ISteamUser/GetPlayerSummaries/v2/", ["key": key, "steamids": id]) else { throw SteamAPIError.badData }
        let root = try JSONDecoder().decode(RawPlayersRoot.self, from: try await get(u))
        guard let p = root.response?.players?.first else { throw SteamAPIError.notFound }
        return SteamProfile(steamID: p.steamid ?? id, name: p.personaname ?? "Steam", avatar: p.avatarfull,
                            state: p.personastate ?? 0, playing: p.gameextrainfo)
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

    /// ウィッシュリストのうち、いま割引中のもの（多くても8本の価格を調べる）
    static func fetchWishlistDeals(id: String) async throws -> [SteamDeal] {
        guard let u = url("IWishlistService/GetWishlist/v1/", ["steamid": id]) else { throw SteamAPIError.badData }
        let root = try JSONDecoder().decode(RawWishRoot.self, from: try await get(u))
        let items: [RawWishItem] = (root.response?.items ?? []).sorted { ($0.priority ?? 99) < ($1.priority ?? 99) }
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
        return deals.sorted { $0.discount > $1.discount }
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
