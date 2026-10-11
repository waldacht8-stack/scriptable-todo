import Foundation
import WidgetKit

// MARK: - 情報のウィジェットに渡す元データ（info-widget.json。ウィジェット担当が読む。項目名は変えない）
// 書くのはアプリ（App/Info/InfoWidgetSync.swift）。話題・スプラ・Steam を読み込んだあとに、中身が変わったときだけ書く

struct InfoWidgetFeed: Codable, Equatable {
    struct Headline: Codable, Equatable {
        var title: String
        var source: String          // 媒体・投稿者（なければ取得元の名前）
        var topic: String           // 話題のキーワード
        var colorIndex: Int         // InfoTopicColor の番号（0 はデザインの強調色）
    }

    struct Splat: Codable, Equatable {
        var endsAt: String          // ISO8601（いまの時間帯の終わり）
        var regular: String?        // ステージ名（「・」区切り）
        var bankara: String?        // バンカラマッチ（チャレンジ）
        var x: String?              // Xマッチ
    }

    struct SteamSale: Codable, Equatable {
        var title: String
        var discount: Int           // 割引率（%）
    }

    var headlines: [Headline] = []  // 新しい未読から3件
    var splat: Splat?
    var steamSale: SteamSale?
}

enum InfoWidgetStore {
    static let file = "info-widget.json"

    static func load() -> InfoWidgetFeed? { SharedStore.load(InfoWidgetFeed.self, from: file) }

    /// 前と同じなら書かない（ウィジェットの更新を増やさない）
    @discardableResult
    static func writeIfChanged(_ feed: InfoWidgetFeed) -> Bool {
        if load() == feed { return false }
        SharedStore.save(feed, to: file)   // SharedStore.save が WidgetCenter.shared.reloadAllTimelines() も呼ぶ
        return true
    }
}
