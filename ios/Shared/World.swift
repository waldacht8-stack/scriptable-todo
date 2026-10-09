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
    case hinata     // 日なた：いまの1件に日が当たる。暖かい光
    case brutal     // ネオブルータル：太い黒枠とずらした影、原色
    case aurora     // オーロラ：流れる光の背景にすりガラス
    case bento      // ベント：大小のタイルを組んだ1画面
    case clay       // クレイ：粘土のようにぷっくり
    case swiss      // スイス：巨大な数字と格子

    var id: String { rawValue }
    static func from(_ raw: String) -> World { World(rawValue: raw) ?? World.none }

    /// 世界観を選んでいるか（「なし」以外）
    var isOn: Bool { self != World.none }

    var name: String {
        switch self {
        case .none: "なし"
        case .hinata: "日なた"
        case .brutal: "ネオブルータル"
        case .aurora: "オーロラ"
        case .bento: "ベント"
        case .clay: "クレイ"
        case .swiss: "スイス"
        }
    }

    var summary: String {
        switch self {
        case .none: "色合いだけで描く"
        case .hinata: "いまの1件に日が当たる"
        case .brutal: "太い黒枠とずらした影"
        case .aurora: "光の背景にすりガラス"
        case .bento: "大小のタイルを組む"
        case .clay: "粘土のようにぷっくり"
        case .swiss: "巨大な数字と細い罫線"
        }
    }

    /// この世界観の動き方（nil は色合いの動き方のまま）
    var motion: MotionStyle? {
        switch self {
        case .none: nil
        case .hinata: .smooth
        case .brutal: .crisp
        case .aurora: .smooth
        case .bento: .snappy
        case .clay: .bouncy
        case .swiss: .crisp
        }
    }

    /// この世界観の色の組（nil は色合いのまま）。文字/カード・onAccent/accent はどれも 4.5:1 以上
    var palette: Palette? {
        switch self {
        case .none:
            return nil
        case .hinata:
            return Palette(background: [wx(0xFFF1DC), wx(0xF6D2B4)], card: wx(0xFFFAEE),
                           text: wx(0x2B2116), sub: wx(0x6B4A1F), accent: wx(0xB4461E),
                           overdue: wx(0xA8320F), onAccent: .white,
                           fontDesign: .rounded, radius: 26, scheme: .light, world: .hinata)
        case .brutal:
            return Palette(background: [wx(0xFFF3D6)], card: .white,
                           text: wx(0x111111), sub: wx(0x3D3D3D), accent: wx(0xFF7EB6),
                           overdue: wx(0xC4122F), onAccent: wx(0x111111),
                           fontDesign: .default, radius: 14, scheme: .light, outline: wx(0x111111), world: .brutal)
        case .aurora:
            // カードの色は不透明にする（重なったカードの文字が透けないように）。すりガラスの見た目は WorldCardSurface で出す
            return Palette(background: [wx(0x0D0B1E), wx(0x161034)], card: wx(0x231C47),
                           text: wx(0xF4F2FF), sub: wx(0xBDB6E0), accent: wx(0x9EF0E6),
                           overdue: wx(0xFF9D7A), onAccent: wx(0x0D0B1E),
                           fontDesign: .rounded, radius: 24, scheme: .dark, world: .aurora)
        case .bento:
            return Palette(background: [wx(0xEEEDE8)], card: .white,
                           text: wx(0x1E1B16), sub: wx(0x625E55), accent: wx(0x1F3D36),
                           overdue: wx(0xB83A30), onAccent: .white,
                           fontDesign: .default, radius: 22, scheme: .light, world: .bento)
        case .clay:
            return Palette(background: [wx(0xEEE9FF), wx(0xF8E6F4)], card: wx(0xFBF8FF),
                           text: wx(0x33286E), sub: wx(0x625897), accent: wx(0x6243D8),
                           overdue: wx(0xB8400E), onAccent: .white,
                           fontDesign: .rounded, radius: 30, scheme: .light, world: .clay)
        case .swiss:
            return Palette(background: [wx(0xF4F4F1)], card: .white,
                           text: wx(0x111111), sub: wx(0x555555), accent: wx(0xD71F16),
                           overdue: wx(0xD71F16), onAccent: .white,
                           fontDesign: .default, radius: 3, scheme: .light, world: .swiss)
        }
    }

    /// 画面上部の大きな数字の大きさ
    var bigNumberSize: CGFloat {
        switch self {
        case .swiss: 76
        case .brutal: 60
        default: 56
        }
    }

    /// 大きな数字の字間（スイスは詰める）
    var bigNumberTracking: CGFloat { self == .swiss ? -3 : 0 }

    /// 大きな数字を強調色で描くか
    var bigNumberAccent: Bool { self == .swiss }

    /// 「今日」のフォーカスで、左へ払ったときの言葉（日なたは「日陰」）
    var postponeWord: String { self == .hinata ? "日陰へ" : "明日へ" }
}

// MARK: - 世界観ごとの背景

/// 全画面の背景。日なたは右上から日が差し、オーロラは光がゆっくり流れる
struct WorldBackground: View {
    let p: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors: [Color] = p.background.count > 1 ? p.background : [p.background[0], p.background[0]]
        let base = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        switch p.world {
        case .hinata:
            ZStack {
                base
                RadialGradient(colors: [wx(0xFFE3A8, 0.95), wx(0xFFD08A, 0.45), .clear],
                               center: UnitPoint(x: 0.78, y: 0.12), startRadius: 10, endRadius: 520)
            }
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
        case .brutal:
            // ずらした黒い影の上に、太い黒枠のカード
            ZStack {
                shape.fill(Color.black).offset(x: 5, y: 5)
                shape.fill(p.card)
                shape.strokeBorder(Color.black, lineWidth: 3)
            }
        case .aurora:
            // すりガラス（下の光がうっすら見える程度。文字が読めるよう濃いめに）
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(p.card.opacity(0.78)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.26), lineWidth: 1))
        case .clay:
            // 粘土：内側の明るい縁と暗い縁、外側のやわらかい影
            let inner = p.card
                .shadow(.inner(color: .white.opacity(0.9), radius: 6, x: 5, y: 5))
                .shadow(.inner(color: wx(0x5A3CA0, 0.16), radius: 8, x: -6, y: -7))
            shape.fill(inner)
                .shadow(color: wx(0x5A3CA0, 0.22), radius: 14, x: 8, y: 10)
        case .swiss:
            // 角はほぼ四角。上に黒い罫線
            ZStack(alignment: .top) {
                shape.fill(p.card)
                Rectangle().fill(Color.black).frame(height: 2)
            }
        case .hinata:
            shape.fill(p.card)
                .shadow(color: wx(0x784614, 0.18), radius: 18, y: 10)
        case .bento:
            shape.fill(p.card)
        case .none:
            let shadow: Color = .black.opacity(p.scheme == .dark || p.outline != nil ? 0 : 0.06)
            shape.fill(p.card).shadow(color: shadow, radius: 12, y: 4)
                .overlay(shape.strokeBorder(p.outline ?? .clear, lineWidth: p.outline == nil ? 0 : 1.5))
        }
    }
}
