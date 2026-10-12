import Foundation

// MARK: - 情報 › ゲームの並びと表示（アプリの設定 settings.json に保存。情報のウィジェットも読む）
// Discord はここに入れない（一覧にも、並べ替えの画面にも出さない。InfoGameSection の隠しコマンドでだけ出す）

/// ゲームの一覧に並べるもの
enum GameItem: String, CaseIterable, Identifiable, Hashable {
    case splatoon, steam, identityV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .splatoon: "スプラトゥーン3"
        case .steam: "Steam"
        case .identityV: "第五人格"
        }
    }

    var symbol: String {
        switch self {
        case .splatoon: "drop.fill"
        case .steam: "gamecontroller.fill"
        case .identityV: "theatermasks.fill"
        }
    }
}

enum GameListLogic {
    /// 保存された並び（知らない名前・重なりは捨て、まだないものは後ろに既定の順で足す）
    static func order(_ saved: [String]) -> [GameItem] {
        var out: [GameItem] = []
        for raw in saved {
            guard let g = GameItem(rawValue: raw), !out.contains(g) else { continue }
            out.append(g)
        }
        for g in GameItem.allCases where !out.contains(g) { out.append(g) }
        return out
    }

    /// 表示するものだけを、保存された並びで
    static func visible(order saved: [String], hidden: [String]) -> [GameItem] {
        let off: Set<String> = Set(hidden)
        return order(saved).filter { !off.contains($0.rawValue) }
    }
}

extension AppSettings {
    /// すべてのゲーム（隠したものも含む）を並びの順で
    var gameOrderItems: [GameItem] { GameListLogic.order(gameOrder) }

    /// 一覧に出すゲーム
    var visibleGames: [GameItem] { GameListLogic.visible(order: gameOrder, hidden: hiddenGames) }

    func isGameShown(_ g: GameItem) -> Bool { !hiddenGames.contains(g.rawValue) }
}
