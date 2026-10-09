import SwiftUI

/// 色合い（テーマ）ごとの「動き方」。画面・ウィジェットのアニメーションはここから取る。
/// 例：withAnimation(motion.tap) { … } / .animation(motion.change, value: x) / .transition(motion.appear)
enum MotionStyle: String {
    case snappy     // きびきび（クリーン）
    case smooth     // ゆったり滑らか（ナイト）
    case bouncy     // 弾む（朝焼け）
    case gentle     // 控えめ（手帳）

    /// テーマから決める。新しいテーマを足したら、ここにも1行足す（未登録はきびきび）
    static func from(_ theme: AppTheme) -> MotionStyle {
        switch theme.rawValue {
        case "night": .smooth
        case "dawn": .bouncy
        case "paper": .gentle
        default: .snappy
        }
    }

    /// ボタンを押した・完了にしたときの反応
    var tap: Animation {
        switch self {
        case .snappy: .snappy(duration: 0.25)
        case .smooth: .smooth(duration: 0.45)
        case .bouncy: .bouncy(duration: 0.4, extraBounce: 0.15)
        case .gentle: .easeOut(duration: 0.3)
        }
    }

    /// 並びや中身が変わったとき
    var change: Animation {
        switch self {
        case .snappy: .snappy(duration: 0.3)
        case .smooth: .smooth(duration: 0.55)
        case .bouncy: .spring(duration: 0.5, bounce: 0.3)
        case .gentle: .easeInOut(duration: 0.35)
        }
    }

    /// 出てくる・消えるとき
    var appear: AnyTransition {
        switch self {
        case .snappy: .opacity.combined(with: .scale(scale: 0.96))
        case .smooth: .opacity.combined(with: .offset(y: 12))
        case .bouncy: .scale(scale: 0.85).combined(with: .opacity)
        case .gentle: .opacity
        }
    }
}

private struct MotionKey: EnvironmentKey { static let defaultValue = MotionStyle.snappy }

extension EnvironmentValues {
    /// 今のテーマの動き方（RootView が設定する）
    var motion: MotionStyle {
        get { self[MotionKey.self] }
        set { self[MotionKey.self] = newValue }
    }
}
