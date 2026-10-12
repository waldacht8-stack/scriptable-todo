import SwiftUI

// MARK: - 空：時間帯ごとに飛ぶもの
// 朝（5〜10時）：スズメの小さな群れが、はずむように飛んで出かける
// 昼（10〜16時）：カモメと紙飛行機（いままでどおり）
// 夕方（16〜19時）：夕焼けの中を、カラスがゆるい V の字で帰っていく
// 夜（19〜5時）：鳥はいない。赤と白の灯りを点滅させた飛行機がゆっくり横切り、ときどき流れ星
// 完了の反応も時間帯で変わる（朝はスズメが飛び立つ・昼は風船・夕方は夕焼け色の風船・夜は天灯と流れ星）

enum SkySlot {
    case morning, day, evening, night

    @_optimize(none)
    static func at(minutes m: Double) -> SkySlot {
        switch m {
        case 300..<600: return .morning
        case 600..<960: return .day
        case 960..<1140: return .evening
        default: return .night
        }
    }

    /// 一日の位置（0〜1）から。画面写真用の -skyhour があればそちらを使う
    @_optimize(none)
    static func at(day: Double) -> SkySlot {
        let args: [String] = ProcessInfo.processInfo.arguments
        if args.contains("-skyhour") {
            return at(minutes: SkyPhase.minuteOfDay())
        }
        return at(minutes: day * 1440)
    }
}

extension Critters {
    /// スズメ（右向き。幅 20 くらい。flap は -1〜1 の羽ばたき）
    @_optimize(none)
    static func sparrow(_ c: GraphicsContext, flap: Double) {
        let brown: Color = sceneColor(0x8A5A3B)
        let cream: Color = sceneColor(0xF2DFC4)
        let dark: Color = sceneColor(0x3A2A20)
        D.polygon(c, [D.pt(-5, -0.5), D.pt(-10.5, -3), D.pt(-10, 1.4)], dark)
        D.ellipse(c, 0, 0, 12.5, 9, brown)
        D.ellipse(c, 1.2, 2, 8, 4.4, cream)
        D.circle(c, 5.2, -3.2, 3.7, brown)
        D.ellipse(c, 6.2, -1.8, 3.2, 1.7, cream)
        D.circle(c, 6.6, -3.9, 0.8, dark)
        D.polygon(c, [D.pt(8.6, -3.6), D.pt(10.8, -2.8), D.pt(8.6, -2.1)], sceneColor(0xE0A040))
        let tipY: Double = -2 - flap * 6
        var wing = Path()
        wing.move(to: D.pt(-3.5, -1))
        wing.addQuadCurve(to: D.pt(-7, tipY), control: D.pt(-1.5, tipY - 1))
        wing.addQuadCurve(to: D.pt(2.5, -1.2), control: D.pt(-1, tipY * 0.35))
        wing.closeSubpath()
        c.fill(wing, with: .color(sceneColor(0x6B4329)))
    }

    /// カラス（右向き。幅 26 くらい。夕焼けに映える影）
    @_optimize(none)
    static func crow(_ c: GraphicsContext, flap: Double, color: Color) {
        D.polygon(c, [D.pt(-6, -1.2), D.pt(-13, -3.2), D.pt(-12.6, 2.4), D.pt(-6, 1.6)], color)
        D.ellipse(c, 0, 0, 15, 6.4, color)
        D.circle(c, 7.4, -1.4, 3.2, color)
        D.polygon(c, [D.pt(10, -2.2), D.pt(13.8, -0.8), D.pt(10, 0)], color)
        let tipY: Double = -1 - flap * 10
        var wing = Path()
        wing.move(to: D.pt(-4, -1))
        wing.addQuadCurve(to: D.pt(-9, tipY), control: D.pt(-3, tipY * 0.6 - 1))
        wing.addLine(to: D.pt(-6.4, tipY * 0.82))
        wing.addLine(to: D.pt(-5, tipY * 0.9))
        wing.addQuadCurve(to: D.pt(3, -1), control: D.pt(1, tipY * 0.4))
        wing.closeSubpath()
        c.fill(wing, with: .color(color))
    }

    /// 夜の飛行機（右向き。幅 30 くらい。左の翼端に赤、尾に白の点滅灯）
    @_optimize(none)
    static func nightPlane(_ c: GraphicsContext, t: Double) {
        let body: Color = sceneColor(0x4A5280, 0.9)
        let edge: Color = sceneColor(0x8C95C8, 0.6)
        D.polygon(c, [D.pt(1, 0), D.pt(-6, -9), D.pt(-3, -9), D.pt(6, 0)], body)
        let fuselage = Path(roundedRect: CGRect(x: -14, y: -2, width: 28, height: 4), cornerRadius: 2)
        c.fill(fuselage, with: .color(body))
        c.stroke(fuselage, with: .color(edge), lineWidth: 0.6)
        D.polygon(c, [D.pt(1, 0.5), D.pt(-5, 7), D.pt(-2.4, 7), D.pt(6, 0.5)], body)
        D.polygon(c, [D.pt(-11, -1.5), D.pt(-14.5, -6.5), D.pt(-12.4, -6.5), D.pt(-8.5, -1.5)], body)
        for i in 0..<4 {
            D.circle(c, 6 - Double(i) * 3.4, -0.4, 0.45, sceneColor(0xFFE9B0, 0.75))
        }
        let red: Bool = (t * 0.9).truncatingRemainder(dividingBy: 1) < 0.16
        let s: Double = (t * 0.75).truncatingRemainder(dividingBy: 1)
        let white: Bool = s < 0.06 || (s > 0.14 && s < 0.2)
        D.glow(c, -5.5, -9, red ? 7 : 3, sceneColor(0xFF4A4A), red ? 0.95 : 0.35)
        D.circle(c, -5.5, -9, 0.9, sceneColor(0xFF6B6B))
        D.glow(c, -14, 0, white ? 8 : 2.5, Color.white, white ? 1 : 0.3)
        D.circle(c, -14, 0, 0.8, Color.white)
    }

    /// 天灯（夜の完了の反応。暖かく光りながら上る。原点は灯りの中心）
    @_optimize(none)
    static func skyLantern(_ c: GraphicsContext, flicker: Double) {
        D.glow(c, 0, 2, 30, sceneColor(0xFFB25C), 0.45 + 0.15 * flicker)
        var paper = Path()
        paper.move(to: D.pt(-6.5, -9))
        paper.addLine(to: D.pt(6.5, -9))
        paper.addQuadCurve(to: D.pt(4.6, 9), control: D.pt(8.4, 0))
        paper.addLine(to: D.pt(-4.6, 9))
        paper.addQuadCurve(to: D.pt(-6.5, -9), control: D.pt(-8.4, 0))
        paper.closeSubpath()
        let g = Gradient(colors: [sceneColor(0xFFE7B0), sceneColor(0xFFB25C), sceneColor(0xE0703A)])
        c.fill(paper, with: .linearGradient(g, startPoint: D.pt(0, -9), endPoint: D.pt(0, 9)))
        D.line(c, D.pt(-4.6, 9), D.pt(4.6, 9), sceneColor(0x8A4A28), 1)
        D.glow(c, 0, 7, 5, Color.white, 0.6 + 0.3 * flicker)
    }
}

extension CritterArt {
    /// 空の飛ぶもの（時間帯ごと）
    @_optimize(none)
    static func skyFlyers(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let slot: SkySlot = SkySlot.at(day: k.day)
        switch slot {
        case .morning:
            // スズメの小さな群れ：上下にはずみながら左から右へ
            let bp: Double = (k.progress * 26 / 30 + 0.2).truncatingRemainder(dividingBy: 1)
            let bx: Double = -40 + bp * (w + 80)
            let flock: [(Double, Double, Double)] = [(0, 0, 0), (-18, 8, 1.3), (-30, -6, 2.1), (-44, 4, 0.7)]
            for item in flock {
                let hop: Double = -abs(sin(k.t * 3.2 + item.2)) * 7
                let flap: Double = sin(k.t * 18 + item.2 * 2)
                let x: Double = bx + item.0
                let y: Double = lane - 18 + item.1 + hop
                Critters.sparrow(D.local(ctx, at: D.pt(x, y), scale: 1.05), flap: flap)
            }
        case .day:
            let birdColor: Color = k.dark ? sceneColor(0xBAC3E8, 0.6) : sceneColor(0x2B4560, 0.55)
            let bp: Double = (k.progress * 26 / 34 + 0.3).truncatingRemainder(dividingBy: 1)
            let bx: Double = -40 + bp * (w + 80)
            let by: Double = lane - 22 + sin(k.t * 0.5) * 4
            let flock: [(Double, Double)] = [(0, 0), (-10, -5), (-10, 6), (-20, -10), (-19, 11)]
            for (i, o) in flock.enumerated() {
                let flap: Double = sin(k.t * 9 + Double(i) * 1.3) * 2.2
                Critters.bird(D.local(ctx, at: D.pt(bx + o.0, by + o.1), scale: 1), flap: flap, color: birdColor)
            }
            let px: Double = w + 30 - k.progress * (w + 60)
            let py: Double = lane + 14 + sin(k.progress * 4 * Double.pi) * 7
            let tilt: Double = cos(k.progress * 4 * Double.pi) * 0.22
            Critters.paperPlane(D.local(ctx, at: D.pt(px, py), scale: 1.05, angle: -tilt, flip: true), dark: k.dark)
        case .evening:
            // カラスの V の字：右から左へ、ねぐらへ帰る
            let cp: Double = (k.progress * 26 / 40 + 0.1).truncatingRemainder(dividingBy: 1)
            let cx: Double = w + 60 - cp * (w + 160)
            let cy: Double = lane - 12 + sin(k.t * 0.4) * 4
            let crowColor: Color = sceneColor(0x2A2030, 0.82)
            let v: [(Double, Double, Double)] = [(0, 0, 0), (16, -9, 0.8), (16, 9, 1.6), (33, -17, 2.2), (31, 18, 0.4), (50, -25, 1.1)]
            for item in v {
                let flap: Double = sin(k.t * 4.2 + item.2)
                let jitter: Double = sin(k.t * 0.7 + item.2 * 3) * 2
                let at = D.pt(cx + item.0, cy + item.1 + jitter)
                Critters.crow(D.local(ctx, at: at, scale: 0.95, flip: true), flap: flap, color: crowColor)
            }
        case .night:
            // 鳥はいない。灯りを点滅させた飛行機がゆっくり横切る
            let pp: Double = (k.progress * 26 / 60).truncatingRemainder(dividingBy: 1)
            let px: Double = -40 + pp * (w + 80)
            let py: Double = lane + 8 - pp * 10
            Critters.nightPlane(D.local(ctx, at: D.pt(px, py), scale: 1.25, angle: -0.05), t: k.t)
            skyShootingStar(ctx, w: w, lane: lane, t: k.t)
        }
    }

    /// ときどき流れ星（14秒ごとに 1.1 秒）
    @_optimize(none)
    static func skyShootingStar(_ ctx: GraphicsContext, w: Double, lane: Double, t: Double) {
        let period: Double = 14
        let cycle: Double = floor(t / period)
        let ph: Double = t - cycle * period
        guard ph < 1.1 else { return }
        var rnd = SceneRandom(UInt64(max(0, cycle)) &+ 77)
        let k: Double = ph / 1.1
        let x0: Double = w * rnd.range(0.55, 0.95)
        let y0: Double = lane * rnd.range(0.08, 0.3)
        let dx: Double = -0.86
        let dy: Double = 0.5
        let head = D.pt(x0 + dx * 180 * k, y0 + dy * 180 * k)
        let alpha: Double = k < 0.2 ? k / 0.2 : 1 - k
        Critters.shootingStar(ctx, head: head, dirX: dx, dirY: dy, length: 60, alpha: alpha)
    }

    /// 空の完了の反応（時間帯ごと）
    @_optimize(none)
    static func skyReaction(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, r: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let slot: SkySlot = SkySlot.at(day: k.day)
        switch slot {
        case .morning:
            // スズメが右下からぱっと飛び立つ
            for i in 0..<5 {
                let fi: Double = Double(i)
                let u: Double = D.span(r, fi * 0.06, 0.7 + fi * 0.05)
                guard u > 0 && u < 1 else { continue }
                let x: Double = w - 20 - fi * 9 - u * (40 + fi * 18)
                let y: Double = h * 0.86 - u * (h * 0.3 + fi * 20) - sin(u * 9 + fi) * 4
                var c: GraphicsContext = D.local(ctx, at: D.pt(x, y), scale: 0.95, flip: true)
                c.opacity = min(1, u * 6) * (1 - D.span(u, 0.8, 1))
                Critters.sparrow(c, flap: sin(r * 60 + fi))
            }
        case .day, .evening:
            let sway: Double = sin(r * 9)
            let x: Double = w - 10 + sway * 2.5
            let y: Double = h * 0.93 - D.ease(r) * (h * 0.93 + 40)
            var c: GraphicsContext = D.local(ctx, at: D.pt(x, y), scale: 1, angle: sway * 0.08)
            c.opacity = min(1, r * 10)
            if slot == .evening {
                // 夕焼け色の風船
                c.addFilter(.hueRotation(Angle.degrees(28)))
            }
            Critters.balloon(c, sway: sway)
        case .night:
            // 天灯がゆらゆら上り、流れ星がはじける
            let sway: Double = sin(r * 7)
            let x: Double = w - 22 + sway * 4
            let y: Double = h * 0.9 - D.ease(r) * (h * 0.55)
            var c: GraphicsContext = D.local(ctx, at: D.pt(x, y), scale: 1, angle: sway * 0.05)
            c.opacity = min(1, r * 8) * (1 - D.span(r, 0.85, 1))
            Critters.skyLantern(c, flicker: 0.5 + 0.5 * sin(r * 40))
            let burst: Double = D.span(r, 0.1, 0.6)
            if burst > 0 && burst < 1 {
                for i in 0..<5 {
                    let a: Double = 0.3 + Double(i) * 1.256
                    let len: Double = 14 + burst * 46
                    let ox: Double = x
                    let oy: Double = y - 4
                    let head = D.pt(ox + cos(a) * len, oy - sin(a) * len * 0.6)
                    let alpha: Double = (1 - burst) * 0.9
                    Critters.shootingStar(ctx, head: head, dirX: cos(a), dirY: -sin(a) * 0.6, length: 26, alpha: alpha)
                }
            }
        }
    }
}
