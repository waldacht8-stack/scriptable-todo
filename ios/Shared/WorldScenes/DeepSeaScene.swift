import SwiftUI

// MARK: - 深海：日の差す浅瀬から、光の届かない深みへ。水面のゆらめく光（コースティクス）、斜めの光の筋、
// 降りつづくマリンスノー、深いところでかすかに光る発光の粒。にぎやかにせず、深さで暗くなる色と静かな動きで見せる。
// コースティクス・マリンスノー・発光は TimelineView（15fps）の Canvas 1枚、光の筋は repeatForever の明滅。

enum DeepSeaScene {
    static let water: [Gradient.Stop] = [
        Gradient.Stop(color: sceneColor(0x167E9C), location: 0),
        Gradient.Stop(color: sceneColor(0x0B5F80), location: 0.07),
        Gradient.Stop(color: sceneColor(0x07405F), location: 0.18),
        Gradient.Stop(color: sceneColor(0x042A47), location: 0.32),
        Gradient.Stop(color: sceneColor(0x02172E), location: 0.5),
        Gradient.Stop(color: sceneColor(0x010B19), location: 0.7),
        Gradient.Stop(color: sceneColor(0x00040A), location: 1),
    ]

    struct Mote { let x: Double; let y: Double; let r: Double; let speed: Double; let phase: Double }

    static let snow: [Mote] = {
        var rnd = SceneRandom(1201)
        var out: [Mote] = []
        for _ in 0..<36 {
            out.append(Mote(x: rnd.next(), y: rnd.next(), r: rnd.range(0.3, 1.1), speed: rnd.range(0.0035, 0.009), phase: rnd.range(0, 6.28)))
        }
        return out
    }()

    static let glows: [Mote] = {
        var rnd = SceneRandom(88)
        var out: [Mote] = []
        for _ in 0..<4 {
            out.append(Mote(x: rnd.range(0.05, 0.95), y: rnd.range(0.6, 0.95), r: rnd.range(0.7, 1.3), speed: rnd.range(0.25, 0.6), phase: rnd.range(0, 6.28)))
        }
        return out
    }()

    /// 水面の光の網（上ほど明るく、下へ消える）
    @_optimize(none)
    static func drawCaustics(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let depth: Double = Double(size.height) * (compact ? 0.32 : 0.2)
        let rows: Int = compact ? 4 : 5
        let steps: Int = 16
        let drift: Double = t * 0.3
        for layer in 0..<2 {
            let alpha: Double = layer == 0 ? 0.2 : 0.1
            let width: Double = layer == 0 ? 1.6 : 0.9
            let speed: Double = layer == 0 ? 1 : -0.7
            // 横の波線
            for i in 0..<rows {
                let fy: Double = (Double(i) + 0.4 + Double(layer) * 0.5) / Double(rows)
                let y0: Double = fy * depth
                var path = Path()
                for s in 0...steps {
                    let fx: Double = Double(s) / Double(steps)
                    let y: Double = y0 + sin(fx * 9 + Double(i) * 1.7 + drift * speed) * 6 + sin(fx * 3.4 - drift * 0.6) * 4
                    if s == 0 { path.move(to: CGPoint(x: fx * w, y: y)) } else { path.addLine(to: CGPoint(x: fx * w, y: y)) }
                }
                let a: Double = alpha * (1 - fy)
                ctx.stroke(path, with: .color(sceneColor(0xEBFFFF, a)), lineWidth: width)
            }
            // 縦の波線（下へ行くほど薄く。区切って描く）
            let cols: Int = compact ? 4 : 6
            for j in 0..<cols {
                let fx0: Double = (Double(j) + 0.3 + Double(layer) * 0.5) / Double(cols)
                let segs: Int = 4
                for k in 0..<segs {
                    var path = Path()
                    for s in 0...4 {
                        let fy: Double = (Double(k) + Double(s) / 4) / Double(segs)
                        let x: Double = fx0 * w + sin(fy * 7 + Double(j) * 2.3 + drift * speed * 0.8) * 10
                        let y: Double = fy * depth
                        if s == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let a: Double = alpha * (1 - Double(k) / Double(segs))
                    ctx.stroke(path, with: .color(sceneColor(0xEBFFFF, a)), lineWidth: width)
                }
            }
        }
    }

    /// マリンスノー・発光の粒・クラゲ
    @_optimize(none)
    static func drawLife(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        // マリンスノー：小さく不ぞろいなかけらが、ゆっくり沈みながら横へ少しただよう（光の届く上ほど見えやすい）
        for (i, m) in snow.enumerated() where !compact || i % 2 == 0 {
            let y: Double = ((m.y + t * m.speed).truncatingRemainder(dividingBy: 1)) * h
            let x: Double = m.x * w + sin(t / 7 + m.phase) * 3
            let depthFade: Double = 1 - 0.55 * (y / h)
            let a: Double = (0.14 + 0.3 * (0.5 + 0.5 * sin(m.phase * 3))) * depthFade
            let rx: Double = m.r * (i % 3 == 0 ? 1.6 : 1)
            ctx.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - m.r, width: rx * 2, height: m.r * 2)),
                     with: .color(sceneColor(0xD8E8EE, a)))
        }
        for (i, g) in glows.enumerated() where !compact || i % 2 == 0 {
            let pulse: Double = t == 0 ? 0.35 : 0.15 + 0.35 * (0.5 + 0.5 * sin(t * g.speed + g.phase))
            let c = CGPoint(x: g.x * w, y: g.y * h)
            let color: Color = i % 2 == 0 ? sceneColor(0x7DF9E6) : sceneColor(0x9FD8FF)
            let gr: Double = g.r * 5
            let shade = GraphicsContext.Shading.radialGradient(Gradient(colors: [color.opacity(0.6 * pulse), color.opacity(0)]),
                                                               center: c, startRadius: 0, endRadius: gr)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)), with: shade)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - g.r, y: c.y - g.r, width: g.r * 2, height: g.r * 2)), with: .color(color.opacity(pulse)))
        }
        // クラゲは描かない（主役は住人の層のクジラかアンコウの1匹だけにする）
    }

    static func bob(_ t: Double, _ delay: Double) -> Double { t == 0 ? 0 : sin((t + delay) * 2 * .pi / 9) * 9 }

    /// クラゲ（傘と触手。淡く光る）
    @_optimize(none)
    static func drawJelly(_ ctx: GraphicsContext, at c: CGPoint, size: Double, tint: Color, t: Double) {
        let glow: Double = t == 0 ? 0.6 : 0.4 + 0.45 * (0.5 + 0.5 * sin(t * 2 * .pi / 5))
        let bell = CGRect(x: c.x - size / 2, y: c.y - size * 0.32, width: size, height: size * 0.64)
        var top = Path()
        top.addArc(center: CGPoint(x: bell.midX, y: bell.midY), radius: size / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        top.addQuadCurve(to: CGPoint(x: bell.minX, y: bell.midY), control: CGPoint(x: bell.midX, y: bell.midY + size * 0.14))
        let shade = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [tint.opacity(0.5 * glow), tint.opacity(0.12 * glow)]),
            center: CGPoint(x: bell.midX, y: bell.midY - size * 0.15), startRadius: 0, endRadius: size * 0.6)
        ctx.fill(top, with: shade)
        let halo = GraphicsContext.Shading.radialGradient(Gradient(colors: [tint.opacity(0.22 * glow), tint.opacity(0)]),
                                                          center: CGPoint(x: bell.midX, y: bell.midY), startRadius: 0, endRadius: size)
        ctx.fill(Path(ellipseIn: bell.insetBy(dx: -size * 0.5, dy: -size * 0.5)), with: halo)
        for i in 0..<4 {
            let x0: Double = bell.minX + size * (0.2 + 0.2 * Double(i))
            var tent = Path()
            tent.move(to: CGPoint(x: x0, y: bell.midY + 2))
            let sway: Double = sin(t * 1.2 + Double(i)) * 4
            tent.addCurve(to: CGPoint(x: x0 + sway, y: bell.midY + size * 1.3),
                          control1: CGPoint(x: x0 - 5, y: bell.midY + size * 0.4),
                          control2: CGPoint(x: x0 + 5 + sway, y: bell.midY + size * 0.9))
            ctx.stroke(tent, with: .color(tint.opacity(0.32 * glow)), lineWidth: 0.8)
        }
    }
}

/// 深海の全画面の背景
struct DeepSeaBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            let w: CGFloat = size.width
            let h: CGFloat = size.height
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            ZStack {
                LinearGradient(stops: DeepSeaScene.water, startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.14))
                ray(w: w, h: h, x: 0.62, width: 40, length: 0.5, alpha: 0.16)
                    .scenePulse(animated, low: 0.5, high: 1, duration: 14)
                ray(w: w, h: h, x: 0.34, width: 28, length: 0.42, alpha: 0.12)
                    .scenePulse(animated, low: 0.5, high: 1, duration: 14, delay: 6)
                SceneClock(fps: 15, animated: animated, stillT: stillT) { t in
                    Canvas { ctx, s in
                        DeepSeaScene.drawCaustics(ctx, size: s, t: t, compact: compact)
                        DeepSeaScene.drawLife(ctx, size: s, t: t, compact: compact)
                    }
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    /// 斜めの光の筋（上から差しこみ、下へ消える）
    private func ray(w: CGFloat, h: CGFloat, x: CGFloat, width: CGFloat, length: CGFloat, alpha: Double) -> some View {
        let g = LinearGradient(colors: [sceneColor(0xDCFFFF, alpha), sceneColor(0xDCFFFF, 0)], startPoint: .top, endPoint: .bottom)
        return Rectangle().fill(g)
            .frame(width: width, height: h * length)
            .rotationEffect(Angle.degrees(18), anchor: .top)
            .position(x: w * x, y: h * length / 2 - 30)
    }
}

/// 深海のカード：冷たく光るガラスの板
struct DeepSeaGlass: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let sheen = LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        let rim = LinearGradient(colors: [sceneColor(0xA0E6FF, 0.5), sceneColor(0x7DF9E6, 0.18)], startPoint: .top, endPoint: .bottom)
        ZStack {
            shape.fill(p.card.opacity(light ? 0.8 : 1))
            shape.fill(sheen)
            shape.strokeBorder(rim, lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0x7DF9E6, light ? 0.16 : 0.2), radius: light ? 5 : 12)
    }
}
