import SwiftUI

// MARK: - 新しい世界観（地層・銀河・空・霧・深海）のウィジェット用の部品
// WorldWidget.swift の switch から呼ぶ。背景は WorldScenes の絵を止めたまま（still）・軽く（compact）描く。
// カードはすりガラス（material）や外側の光の輪を使わない軽い版。WidgetKit は止まった絵なので、動きは描き直しのときの入れ替わりだけ。

/// ウィジェット全体の背景
struct WidgetSceneBackground: View {
    let p: Palette

    var body: some View {
        switch p.world {
        case .strata: StrataBackdrop(p: p, still: true, compact: true)
        case .galaxy: GalaxyBackdrop(p: p, still: true, compact: true)
        case .sky: SkyBackdrop(p: p, still: true, compact: true)
        case .mist: MistBackdrop(p: p, still: true, compact: true)
        case .deepsea: DeepSeaBackdrop(p: p, still: true, compact: true)
        default: p.background[0]
        }
    }
}

/// ウィジェットの中の小さなカード
struct WidgetSceneCard: View {
    let p: Palette
    let radius: CGFloat

    var body: some View {
        switch p.world {
        case .strata: StrataSlab(p: p, radius: radius, light: true)
        case .galaxy: GalaxyCard(p: p, radius: radius, light: true)
        case .sky: SkyCloudCard(p: p, radius: radius, light: true)
        case .mist: MistCard(p: p, radius: radius, light: true)
        case .deepsea: DeepSeaGlass(p: p, radius: radius, light: true)
        default: RoundedRectangle(cornerRadius: radius, style: .continuous).fill(p.card)
        }
    }
}

/// 強調色のボタンの面。銀河・深海はかすかに光り、空は白い縁、地層は下が少し濃い
struct WidgetSceneButton: View {
    let p: Palette
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch p.world {
        case .galaxy, .deepsea:
            shape.fill(p.accent)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                .shadow(color: p.accent.opacity(0.5), radius: 6)
        case .sky:
            shape.fill(p.accent)
                .overlay(shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
        case .strata:
            let g = LinearGradient(colors: [p.accent, p.accent.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            shape.fill(g)
                .shadow(color: sceneColor(0x5A3A1E, 0.25), radius: 3, y: 2)
        default:
            shape.fill(p.accent)
        }
    }
}

extension World {
    /// 新しい世界観の、行が抜ける・入るときの動き
    /// 地層：沈んで崩れる／銀河：流れ星のように右へ抜ける／空：雲のように流れる／霧：かすむ／深海：泡のように上へ
    func sceneRowTransition() -> AnyTransition {
        switch self {
        case .strata:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.move(edge: .top).combined(with: .opacity),
                removal: AnyTransition.offset(y: 10).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom)))
        case .galaxy:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.scale(scale: 0.8).combined(with: .opacity),
                removal: AnyTransition.offset(x: 60, y: 24).combined(with: .opacity).combined(with: .scale(scale: 0.6)))
        case .sky:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.offset(x: -20).combined(with: .opacity),
                removal: AnyTransition.offset(x: 40).combined(with: .opacity))
        case .mist:
            let blur: BlurReplaceTransition = .blurReplace
            return AnyTransition(blur)
        case .deepsea:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.offset(y: 12).combined(with: .opacity),
                removal: AnyTransition.offset(y: -14).combined(with: .opacity))
        default:
            return AnyTransition.opacity
        }
    }

    /// 新しい世界観か（WorldWidget.swift の switch でまとめて扱う）
    var isScene: Bool {
        switch self {
        case .strata, .galaxy, .sky, .mist, .deepsea: true
        default: false
        }
    }
}
