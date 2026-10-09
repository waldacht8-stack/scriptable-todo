import SwiftUI

/// スプラトゥーン3 の画面で共有する状態（入口のカードと全画面が同じものを見る）
@MainActor
final class SplatStore: ObservableObject {
    static let shared = SplatStore()

    @Published private(set) var schedule: SplatSchedule?
    @Published private(set) var records: SplatRecords?
    @Published private(set) var settings: SplatSettings
    @Published private(set) var loadingSchedule = false
    @Published private(set) var loadingRecords = false
    @Published private(set) var scheduleError: String?
    @Published private(set) var recordsError: String?

    let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    private init() {
        if isDemo {
            settings = SplatSettings()
            settings.screenName = "sample"
            schedule = SplatDemo.schedule()
            records = SplatDemo.records()
        } else {
            settings = SplatFiles.load(SplatSettings.self, SplatFiles.settings) ?? SplatSettings()
            schedule = SplatFiles.load(SplatSchedule.self, SplatFiles.schedule)
            let r = SplatFiles.load(SplatRecords.self, SplatFiles.records)
            records = (r?.screenName == settings.screenName) ? r : nil
        }
    }

    var hasScreenName: Bool { !settings.screenName.isEmpty }

    /// 古ければ読み直す（ステージは10分、戦績は5分）
    func refreshIfNeeded() async {
        guard !isDemo else { return }
        let now = Date.now
        let s = schedule
        let staleSchedule = s == nil || now.timeIntervalSince(s!.fetchedAt) > 600 || s!.nextSwitch(now: now) == nil
        if staleSchedule { await refreshSchedule() }
        if hasScreenName, records == nil || now.timeIntervalSince(records!.fetchedAt) > 300 {
            await refreshRecords()
        }
    }

    func refreshAll() async {
        guard !isDemo else { return }
        await refreshSchedule()
        if hasScreenName { await refreshRecords() }
    }

    func refreshSchedule() async {
        guard !isDemo, !loadingSchedule else { return }
        loadingSchedule = true
        defer { loadingSchedule = false }
        do {
            let s = try await SplatAPI.fetchSchedule()
            schedule = s
            scheduleError = nil
            SplatFiles.save(s, SplatFiles.schedule)
        } catch {
            scheduleError = "ステージ情報を読み込めませんでした。通信を確認してください。"
        }
    }

    func refreshRecords() async {
        guard !isDemo, hasScreenName, !loadingRecords else { return }
        loadingRecords = true
        defer { loadingRecords = false }
        do {
            let r = try await SplatAPI.fetchRecords(screenName: settings.screenName)
            records = r
            recordsError = nil
            SplatFiles.save(r, SplatFiles.records)
        } catch SplatAPIError.notFound {
            recordsError = "stat.ink に「\(settings.screenName)」が見つかりませんでした。スクリーンネームを確かめてください。"
        } catch {
            recordsError = "戦績を読み込めませんでした。通信を確認してください。"
        }
    }

    /// スクリーンネームを保存して読み直す（空にすると戦績を消す）
    func setScreenName(_ raw: String) async {
        let name = SplatAPI.cleanScreenName(raw)
        guard name != settings.screenName else { return }
        settings.screenName = name
        recordsError = nil
        records = nil
        guard !isDemo else { return }
        SplatFiles.save(settings, SplatFiles.settings)
        SplatFiles.remove(SplatFiles.records)
        if !name.isEmpty { await refreshRecords() }
    }
}
