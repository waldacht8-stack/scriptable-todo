import SwiftUI

// MARK: - ウィジェットの住人（止まった絵。entry.date から位置が決まり、WidgetKit が次の絵との間を動かす）
// 位置は .position / .rotationEffect / .trim で決める（Canvas の中で動かすと、描き直しの間がつながらないため）。
// 住人はウィジェットの下の余白（中身の外側の 16pt）の中だけを通る。なので文字には決して重ならない。
// 空の太陽だけは上の余白を進む。オーロラのカーテンは背景の光としてうっすら敷く。ぼかしは使わず、図形は1匹あたり数個。

enum CritterWidgetArt {
    typealias D = CritterDraw
    typealias C = Critters

    /// 下の余白の真ん中（ここを通り道にする）
    static func laneY(_ h: CGFloat) -> CGFloat { h - 8 }

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
        let lane: CGFloat = laneY(h)
        switch p.world {
        case .strata: return AnyView(WidgetMole(size: size, k: k))
        case .galaxy:
            let x: CGFloat = w * CGFloat(0.1 + 0.8 * k.progress)
            let y: CGFloat = lane - 1 + CGFloat(sin(k.progress * 2 * Double.pi)) * 1.5
            let angle: Double = (k.progress - 0.5) * 1.6
            return AnyView(sprite(18, 18, x: x, y: y, angle: angle) { c, s in
                C.astronaut(D.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2 + 1), scale: 0.5), t: 0)
            })
        case .sky: return AnyView(WidgetSky(size: size, k: k))
        case .mist:
            let x: CGFloat = w * CGFloat(0.9 - 0.78 * k.progress)
            return AnyView(ZStack {
                sprite(24, 24, x: 12, y: lane, angle: 0) { c, s in
                    D.glow(c, Double(s.width) / 2, Double(s.height) / 2, 11, sceneColor(0xFFC77A), 0.55)
                    D.circle(c, Double(s.width) / 2, Double(s.height) / 2, 1.8, sceneColor(0xFFD9A0))
                }
                sprite(18, 16, x: x, y: h - 9, angle: 0) { c, s in
                    C.deer(D.local(c, at: CritterDraw.cpt(s.width / 2 + 1, s.height - 1), scale: 0.34),
                           walk: k.progress * 40, color: sceneColor(0x3E4A55, 0.6))
                }
            })
        case .deepsea:
            let x: CGFloat = w * CGFloat(0.9 - 0.8 * k.progress)
            return AnyView(sprite(34, 12, x: x, y: lane, angle: 0) { c, s in
                C.whale(D.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2), scale: 0.32), t: k.progress * 30)
            })
        case .hinata: return AnyView(WidgetCat(size: size, k: k))
        case .brutal:
            return AnyView(Canvas { c, s in stickers(c, size: s, count: k.count) })
        case .aurora:
            return AnyView(Canvas { c, s in curtains(c, size: s, day: k.day) })
        case .bento: return AnyView(WidgetBento(size: size, k: k))
        case .swiss: return AnyView(WidgetSwiss(size: size, k: k))
        case .yohaku: return AnyView(WidgetYohaku(size: size, k: k))
        case .terminal: return AnyView(WidgetTerminal(size: size, k: k))
        case .zankou, .breath: return AnyView(EmptyView())
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

    /// ネオブルータル：今日完了した数だけシールを貼る（下の余白を右から左へ。10枚まで）
    @_optimize(none)
    static func stickers(_ ctx: GraphicsContext, size: CGSize, count: Int) {
        let w: Double = Double(size.width)
        let y0: Double = Double(laneY(size.height))
        let n: Int = min(10, max(0, count))
        for i in 0..<n {
            let x: Double = w - 14 - Double(i) * 13
            let y: Double = y0 - (i % 2 == 0 ? 0 : 1.5)
            let angle: Double = i % 2 == 0 ? -0.22 : 0.18
            C.sticker(D.local(ctx, at: D.pt(x, y), scale: 0.42, angle: angle), kind: i)
        }
    }

    /// オーロラ：15分ごとに形の変わるカーテン（上の方にうっすら。背景の光）
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

/// 地層：一日かけて下の余白にトンネルが伸び、その先でモグラが掘っている
private struct WidgetMole: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let y: CGFloat = CritterWidgetArt.laneY(size.height)
        let reach: Double = max(0.03, min(1, k.day))
        let mx: CGFloat = 8 + (w - 16) * CGFloat(reach)
        ZStack {
            WidgetTunnel(y: y)
                .trim(from: 0, to: reach)
                .stroke(sceneColor(0x5E4129, 0.45), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            CritterWidgetArt.sprite(20, 12, x: mx, y: WidgetTunnel.wave(Double(mx), w: Double(w), y: Double(y)), angle: 0) { c, s in
                Critters.mole(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2 - 2, s.height / 2), scale: 0.55), t: 0, digging: false)
            }
        }
    }
}

/// トンネルの道筋（左端から右端へ、ゆるく波打つ）
private struct WidgetTunnel: Shape {
    let y: CGFloat

    static func wave(_ x: Double, w: Double, y: Double) -> CGFloat {
        CGFloat(y + sin(x / max(w, 1) * Double.pi * 3) * 1.5)
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

/// 空：太陽が上の余白を東から西へ進み、紙飛行機が下の余白を飛ぶ（雲は背景が時刻で流す）
private struct WidgetSky: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let sunF: Double = CritterDraw.span(k.day, 0.25, 0.75)
        let showSun: Bool = !SkyPhase.current().isNight && sunF > 0 && sunF < 1
        let sx: CGFloat = w * CGFloat(0.08 + 0.84 * sunF)
        let sy: CGFloat = 8 - CGFloat(sin(sunF * Double.pi)) * 2
        let px: CGFloat = w * CGFloat(0.08 + 0.84 * k.progress)
        let py: CGFloat = CritterWidgetArt.laneY(h) + CGFloat(sin(k.progress * 4 * Double.pi)) * 1.5
        let tilt: Double = -cos(k.progress * 4 * Double.pi) * 0.2
        ZStack {
            if showSun {
                CritterWidgetArt.sprite(22, 22, x: sx, y: sy, angle: 0) { c, s in
                    CritterDraw.glow(c, Double(s.width) / 2, Double(s.height) / 2, 11, sceneColor(0xFFF1B8), 0.8)
                    CritterDraw.circle(c, Double(s.width) / 2, Double(s.height) / 2, 4, sceneColor(0xFFE9A0))
                }
            }
            CritterWidgetArt.sprite(18, 12, x: px, y: py, angle: tilt) { c, s in
                Critters.paperPlane(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2), scale: 0.65), dark: k.dark)
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
        let x: CGFloat = w * CGFloat(0.12 + 0.76 * f)
        let ground: CGFloat = h - 2
        let pool = RadialGradient(colors: [sceneColor(0xFFD08A, 0.8), sceneColor(0xFFD08A, 0)], center: .center,
                                  startRadius: 0, endRadius: 22)
        ZStack {
            Ellipse().fill(pool).frame(width: 44, height: 8).position(x: x, y: ground - 2)
            CritterWidgetArt.sprite(14, 15, x: x, y: ground - 7.5, angle: 0) { c, s in
                Critters.catSitting(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height), scale: 0.6))
            }
        }
    }
}

/// ベント：右下の余白の小さなタイル。15分ごとに並びが変わる（WidgetKit が入れ替わりを動かす）
private struct WidgetBento: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let cell: CGFloat = 5.5
        let gap: CGFloat = 1.5
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let originX: CGFloat = w - 16 - cell * 3 - gap * 2
        let originY: CGFloat = h - 2.5 - cell * 2 - gap
        let orders: [[Int]] = Critters.bentoOrders
        let order: [Int] = orders[Int(k.day * 96) % orders.count]
        ZStack {
            ForEach(0..<Critters.bentoColors.count, id: \.self) { i in
                let slot: CGPoint = Critters.bentoSlot(order[i], cell: Double(cell), gap: Double(gap))
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(sceneColor(Critters.bentoColors[i]))
                    .overlay(RoundedRectangle(cornerRadius: 1.6, style: .continuous).strokeBorder(sceneColor(0x1E1B16, 0.18), lineWidth: 0.5))
                    .frame(width: cell, height: cell)
                    .position(x: originX + slot.x + cell / 2, y: originY + slot.y + cell / 2)
            }
        }
    }
}

/// スイス：右下の余白の小さな時計と図形。針・四角・三角の角度がいまの時刻になる
private struct WidgetSwiss: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let hour: Double = k.day * 2 * 360
        let minute: Double = k.day * 24 * 360
        let r: CGFloat = 6
        let cx: CGFloat = w - 18 - r
        let cy: CGFloat = CritterWidgetArt.laneY(size.height)
        let ink: Color = sceneColor(0x111111)
        ZStack {
            Circle().strokeBorder(ink, lineWidth: 0.8).frame(width: r * 2, height: r * 2).position(x: cx, y: cy)
            Capsule().fill(ink).frame(width: 1.4, height: r * 0.55)
                .offset(y: -r * 0.27).rotationEffect(Angle.degrees(hour)).position(x: cx, y: cy)
            Capsule().fill(ink).frame(width: 0.9, height: r * 0.85)
                .offset(y: -r * 0.42).rotationEffect(Angle.degrees(minute)).position(x: cx, y: cy)
            Circle().fill(sceneColor(0xD71F16)).frame(width: 2, height: 2).position(x: cx, y: cy)
            Rectangle().fill(sceneColor(0xD71F16)).frame(width: 5, height: 5)
                .rotationEffect(Angle.degrees(minute / 2)).position(x: cx - r - 8, y: cy)
            CritterWidgetArt.sprite(8, 8, x: cx - r - 19, y: cy, angle: -hour * Double.pi / 180) { c, s in
                let mx: Double = Double(s.width) / 2
                let my: Double = Double(s.height) / 2
                CritterDraw.polygon(c, [CritterDraw.pt(mx, my - 3.5), CritterDraw.pt(mx + 3.2, my + 2.5),
                                        CritterDraw.pt(mx - 3.2, my + 2.5)], sceneColor(0x111111))
            }
        }
    }
}
