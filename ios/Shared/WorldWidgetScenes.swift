import SwiftUI

// MARK: - 新しい世界観（地層・銀河・空・霧・深海）のウィジェット用の部品
// WorldWidget.swift の switch から呼ぶ。背景は WorldScenes の絵を止めたまま（still）・軽く（compact）描く。
// カードはすりガラス（material）や外側の光の輪を使わない軽い版。WidgetKit は止まった絵なので、動きは描き直しのときの入れ替わりだけ。
// 型は AnyView で消して1つにまとめる（世界観の switch が深い入れ子の型になり、Release の最適化が重くならないように）。

/// ウィジェット全体の背景
struct WidgetSceneBackground: View {
    let p: Palette

    var body: some View {
        let v: AnyView
        switch p.world {
        case .strata: v = AnyView(StrataBackdrop(p: p, still: true, compact: true))
        case .galaxy: v = AnyView(GalaxyBackdrop(p: p, still: true, compact: true))
        case .sky: v = AnyView(SkyBackdrop(p: p, still: true, compact: true))
        case .mist: v = AnyView(MistBackdrop(p: p, still: true, compact: true))
        case .deepsea: v = AnyView(DeepSeaBackdrop(p: p, still: true, compact: true))
        default: v = AnyView(p.background[0])
        }
        return v
    }
}

/// ウィジェットの中の小さなカード
struct WidgetSceneCard: View {
    let p: Palette
    let radius: CGFloat

    var body: some View {
        let v: AnyView
        switch p.world {
        case .strata: v = AnyView(StrataSlab(p: p, radius: radius, light: true))
        case .galaxy: v = AnyView(GalaxyCard(p: p, radius: radius, light: true))
        case .sky: v = AnyView(SkyCloudCard(p: p, radius: radius, light: true))
        case .mist: v = AnyView(MistCard(p: p, radius: radius, light: true))
        case .deepsea: v = AnyView(DeepSeaGlass(p: p, radius: radius, light: true))
        default: v = AnyView(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(p.card))
        }
        return v
    }
}

/// 強調色のボタンの面。銀河・深海はかすかに光り、空は白い縁、地層は下が少し濃い
struct WidgetSceneButton: View {
    let p: Palette
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let glow: Bool = p.world == .galaxy || p.world == .deepsea
        let rimAlpha: Double = p.world == .sky ? 0.5 : (glow ? 0.45 : 0)
        let rimWidth: CGFloat = p.world == .sky ? 1.5 : 0.8
        let shadow: Color = glow ? p.accent.opacity(0.5) : (p.world == .strata ? sceneColor(0x5A3A1E, 0.25) : Color.clear)
        let fill = LinearGradient(colors: [p.accent, p.world == .strata ? p.accent.opacity(0.85) : p.accent],
                                  startPoint: .top, endPoint: .bottom)
        return shape.fill(fill)
            .overlay(shape.strokeBorder(Color.white.opacity(rimAlpha), lineWidth: rimWidth))
            .shadow(color: shadow, radius: glow ? 6 : 3, y: glow ? 0 : 2)
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
