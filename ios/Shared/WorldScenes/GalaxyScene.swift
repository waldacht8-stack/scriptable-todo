import SwiftUI

// MARK: - 銀河：深い宇宙に渦巻く銀河。星の腕がゆっくり回り、星がまたたき、ときどき流れ星
// 腕（たくさんの星と淡いもや）は止まった絵を1枚描き、repeatForever の回転で回す（毎フレーム描き直さない）。
// またたきと流れ星だけを TimelineView（20fps）の小さな Canvas で描く。

enum GalaxyScene {
    struct Star { let x: Double; let y: Double; let r: Double; let tint: Int; let alpha: Double }

    static let tints: [Color] = [Color.white, sceneColor(0xDCE4FF), sceneColor(0xB9A8FF), sceneColor(0xFFC2E6), sceneColor(0x9FC4FF)]

    /// 渦の腕の星（中心を 0.5,0.5 とした比の座標）
    @_optimize(none)
    static func armStars(count: Int) -> [Star] {
        var rnd = SceneRandom(2026)
        var out: [Star] = []
        for arm in 0..<2 {
            for _ in 0..<(count / 2) {
                let s: Double = pow(rnd.next(), 0.8)                 // 腕の付け根からの距離 0〜1
                let theta: Double = s * 3.6 + Double(arm) * .pi      // 対数らせんの角度
                let radius: Double = 0.04 + s * 0.44
                let spread: Double = (0.012 + s * 0.05) * (rnd.next() - 0.5) * 2
                let ang: Double = theta + spread * 3
                let rr: Double = radius + spread
                let x: Double = 0.5 + cos(ang) * rr
                let y: Double = 0.5 + sin(ang) * rr
                let big: Bool = rnd.next() > 0.9
                let r: Double = big ? rnd.range(1.1, 1.9) : rnd.range(0.35, 0.95)
                out.append(Star(x: x, y: y, r: r, tint: Int(rnd.next() * 4.99), alpha: rnd.range(0.45, 1)))
            }
        }
        // 腕の外の散らばった星
        for _ in 0..<(count / 4) {
            out.append(Star(x: rnd.next(), y: rnd.next(), r: rnd.range(0.3, 0.9), tint: Int(rnd.next() * 1.99), alpha: rnd.range(0.3, 0.8)))
        }
        return out
    }

    static let fullStars: [Star] = armStars(count: 360)
    static let compactStars: [Star] = armStars(count: 140)

    /// またたく明るい星（画面の比の座標）
    static let twinkles: [Star] = {
        var rnd = SceneRandom(909)
        var out: [Star] = []
        for _ in 0..<22 {
            out.append(Star(x: rnd.next(), y: rnd.range(0.02, 0.92), r: rnd.range(0.8, 1.7), tint: Int(rnd.next() * 3.99), alpha: rnd.range(0, 6.28)))
        }
        return out
    }()

    /// 腕（止まった絵）。size は正方形
    @_optimize(none)
    static func drawArms(_ ctx: GraphicsContext, size: CGSize, compact: Bool) {
        let w: Double = Double(size.width)
        let center = CGPoint(x: w / 2, y: w / 2)
        // 中心の光
        let coreR: Double = w * 0.2
        let core = Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))
        let coreShade = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [sceneColor(0xFFF4DE, 0.85), sceneColor(0xE8C8FF, 0.32), sceneColor(0x8A6BFF, 0)]),
            center: center, startRadius: 0, endRadius: coreR)
        ctx.fill(core, with: coreShade)
        // 腕のもや（淡い丸を腕に沿って並べる。ぼかしは使わない）
        let hazeCount: Int = compact ? 9 : 16
        for arm in 0..<2 {
            for i in 0..<hazeCount {
                let s: Double = Double(i) / Double(hazeCount - 1)
                let theta: Double = s * 3.6 + Double(arm) * .pi
                let radius: Double = (0.04 + s * 0.44) * w
                let p = CGPoint(x: center.x + cos(theta) * radius, y: center.y + sin(theta) * radius)
                let hr: Double = w * (0.05 + s * 0.06)
                let tint: Color = arm == 0 ? sceneColor(0x9682FF, 0.22) : sceneColor(0x6E96FF, 0.2)
                let shade = GraphicsContext.Shading.radialGradient(Gradient(colors: [tint, tint.opacity(0)]),
                                                                   center: p, startRadius: 0, endRadius: hr)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - hr, y: p.y - hr, width: hr * 2, height: hr * 2)), with: shade)
            }
        }
        // 星
        let stars: [Star] = compact ? compactStars : fullStars
        for s in stars {
            let rect = CGRect(x: s.x * w - s.r, y: s.y * w - s.r, width: s.r * 2, height: s.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(tints[s.tint].opacity(s.alpha)))
        }
    }

    /// またたきと流れ星（t は秒。t = 0 は止まった絵）
    @_optimize(none)
    static func drawSparkle(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        for s in twinkles {
            let wave: Double = t == 0 ? 0.7 : 0.5 + 0.5 * sin(t * 2 * .pi / 3.2 + s.alpha)
            let a: Double = 0.25 + 0.75 * wave
            let c = CGPoint(x: s.x * w, y: s.y * h)
            let gr: Double = s.r * 4
            let glow = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [tints[s.tint].opacity(0.55 * a), tints[s.tint].opacity(0)]),
                center: c, startRadius: 0, endRadius: gr)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)), with: glow)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s.r, y: c.y - s.r, width: s.r * 2, height: s.r * 2)), with: .color(Color.white.opacity(a)))
        }
        // 流れ星：9秒ごとに 0.9 秒だけ
        guard t != 0 else { return }
        let period: Double = 9
        let cycle: Double = floor(t / period)
        let phase: Double = t - cycle * period
        guard phase < 0.9 else { return }
        var rnd = SceneRandom(UInt64(max(0, cycle)))
        let sx: Double = rnd.range(0.45, 1.0) * w
        let sy: Double = rnd.range(0.04, 0.4) * h
        let len: Double = 230
        let dx: Double = -cos(28 * .pi / 180)
        let dy: Double = sin(28 * .pi / 180)
        let k: Double = phase / 0.9
        let head = CGPoint(x: sx + dx * len * k, y: sy + dy * len * k)
        let tail = CGPoint(x: head.x - dx * 70, y: head.y - dy * 70)
        var streak = Path()
        streak.move(to: tail)
        streak.addLine(to: head)
        let fade: Double = k < 0.15 ? k / 0.15 : (1 - k)
        let shade = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Color.white.opacity(0), Color.white.opacity(0.95 * fade)]),
            startPoint: tail, endPoint: head)
        ctx.stroke(streak, with: shade, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }
}

/// 銀河の全画面の背景
struct GalaxyBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            let side: CGFloat = max(size.width, size.height * 0.62) * 1.55
            let base = EllipticalGradient(colors: [sceneColor(0x1B1440), sceneColor(0x0A0820), sceneColor(0x03030A)],
                                          center: UnitPoint(x: 0.5, y: 0.34), startRadiusFraction: 0, endRadiusFraction: 0.85)
            ZStack {
                base
                nebula(sceneColor(0x7B4DFF, 0.42), at: CGPoint(x: size.width * 0.05, y: size.height * 0.16), r: size.width * 0.62)
                nebula(sceneColor(0x3C7BFF, 0.32), at: CGPoint(x: size.width * 1.0, y: size.height * 0.4), r: size.width * 0.6)
                nebula(sceneColor(0xFF5FB0, 0.24), at: CGPoint(x: size.width * 0.35, y: size.height * 0.8), r: size.width * 0.55)
                Canvas { ctx, s in
                    GalaxyScene.drawArms(ctx, size: s, compact: compact)
                }
                .frame(width: side, height: side)
                .sceneSpin(animated, period: 140)
                .position(x: size.width * 0.5, y: size.height * 0.33)
                .opacity(0.9)
                SceneClock(fps: 20, animated: animated, stillT: stillT) { t in
                    Canvas { ctx, s in
                        GalaxyScene.drawSparkle(ctx, size: s, t: t)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private func nebula(_ c: Color, at point: CGPoint, r: CGFloat) -> some View {
        let g = RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: r)
        return Circle().fill(g).frame(width: r * 2, height: r * 2).position(point)
    }
}

/// 銀河のカード：暗い半透明の板に、星明かりのかすかな縁
struct GalaxyCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let rim = LinearGradient(colors: [Color.white.opacity(0.42), sceneColor(0xB9A8FF, 0.16), sceneColor(0xFFB8DA, 0.3)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        let sheen = LinearGradient(colors: [sceneColor(0x8A6BFF, 0.14), Color.clear],
                                   startPoint: .top, endPoint: .center)
        ZStack {
            shape.fill(p.card.opacity(light ? 0.78 : 1))
            shape.fill(sheen)
            shape.strokeBorder(rim, lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0x8A6BFF, light ? 0.25 : 0.3), radius: light ? 5 : 12)
    }
}
