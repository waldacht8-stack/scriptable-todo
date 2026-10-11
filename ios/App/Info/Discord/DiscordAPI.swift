import SwiftUI

// MARK: - Discord（サーバーの様子・お知らせ／募集）
// 1. サーバーの様子：公開のサーバーウィジェット（https://discord.com/api/guilds/<id>/widget.json）。認証なし。
//    サーバー設定 › ウィジェット で「サーバーウィジェットを有効化」したサーバーだけ読める
// 2. お知らせ／募集（任意）：自分で作ったボットのトークンで、選んだチャンネルの最新メッセージを読む
//    GET /channels/{id}/messages?limit=20（Authorization: Bot <token>）。ボットには Message Content Intent と「メッセージ履歴を読む」が必要
// - ユーザーのトークン（セルフボット）は使わない。トークンは Keychain にだけ保存し、ログにも出さない
// - 起動引数 -demo では通信せず、架空のサーバーを出す

struct DiscordWidget: Codable, Equatable {
    struct Channel: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var position: Int?
    }

    struct Game: Codable, Equatable { var name: String? }

    struct Member: Codable, Equatable, Identifiable {
        var id: String
        var username: String
        var status: String?
        var avatarURL: String?
        var channelID: String?
        var game: Game?
        var selfMute: Bool?
        var selfDeaf: Bool?

        enum CodingKeys: String, CodingKey {
            case id, username, status, game
            case avatarURL = "avatar_url"
            case channelID = "channel_id"
            case selfMute = "self_mute"
            case selfDeaf = "self_deaf"
        }
    }

    var id: String
    var name: String
    var instantInvite: String?
    var channels: [Channel]
    var members: [Member]
    var presenceCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, channels, members
        case instantInvite = "instant_invite"
        case presenceCount = "presence_count"
    }

    init(id: String, name: String, instantInvite: String?, channels: [Channel], members: [Member], presenceCount: Int) {
        self.id = id
        self.name = name
        self.instantInvite = instantInvite
        self.channels = channels
        self.members = members
        self.presenceCount = presenceCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        instantInvite = try c.decodeIfPresent(String.self, forKey: .instantInvite)
        channels = try c.decodeIfPresent([Channel].self, forKey: .channels) ?? []
        members = try c.decodeIfPresent([Member].self, forKey: .members) ?? []
        presenceCount = try c.decodeIfPresent(Int.self, forKey: .presenceCount) ?? members.count
    }

    /// ボイスチャンネルにいる人（ウィジェットに出ている分だけ）。人の多い順
    var voiceGroups: [DiscordVoiceGroup] {
        let byChannel = Dictionary(grouping: members.filter { $0.channelID != nil }) { $0.channelID ?? "" }
        let groups: [DiscordVoiceGroup] = channels.compactMap { ch in
            guard let m = byChannel[ch.id], !m.isEmpty else { return nil }
            return DiscordVoiceGroup(channel: ch, members: m)
        }
        return groups.sorted { a, b in
            a.members.count != b.members.count ? a.members.count > b.members.count : (a.channel.position ?? 0) < (b.channel.position ?? 0)
        }
    }

    /// 招待の URL（https のときだけ）
    var inviteURL: URL? {
        guard let s = instantInvite, let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }

    static func decode(_ data: Data) throws -> DiscordWidget {
        try JSONDecoder().decode(DiscordWidget.self, from: data)
    }
}

struct DiscordVoiceGroup: Identifiable, Equatable {
    var channel: DiscordWidget.Channel
    var members: [DiscordWidget.Member]
    var id: String { channel.id }
}

struct DiscordMessage: Codable, Equatable, Identifiable {
    var id: String
    var channelID: String
    var guildID: String?
    var channelName: String
    var author: String
    var content: String
    var date: Date

    /// メッセージへのリンク（Discord のアプリで開く）
    var link: URL? {
        guard let g = guildID else { return nil }
        return URL(string: "https://discord.com/channels/\(g)/\(channelID)/\(id)")
    }

    func matches(_ keyword: String) -> Bool {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        return !k.isEmpty && content.range(of: k, options: [.caseInsensitive, .widthInsensitive]) != nil
    }
}

enum DiscordError: Error, Equatable {
    case widgetDisabled
    case notFound
    case unauthorized
    case forbidden
    case rateLimited
    case http(Int)
}

enum DiscordAPI {
    static let userAgent = "DiscordBot (Hiyori iOS app, 1.0)"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// サーバーIDは数字17〜20桁
    static func isSnowflake(_ s: String) -> Bool {
        s.range(of: #"^\d{17,20}$"#, options: .regularExpression) != nil
    }

    static func widget(guildID: String) async throws -> DiscordWidget {
        guard isSnowflake(guildID), let url = URL(string: "https://discord.com/api/guilds/\(guildID)/widget.json") else {
            throw DiscordError.notFound
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, res) = try await session.data(for: req)
        try check(res, data)
        return try DiscordWidget.decode(data)
    }

    /// エラーの中身：{"message": "Widget Disabled", "code": 50004}
    private struct RawError: Decodable { var code: Int? }

    private static func check(_ res: URLResponse, _ data: Data) throws {
        let code = (res as? HTTPURLResponse)?.statusCode ?? 200
        if (200..<300).contains(code) { return }
        let api = (try? JSONDecoder().decode(RawError.self, from: data))?.code
        if api == 50004 { throw DiscordError.widgetDisabled }
        switch code {
        case 401: throw DiscordError.unauthorized
        case 403: throw DiscordError.forbidden
        case 404: throw DiscordError.notFound
        case 429: throw DiscordError.rateLimited
        default: throw DiscordError.http(code)
        }
    }

    // MARK: ボット（任意）

    private struct RawChannel: Decodable {
        var id: String
        var name: String?
        var guild_id: String?
    }

    private struct RawMessage: Decodable {
        struct Author: Decodable { var username: String?; var global_name: String? }
        var id: String
        var channel_id: String
        var content: String?
        var timestamp: String?
        var author: Author?
    }

    private static func botRequest(_ path: String, token: String) -> URLRequest? {
        guard let url = URL(string: "https://discord.com/api/v10\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return req
    }

    /// 1つのチャンネルの最新20件（新しい順）
    static func messages(channelID: String, token: String) async throws -> [DiscordMessage] {
        guard isSnowflake(channelID),
              let chReq = botRequest("/channels/\(channelID)", token: token),
              let msgReq = botRequest("/channels/\(channelID)/messages?limit=20", token: token) else { throw DiscordError.notFound }
        let (chData, chRes) = try await session.data(for: chReq)
        try check(chRes, chData)
        let ch = try JSONDecoder().decode(RawChannel.self, from: chData)
        let (data, res) = try await session.data(for: msgReq)
        try check(res, data)
        return try decodeMessages(data, channelName: ch.name ?? "チャンネル", guildID: ch.guild_id)
    }

    static func decodeMessages(_ data: Data, channelName: String, guildID: String?) throws -> [DiscordMessage] {
        let raw = try JSONDecoder().decode([RawMessage].self, from: data)
        return raw.compactMap { m in
            let text = (m.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let name = m.author?.global_name ?? m.author?.username ?? "だれか"
            return DiscordMessage(id: m.id, channelID: m.channel_id, guildID: guildID, channelName: channelName,
                                  author: name, content: text, date: date(m.timestamp) ?? .distantPast)
        }
    }

    /// 例：2026-10-11T12:00:00.123000+00:00（小数の秒は6桁のことがあるので外してから読む）
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: trimmed)
    }
}

// MARK: - 状態（入口のカードと、くわしく画面が同じものを見る）

struct DiscordSettings: Codable, Equatable {
    var guildID = ""
    var channelIDs: [String] = []
    var keywords: [String] = ["スプラ", "募集"]
    var appID = ""
}

@MainActor
final class DiscordStore: ObservableObject {
    static let shared = DiscordStore()
    static let tokenKey = "discord.bottoken"
    private static let settingsFile = "discord-settings.json"
    private static let widgetFile = "discord-widget.json"

    @Published private(set) var settings: DiscordSettings
    @Published private(set) var widget: DiscordWidget? = nil
    @Published private(set) var messages: [DiscordMessage] = []
    @Published private(set) var hasToken: Bool
    @Published private(set) var loading = false
    @Published private(set) var error: String? = nil
    @Published private(set) var botError: String? = nil
    @Published private(set) var updatedAt: Date? = nil

    let isDemo = InfoLaunch.isDemo

    private init() {
        if isDemo {
            settings = DiscordDemo.settings
            hasToken = true
            widget = DiscordDemo.widget()
            messages = DiscordDemo.messages()
            updatedAt = .now
        } else {
            settings = SplatFiles.load(DiscordSettings.self, Self.settingsFile) ?? DiscordSettings()
            hasToken = InfoSecrets.has(Self.tokenKey)
            let w = SplatFiles.load(DiscordWidget.self, Self.widgetFile)
            widget = (w?.id == settings.guildID) ? w : nil
        }
    }

    var isConfigured: Bool { DiscordAPI.isSnowflake(settings.guildID) }
    var botReady: Bool { hasToken && !settings.channelIDs.isEmpty }

    /// 3分たっていたら読み直す
    func refreshIfNeeded() async {
        guard !isDemo, isConfigured else { return }
        if let u = updatedAt, Date.now.timeIntervalSince(u) < 180 { return }
        await refresh()
    }

    func refresh() async {
        guard !isDemo, isConfigured, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let w = try await DiscordAPI.widget(guildID: settings.guildID)
            widget = w
            error = nil
            SplatFiles.save(w, Self.widgetFile)
        } catch DiscordError.widgetDisabled {
            error = "このサーバーはウィジェットがオフです。サーバー設定 › ウィジェット で「サーバーウィジェットを有効化」をオンにしてください。"
        } catch DiscordError.notFound {
            error = "サーバーが見つかりませんでした。サーバーIDを確かめてください。"
        } catch {
            self.error = "Discord を読み込めませんでした。通信を確認してください。"
        }
        await refreshMessages()
        updatedAt = .now
    }

    private func refreshMessages() async {
        guard botReady, let token = InfoSecrets.get(Self.tokenKey) else {
            messages = []
            return
        }
        var all: [DiscordMessage] = []
        var failed: DiscordError?
        for id in settings.channelIDs.prefix(5) {
            do {
                all += try await DiscordAPI.messages(channelID: id, token: token)
            } catch let e as DiscordError {
                failed = e
            } catch {
                failed = .http(0)
            }
        }
        messages = all.sorted { $0.date > $1.date }
        switch failed {
        case .none: botError = nil
        case .some(.unauthorized): botError = "ボットのトークンが使えませんでした。開発者ポータルで作り直して入れてください。"
        case .some(.forbidden): botError = "読めないチャンネルがあります。ボットに「チャンネルを見る」「メッセージ履歴を読む」を許可してください。"
        case .some(.notFound): botError = "見つからないチャンネルがあります。チャンネルIDを確かめてください。"
        case .some(.rateLimited): botError = "読み込みが多すぎました。少し待ってから更新してください。"
        default: botError = "お知らせを読み込めませんでした。"
        }
    }

    /// 本文が空のメッセージ（Message Content Intent がオフ）しかないとき
    var contentMissingHint: Bool { botReady && messages.isEmpty && botError == nil && updatedAt != nil }

    func recruits(_ keyword: String?) -> [DiscordMessage] {
        let keys: [String] = keyword.map { [$0] } ?? settings.keywords
        return messages.filter { m in keys.contains { m.matches($0) } }
    }

    func save(_ s: DiscordSettings) async {
        var clean = s
        clean.guildID = s.guildID.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.channelIDs = s.channelIDs.map { $0.trimmingCharacters(in: .whitespaces) }.filter(DiscordAPI.isSnowflake)
        clean.keywords = s.keywords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        clean.appID = s.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDemo else { return }
        if clean.guildID != settings.guildID {
            widget = nil
            SplatFiles.remove(Self.widgetFile)
        }
        settings = clean
        SplatFiles.save(clean, Self.settingsFile)
        updatedAt = nil
        await refresh()
    }

    func saveToken(_ raw: String) async {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDemo, !t.isEmpty else { return }
        InfoSecrets.set(Self.tokenKey, t)
        hasToken = InfoSecrets.has(Self.tokenKey)
        updatedAt = nil
        await refresh()
    }

    func removeToken() {
        guard !isDemo else { return }
        InfoSecrets.set(Self.tokenKey, nil)
        hasToken = false
        messages = []
        botError = nil
    }

    func disconnect() {
        guard !isDemo else { return }
        removeToken()
        SplatFiles.remove(Self.settingsFile)
        SplatFiles.remove(Self.widgetFile)
        settings = DiscordSettings()
        widget = nil
        error = nil
        updatedAt = nil
    }
}

// MARK: - 見本（-demo。架空のサーバー・人・メッセージ）

enum DiscordDemo {
    static let guild = "100000000000000001"
    static let settings = DiscordSettings(guildID: guild, channelIDs: ["100000000000000010", "100000000000000011"],
                                          keywords: ["スプラ", "募集"], appID: "")

    static func widget() -> DiscordWidget {
        let voice1 = DiscordWidget.Channel(id: "100000000000000020", name: "ナワバリ部屋", position: 1)
        let voice2 = DiscordWidget.Channel(id: "100000000000000021", name: "作業通話", position: 2)
        let names = ["あおい", "はると", "みずき", "そら", "ゆうき", "こはる", "りん", "かえで", "なぎ", "ひなた", "つむぎ", "れん"]
        var members: [DiscordWidget.Member] = []
        for (i, n) in names.enumerated() {
            let ch: String? = i < 3 ? voice1.id : (i == 3 ? voice2.id : nil)
            let status: String = i % 5 == 4 ? "idle" : (i % 7 == 6 ? "dnd" : "online")
            let game: DiscordWidget.Game? = i < 3 ? DiscordWidget.Game(name: "スプラトゥーン3") : nil
            members.append(DiscordWidget.Member(id: String(i), username: n, status: status, avatarURL: nil, channelID: ch,
                                                game: game, selfMute: i == 2, selfDeaf: nil))
        }
        return DiscordWidget(id: guild, name: "あおぞらゲーム部", instantInvite: "https://discord.com/invite/example",
                             channels: [voice1, voice2], members: members, presenceCount: 12)
    }

    static func messages(now: Date = .now) -> [DiscordMessage] {
        func m(_ id: String, _ ch: String, _ name: String, _ who: String, _ text: String, _ minutesAgo: Double) -> DiscordMessage {
            DiscordMessage(id: id, channelID: ch, guildID: guild, channelName: name, author: who, content: text,
                           date: now.addingTimeInterval(-minutesAgo * 60))
        }
        return [
            m("1", "100000000000000011", "募集", "はると", "21時からスプラのナワバリ募集！あと2人。初心者さん歓迎です", 12),
            m("2", "100000000000000010", "お知らせ", "あおい", "今週末は部内大会です。参加する人はこのチャンネルに一言ください", 55),
            m("3", "100000000000000011", "募集", "みずき", "サーモンラン 22時ごろ 1人募集", 90),
            m("4", "100000000000000011", "募集", "そら", "土曜の夜に Steam のゲームを一緒に遊べる人募集", 240),
            m("5", "100000000000000010", "お知らせ", "あおい", "新しいボイスチャンネル「作業通話」を作りました", 60 * 26),
        ]
    }
}
