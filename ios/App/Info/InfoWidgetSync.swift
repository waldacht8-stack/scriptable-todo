import Foundation

/// 情報のウィジェットの元データ（Shared/InfoWidgetFeed.swift）を、アプリの状態から作って書く
/// 呼ぶところ：話題の更新（InfoModel.refresh）・スプラのステージの更新・Steam の更新のあと。1回の更新につき1回まで、中身が同じなら書かない
@MainActor
enum InfoWidgetSync {
    /// headlines を渡さなければ前のものを残す（スプラ・Steam だけ更新したとき）
    static func update(headlines: [InfoWidgetFeed.Headline]? = nil, now: Date = .now) {
        guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        var feed = InfoWidgetStore.load() ?? InfoWidgetFeed()
        if let headlines { feed.headlines = Array(headlines.prefix(3)) }
        // 情報 › ゲームでオフにしたゲームは、ウィジェットにも出さない
        let s: AppSettings = SettingsData.load()
        feed.splat = s.isGameShown(.splatoon) ? splat(SplatStore.shared.schedule, now: now) : nil
        feed.steamSale = s.isGameShown(.steam) ? steam(SteamStore.shared.snapshot) : nil
        InfoWidgetStore.writeIfChanged(feed)
    }

    static func headlines(_ model: InfoModel) -> [InfoWidgetFeed.Headline] {
        model.deck(.all).prefix(3).map { a in
            let t: InfoTopic? = model.topic(for: a)
            return InfoWidgetFeed.Headline(title: model.title(a), source: a.site ?? a.sourceName,
                                           topic: t?.keyword ?? "", colorIndex: t?.color ?? 0)
        }
    }

    static func splat(_ s: SplatSchedule?, now: Date) -> InfoWidgetFeed.Splat? {
        guard let s, let end = s.nextSwitch(now: now) else { return nil }
        let active = s.rotations.filter { $0.isActive(at: now) }
        func names(_ mode: SplatMode) -> String? {
            guard let r = active.first(where: { $0.mode == mode }), !r.stages.isEmpty else { return nil }
            return r.stages.map(\.name).joined(separator: "・")
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return InfoWidgetFeed.Splat(endsAt: f.string(from: end), regular: names(.regular),
                                    bankara: names(.bankaraChallenge) ?? names(.bankaraOpen), x: names(.x))
    }

    static func steam(_ s: SteamSnapshot?) -> InfoWidgetFeed.SteamSale? {
        guard let d = s?.deals.filter({ $0.discount > 0 }).max(by: { $0.discount < $1.discount }) else { return nil }
        return InfoWidgetFeed.SteamSale(title: d.name, discount: d.discount)
    }
}
