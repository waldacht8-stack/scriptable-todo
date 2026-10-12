import SwiftUI

// MARK: - ウィジェットの住人（止まった絵。entry.date から位置が決まり、WidgetKit が次の絵との間を動かす）
// 位置は .position / .rotationEffect / .trim で決める（Canvas の中で動かすと、描き直しの間がつながらないため）。
// 住人はウィジェットの下の余白（中身の外側）の中の「帯」だけを通る。帯は余白から文字との間を 2.5pt あけた高さで、
// 住人の絵はこの帯の高さに収まる大きさに縮めて描く（Canvas は枠の外を描かないので、光もはみ出さない）。なので文字には決して重ならない。
// 空の太陽だけは上の余白の帯を進む。オーロラのカーテンは背景の光としてうっすら敷く。ぼかしは使わない。

/// 住人が通ってよい帯（上端と下端）
struct CritterBand {
    let top: CGFloat
    let bottom: CGFloat
    var height: CGFloat { max(1, bottom - top) }
    var mid: CGFloat { (top + bottom) / 2 }
}

enum CritterWidgetArt {
    typealias D = CritterDraw
    typealias C = Critters
    typealias F = Fantasy

    /// 余白（WidgetKit の widgetContentMargins。アプリの中の見本では 0 なので 16 とみなす）
    static func margin(_ m: CGFloat) -> CGFloat { m < 8 ? 16 : m }

    /// 下の余白の帯（文字との間を 2.5pt あける）
    static func bottomBand(_ h: CGFloat, margin m: CGFloat) -> CritterBand {
        CritterBand(top: h - margin(m) + 2.5, bottom: h - 0.5)
    }

    /// 上の余白の帯（空の太陽）
    static func topBand(margin m: CGFloat) -> CritterBand {
        CritterBand(top: 0.5, bottom: margin(m) - 2.5)
    }

    /// 一巡の秒数（15分ごとの絵で、どれだけ進むか）
    static func period(_ w: World) -> Double {
        switch w {
        case .galaxy, .sky: 2 * 3600
        case .mist, .deepsea, .aurora: 3 * 3600
        default: 86400
        }
    }

    static func view(_ p: Palette, size: CGSize, knobs k: CritterKnobs, margins: EdgeInsets) -> AnyView {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        guard w > 1 && h > 1 else { return AnyView(EmptyView()) }
        let band: CritterBand = bottomBand(h, margin: margins.bottom)
        switch p.world {
        case .strata: return AnyView(WidgetMole(size: size, band: band, k: k))
        case .galaxy: return galaxy(w: w, band: band, k: k)
        case .sky: return AnyView(WidgetSky(size: size, band: band, top: topBand(margin: margins.top), k: k))
        case .mist: return mist(w: w, band: band, k: k)
        case .deepsea: return deepsea(w: w, band: band, k: k)
        case .hinata: return AnyView(WidgetCat(size: size, band: band, k: k))
        case .brutal:
            return AnyView(Canvas { c, s in stickers(c, size: s, band: band, count: k.count) })
        case .aurora: return aurora(w: w, band: band, k: k)
        case .bento: return AnyView(WidgetBento(size: size, band: band, k: k))
        case .swiss: return AnyView(WidgetSwiss(size: size, band: band, k: k))
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

    /// 帯の高さに収まるように縮めた絵（box は絵の元の大きさ、origin は box の中の原点）
    static func fitted(box: CGSize, origin: CGPoint, band: CritterBand, x: CGFloat, maxScale: CGFloat,
                       draw: @escaping (GraphicsContext) -> Void) -> some View {
        let scale: CGFloat = min(maxScale, band.height / box.height)
        let sw: CGFloat = box.width * scale
        let sh: CGFloat = box.height * scale
        let ox: CGFloat = origin.x * scale
        let oy: CGFloat = origin.y * scale
        return sprite(sw, sh, x: x, y: band.bottom - sh / 2, angle: 0) { c, _ in
            draw(D.local(c, at: D.cpt(ox, oy), scale: Double(scale)))
        }
    }

    /// 銀河：寝そべるように漂う宇宙飛行士（左から右へ）
    static func galaxy(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.14 + 0.72 * k.progress)
        let tilt: Double = sin(k.progress * 4 * Double.pi) * 0.12
        let t: Double = k.progress * 600
        let v = fitted(box: CGSize(width: 64, height: 40), origin: CGPoint(x: 33, y: 23), band: band, x: x, maxScale: 0.5) { c in
            var a: GraphicsContext = c
            a.rotate(by: Angle.radians(-1.35 + tilt))
            Fantasy.astronaut(a, t: t, halo: false)
        }
        return AnyView(v)
    }

    /// 霧：左端の灯りと、草をはみながら右から左へ進む鹿
    static func mist(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.86 - 0.66 * k.progress)
        let walk: Double = k.progress * 40
        let lampBox = CGSize(width: 30, height: 58)
        let lampScale: CGFloat = band.height / lampBox.height
        let lampX: CGFloat = 4 + lampBox.width * lampScale / 2
        return AnyView(ZStack {
            fitted(box: lampBox, origin: CGPoint(x: 8, y: 57), band: band, x: lampX, maxScale: 1) { c in
                D.glow(c, 12.5, -36, 13, sceneColor(0xFFC77A), 0.55)
                Fantasy.lantern(c, height: 46, swing: 0.08, flicker: 0.6, t: 0, halo: false)
            }
            fitted(box: CGSize(width: 92, height: 56), origin: CGPoint(x: 62, y: 55), band: band, x: x, maxScale: 0.4) { c in
                let pose = Fantasy.DeerPose(walk: walk, headDown: 1, ear: 0, tail: 0, breath: nil, lightSide: -1, light: 0.5)
                Fantasy.deer(c, pose: pose, near: sceneColor(0x4D5964), far: sceneColor(0x7D8891), belly: sceneColor(0x37414A),
                             rim: sceneColor(0xFFC98A))
            }
        })
    }

    /// 深海：右から左へゆっくり泳ぐクジラ
    static func deepsea(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.84 - 0.68 * k.progress)
        let t: Double = 2.6 + k.progress * 40
        let v = fitted(box: CGSize(width: 108, height: 38), origin: CGPoint(x: 52, y: 16), band: band, x: x, maxScale: 0.5) { c in
            Fantasy.whale(c, t: t, length: 100, haze: 0, finSweep: 0.45)
        }
        return AnyView(v)
    }

    /// オーロラ：15分ごとに形の変わるカーテン（上の方にうっすら。背景の光）と、雪の上を駆ける狐
    static func aurora(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.14 + 0.72 * k.progress)
        let run: Double = k.progress * 90
        let day: Double = k.day
        return AnyView(ZStack {
            Canvas { c, s in curtains(c, size: s, day: day) }
            fitted(box: CGSize(width: 74, height: 35), origin: CGPoint(x: 42, y: 34), band: band, x: x, maxScale: 0.5) { c in
                Fantasy.foxRun(c, run: run, rim: sceneColor(0x86FBDD))
            }
        })
    }

    /// ネオブルータル：今日完了した数だけシールを貼る（下の余白を右から左へ。10枚まで）
    @_optimize(none)
    static func stickers(_ ctx: GraphicsContext, size: CGSize, band: CritterBand, count: Int) {
        let w: Double = Double(size.width)
        let y0: Double = Double(band.mid)
        let scale: Double = min(0.42, Double(band.height) / 28)
        let n: Int = min(10, max(0, count))
        for i in 0..<n {
            let x: Double = w - 14 - Double(i) * 13
            let y: Double = y0 - (i % 2 == 0 ? 0 : 0.8)
            let angle: Double = i % 2 == 0 ? -0.22 : 0.18
            C.sticker(D.local(ctx, at: D.pt(x, y), scale: scale, angle: angle), kind: i)
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
    let band: CritterBand
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let y: CGFloat = band.mid
        let reach: Double = max(0.03, min(1, k.day))
        let mx: CGFloat = 8 + (w - 16) * CGFloat(reach)
        let my: CGFloat = WidgetTunnel.wave(Double(mx), w: Double(w), y: Double(y))
        let scale: Double = min(0.55, Double(band.height) / 16)
        ZStack {
            WidgetTunnel(y: y)
                .trim(from: 0, to: reach)
                .stroke(sceneColor(0x5E4129, 0.45), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            CritterWidgetArt.sprite(20, min(12, band.height), x: mx, y: my, angle: 0) { c, s in
                Critters.mole(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2 - 2, s.height / 2), scale: scale), t: 0, digging: false)
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

/// 空：太陽が上の余白の帯を東から西へ進み、紙飛行機が下の余白を飛ぶ（雲は背景が時刻で流す）
private struct WidgetSky: View {
    let size: CGSize
    let band: CritterBand
    let top: CritterBand
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let sunF: Double = CritterDraw.span(k.day, 0.25, 0.75)
        let showSun: Bool = !SkyPhase.current().isNight && sunF > 0 && sunF < 1
        let sh: CGFloat = top.height
        let sx: CGFloat = w * CGFloat(0.08 + 0.84 * sunF)
        let px: CGFloat = w * CGFloat(0.08 + 0.84 * k.progress)
        let py: CGFloat = band.mid + CGFloat(sin(k.progress * 4 * Double.pi)) * 0.8
        let tilt: Double = -cos(k.progress * 4 * Double.pi) * 0.12
        let planeScale: Double = min(0.65, Double(band.height) / 14)
        ZStack {
            if showSun {
                CritterWidgetArt.sprite(sh * 2, sh, x: sx, y: top.mid, angle: 0) { c, s in
                    let cx: Double = Double(s.width) / 2
                    let cy: Double = Double(s.height) / 2
                    Fantasy.softEllipse(c, cx, cy, cx, cy, sceneColor(0xFFF1B8), 0.8)
                    CritterDraw.circle(c, cx, cy, cy * 0.55, sceneColor(0xFFE9A0))
                }
            }
            CritterWidgetArt.sprite(18, min(12, band.height), x: px, y: py, angle: tilt) { c, s in
                Critters.paperPlane(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2), scale: planeScale), dark: k.dark)
            }
        }
    }
}

/// 日なた：日の当たる場所（朝は左、夕方は右へ移る）に猫が座る
private struct WidgetCat: View {
    let size: CGSize
    let band: CritterBand
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let f: Double = CritterDraw.span(k.day, 0.25, 0.75)
        let x: CGFloat = w * CGFloat(0.12 + 0.76 * f)
        let ground: CGFloat = band.bottom - 1
        let scale: CGFloat = min(0.6, (band.height - 1) / 23)
        let catH: CGFloat = 23 * scale
        let pool = RadialGradient(colors: [sceneColor(0xFFD08A, 0.8), sceneColor(0xFFD08A, 0)], center: .center,
                                  startRadius: 0, endRadius: 22)
        ZStack {
            Ellipse().fill(pool).frame(width: 44, height: min(8, band.height)).position(x: x, y: ground - 2)
            CritterWidgetArt.sprite(16, catH, x: x, y: ground - catH / 2, angle: 0) { c, s in
                Critters.catSitting(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height), scale: Double(scale)))
            }
        }
    }
}

/// ベント：右下の余白の小さなタイル。15分ごとに並びが変わる（WidgetKit が入れ替わりを動かす）
private struct WidgetBento: View {
    let size: CGSize
    let band: CritterBand
    let k: CritterKnobs

    var body: some View {
        let gap: CGFloat = 1.5
        let cell: CGFloat = min(5.5, (band.height - gap) / 2)
        let w: CGFloat = size.width
        let originX: CGFloat = w - 16 - cell * 3 - gap * 2
        let originY: CGFloat = band.bottom - cell * 2 - gap
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
    let band: CritterBand
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let hour: Double = k.day * 2 * 360
        let minute: Double = k.day * 24 * 360
        let r: CGFloat = min(6, band.height / 2 - 0.5)
        let cx: CGFloat = w - 18 - r
        let cy: CGFloat = band.mid
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
