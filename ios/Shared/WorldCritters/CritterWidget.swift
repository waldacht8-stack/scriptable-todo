import SwiftUI

// MARK: - ウィジェットの住人（止まった絵。entry.date から位置が決まり、WidgetKit が次の絵との間を動かす）
// 位置は .position / .rotationEffect / .trim で決める（Canvas の中で動かすと、描き直しの間がつながらないため）。
// 下の帯（高さの 88〜96%）を通り道にして、文字の多い上の方は避ける。ぼかしは使わず、図形は1匹あたり数個。

enum CritterWidgetArt {
    typealias D = CritterDraw
    typealias C = Critters

    /// 一巡の秒数（15分ごとの絵で、どれだけ進むか）
    static func period(_ w: World) -> Double {
        switch w {
        case .galaxy, .sky: 2 * 3600
        case .mist, .deepsea: 3 * 3600
        default: 86400
        }
    }

    static func view(_ p: Palette, size: CGSize, knobs k: CritterKnobs) -> AnyView {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        guard w > 1 && h > 1 else { return AnyView(EmptyView()) }
        switch p.world {
        case .strata: return AnyView(WidgetMole(size: size, k: k))
        case .galaxy:
            let x: CGFloat = w * CGFloat(0.12 + 0.76 * k.progress)
            let y: CGFloat = h * CGFloat(0.86 - 0.05 * sin(k.progress * 2 * Double.pi))
            let angle: Double = (k.progress - 0.5) * 1.4
            return AnyView(sprite(28, 34, x: x, y: y, angle: angle) { c, s in
                C.astronaut(D.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2 + 2), scale: 0.78), t: 0)
            })
        case .sky: return AnyView(WidgetSky(size: size, k: k))
        case .mist:
            let x: CGFloat = w * CGFloat(0.9 - 0.8 * k.progress)
            return AnyView(ZStack {
                sprite(30, 30, x: w * 0.07, y: h * 0.86, angle: 0) { c, s in
                    D.glow(c, Double(s.width) / 2, Double(s.height) / 2, 14, sceneColor(0xFFC77A), 0.5)
                    D.circle(c, Double(s.width) / 2, Double(s.height) / 2, 2, sceneColor(0xFFD9A0))
                }
                sprite(30, 32, x: x, y: h * 0.95 - 16, angle: 0) { c, s in
                    C.deer(D.local(c, at: CritterDraw.cpt(s.width / 2 + 2, s.height - 1), scale: 0.68),
                           walk: k.progress * 40, color: sceneColor(0x3E4A55, 0.5))
                }
            })
        case .deepsea:
            let x: CGFloat = w * CGFloat(0.92 - 0.84 * k.progress)
            return AnyView(sprite(64, 24, x: x, y: h * 0.88, angle: 0) { c, s in
                C.whale(D.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2), scale: 0.6), t: k.progress * 30)
            })
        case .hinata: return AnyView(WidgetCat(size: size, k: k))
        case .brutal:
            return AnyView(Canvas { c, s in stickers(c, size: s, count: k.count) })
        case .aurora:
            return AnyView(Canvas { c, s in curtains(c, size: s, day: k.day) })
        case .bento: return AnyView(WidgetBento(size: size, k: k))
        case .swiss: return AnyView(WidgetSwiss(size: size, k: k))
        case .none, .clay: return AnyView(EmptyView())
        }
    }

    /// 小さな絵を1枚、決まった位置に置く（位置と向きは WidgetKit が描き直しの間でつなぐ）
    static func sprite(_ sw: CGFloat, _ sh: CGFloat, x: CGFloat, y: CGFloat, angle: Double,
                       draw: @escaping (GraphicsContext, CGSize) -> Void) -> some View {
        Canvas { c, s in draw(c, s) }
            .frame(width: sw, height: sh)
            .rotationEffect(Angle.radians(angle))
            .position(x: x, y: y)
    }

    /// ネオブルータル：今日完了した数だけシールを貼る（右下から左へ。8枚まで）
    @_optimize(none)
    static func stickers(_ ctx: GraphicsContext, size: CGSize, count: Int) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let n: Int = min(8, max(0, count))
        for i in 0..<n {
            let x: Double = w - 13 - Double(i) * 15
            let y: Double = h * 0.93 - (i % 2 == 0 ? 0 : 5)
            let angle: Double = i % 2 == 0 ? -0.22 : 0.18
            C.sticker(D.local(ctx, at: D.pt(x, y), scale: 0.5, angle: angle), kind: i)
        }
    }

    /// オーロラ：15分ごとに形の変わるカーテン（上の方にうっすら）
    @_optimize(none)
    static func curtains(_ ctx: GraphicsContext, size: CGSize, day: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let slot: Int = Int(day * 96)
        var rnd = SceneRandom(UInt64(slot + 11))
        let colors: [UInt32] = [0x5CF2C8, 0xB28CFF]
        for i in 0..<2 {
            let top: Double = h * rnd.range(0.02, 0.16) + Double(i) * h * 0.08
            let amp: Double = rnd.range(6, 14)
            let wave: Double = rnd.range(0.7, 1.8)
            let phase: Double = rnd.range(0, 6.28)
            C.auroraCurtain(ctx, width: w, top: top, amp: amp, thick: h * 0.22, wave: wave,
                            phase: phase, color: sceneColor(colors[i]), alpha: 0.2)
        }
    }
}

/// 地層：一日かけてトンネルが伸び、その先でモグラが掘っている
private struct WidgetMole: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let y: CGFloat = h * 0.905
        let reach: Double = max(0.03, min(1, k.day))
        let mx: CGFloat = 8 + (w - 16) * CGFloat(reach)
        ZStack {
            WidgetTunnel(y: y)
                .trim(from: 0, to: reach)
                .stroke(sceneColor(0x5E4129, 0.42), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            CritterWidgetArt.sprite(28, 18, x: mx, y: WidgetTunnel.wave(Double(mx), w: Double(w), y: Double(y)), angle: 0) { c, s in
                Critters.mole(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2 - 2, s.height / 2), scale: 0.72), t: 0, digging: false)
            }
        }
    }
}

/// トンネルの道筋（左端から右端へ、ゆるく波打つ）
private struct WidgetTunnel: Shape {
    let y: CGFloat

    static func wave(_ x: Double, w: Double, y: Double) -> CGFloat {
        CGFloat(y + sin(x / max(w, 1) * Double.pi * 3) * 2.5)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w: Double = Double(rect.width)
        var x: Double = 8
        p.move(to: CGPoint(x: CGFloat(x), y: Self.wave(x, w: w, y: Double(y))))
        while x < w - 8 {
            x = min(w - 8, x + 6)
            p.addLine(to: CGPoint(x: CGFloat(x), y: Self.wave(x, w: w, y: Double(y))))
        }
        return p
    }
}

/// 空：太陽が弧を進み、紙飛行機が下を飛ぶ（雲は背景が時刻で流す）
private struct WidgetSky: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let sunF: Double = CritterDraw.span(k.day, 0.25, 0.75)
        let showSun: Bool = !SkyPhase.current().isNight && sunF > 0 && sunF < 1
        let sx: CGFloat = w * CGFloat(0.08 + 0.84 * sunF)
        let sy: CGFloat = h * CGFloat(0.4 - 0.3 * sin(sunF * Double.pi))
        let px: CGFloat = w * CGFloat(0.08 + 0.84 * k.progress)
        let py: CGFloat = h * CGFloat(0.9 - 0.035 * sin(k.progress * 4 * Double.pi))
        let tilt: Double = -cos(k.progress * 4 * Double.pi) * 0.2
        ZStack {
            if showSun {
                CritterWidgetArt.sprite(34, 34, x: sx, y: sy, angle: 0) { c, s in
                    CritterDraw.glow(c, Double(s.width) / 2, Double(s.height) / 2, 17, sceneColor(0xFFF1B8), 0.75)
                    CritterDraw.circle(c, Double(s.width) / 2, Double(s.height) / 2, 5.5, sceneColor(0xFFE9A0))
                }
            }
            CritterWidgetArt.sprite(22, 14, x: px, y: py, angle: tilt) { c, s in
                Critters.paperPlane(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2), scale: 0.8), dark: k.dark)
            }
        }
    }
}

/// 日なた：日の当たる場所（朝は左、夕方は右へ移る）に猫が座る
private struct WidgetCat: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let f: Double = CritterDraw.span(k.day, 0.25, 0.75)
        let x: CGFloat = w * CGFloat(0.14 + 0.72 * f)
        let ground: CGFloat = h * 0.955
        let pool = RadialGradient(colors: [sceneColor(0xFFD08A, 0.75), sceneColor(0xFFD08A, 0)], center: .center,
                                  startRadius: 0, endRadius: 30)
        ZStack {
            Ellipse().fill(pool).frame(width: 60, height: 14).position(x: x, y: ground - 2)
            CritterWidgetArt.sprite(20, 24, x: x, y: ground - 12, angle: 0) { c, s in
                Critters.catSitting(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height), scale: 0.85))
            }
        }
    }
}

/// ベント：右下の小さなタイル。15分ごとに並びが変わる（WidgetKit が入れ替わりを動かす）
private struct WidgetBento: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let cell: CGFloat = 8
        let gap: CGFloat = 2
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let originX: CGFloat = w - 10 - cell * 3 - gap * 2
        let originY: CGFloat = h - 10 - cell * 2 - gap
        let orders: [[Int]] = Critters.bentoOrders
        let order: [Int] = orders[Int(k.day * 96) % orders.count]
        ZStack {
            ForEach(0..<Critters.bentoColors.count, id: \.self) { i in
                let slot: CGPoint = Critters.bentoSlot(order[i], cell: Double(cell), gap: Double(gap))
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .fill(sceneColor(Critters.bentoColors[i]))
                    .overlay(RoundedRectangle(cornerRadius: 2.2, style: .continuous).strokeBorder(sceneColor(0x1E1B16, 0.14), lineWidth: 0.5))
                    .frame(width: cell, height: cell)
                    .position(x: originX + slot.x + cell / 2, y: originY + slot.y + cell / 2)
            }
        }
    }
}

/// スイス：右下の小さな時計。針と四角の角度がいまの時刻になる
private struct WidgetSwiss: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let hour: Double = k.day * 2 * 360
        let minute: Double = k.day * 24 * 360
        let r: CGFloat = 10
        let cx: CGFloat = w - 14 - r
        let cy: CGFloat = h - 12 - r
        let ink: Color = sceneColor(0x111111)
        ZStack {
            Circle().strokeBorder(ink, lineWidth: 1).frame(width: r * 2, height: r * 2).position(x: cx, y: cy)
            Capsule().fill(ink).frame(width: 2, height: r * 0.55)
                .offset(y: -r * 0.27).rotationEffect(Angle.degrees(hour)).position(x: cx, y: cy)
            Capsule().fill(ink).frame(width: 1.2, height: r * 0.8)
                .offset(y: -r * 0.4).rotationEffect(Angle.degrees(minute)).position(x: cx, y: cy)
            Circle().fill(sceneColor(0xD71F16)).frame(width: 3, height: 3).position(x: cx, y: cy)
            Rectangle().fill(sceneColor(0xD71F16)).frame(width: 7, height: 7)
                .rotationEffect(Angle.degrees(minute / 2)).position(x: cx - r - 10, y: cy + 2)
        }
    }
}
