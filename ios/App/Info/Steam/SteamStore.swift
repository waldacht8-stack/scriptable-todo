import SwiftUI

/// Steam の画面で共有する状態（入口のカードと全画面が同じものを見る）
/// SteamID は端末のファイル（steam-settings.json）、Web API キーは Keychain にだけ保存する。
/// キーは任意：SteamID だけでプロフィール・ウィッシュリストのセール・ストアのセール・ニュースを読む。
@MainActor
final class SteamStore: ObservableObject {
    static let shared = SteamStore()
    static let keyName = "steam.webapikey"

    @Published private(set) var snapshot: SteamSnapshot?
    @Published private(set) var steamID: String
    @Published private(set) var hasKey: Bool
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    private static let settingsFile = "steam-settings.json"
    private static let snapshotFile = "steam-snapshot.json"

    private struct Settings: Codable { var steamID: String = "" }

    private init() {
        if isDemo {
            // -steamnokey：キーなしの見本・-steamprivate：非公開の見本
            let args: [String] = ProcessInfo.processInfo.arguments
            let priv: Bool = args.contains("-steamprivate")
            let noKey: Bool = priv || args.contains("-steamnokey")
            steamID = "76561190000000000"
            hasKey = !noKey
            snapshot = SteamDemo.snapshot(keyless: noKey, isPrivate: priv)
        } else {
            steamID = SplatFiles.load(Settings.self, Self.settingsFile)?.steamID ?? ""
            hasKey = InfoSecrets.has(Self.keyName)
            let s = SplatFiles.load(SteamSnapshot.self, Self.snapshotFile)
            snapshot = (s?.profile?.steamID == steamID) ? s : nil
        }
    }

    /// SteamID があれば使える（キーはなくてよい）
    var isConfigured: Bool { !steamID.isEmpty }

    /// 古ければ読み直す（10分）
    func refreshIfNeeded() async {
        guard !isDemo, isConfigured else { return }
        if let s = snapshot, Date.now.timeIntervalSince(s.fetchedAt) < 600 { return }
        await refresh()
    }

    func refresh() async {
        guard !isDemo, isConfigured, !loading else { return }
        let key: String? = InfoSecrets.get(Self.keyName)
        loading = true
        defer { loading = false }
        do {
            let s = try await SteamAPI.fetchAll(id: steamID, key: key, previous: snapshot)
            snapshot = s
            error = nil
            SplatFiles.save(s, Self.snapshotFile)
            InfoWidgetSync.update()   // 情報のウィジェット（セール）
        } catch SteamAPIError.notFound {
            error = "プロフィールが見つかりませんでした。SteamID を確かめてください。"
        } catch {
            // 前のデータはそのまま表示しておく
            self.error = "Steam を読み込めませんでした。通信を確認してください。"
        }
    }

    /// 設定を保存して読み直す。id はプロフィールの URL・カスタム URL の名前・17桁の SteamID のどれでもよい。キーは空でよい
    func save(idInput: String, key keyInput: String) async {
        let keyText = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyText.isEmpty { InfoSecrets.set(Self.keyName, keyText) }
        hasKey = InfoSecrets.has(Self.keyName)
        let raw = idInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDemo, !raw.isEmpty else { return }
        let key: String? = InfoSecrets.get(Self.keyName)
        loading = true
        do {
            let id = try await SteamAPI.resolveID(raw, key: key)
            loading = false
            if id != steamID {
                steamID = id
                snapshot = nil
                SplatFiles.save(Settings(steamID: id), Self.settingsFile)
                SplatFiles.remove(Self.snapshotFile)
            }
            error = nil
            await refresh()
        } catch SteamAPIError.badKey {
            loading = false
            error = "Web API キーが使えませんでした。キーを確かめるか、消してください。"
        } catch SteamAPIError.notFound {
            loading = false
            error = "「\(raw)」のプロフィールが見つかりませんでした。"
        } catch {
            loading = false
            self.error = "「\(raw)」を調べられませんでした。通信を確認するか、17桁の SteamID を入れてください。"
        }
    }

    /// Web API キーだけ消す（SteamID とデータは残す）
    func removeKey() async {
        guard !isDemo else { return }
        InfoSecrets.set(Self.keyName, nil)
        hasKey = false
        if var s = snapshot {
            s.recent = []
            s.ownedCount = nil
            snapshot = s
        }
        await refresh()
    }

    /// 連携をやめる（SteamID・キー・保存したデータを消す）
    func disconnect() {
        guard !isDemo else { return }
        InfoSecrets.set(Self.keyName, nil)
        SplatFiles.remove(Self.settingsFile)
        SplatFiles.remove(Self.snapshotFile)
        steamID = ""
        hasKey = false
        snapshot = nil
        error = nil
    }
}

// MARK: - 見本データ（起動引数 -demo。通信しない・架空の内容）

enum SteamDemo {
    /// keyless：キーなしで読める分だけ・isPrivate：プロフィールとウィッシュリストが非公開
    static func snapshot(now: Date = .now, keyless: Bool = false, isPrivate: Bool = false) -> SteamSnapshot {
        var s = SteamSnapshot()
        s.profile = SteamProfile(steamID: "76561190000000000", name: "sample_player", avatar: nil, state: isPrivate ? 0 : 1,
                                 playing: isPrivate ? nil : "Hollow Knight", isPublic: !isPrivate)
        if !keyless {
            s.recent = [
                SteamGame(appID: 367520, name: "Hollow Knight", minutes2Weeks: 492, minutesTotal: 3120, achieved: 34, achievementsTotal: 63),
                SteamGame(appID: 1145360, name: "Hades", minutes2Weeks: 186, minutesTotal: 2280, achieved: 21, achievementsTotal: 49),
                SteamGame(appID: 413150, name: "Stardew Valley", minutes2Weeks: 75, minutesTotal: 9400, achieved: 30, achievementsTotal: 49),
            ]
            s.ownedCount = 128
        }
        if isPrivate {
            s.wishlistHidden = true
        } else {
            s.wishlistHidden = false
            s.deals = [
                SteamDeal(appID: 646570, name: "Slay the Spire", discount: 70, finalPrice: "¥ 765", initialPrice: "¥ 2,550"),
                SteamDeal(appID: 588650, name: "Dead Cells", discount: 40, finalPrice: "¥ 1,470", initialPrice: "¥ 2,450"),
                SteamDeal(appID: 1794680, name: "Vampire Survivors", discount: 0, finalPrice: "¥ 600", initialPrice: nil),
            ]
        }
        let day: TimeInterval = 86400
        s.specials = [
            SteamSpecial(appID: 105600, name: "Terraria", discount: 50, finalYen: 490, originalYen: 980, endsAt: now.addingTimeInterval(day * 3)),
            SteamSpecial(appID: 504230, name: "Celeste", discount: 75, finalYen: 495, originalYen: 1980, endsAt: now.addingTimeInterval(day * 5)),
            SteamSpecial(appID: 1092790, name: "Inscryption", discount: 60, finalYen: 1032, originalYen: 2580, endsAt: nil),
            SteamSpecial(appID: 753640, name: "Outer Wilds", discount: 40, finalYen: 1500, originalYen: 2500, endsAt: now.addingTimeInterval(day * 2)),
        ]
        s.news = [
            SteamNews(id: "demo1", appName: keyless ? "Slay the Spire" : "Hollow Knight", title: "アップデートのお知らせ（見本）",
                      url: "https://store.steampowered.com/", date: now.addingTimeInterval(-7200)),
            SteamNews(id: "demo2", appName: keyless ? "Terraria" : "Stardew Valley", title: "季節のイベントが始まります（見本）",
                      url: "https://store.steampowered.com/", date: now.addingTimeInterval(-day * 2)),
        ]
        s.fetchedAt = now
        return s
    }
}
