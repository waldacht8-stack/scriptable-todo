import SwiftUI

// MARK: - 世界観（アプリ全体の見た目と動き）
// 色合い（AppTheme）が「色」を決めるのに対し、世界観は背景・カード・大きな数字・動き方まで描き分ける。
// 世界観を選ぶと、その世界観の色の組が色合いより優先される（強調色などのカスタマイズはその上に重なる）。
// 各画面は今までどおり paletteBackground / paletteCard / BigCount を使えば、世界観に合わせて描き変わる。
// 設定の値は AppSettings.world（"none" は色合いのまま）。起動引数 -world <値>（スクリーンショット用）。

/// 0xRRGGBB から色を作る（このファイルの中だけで使う）
fileprivate func wx(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

enum World: String, CaseIterable, Identifiable {
    case none       // 色合いのまま
    case aurora     // オーロラ：流れる光の背景にすりガラス
    case strata     // 地層：用事が積もる。砂の層と堆積した板（WorldScenes/StrataScene.swift）
    case galaxy     // 銀河：深い宇宙で星の腕が回る（WorldScenes/GalaxyScene.swift）
    case sky        // 空：いまの時刻と天気の空に雲が流れる（WorldScenes/SkyScene.swift）
    case mist       // 霧：夜明けの湖と森。霧の層が流れる（WorldScenes/MistScene.swift）
    case deepsea    // 深海：浅瀬から深みへ。光がゆらぎマリンスノーが降る（WorldScenes/DeepSeaScene.swift）

    var id: String { rawValue }
    static func from(_ raw: String) -> World { World(rawValue: raw) ?? World.none }

    /// 世界観を選んでいるか（「なし」以外）
    var isOn: Bool { self != World.none }

    var name: String {
        switch self {
        case .none: "なし"
        case .aurora: "オーロラ"
        case .strata: "地層"
        case .galaxy: "銀河"
        case .sky: "空"
        case .mist: "霧"
        case .deepsea: "深海"
        }
    }

    var summary: String {
        switch self {
        case .none: "色合いだけで描く"
        case .aurora: "光の背景にすりガラス"
        case .strata: "用事が砂の層に積もる"
        case .galaxy: "星の腕がゆっくり回る"
        case .sky: "いまの時刻の空と雲"
        case .mist: "夜明けの湖に霧が流れる"
        case .deepsea: "光がゆらぐ深い海"
        }
    }

    /// この世界観の動き方（nil は色合いの動き方のまま）
    var motion: MotionStyle? {
        switch self {
        case .none: nil
        case .aurora: .smooth
        case .strata: .gentle      // 静かに沈んで積もる・削れる
        case .galaxy: .smooth      // 星がなめらかに流れる
        case .sky: .smooth         // 雲のようにふわりと
        case .mist: .gentle        // 霧のように控えめに
        case .deepsea: .smooth     // 水の中のようにゆったり
        }
    }

    /// この世界観の色の組（nil は色合いのまま）。文字/カード・onAccent/accent はどれも 4.5:1 以上
    var palette: Palette? {
        switch self {
        case .none:
            return nil
        case .aurora:
            // カードの色は不透明にする（重なったカードの文字が透けないように）。すりガラスの見た目は WorldCardSurface で出す
            return Palette(background: [wx(0x0D0B1E), wx(0x161034)], card: wx(0x231C47),
                           text: wx(0xF4F2FF), sub: wx(0xBDB6E0), accent: wx(0x9EF0E6),
                           overdue: wx(0xFF9D7A), onAccent: wx(0x0D0B1E),
                           fontDesign: .rounded, radius: 24, scheme: .dark, world: .aurora)
        case .strata:
            // 文字は上〜86% の明るい層に載る（いちばん濃い層 #D9B985 でも本文 8.2・補足 5.4・強調 4.9）
            return Palette(background: [wx(0xF4EADB), wx(0xD9B985)], card: wx(0xFAF3E7),
                           text: wx(0x2A1A0C), sub: wx(0x523C2A), accent: wx(0x7A2E0C),
                           overdue: wx(0x8F1F0B), onAccent: .white,
                           fontDesign: .default, radius: 16, scheme: .light, world: .strata)
        case .galaxy:
            return Palette(background: [wx(0x1B1440), wx(0x03030A)], card: wx(0x161236),
                           text: wx(0xF5F2FF), sub: wx(0xC9C5EA), accent: wx(0xFFD9A8),
                           overdue: wx(0xFF9DB8), onAccent: wx(0x1E1638),
                           fontDesign: .rounded, radius: 22, scheme: .dark, world: .galaxy)
        case .sky:
            // 時刻で変わる（明け方・昼・夕方は明るい色合い、夜は暗い色合い）
            return SkyPhase.current().palette
        case .mist:
            return Palette(background: [wx(0xC4CBD0), wx(0xAEB8C0)], card: wx(0xF3F4F3),
                           text: wx(0x1C2731), sub: wx(0x283846), accent: wx(0x27435A),
                           overdue: wx(0x7E300C), onAccent: .white,
                           fontDesign: .default, radius: 20, scheme: .light, world: .mist)
        case .deepsea:
            // 上の浅瀬（#0C6A8A）でも本文 5.7・補足 4.8
            return Palette(background: [wx(0x0C6A8A), wx(0x01060E)], card: wx(0x0A2E48),
                           text: wx(0xE8F8FF), sub: wx(0xC8EAF5), accent: wx(0x7DF9E6),
                           overdue: wx(0xFFC2A3), onAccent: wx(0x02213A),
                           fontDesign: .rounded, radius: 22, scheme: .dark, world: .deepsea)
        }
    }

    /// 画面上部の大きな数字の大きさ
    var bigNumberSize: CGFloat {
        switch self {
        case .galaxy: 60
        default: 56
        }
    }

    /// 大きな数字の字間
    var bigNumberTracking: CGFloat { 0 }

    /// 大きな数字を強調色で描くか
    var bigNumberAccent: Bool { false }

    /// 「今日」のフォーカスで、左へ払ったときの言葉
    var postponeWord: String { "明日へ" }
}

// MARK: - 世界観ごとの背景

/// 全画面の背景。オーロラは光がゆっくり流れる
struct WorldBackground: View {
    let p: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 住人（モグラ・猫など）を描くか（タブの画面だけ。WorldCritters/CritterCore.swift）
    @Environment(\.worldCritters) private var critters

    var body: some View {
        ZStack {
            scenery
            if critters && WorldMotion.hasCritters(p.world) {
                WorldCritterLayer(p: p)
            }
        }
    }

    @ViewBuilder
    private var scenery: some View {
        let colors: [Color] = p.background.count > 1 ? p.background : [p.background[0], p.background[0]]
        let base = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        switch p.world {
        case .aurora:
            ZStack {
                base
                if reduceMotion {
                    AuroraGlow(t: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 20)) { ctx in
                        AuroraGlow(t: ctx.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        case .strata, .galaxy, .sky, .mist, .deepsea:
            SceneBackdrop(p: p)
        default:
            base
        }
    }
}

/// オーロラの光（紫・青緑・桃色のぼかした丸がゆっくり動く）
private struct AuroraGlow: View {
    let t: Double

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let a: CGFloat = CGFloat(sin(t / 9)) * 40
            let b: CGFloat = CGFloat(cos(t / 11)) * 50
            ZStack {
                Circle().fill(wx(0x6D4BFF)).frame(width: 300, height: 300)
                    .position(x: w * 0.15 + a, y: h * 0.12 + b * 0.5).opacity(0.75)
                Circle().fill(wx(0x12C2B5)).frame(width: 300, height: 300)
                    .position(x: w * 0.95 - a, y: h * 0.42 + b).opacity(0.5)
                Circle().fill(wx(0xFF5FA2)).frame(width: 280, height: 280)
                    .position(x: w * 0.3 + b, y: h * 0.92 - a).opacity(0.4)
            }
            .blur(radius: 70)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 世界観ごとのカード

/// カードの面（形・塗り・影・枠）。paletteCard の背景に敷く
struct WorldCardSurface: View {
    let p: Palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: p.radius, style: .continuous)
        switch p.world {
        case .aurora:
            // すりガラス（下の光がうっすら見える程度。文字が読めるよう濃いめに）
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(p.card.opacity(0.78)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.26), lineWidth: 1))
        case .strata, .galaxy, .sky, .mist, .deepsea:
            SceneCardSurface(p: p)
        case .none:
            let shadow: Color = .black.opacity(p.scheme == .dark || p.outline != nil ? 0 : 0.06)
            shape.fill(p.card).shadow(color: shadow, radius: 12, y: 4)
                .overlay(shape.strokeBorder(p.outline ?? .clear, lineWidth: p.outline == nil ? 0 : 1.5))
        }
    }
}

// MARK: - 世界観ごとの大きな数字の光（BigCount が使う）

extension World {
    /// 大きな数字の光（内側・外側の2つの影）。銀河は星のように光り、深海は冷たく光る。地層は刻んだような白い縁
    func numberGlow(_ p: Palette) -> (inner: Color, innerRadius: CGFloat, innerY: CGFloat, outer: Color, outerRadius: CGFloat) {
        switch self {
        case .galaxy: return (wx(0xFFE4B8, 0.75), 6, 0, wx(0x8A6BFF, 0.65), 18)
        case .deepsea: return (wx(0x7DF9E6, 0.5), 10, 0, .clear, 0)
        case .strata: return (Color.white.opacity(0.6), 0, 1, .clear, 0)
        case .sky: return (Color.white.opacity(p.scheme == .dark ? 0.25 : 0.55), 10, 0, .clear, 0)
        case .mist: return (wx(0xFFE2BC, 0.7), 12, 0, .clear, 0)
        default: return (.clear, 0, 0, .clear, 0)
        }
    }
}

extension View {
    /// 大きな数字に世界観の光をのせる（ほかの世界観では透明な影なので見た目は変わらない）
    func worldNumberGlow(_ p: Palette) -> some View {
        let g = p.world.numberGlow(p)
        return self
            .shadow(color: g.inner, radius: g.innerRadius, x: 0, y: g.innerY)
            .shadow(color: g.outer, radius: g.outerRadius)
    }
}

/// 新しい世界観（地層・銀河・空・霧・深海）の背景。型を消して1つにまとめる（Release の最適化が重くならないように）
struct SceneBackdrop: View {
    let p: Palette

    var body: some View {
        let v: AnyView
        switch p.world {
        case .strata: v = AnyView(StrataBackdrop(p: p))
        case .galaxy: v = AnyView(GalaxyBackdrop(p: p))
        case .sky: v = AnyView(SkyBackdrop(p: p))
        case .mist: v = AnyView(MistBackdrop(p: p))
        case .deepsea: v = AnyView(DeepSeaBackdrop(p: p))
        default: v = AnyView(p.background[0])
        }
        return v
    }
}

/// 新しい世界観のカードの面（型を消して1つにまとめる）
struct SceneCardSurface: View {
    let p: Palette

    var body: some View {
        let v: AnyView
        switch p.world {
        case .strata: v = AnyView(StrataSlab(p: p))
        case .galaxy: v = AnyView(GalaxyCard(p: p))
        case .sky: v = AnyView(SkyCloudCard(p: p))
        case .mist: v = AnyView(MistCard(p: p))
        case .deepsea: v = AnyView(DeepSeaGlass(p: p))
        default: v = AnyView(RoundedRectangle(cornerRadius: p.radius, style: .continuous).fill(p.card))
        }
        return v
    }
}
