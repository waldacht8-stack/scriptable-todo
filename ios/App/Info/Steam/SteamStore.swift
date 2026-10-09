import SwiftUI

/// Steam の画面で共有する状態（入口のカードと全画面が同じものを見る）
/// SteamID は端末のファイル（steam-settings.json）、Web API キーは Keychain にだけ保存する。
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
            steamID = "76561190000000000"
            hasKey = true
            snapshot = SteamDemo.snapshot()
        } else {
            steamID = SplatFiles.load(Settings.self, Self.settingsFile)?.steamID ?? ""
            hasKey = InfoSecrets.has(Self.keyName)
            let s = SplatFiles.load(SteamSnapshot.self, Self.snapshotFile)
            snapshot = (s?.profile?.steamID == steamID) ? s : nil
        }
    }

    var isConfigured: Bool { !steamID.isEmpty && hasKey }

    /// 古ければ読み直す（10分）
    func refreshIfNeeded() async {
        guard !isDemo, isConfigured else { return }
        if let s = snapshot, Date.now.timeIntervalSince(s.fetchedAt) < 600 { return }
        await refresh()
    }

    func refresh() async {
        guard !isDemo, isConfigured, !loading, let key = InfoSecrets.get(Self.keyName) else { return }
        loading = true
        defer { loading = false }
        do {
            let s = try await SteamAPI.fetchAll(id: steamID, key: key)
            snapshot = s
            error = nil
            SplatFiles.save(s, Self.snapshotFile)
        } catch SteamAPIError.badKey {
            error = "Web API キーが使えませんでした。キーを確かめてください。"
        } catch SteamAPIError.notFound {
            error = "プロフィールが見つかりませんでした。SteamID を確かめてください。"
        } catch {
            self.error = "Steam を読み込めませんでした。通信を確認してください。"
        }
    }

    /// 設定を保存して読み直す。id はプロフィールの URL・カスタム URL の名前・17桁の SteamID のどれでもよい
    func save(idInput: String, key keyInput: String) async {
        let keyText = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyText.isEmpty { InfoSecrets.set(Self.keyName, keyText) }
        hasKey = InfoSecrets.has(Self.keyName)
        let raw = idInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isDemo, let key = InfoSecrets.get(Self.keyName), !raw.isEmpty else { return }
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
            error = "Web API キーが使えませんでした。キーを確かめてください。"
        } catch {
            loading = false
            self.error = "「\(raw)」のプロフィールが見つかりませんでした。"
        }
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
    static func snapshot(now: Date = .now) -> SteamSnapshot {
        var s = SteamSnapshot()
        s.profile = SteamProfile(steamID: "76561190000000000", name: "sample_player", avatar: nil, state: 1,
                                 playing: "Hollow Knight")
        s.recent = [
            SteamGame(appID: 367520, name: "Hollow Knight", minutes2Weeks: 492, minutesTotal: 3120, achieved: 34, achievementsTotal: 63),
            SteamGame(appID: 1145360, name: "Hades", minutes2Weeks: 186, minutesTotal: 2280, achieved: 21, achievementsTotal: 49),
            SteamGame(appID: 413150, name: "Stardew Valley", minutes2Weeks: 75, minutesTotal: 9400, achieved: 30, achievementsTotal: 49),
        ]
        s.ownedCount = 128
        s.deals = [
            SteamDeal(appID: 646570, name: "Slay the Spire", discount: 70, finalPrice: "¥ 765", initialPrice: "¥ 2,550"),
            SteamDeal(appID: 588650, name: "Dead Cells", discount: 40, finalPrice: "¥ 1,470", initialPrice: "¥ 2,450"),
            SteamDeal(appID: 1794680, name: "Vampire Survivors", discount: 0, finalPrice: "¥ 600", initialPrice: nil),
        ]
        s.news = [
            SteamNews(id: "demo1", appName: "Hollow Knight", title: "アップデートのお知らせ（見本）", url: "https://store.steampowered.com/",
                      date: now.addingTimeInterval(-7200)),
            SteamNews(id: "demo2", appName: "Stardew Valley", title: "季節のイベントが始まります（見本）", url: "https://store.steampowered.com/",
                      date: now.addingTimeInterval(-86400 * 2)),
        ]
        s.fetchedAt = now
        return s
    }
}
