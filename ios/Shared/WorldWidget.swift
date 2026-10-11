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

/// ウィジェット全体の背景。日なたは右上から日だまり、オーロラは光の丸（ぼかさずグラデーションで）、
/// ネオブルータルは平らな色に太い黒枠、クレイはパステルのふくらみ、スイスは白地に罫線、ベントはタイルの格子
struct WidgetWorldBackground: View {
    let p: Palette

    var body: some View {
        let colors: [Color] = p.background.count > 1 ? p.background : [p.background[0], p.background[0]]
        let base = LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        switch p.world {
        case .none:
            base
        case .hinata:
            ZStack {
                base
                RadialGradient(colors: [wwx(0xFFE3A8, 0.95), wwx(0xFFD08A, 0.4), .clear],
                               center: UnitPoint(x: 0.92, y: 0.0), startRadius: 4, endRadius: 280)
            }
        case .aurora:
            ZStack {
                base
                auroraBlob(wwx(0x6D4BFF, 0.75), at: UnitPoint(x: 0.08, y: 0.05), radius: 190)
                auroraBlob(wwx(0x12C2B5, 0.5), at: UnitPoint(x: 1.0, y: 0.55), radius: 170)
                auroraBlob(wwx(0xFF5FA2, 0.38), at: UnitPoint(x: 0.3, y: 1.05), radius: 160)
            }
        case .brutal:
            ZStack {
                base
                ContainerRelativeShape().strokeBorder(Color.black, lineWidth: 4)
            }
        case .clay:
            ZStack {
                base
                RadialGradient(colors: [wwx(0xD9CCFF, 0.9), .clear], center: UnitPoint(x: 0.95, y: 0.05), startRadius: 2, endRadius: 150)
                RadialGradient(colors: [wwx(0xFFD3EC, 0.85), .clear], center: UnitPoint(x: 0.0, y: 1.0), startRadius: 2, endRadius: 150)
            }
        case .swiss:
            SwissRules(p: p, base: base)
        case .bento:
            BentoTiles(p: p, base: base)
        }
    }

    private func auroraBlob(_ c: Color, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [c, c.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }
}

/// スイス：白地に細い罫線（4等分）と、左端の赤い帯
private struct SwissRules: View {
    let p: Palette
    let base: LinearGradient

    var body: some View {
        GeometryReader { geo in
            let h: CGFloat = geo.size.height
            ZStack(alignment: .topLeading) {
                base
                ForEach(1..<4, id: \.self) { i in
                    Rectangle().fill(p.text.opacity(0.08)).frame(height: 0.5)
                        .offset(y: h * CGFloat(i) / 4)
                }
                Rectangle().fill(p.accent).frame(width: 5, height: h)
            }
        }
    }
}

/// ベント：上の帯と下のタイル（中身の下にうっすら敷く）。小さいサイズは下を1枚にして、題名がタイルの境目にかからないようにする
private struct BentoTiles: View {
    let p: Palette
    let base: LinearGradient

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let w: CGFloat = geo.size.width - gap * 2
            let h: CGFloat = geo.size.height - gap * 2
            let topH: CGFloat = (h - gap) * 0.26
            let bottomH: CGFloat = h - gap - topH
            let wide: Bool = geo.size.width > 250
            let mainW: CGFloat = wide ? (w - gap) * 0.74 : w
            let sideW: CGFloat = w - gap - mainW
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            let tile: Color = p.card.opacity(0.55)
            ZStack {
                base
                VStack(spacing: gap) {
                    shape.fill(tile).frame(width: w, height: topH)
                    HStack(spacing: gap) {
                        shape.fill(tile).frame(width: mainW, height: bottomH)
                        if wide {
                            shape.fill(p.accent.opacity(0.06)).frame(width: sideW, height: bottomH)
                        }
                    }
                }
            }
        }
    }
}

// MARK: カード・ボタンの面

/// ウィジェットの中の小さなカード（件数の行・日付・かんばんのカードなど）。
/// ブルータルは太い黒枠とずらした影、クレイはぷっくり、オーロラはすりガラス、スイスは上の罫線
struct WidgetCardSurface: View {
    let p: Palette
    var radius: CGFloat = 10

    var body: some View {
        let r: CGFloat = min(p.radius, radius)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        switch p.world {
        case .none, .bento:
            shape.fill(p.card)
        case .brutal:
            ZStack {
                shape.fill(Color.black).offset(x: 2.5, y: 2.5)
                shape.fill(p.card)
                shape.strokeBorder(Color.black, lineWidth: 2)
            }
        case .aurora:
            let sheen = LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom)
            ZStack {
                shape.fill(p.card.opacity(0.62))
                shape.fill(sheen)
                shape.strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
            }
        case .clay:
            let puffy = p.card
                .shadow(.inner(color: Color.white.opacity(0.95), radius: 2.5, x: 2, y: 2))
                .shadow(.inner(color: wwx(0x5A3CA0, 0.16), radius: 3, x: -2, y: -3))
            shape.fill(puffy)
                .shadow(color: wwx(0x5A3CA0, 0.2), radius: 4, x: 2, y: 3)
        case .swiss:
            ZStack(alignment: .top) {
                shape.fill(p.card)
                Rectangle().fill(p.text).frame(height: 1.5)
            }
        case .hinata:
            shape.fill(p.card)
                .shadow(color: wwx(0x784614, 0.16), radius: 5, y: 3)
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
        case .brutal:
            ZStack {
                shape.fill(Color.black).offset(x: 3, y: 3)
                shape.fill(p.accent)
                shape.strokeBorder(Color.black, lineWidth: 2.5)
            }
        case .clay:
            let puffy = p.accent
                .shadow(.inner(color: Color.white.opacity(0.45), radius: 3, x: 2, y: 2))
                .shadow(.inner(color: Color.black.opacity(0.18), radius: 3, x: -2, y: -3))
            shape.fill(puffy)
                .shadow(color: p.accent.opacity(0.35), radius: 5, x: 2, y: 4)
        case .aurora:
            shape.fill(p.accent)
                .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
                .shadow(color: p.accent.opacity(0.45), radius: 6)
        case .hinata:
            shape.fill(p.accent)
                .shadow(color: wwx(0x784614, 0.25), radius: 5, y: 3)
        case .none, .bento, .swiss:
            shape.fill(p.accent)
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

/// ウィジェットの件数・時刻。世界観の大きな数字（スイスは巨大で字詰め・赤、ブルータルは太く大きく）に合わせる
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

    /// ウィジェットの数字の字間（スイスは詰める。画面の大きな数字と同じ比）
    func widgetNumberTracking(_ size: CGFloat) -> CGFloat {
        let shown: CGFloat = (size * world.widgetNumberScale).rounded()
        return world.bigNumberTracking * shown / max(world.bigNumberSize, 1)
    }

    /// ウィジェットの数字の色（スイスは強調色）
    var widgetNumberColor: Color { world.bigNumberAccent ? accent : text }
}

extension World {
    /// ウィジェットの数字の倍率（画面の大きな数字の比を保つ）
    var widgetNumberScale: CGFloat {
        switch self {
        case .swiss: 1.3
        case .brutal: 1.1
        default: 1
        }
    }

    /// ウィジェットの数字の太さ
    var widgetNumberWeight: Font.Weight {
        switch self {
        case .brutal, .swiss: .black
        case .aurora: .bold
        default: .heavy
        }
    }

    /// 描き直しの動き（World.motion の「並びや中身が変わったとき」。WidgetKit は 2 秒まで）
    var widgetAnimation: Animation? { motion?.change }

    /// 丸の印（未完了・完了）。ブルータルは四角
    func widgetCheckSymbol(done: Bool) -> String {
        switch self {
        case .brutal: done ? "checkmark.square.fill" : "square"
        default: done ? "checkmark.circle.fill" : "circle"
        }
    }

    /// 丸の印の線の太さ
    var widgetCheckWeight: Font.Weight {
        switch self {
        case .brutal: .black
        case .swiss: .regular
        default: .semibold
        }
    }

    /// 印が入れ替わるときの動き（SF Symbols の置き換え）
    var widgetSymbolTransition: ContentTransition {
        switch self {
        case .clay, .bento: ContentTransition.symbolEffect(ReplaceSymbolEffect.replace.downUp)
        case .aurora, .hinata: ContentTransition.symbolEffect(ReplaceSymbolEffect.replace.offUp)
        default: ContentTransition.symbolEffect(ReplaceSymbolEffect.replace)
        }
    }

    /// 完了した行が抜ける・新しい行が入るときの動き
    /// ブルータル：短く押し出す／クレイ：縮んで弾む／オーロラ：ぼけて消える／日なた：暖色に染まって消える／スイス：横へ滑る
    func widgetRowTransition(_ p: Palette) -> AnyTransition {
        switch self {
        case .none:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.move(edge: .bottom).combined(with: .opacity),
                removal: AnyTransition.move(edge: .trailing).combined(with: .opacity))
        case .brutal:
            return AnyTransition.asymmetric(insertion: AnyTransition.push(from: .bottom),
                                            removal: AnyTransition.push(from: .leading))
        case .clay:
            return AnyTransition.asymmetric(
                insertion: AnyTransition.scale(scale: 0.7).combined(with: .opacity),
                removal: AnyTransition.scale(scale: 0.4).combined(with: .opacity))
        case .aurora:
            let blur: BlurReplaceTransition = .blurReplace
            return AnyTransition(blur)
        case .hinata:
            let warm = AnyTransition.modifier(active: WarmFade(tint: p.accent, on: true),
                                              identity: WarmFade(tint: p.accent, on: false))
            return AnyTransition.asymmetric(insertion: AnyTransition.opacity, removal: warm)
        case .swiss:
            return AnyTransition.asymmetric(insertion: AnyTransition.move(edge: .trailing),
                                            removal: AnyTransition.move(edge: .leading))
        case .bento:
            return AnyTransition.scale(scale: 0.88).combined(with: .opacity)
        }
    }

    /// 1件を大きく出す表示（フォーカス・起床の前後）で、中身が入れ替わるときの動き
    func widgetSwapTransition(_ p: Palette) -> AnyTransition {
        switch self {
        case .none, .brutal, .bento:
            return AnyTransition.push(from: .bottom)
        case .swiss:
            return AnyTransition.push(from: .trailing)
        default:
            return widgetRowTransition(p)
        }
    }
}

/// 日なたの「暖色に染まって消える」（消える側だけ。少し上へ浮かぶ）
private struct WarmFade: ViewModifier {
    let tint: Color
    let on: Bool

    func body(content: Content) -> some View {
        content
            .colorMultiply(on ? tint : Color.white)
            .opacity(on ? 0 : 1)
            .offset(y: on ? -8 : 0)
    }
}

// MARK: 進み具合の輪（習慣）

/// 世界観ごとの輪。ブルータルは黒い太線、スイスは角の線端と細い下地、クレイはぷっくり、オーロラは光る
struct WidgetWorldRing: View {
    let p: Palette
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        let shown: Double = max(0, min(1, fraction))
        switch p.world {
        case .brutal:
            ZStack {
                Circle().stroke(Color.black, lineWidth: lineWidth + 3)
                Circle().stroke(p.card, lineWidth: lineWidth - 1)
                Circle().trim(from: 0, to: shown)
                    .stroke(p.accent, style: StrokeStyle(lineWidth: lineWidth - 1, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .opacity(shown > 0 ? 1 : 0)
            }
        case .swiss:
            ZStack {
                Circle().stroke(p.text.opacity(0.12), lineWidth: max(1, lineWidth * 0.35))
                Circle().trim(from: 0, to: shown)
                    .stroke(p.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .opacity(shown > 0 ? 1 : 0)
            }
        case .clay:
            HabitRing(fraction: shown, color: p.accent, track: p.card, lineWidth: lineWidth)
                .shadow(color: wwx(0x5A3CA0, 0.22), radius: 3, x: 1, y: 2)
        case .aurora:
            HabitRing(fraction: shown, color: p.accent, track: Color.white.opacity(0.12), lineWidth: lineWidth)
                .shadow(color: p.accent.opacity(0.6), radius: 4)
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
        case .hinata, .clay, .aurora: .rounded
        case .brutal, .swiss, .bento: .default
        }
    }

    /// ロック画面の文字の太さ（ブルータルはいちばん太く）
    func accessoryWeight(_ w: Font.Weight) -> Font.Weight {
        switch self {
        case .brutal: (w == .regular || w == .medium) ? .bold : .black
        case .aurora: w == .heavy ? .bold : w
        default: w
        }
    }

    /// ロック画面の文字
    func accessoryFont(_ style: Font.TextStyle, _ weight: Font.Weight) -> Font {
        Font.system(style, design: accessoryDesign, weight: accessoryWeight(weight))
    }

    /// ロック画面の大きな数字（スイスは大きく字を詰める）
    func accessoryNumberFont(_ size: CGFloat) -> Font {
        let s: CGFloat = self == .swiss ? size * 1.2 : size
        let w: Font.Weight = self == .swiss || self == .brutal ? .black : (self == .aurora ? .bold : .heavy)
        return Font.system(size: s, weight: w, design: accessoryDesign ?? .default)
    }

    /// ロック画面の大きな数字の字間
    var accessoryTracking: CGFloat { self == .swiss ? -1.2 : 0 }
}

/// ロック画面の丸い背景。ブルータルは太い輪、スイスは細い輪、オーロラは二重の輪、クレイは内側にふくらみ
struct AccessoryWorldBackground: View {
    let world: World

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch world {
            case .brutal:
                Circle().strokeBorder(lineWidth: 3.5)
            case .swiss:
                Circle().strokeBorder(lineWidth: 1)
            case .aurora:
                Circle().strokeBorder(lineWidth: 1).opacity(0.5).padding(3)
            case .clay:
                Circle().fill(HierarchicalShapeStyle.primary.opacity(0.12)).padding(5)
            default:
                EmptyView()
            }
        }
    }
}

/// ロック画面の四角いウィジェットの飾り。スイスは左に細い罫線、ブルータルは太い帯
struct AccessoryWorldFrame: ViewModifier {
    let world: World

    func body(content: Content) -> some View {
        switch world {
        case .swiss:
            HStack(spacing: 5) {
                Rectangle().frame(width: 1.5)
                content
            }
        case .brutal:
            HStack(spacing: 5) {
                Rectangle().frame(width: 4)
                content
            }
        default:
            content
        }
    }
}

extension View {
    /// ロック画面の四角いウィジェットに世界観の飾りを付ける
    func accessoryWorldFrame(_ world: World) -> some View { modifier(AccessoryWorldFrame(world: world)) }
}
