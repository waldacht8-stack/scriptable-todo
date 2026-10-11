import SwiftUI

// MARK: - 霧：夜明けの湖と森。遠くの山と木立がかすみ、霧の層が違う速さで流れる。霧の向こうに暖かい朝の光
// 山・木立・湖は止まった絵（Canvas）、霧の層は repeatForever で左右に流し、光の筋はゆっくり明滅させる。

enum MistScene {
    static let sky: [Gradient.Stop] = [
        Gradient.Stop(color: sceneColor(0xA9B4BE), location: 0),
        Gradient.Stop(color: sceneColor(0xC4CBD0), location: 0.28),
        Gradient.Stop(color: sceneColor(0xD8D6CF), location: 0.44),
        Gradient.Stop(color: sceneColor(0xC6CDD1), location: 0.6),
        Gradient.Stop(color: sceneColor(0xAEB8C0), location: 1),
    ]

    /// 地平線の高さ（比）
    static let horizon: Double = 0.47

    /// 遠くの山・木立・湖・両脇の針葉樹（止まった絵）
    static func drawLand(_ ctx: GraphicsContext, size: CGSize, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let hy: Double = horizon * h
        // 遠くの山の稜線
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: hy))
        let steps: Int = 24
        for s in 0...steps {
            let fx: Double = Double(s) / Double(steps)
            let y: Double = hy - 30 - sin(fx * 3.1 + 0.6) * 16 - sin(fx * 7.3) * 6
            ridge.addLine(to: CGPoint(x: fx * w, y: y))
        }
        ridge.addLine(to: CGPoint(x: w, y: hy))
        ridge.closeSubpath()
        ctx.fill(ridge, with: .color(sceneColor(0xA3AEB7, 0.5)))
        // 木立（ぎざぎざ）
        var trees = Path()
        trees.move(to: CGPoint(x: 0, y: hy + 6))
        var rnd = SceneRandom(55)
        var x: Double = 0
        while x < w {
            let tw: Double = rnd.range(5, 11)
            let th: Double = rnd.range(8, 22)
            trees.addLine(to: CGPoint(x: x + tw / 2, y: hy - th + 4))
            trees.addLine(to: CGPoint(x: x + tw, y: hy + 2))
            x += tw
        }
        trees.addLine(to: CGPoint(x: w, y: hy + 6))
        trees.closeSubpath()
        ctx.fill(trees, with: .color(sceneColor(0x8794A0, 0.5)))
        // 湖
        let lake = CGRect(x: 0, y: hy + 4, width: w, height: h - hy - 4)
        let lakeShade = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [sceneColor(0xCBD1D4), sceneColor(0xA9B4BC)]),
            startPoint: CGPoint(x: 0, y: lake.minY), endPoint: CGPoint(x: 0, y: h))
        ctx.fill(Path(lake), with: lakeShade)
        // 朝の光の映り込み
        let refl = CGPoint(x: w * 0.7, y: hy + 20)
        let reflShade = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [sceneColor(0xFFDEBA, 0.55), sceneColor(0xFFDEBA, 0)]),
            center: refl, startRadius: 0, endRadius: w * 0.3)
        ctx.fill(Path(ellipseIn: CGRect(x: refl.x - w * 0.3, y: refl.y - 14, width: w * 0.6, height: 28)), with: reflShade)
        // 水面のきらめきの線
        let lines: Int = compact ? 3 : 6
        for i in 0..<lines {
            let y: Double = hy + 34 + Double(i) * (h - hy) * 0.11
            let inset: Double = Double(i % 3) * w * 0.06
            var l = Path()
            l.move(to: CGPoint(x: inset, y: y))
            l.addLine(to: CGPoint(x: w - inset * 1.4, y: y))
            ctx.stroke(l, with: .color(Color.white.opacity(0.2)), lineWidth: 1)
        }
        // 両脇の針葉樹（うすく。上に文字が載っても読めるように）
        drawConifer(ctx, baseX: w * 0.02, baseY: hy + 10, height: h * 0.2, width: w * 0.16)
        drawConifer(ctx, baseX: w * 0.95, baseY: hy + 14, height: h * 0.24, width: w * 0.18)
        if !compact {
            drawConifer(ctx, baseX: w * 0.88, baseY: hy + 8, height: h * 0.14, width: w * 0.12)
        }
    }

    static func drawConifer(_ ctx: GraphicsContext, baseX: Double, baseY: Double, height: Double, width: Double) {
        var p = Path()
        let tiers: Int = 4
        p.move(to: CGPoint(x: baseX, y: baseY - height))
        for i in 1...tiers {
            let k: Double = Double(i) / Double(tiers)
            p.addLine(to: CGPoint(x: baseX + width / 2 * k, y: baseY - height + height * k))
            if i < tiers { p.addLine(to: CGPoint(x: baseX + width / 4 * k, y: baseY - height + height * k)) }
        }
        for i in stride(from: tiers, through: 1, by: -1) {
            let k: Double = Double(i) / Double(tiers)
            if i < tiers { p.addLine(to: CGPoint(x: baseX - width / 4 * k, y: baseY - height + height * k)) }
            p.addLine(to: CGPoint(x: baseX - width / 2 * k, y: baseY - height + height * k))
        }
        p.closeSubpath()
        ctx.fill(p, with: .color(sceneColor(0x6F7C87, 0.42)))
    }
}

/// 霧の全画面の背景
struct MistBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            let w: CGFloat = size.width
            let h: CGFloat = size.height
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            ZStack {
                LinearGradient(stops: MistScene.sky, startPoint: .top, endPoint: .bottom)
                // 霧の向こうの朝日
                RadialGradient(colors: [sceneColor(0xFFE2BC, 0.8), sceneColor(0xFFD6AA, 0.28), sceneColor(0xFFD6AA, 0)],
                               center: UnitPoint(x: 0.72, y: 0.27), startRadius: 0, endRadius: w * 0.5)
                if !compact {
                    ray(w: w, h: h, y: 0.3, angle: 30, thick: 26, alpha: 0.42)
                        .scenePulse(animated, low: 0.35, high: 0.9, duration: 9)
                    ray(w: w, h: h, y: 0.34, angle: 17, thick: 18, alpha: 0.34)
                        .scenePulse(animated, low: 0.35, high: 0.9, duration: 9, delay: 3)
                }
                Canvas { ctx, s in
                    MistScene.drawLand(ctx, size: s, compact: compact)
                }
                fog(w: w, h: h, y: 0.37, height: 0.15, alpha: 0.82)
                    .sceneDrift(animated, distance: 50, duration: 60)
                fog(w: w, h: h, y: 0.5, height: 0.12, alpha: 0.78)
                    .sceneDrift(animated, distance: 46, duration: 38, reverse: true)
                fog(w: w, h: h, y: 0.66, height: 0.11, alpha: 0.6)
                    .sceneDrift(animated, distance: 56, duration: 22)
                if !compact {
                    fog(w: w, h: h, y: 0.86, height: 0.13, alpha: 0.55)
                        .sceneDrift(animated, distance: 40, duration: 30, reverse: true)
                    fog(w: w, h: h, y: 0.16, height: 0.12, alpha: 0.45)
                        .sceneDrift(animated, distance: 36, duration: 46, reverse: true)
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    /// 霧の帯（横に長い楕円。ふちはグラデーションで消える）
    private func fog(w: CGFloat, h: CGFloat, y: CGFloat, height: CGFloat, alpha: Double) -> some View {
        let c: Color = sceneColor(0xECEEEE, alpha)
        let g = RadialGradient(colors: [c, c.opacity(alpha * 0.5), c.opacity(0)], center: .center, startRadius: 0, endRadius: w * 0.95)
        return Ellipse().fill(g)
            .frame(width: w * 1.9, height: h * height)
            .position(x: w / 2, y: h * y)
    }

    /// 光の筋（朝日の方から斜めに）
    private func ray(w: CGFloat, h: CGFloat, y: CGFloat, angle: Double, thick: CGFloat, alpha: Double) -> some View {
        let g = LinearGradient(colors: [sceneColor(0xFFECD2, alpha), sceneColor(0xFFECD2, 0)], startPoint: .trailing, endPoint: .leading)
        return Rectangle().fill(g)
            .frame(width: w * 0.9, height: thick)
            .rotationEffect(Angle.degrees(angle), anchor: .trailing)
            .position(x: w * 0.27, y: h * y)
    }
}

/// 霧のカード：すりガラスのように白くかすむ板
struct MistCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let frost = LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
        ZStack {
            if light {
                shape.fill(p.card.opacity(0.82))
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(p.card.opacity(0.8))
            }
            shape.fill(frost)
            shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: sceneColor(0x28374A, light ? 0.1 : 0.14), radius: light ? 4 : 14, x: 0, y: light ? 2 : 8)
    }
}
