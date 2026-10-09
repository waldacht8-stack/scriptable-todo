import Foundation

/// 「今日」の画面構成。構成ごとにボタンの位置と操作が変わる。
/// rawValue は設定ファイルに保存されるので変えない（足すだけにする）。
enum TodayLayout: String, CaseIterable, Identifiable {
    case focus      // 1件ずつ大きなカード。右下の＋、スワイプで完了・延期
    case board      // グループ：期限ごとの見出しで分けた一覧。下の入力欄で追加
    case thumb      // 週間：日付ボタンで日を選び、時刻つきで一覧
    case timeline   // ながれ：1本の線でつないだ時系列と「いま」の印
    case kanban     // かんばん：今日・明日・あとで の3列を横にめくる
    case checklist  // チェックリスト：紙のリストのように詰めた一覧と大きなチェック欄

    var id: String { rawValue }

    var name: String {
        switch self {
        case .focus: "フォーカス"
        case .board: "グループ"
        case .thumb: "週間"
        case .timeline: "ながれ"
        case .kanban: "かんばん"
        case .checklist: "チェックリスト"
        }
    }

    var summary: String {
        switch self {
        case .focus: "1件ずつ大きく。スワイプで完了・延期"
        case .board: "今日・明日…と期限ごとに分けて一覧"
        case .thumb: "日付を選んで、その日を時刻順に"
        case .timeline: "1本の線で時系列。いまの位置がわかる"
        case .kanban: "今日・明日・あとでの3列を横にめくる"
        case .checklist: "紙のリストのように、たくさんを一度に"
        }
    }

    static func from(_ raw: String) -> TodayLayout { TodayLayout(rawValue: raw) ?? .focus }
}
