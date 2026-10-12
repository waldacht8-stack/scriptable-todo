import SwiftUI
import WidgetKit

// MARK: - 世界観のウィジェット用の部品
// World.swift の背景・カード・大きな数字は画面用（流れる光やぼかし・大きな影を使う）。
// ウィジェットは描ける量（約 30MB）と動き（描き直しの合間だけ）に限りがあるので、
// ここでは同じ見た目を、止まった絵・軽い影・グラデーションだけで描き直す。
// 色は palette の値と、各世界観の飾りの色（このファイルの中だけ）だけを使う。

/// 0xRRGGBB から色を作る（世界観の飾りの色。このファイルの中だけで使う）
fileprivate func wwx(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

// MARK: 背景（containerBackground に敷く1枚）

/// ウィジェット全体の背景。オーロラは光の丸（ぼかさずグラデーションで）、地層・銀河・空・霧・深海は止まった絵
struct WidgetWorldBackground: View {
    let p: Palette
    /// いつの絵か（タイムラインの entry.date。住人の位置・雲の流れが決まる）
    var date: Date = .now
    /// 見本の画面用：時刻の代わりにこの位相（0〜1）で描く
    var phase: Double? = nil

    var body: some View {
        ZStack {
            scenery
            if WorldMotion.hasCritters(p.world) {
                WidgetWorldCritters(p: p, date: date, phase: phase)
            }
        }
    }

    @ViewBuilder
    private var scenery: some View {
        let colors: [Color] = p.background.count > 1 ? p.background : [p.background[0], p.background[0]]
        let base = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        switch p.world {
        case .none:
            base
        case .strata, .galaxy, .sky, .mist, .deepsea:
            WidgetSceneBackground(p: p, stillT: phase.map { 1 + $0 * 2400 } ?? WorldMotion.sceneTime(date))
        case .yohaku, .terminal, .zankou, .breath, .crystal, .ink:
            WidgetSceneBackground(p: p, stillT: phase.map { 1 + $0 * 2400 } ?? WorldMotion.sceneTime(date))
        case .aurora:
            ZStack {
                base
                auroraBlob(wwx(0x6D4BFF, 0.75), at: UnitPoint(x: 0.08, y: 0.05), radius: 190)
                auroraBlob(wwx(0x12C2B5, 0.5), at: UnitPoint(x: 1.0, y: 0.55), radius: 170)
                auroraBlob(wwx(0xFF5FA2, 0.38), at: UnitPoint(x: 0.3, y: 1.05), radius: 160)
            }
        }
    }

    private func auroraBlob(_ c: Color, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [c, c.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }
}

// MARK: カード・ボタンの面

/// ウィジェットの中の小さなカード（件数の行・日付・かんばんのカードなど）。
/// オーロラはすりガラス、地層・銀河・空・霧・深海はそれぞれの面
struct WidgetCardSurface: View {
    let p: Palette
    var radius: CGFloat = 10

    var body: some View {
        let r: CGFloat = min(p.radius, radius)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        switch p.world {
        case .none:
            shape.fill(p.card)
        case .strata, .galaxy, .sky, .mist, .deepsea:
            WidgetSceneCard(p: p, radius: r)
        case .yohaku, .terminal, .zankou, .breath, .crystal, .ink:
            WidgetSceneCard(p: p, radius: r)
        case .aurora:
            let sheen = LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
            ZStack {
                shape.fill(p.card.opacity(0.62))
                shape.fill(sheen)
                shape.strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
            }
        }
    }
}

/// 強調色のボタンの面（「完了」「起きた！」など）
struct WidgetButtonSurface: View {
    let p: Palette
    var radius: CGFloat = 12

    var body: some View {
        let r: CGFloat = min(p.radius, radius)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        switch p.world {
        case .aurora:
            shape.fill(p.accent)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                .shadow(color: p.accent.opacity(0.45), radius: 6)
        case .none:
            shape.fill(p.accent)
        case .strata, .galaxy, .sky, .mist, .deepsea:
            WidgetSceneButton(p: p, radius: r)
        case .yohaku, .terminal, .zankou, .breath, .crystal, .ink:
            WidgetSceneButton(p: p, radius: r)
        }
    }
}

extension View {
    /// ウィジェットの小さなカードを敷く
    func widgetCard(_ p: Palette, radius: CGFloat = 10) -> some View {
        background(WidgetCardSurface(p: p, radius: radius))
    }

    /// ウィジェットの強調ボタンの面を敷く
    func widgetButton(_ p: Palette, radius: CGFloat = 12) -> some View {
        background(WidgetButtonSurface(p: p, radius: radius))
    }

    /// 世界観の動き方で、描き直し（タイムラインの次の表示・ボタンの後）を動かす。「なし」は WidgetKit の既定のまま
    func worldWidgetAnimation<V: Equatable>(_ p: Palette, value: V) -> some View {
        modifier(WorldWidgetAnimation(animation: p.world.widgetAnimation, value: value))
    }
}

private struct WorldWidgetAnimation<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        if let animation {
            content.animation(animation, value: value)
        } else {
            content
        }
    }
}

// MARK: 大きな数字（BigCount と同じ考え方の小さい版）

/// ウィジェットの件数・時刻。世界観の大きな数字に合わせる
struct WidgetCount: View {
    let p: Palette
    let text: String
    var value: Double? = nil
    var size: CGFloat = 22
    var color: Color? = nil

    var body: some View {
        let tint: Color = color ?? p.widgetNumberColor
        let transition: ContentTransition = value.map { ContentTransition.numericText(value: $0) } ?? ContentTransition.numericText()
        return Text(text)
            .font(p.widgetNumberFont(size))
            .monospacedDigit()
            .tracking(p.widgetNumberTracking(size))
            .foregroundStyle(tint)
            .contentTransition(transition)
            .widgetAccentable()
    }
}

extension Palette {
    /// ウィジェットの数字の字（size は「なし」のときの大きさ）。時刻・カウントダウンにも使う
    func widgetNumberFont(_ size: CGFloat) -> Font {
        let shown: CGFloat = (size * world.widgetNumberScale).rounded()
        return Font.system(size: shown, weight: world.widgetNumberWeight, design: fontDesign)
    }

    /// ウィジェットの数字の字間（画面の大きな数字と同じ比）
    func widgetNumberTracking(_ size: CGFloat) -> CGFloat {
        let shown: CGFloat = (size * world.widgetNumberScale).rounded()
        return world.bigNumberTracking * shown / max(world.bigNumberSize, 1)
    }

    /// ウィジェットの数字の色
    var widgetNumberColor: Color { world.bigNumberAccent ? accent : text }
}

extension World {
    /// ウィジェットの数字の倍率（画面の大きな数字の比を保つ）
    var widgetNumberScale: CGFloat { 1 }

    /// ウィジェットの数字の太さ
    var widgetNumberWeight: Font.Weight {
        switch self {
        case .aurora: .bold
        default: .heavy
        }
    }

    /// 描き直しの動き（World.motion の「並びや中身が変わったとき」。WidgetKit は 2 秒まで）
    var widgetAnimation: Animation? { motion?.change }

    /// 丸の印（未完了・完了）
    func widgetCheckSymbol(done: Bool) -> String {
        done ? "checkmark.circle.fill" : "circle"
    }

    /// 丸の印の線の太さ
    var widgetCheckWeight: Font.Weight { .semibold }

    /// 印が入れ替わるときの動き（SF Symbols の置き換え）
    var widgetSymbolTransition: ContentTransition {
        switch self {
        case .aurora: ContentTransition.symbolEffect(ReplaceSymbolEffect.replace.offUp)
        default: ContentTransition.symbolEffect(ReplaceSymbolEffect.replace)
        }
    }

    /// 完了した行が抜ける・新しい行が入るときの動き
    /// オーロラ：ぼけて消える。地層・銀河・空・霧・深海はそれぞれの動き
    func widgetRowTransition(_ p: Palette) -> AnyTransition {
        switch self {
        case .none:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                removal: AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .aurora:
            let blur: BlurReplaceTransition = .blurReplace
            return AnyTransition(blur)
        case .strata, .galaxy, .sky, .mist, .deepsea:
            return sceneRowTransition()
        case .yohaku, .terminal, .zankou, .breath, .crystal, .ink:
            return sceneRowTransition()
        }
    }

    /// 1件を大きく出す表示（フォーカス・起床の前後）で、中身が入れ替わるときの動き
    func widgetSwapTransition(_ p: Palette) -> AnyTransition {
        switch self {
        case .none:
            return AnyTransition.push(from: .bottom)
        default:
            return widgetRowTransition(p)
        }
    }
}

// MARK: 進み具合の輪（習慣）

/// 世界観ごとの輪。オーロラは光る
struct WidgetWorldRing: View {
    let p: Palette
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        let shown: Double = max(0, min(1, fraction))
        switch p.world {
        case .aurora:
            HabitRing(fraction: shown, color: p.accent, track: Color.white.opacity(0.12), lineWidth: lineWidth)
                .shadow(color: p.accent.opacity(0.6), radius: 4)
        case .crystal:
            CrystalWakeRing(p: p, fraction: shown, lineWidth: lineWidth)
        case .ink:
            InkWakeRing(p: p, fraction: shown, lineWidth: lineWidth)
        default:
            HabitRing(fraction: shown, color: p.accent, lineWidth: lineWidth)
        }
    }
}

// MARK: ロック画面（色は使われないので、形と文字で世界観を出す）

extension World {
    /// ロック画面の文字の形（丸文字かどうか）
    var accessoryDesign: Font.Design? {
        switch self {
        case .none: nil
        case .aurora: .rounded
        case .galaxy, .sky, .deepsea: .rounded
        case .strata, .mist: .default
        case .yohaku: .serif
        case .terminal: .monospaced
        case .zankou: .default
        case .breath: .rounded
        case .crystal: .rounded
        case .ink: .serif
        }
    }

    /// ロック画面の文字の太さ
    func accessoryWeight(_ w: Font.Weight) -> Font.Weight {
        switch self {
        case .aurora: w == .heavy ? .bold : w
        default: w
        }
    }

    /// ロック画面の文字
    func accessoryFont(_ style: Font.TextStyle, _ weight: Font.Weight) -> Font {
        Font.system(style, design: accessoryDesign, weight: accessoryWeight(weight))
    }

    /// ロック画面の大きな数字
    func accessoryNumberFont(_ size: CGFloat) -> Font {
        let s: CGFloat = size
        let w: Font.Weight = self == .aurora ? .bold : .heavy
        return Font.system(size: s, weight: w, design: accessoryDesign ?? .default)
    }

    /// ロック画面の大きな数字の字間
    var accessoryTracking: CGFloat { 0 }
}

/// ロック画面の丸い背景。オーロラは二重の輪
struct AccessoryWorldBackground: View {
    let world: World

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch world {
            case .aurora:
                Circle().strokeBorder(lineWidth: 1).opacity(0.5).padding(3)
            default:
                EmptyView()
            }
        }
    }
}

/// ロック画面の四角いウィジェットの飾り（いまは飾りなし。世界観ごとに足せるよう残す）
struct AccessoryWorldFrame: ViewModifier {
    let world: World

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// ロック画面の四角いウィジェットに世界観の飾りを付ける
    func accessoryWorldFrame(_ world: World) -> some View { modifier(AccessoryWorldFrame(world: world)) }
}
