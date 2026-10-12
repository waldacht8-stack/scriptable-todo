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
    @_optimize(none)
    static func margin(_ m: CGFloat) -> CGFloat { m < 8 ? 16 : m }

    /// 下の余白の帯（文字との間を 2.5pt あける）
    /// 下の余白の通り道（余白・ターミナル・結晶・墨流しの絵が使う。下から 8pt）
    static func laneY(_ h: CGFloat) -> CGFloat { h - 8 }

    @_optimize(none)
    static func bottomBand(_ h: CGFloat, margin m: CGFloat) -> CritterBand {
        CritterBand(top: h - margin(m) + 2.5, bottom: h - 0.5)
    }

    /// 上の余白の帯（空の太陽）
    @_optimize(none)
    static func topBand(margin m: CGFloat) -> CritterBand {
        CritterBand(top: 0.5, bottom: margin(m) - 2.5)
    }

    /// 一巡の秒数（15分ごとの絵で、どれだけ進むか）
    @_optimize(none)
    static func period(_ w: World) -> Double {
        switch w {
        case .galaxy, .sky: 2 * 3600
        case .mist, .deepsea, .aurora: 3 * 3600
        default: 86400
        }
    }

    @_optimize(none)
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
        case .aurora: return aurora(w: w, band: band, k: k)
        case .crystal: return crystalLane(size: size, k: k)
        case .ink: return inkLane(size: size, k: k)
        case .yohaku: return AnyView(WidgetYohaku(size: size, k: k))
        case .terminal: return AnyView(WidgetTerminal(size: size, k: k))
        case .zankou, .breath: return AnyView(EmptyView())
        case .none: return AnyView(EmptyView())
        }
    }

    /// 小さな絵を1枚、決まった位置に置く（位置と向きは WidgetKit が描き直しの間でつなぐ）
    @_optimize(none)
    static func sprite(_ sw: CGFloat, _ sh: CGFloat, x: CGFloat, y: CGFloat, angle: Double,
                       draw: @escaping (GraphicsContext, CGSize) -> Void) -> some View {
        Canvas { c, s in draw(c, s) }
            .frame(width: sw, height: sh)
            .rotationEffect(Angle.radians(angle))
            .position(x: x, y: y)
    }

    /// 帯の高さに収まるように縮めた絵（box は絵の元の大きさ、origin は box の中の原点）
    @_optimize(none)
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
    @_optimize(none)
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
    @_optimize(none)
    static func mist(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.86 - 0.66 * k.progress)
        let walk: Double = k.progress * 40
        let lampBox = CGSize(width: 26, height: 40)
        let lampScale: CGFloat = band.height / lampBox.height
        let lampX: CGFloat = 4 + lampBox.width * lampScale / 2
        return AnyView(ZStack {
            fitted(box: lampBox, origin: CGPoint(x: 5, y: 56), band: band, x: lampX, maxScale: 1) { c in
                D.glow(c, 11.7, -35.5, 11, sceneColor(0xFFC77A), 0.6)
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
    @_optimize(none)
    static func deepsea(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.84 - 0.68 * k.progress)
        let t: Double = 2.6 + k.progress * 40
        let v = fitted(box: CGSize(width: 108, height: 38), origin: CGPoint(x: 52, y: 16), band: band, x: x, maxScale: 0.5) { c in
            Fantasy.whale(c, t: t, length: 100, haze: 0, finSweep: 0.45)
        }
        return AnyView(v)
    }

    /// オーロラ：15分ごとに形の変わるカーテン（上の方にうっすら。背景の光）と、雪の上を駆ける狐
    @_optimize(none)
    static func aurora(w: CGFloat, band: CritterBand, k: CritterKnobs) -> AnyView {
        let x: CGFloat = w * CGFloat(0.14 + 0.72 * k.progress)
        let run: Double = k.progress * 90
        let day: Double = k.day
        return AnyView(ZStack {
            // カーテンは 1 分ごとに少しずつ形を変え、絵の間はふわっと重ねて入れ替える
            Canvas { c, s in curtains(c, size: s, day: day) }
                .id(Int(day * 1440))
                .transition(.opacity)
            fitted(box: CGSize(width: 74, height: 35), origin: CGPoint(x: 42, y: 34), band: band, x: x, maxScale: 0.5) { c in
                Fantasy.foxRun(c, run: run, rim: sceneColor(0x86FBDD))
            }
        })
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
            let phase: Double = rnd.range(0, 6.28) + day * 1440 * 0.05
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

    @_optimize(none)
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

/// 空：上の余白の帯を太陽（夜は月）が進み、下の余白を時間帯ごとの飛ぶものが通る（雲は背景が時刻で流す）
/// 朝はスズメ、昼は紙飛行機、夕方はカラスの V の字、夜は灯りの点滅する飛行機
private struct WidgetSky: View {
    let size: CGSize
    let band: CritterBand
    let top: CritterBand
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let slot: SkySlot = SkySlot.at(day: k.day)
        let sunF: Double = CritterDraw.span(k.day, 0.21, 0.79)
        let moonRaw: Double = k.day >= 0.79 ? k.day - 0.79 : k.day + 0.21
        let moonF: Double = min(1, moonRaw / 0.42)
        let sh: CGFloat = top.height
        let lightF: Double = slot == .night ? moonF : sunF
        let sx: CGFloat = w * CGFloat(0.08 + 0.84 * lightF)
        ZStack {
            CritterWidgetArt.sprite(sh * 2, sh, x: sx, y: top.mid, angle: 0) { c, s in
                let cx: Double = Double(s.width) / 2
                let cy: Double = Double(s.height) / 2
                // 夜の月は背景（止まった空）が描くので、ここでは昼の太陽だけ
                if slot != .night {
                    Fantasy.softEllipse(c, cx, cy, cx, cy, sceneColor(0xFFF1B8), 0.8)
                    CritterDraw.circle(c, cx, cy, cy * 0.55, sceneColor(0xFFE9A0))
                }
            }
            flyer(slot, w: w)
        }
    }

    @ViewBuilder
    private func flyer(_ slot: SkySlot, w: CGFloat) -> some View {
        let p: Double = k.progress
        switch slot {
        case .morning:
            let x: CGFloat = w * CGFloat(0.1 + 0.8 * p)
            let flapA: Double = sin(p * 400)
            CritterWidgetArt.fitted(box: CGSize(width: 50, height: 22), origin: CGPoint(x: 25, y: 12), band: band, x: x, maxScale: 0.7) { c in
                Critters.sparrow(CritterDraw.local(c, at: CritterDraw.pt(10, 1), scale: 1), flap: flapA)
                Critters.sparrow(CritterDraw.local(c, at: CritterDraw.pt(-12, -2), scale: 0.9), flap: -flapA)
            }
        case .day:
            let px: CGFloat = w * CGFloat(0.08 + 0.84 * p)
            let py: CGFloat = band.mid + CGFloat(sin(p * 4 * Double.pi)) * 0.8
            let tilt: Double = -cos(p * 4 * Double.pi) * 0.12
            let planeScale: Double = min(0.65, Double(band.height) / 14)
            CritterWidgetArt.sprite(18, min(12, band.height), x: px, y: py, angle: tilt) { c, s in
                Critters.paperPlane(CritterDraw.local(c, at: CritterDraw.cpt(s.width / 2, s.height / 2), scale: planeScale), dark: k.dark)
            }
        case .evening:
            let x: CGFloat = w * CGFloat(0.9 - 0.8 * p)
            let crowColor: Color = sceneColor(0x2A2030, 0.85)
            CritterWidgetArt.fitted(box: CGSize(width: 70, height: 40), origin: CGPoint(x: 30, y: 20), band: band, x: x, maxScale: 0.5) { c in
                Critters.crow(CritterDraw.local(c, at: CritterDraw.pt(-14, 0), scale: 1, flip: true), flap: 0.8, color: crowColor)
                Critters.crow(CritterDraw.local(c, at: CritterDraw.pt(6, -10), scale: 0.9, flip: true), flap: -0.4, color: crowColor)
                Critters.crow(CritterDraw.local(c, at: CritterDraw.pt(8, 11), scale: 0.9, flip: true), flap: 0.2, color: crowColor)
            }
        case .night:
            let x: CGFloat = w * CGFloat(0.1 + 0.8 * p)
            CritterWidgetArt.fitted(box: CGSize(width: 40, height: 26), origin: CGPoint(x: 20, y: 14), band: band, x: x, maxScale: 0.6) { c in
                Critters.nightPlane(c, t: 0)
            }
        }
    }
}
