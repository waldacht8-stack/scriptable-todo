import SwiftUI

// MARK: - 地層：用事が下から積もる。上は明るい砂、下ほど古く濃い層。層の境目がゆっくり沈み、砂粒が降り積もる
// 文字は上〜86% の層（明るい）に載る前提で色を決めている。濃い層は下のタブバーの裏だけ。

enum StrataScene {
    /// 層（上の境目の高さの比・色）。上から順に重ねて塗る
    struct Band {
        let top: Double
        let color: Color
        let amp: Double       // 境目の波の高さ（pt）
        let wave: Double      // 波の長さ（幅に対する回数）
        let phase: Double
    }

    static let base: Color = sceneColor(0xF4EADB)

    static let bands: [Band] = [
        Band(top: 0.15, color: sceneColor(0xEEDFC6), amp: 5, wave: 1.3, phase: 0.3),
        Band(top: 0.33, color: sceneColor(0xE8D3AC), amp: 6, wave: 1.0, phase: 1.7),
        Band(top: 0.51, color: sceneColor(0xE1C79A), amp: 7, wave: 1.5, phase: 2.9),
        Band(top: 0.69, color: sceneColor(0xD9B985), amp: 7, wave: 0.9, phase: 4.1),
        Band(top: 0.865, color: sceneColor(0xC99A62), amp: 6, wave: 1.2, phase: 5.2),
        Band(top: 0.925, color: sceneColor(0x8E5F36), amp: 5, wave: 1.6, phase: 0.8),
        Band(top: 0.972, color: sceneColor(0x5E4129), amp: 4, wave: 1.1, phase: 2.2),
    ]

    /// 砂粒・小石（位置は比。毎回同じ）
    struct Grain { let x: Double; let y: Double; let r: Double; let light: Bool }

    static let grains: [Grain] = {
        var rnd = SceneRandom(31)
        var out: [Grain] = []
        for _ in 0..<44 {
            let y: Double = rnd.range(0.2, 1.0)
            out.append(Grain(x: rnd.next(), y: y, r: rnd.range(0.6, 2.2), light: rnd.next() > 0.55))
        }
        return out
    }()

    /// 降ってくる砂粒（上から沈んでいく）
    struct Dust { let x: Double; let speed: Double; let offset: Double; let r: Double }

    static let dust: [Dust] = {
        var rnd = SceneRandom(77)
        var out: [Dust] = []
        for _ in 0..<9 {
            out.append(Dust(x: rnd.next(), speed: rnd.range(0.008, 0.02), offset: rnd.next(), r: rnd.range(0.7, 1.6)))
        }
        return out
    }()

    /// 層の境目の波の高さ（x は 0〜1、t は秒）。settle が大きいほど沈んで平らになる
    static func edge(_ b: Band, x: Double, t: Double) -> Double {
        let slow: Double = t / 40
        let a: Double = sin(x * b.wave * 2 * .pi + b.phase + slow) * b.amp
        let c: Double = sin(x * b.wave * 5.3 * .pi + b.phase * 2 - slow * 1.6) * b.amp * 0.35
        let settle: Double = sin(t / 23 + b.phase) * 1.6
        return a + c + settle
    }

    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
        let steps: Int = compact ? 18 : 36
        for (i, b) in bands.enumerated() {
            var path = Path()
            let y0: Double = b.top * h
            path.move(to: CGPoint(x: 0, y: h))
            for s in 0...steps {
                let fx: Double = Double(s) / Double(steps)
                let y: Double = y0 + edge(b, x: fx, t: t)
                path.addLine(to: CGPoint(x: fx * w, y: y))
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            ctx.fill(path, with: .color(b.color))
            // 層の中の細い筋（堆積の縞）
            var line = Path()
            let ly: Double = y0 + (i < bands.count - 1 ? (bands[i + 1].top - b.top) * h * 0.55 : 10)
            for s in 0...steps {
                let fx: Double = Double(s) / Double(steps)
                let y: Double = ly + edge(b, x: fx + 0.2, t: t * 0.7) * 0.6
                if s == 0 { line.move(to: CGPoint(x: 0, y: y)) } else { line.addLine(to: CGPoint(x: fx * w, y: y)) }
            }
            let lineAlpha: Double = i >= 5 ? 0.18 : 0.09
            ctx.stroke(line, with: .color(sceneColor(0x3C1E0A, lineAlpha)), lineWidth: 1)
        }
        // いまの層の縁だけ、ほのかに火の色
        let ember: Band = bands[4]
        var glow = Path()
        for s in 0...steps {
            let fx: Double = Double(s) / Double(steps)
            let y: Double = ember.top * h + edge(ember, x: fx, t: t)
            if s == 0 { glow.move(to: CGPoint(x: 0, y: y)) } else { glow.addLine(to: CGPoint(x: fx * w, y: y)) }
        }
        ctx.stroke(glow, with: .color(sceneColor(0xFFB27A, 0.75)), lineWidth: 1.6)
        // 小石と砂粒
        let grainCount: Int = compact ? 26 : grains.count
        for g in grains.prefix(grainCount) {
            let r: Double = g.r
            let rect = CGRect(x: g.x * w - r * 1.4, y: g.y * h - r * 0.8, width: r * 2.8, height: r * 1.6)
            let c: Color = g.light ? Color.white.opacity(0.22) : sceneColor(0x5A3A1E, 0.16)
            ctx.fill(Path(ellipseIn: rect), with: .color(c))
        }
        // 上から沈んでいく砂粒（動くときだけ）
        guard t != 0 else { return }
        for d in dust {
            let cycle: Double = (t * d.speed + d.offset).truncatingRemainder(dividingBy: 1)
            let y: Double = cycle * h * 0.9
            let x: Double = d.x * w + sin(t / 5 + d.offset * 9) * 4
            let fade: Double = min(1, cycle * 6) * (1 - cycle)
            let rect = CGRect(x: x - d.r, y: y - d.r, width: d.r * 2, height: d.r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(sceneColor(0x7A5532, 0.45 * fade)))
        }
    }
}

/// 地層の全画面の背景
struct StrataBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: geo.size, still: still)
            SceneClock(fps: 10, animated: animated, stillT: stillT) { t in
                Canvas { ctx, size in
                    StrataScene.draw(ctx, size: size, t: t, compact: compact)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 地層のカード：堆積した板。上が明るく下へ少し濃くなり、細い縞と下の縁の層が見える
struct StrataSlab: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let fill = LinearGradient(colors: [sceneColor(0xFCF6EC), p.card, sceneColor(0xF1E3CC)],
                                  startPoint: .top, endPoint: .bottom)
        let rim = LinearGradient(colors: [Color.clear, sceneColor(0xC99A62, 0.0), sceneColor(0xC99A62, 0.38)],
                                 startPoint: .top, endPoint: .bottom)
        ZStack {
            shape.fill(fill)
            if !light {
                Canvas { ctx, size in
                    let w: Double = Double(size.width)
                    let h: Double = Double(size.height)
                    for i in 1...3 {
                        var line = Path()
                        let y0: Double = h * Double(i) / 4.2
                        for s in 0...12 {
                            let fx: Double = Double(s) / 12
                            let y: Double = y0 + sin(fx * 5.2 + Double(i) * 1.9) * 1.6
                            if s == 0 { line.move(to: CGPoint(x: 0, y: y)) } else { line.addLine(to: CGPoint(x: fx * w, y: y)) }
                        }
                        ctx.stroke(line, with: .color(sceneColor(0x8E5F36, 0.07)), lineWidth: 1)
                    }
                }
                .clipShape(shape)
            }
            shape.fill(rim)
            shape.strokeBorder(sceneColor(0xB98B58, 0.35), lineWidth: 1)
        }
        .shadow(color: sceneColor(0x5A3A1E, light ? 0.12 : 0.16), radius: light ? 3 : 8, x: 0, y: light ? 2 : 5)
    }
}
