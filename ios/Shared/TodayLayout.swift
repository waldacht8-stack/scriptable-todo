import Foundation

/// 「今日」の画面構成。構成ごとにボタンの位置と操作が変わる。
enum TodayLayout: String, CaseIterable, Identifiable {
    case focus      // 1件ずつ大きなカード。右下の＋、スワイプで完了・延期
    case board      // グループ：期限ごとの見出しで分けた一覧。下の入力欄で追加
    case thumb      // 週間：日付ボタンで日を選び、時刻つきで一覧
    case timeline   // ながれ：1本の線でつないだ時系列と「いま」の印

    var id: String { rawValue }

    var name: String {
        switch self {
        case .focus: "フォーカス"
        case .board: "グループ"
        case .thumb: "週間"
        case .timeline: "ながれ"
        }
    }

    var summary: String {
        switch self {
        case .focus: "1件ずつ大きく。スワイプで完了・延期"
        case .board: "今日・明日…と期限ごとに分けて一覧"
        case .thumb: "日付を選んで、その日を時刻順に"
        case .timeline: "1本の線で時系列。いまの位置がわかる"
        }
    }

    static func from(_ raw: String) -> TodayLayout { TodayLayout(rawValue: raw) ?? .focus }
}
