import SwiftUI

/// MARK: - 余白：生成りの和紙に細い線と広い余白。紙の奥に、筆で一度だけ描いた円相がうっすら残る
// 和紙（楮の長い繊維・雲のようなむら・小さな塵）と円相は動かないので、1枚の Canvas に一度だけ描く。
// 動くのは、障子越しの光のようなごく淡い明るさのむらだけ（低いフレームレート）。住人の層は「いま」まで墨の線が伸び、綿毛が漂う。完了で朱の印を押す。

enum YohakuScene {
    static let ink: UInt32 = 0x1A1A18
    static let hair: UInt32 = 0xD6D4CE
    static let shu: UInt32 = 0xB4461E

    /// 楮の繊維（位置は比。毎回同じ）。light は光を通して白く見える繊維
    struct Fiber { let x: Double; let y: Double; let len: Double; let angle: Double; let bend: Double; let width: Double; let alpha: Double; let light: Bool }

    static let fibers: [Fiber] = {
        var rnd = SceneRandom(53)
        var out: [Fiber] = []
        for i in 0..<72 {
            let light: Bool = i % 4 == 0
            let x: Double = rnd.next()
            let y: Double = rnd.next()
            let len: Double = rnd.range(14, 64)
            let angle: Double = rnd.range(-3.1, 3.1)
            let bend: Double = rnd.range(-0.5, 0.5)
            let width: Double = rnd.range(0.3, 0.7)
            let alpha: Double = light ? rnd.range(0.35, 0.6) : rnd.range(0.035, 0.08)
            out.append(Fiber(x: x, y: y, len: len, angle: angle, bend: bend, width: width, alpha: alpha, light: light))
        }
        return out
    }()

    /// 紙のむら（雲のように少し濃い・薄いところ）
    struct Cloud { let x: Double; let y: Double; let r: Double; let dark: Bool }

    static let clouds: [Cloud] = {
        var rnd = SceneRandom(211)
        var out: [Cloud] = []
        for i in 0..<7 {
            let x: Double = rnd.next()
            let y: Double = rnd.next()
            let r: Double = rnd.range(0.25, 0.5)
            out.append(Cloud(x: x, y: y, r: r, dark: i % 2 == 0))
        }
        return out
    }()

    /// 和紙（むら・繊維・塵）
    @_optimize(none)
    static func drawPaper(_ ctx: GraphicsContext, size: CGSize, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let rect = CGRect(origin: .zero, size: size)
        let paper = Gradient(colors: [sceneColor(0xFBF8F2), sceneColor(0xF4F1EA)])
        ctx.fill(Path(rect), with: .linearGradient(paper, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        // むら（ごく淡い。暗いほうは生成りの影、明るいほうは白）
        for c in clouds {
            let r: Double = c.r * max(w, h)
            let center = CGPoint(x: c.x * w, y: c.y * h)
            let color: Color = c.dark ? sceneColor(0xE6DFCF) : Color.white
            let a: Double = c.dark ? 0.28 : 0.4
            let stops: [Gradient.Stop] = [
                Gradient.Stop(color: color.opacity(a), location: 0),
                Gradient.Stop(color: color.opacity(a * 0.5), location: 0.45),
                Gradient.Stop(color: color.opacity(0), location: 1),
            ]
            let shade = GraphicsContext.Shading.radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: r)
            ctx.fill(Path(ellipseIn: CGRect(x: Double(center.x) - r, y: Double(center.y) - r, width: r * 2, height: r * 2)), with: shade)
        }
        // 楮の繊維（ゆるく曲がった長い線。白い繊維は光を通したように見える）
        let count: Int = compact ? 26 : fibers.count
        let scale: Double = compact ? 0.6 : 1
        var lightPath = Path()
        for f in fibers.prefix(count) {
            let x: Double = f.x * w
            let y: Double = f.y * h
            let len: Double = f.len * scale
            let ex: Double = x + cos(f.angle) * len
            let ey: Double = y + sin(f.angle) * len
            let mx: Double = (x + ex) / 2 - sin(f.angle) * len * f.bend * 0.4
            let my: Double = (y + ey) / 2 + cos(f.angle) * len * f.bend * 0.4
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addQuadCurve(to: CGPoint(x: ex, y: ey), control: CGPoint(x: mx, y: my))
            if f.light {
                lightPath.addPath(line)
            } else {
                ctx.stroke(line, with: .color(sceneColor(0x8E8775, f.alpha)), lineWidth: f.width)
            }
        }
        ctx.stroke(lightPath, with: .color(Color.white.opacity(0.55)), lineWidth: 0.9)
        // 小さな塵（漉き込まれた皮のかけら）
        var rnd = SceneRandom(97)
        let dots: Int = compact ? 10 : 30
        var specks = Path()
        for _ in 0..<dots {
            let x: Double = rnd.next() * w
            let y: Double = rnd.next() * h
            let r: Double = rnd.range(0.3, 0.8)
            specks.addEllipse(in: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4))
        }
        ctx.fill(specks, with: .color(sceneColor(0x6E6656, 0.12)))
    }

    /// 円相（筆で一度だけ描いた丸）。穂先の毛を1本ずつ描き、終わりに近いほど毛が墨切れして、かすれ（飛白）になる
    @_optimize(none)
    static func enso(_ ctx: GraphicsContext, center: CGPoint, radius: Double, start: Double, alpha: Double) {
        let cx: Double = Double(center.x)
        let cy: Double = Double(center.y)
        let sweep: Double = Double.pi * 1.84
        let maxHalf: Double = radius * 0.06
        let steps: Int = 120
        let bristles: Int = 22
        var rnd = SceneRandom(808)
        var body = Path()
        for j in 0..<bristles {
            let o: Double = Double(j) / Double(bristles - 1) * 2 - 1
            let jitter: Double = rnd.range(-0.04, 0.04)
            let freq: Double = rnd.range(18, 46)
            let phase: Double = rnd.range(0, 6.28)
            // 外側の毛ほど早く墨が切れる
            let dryStart: Double = 0.42 + 0.4 * (1 - abs(o)) * rnd.range(0.6, 1)
            let endF: Double = 1 - rnd.range(0, 0.18) * (0.4 + abs(o))
            var drawing: Bool = false
            for s in 0...steps {
                let f: Double = Double(s) / Double(steps)
                if f > endF { break }
                // 太さ：入りで押さえて太く、抜けで細くなる
                let press: Double = min(1, f / 0.06)
                let half: Double = maxHalf * (0.55 + 0.45 * press) * (1 - 0.55 * f)
                let wobble: Double = 0.022 * sin(f * 5.3 + 0.8) + 0.012 * sin(f * 12.1) - 0.035 * f
                let rr: Double = radius * (1 + wobble) + (o + jitter) * half
                let a: Double = start + sweep * f
                let pt = CGPoint(x: cx + cos(a) * rr, y: cy + sin(a) * rr)
                // かすれ：途中から毛がところどころ紙に触れなくなる
                let dry: Double = max(0, (f - dryStart) / max(0.05, 1 - dryStart))
                let noise: Double = 0.5 + 0.5 * sin(f * freq + phase) * cos(f * freq * 0.37 + phase * 1.7)
                let touch: Bool = noise > dry * 0.95
                if touch {
                    if drawing { body.addLine(to: pt) } else { body.move(to: pt) }
                    drawing = true
                } else {
                    drawing = false
                }
            }
        }
        let bristleW: Double = maxHalf * 2 / Double(bristles) * 1.9
        // 入りのにじみ（筆を置いたところに墨が少しだまる）
        let px: Double = cx + cos(start + 0.04) * radius
        let py: Double = cy + sin(start + 0.04) * radius
        CritterDraw.glow(ctx, px, py, maxHalf * 2.4, sceneColor(ink), alpha * 0.35)
        var brush: GraphicsContext = ctx
        brush.opacity = alpha
        brush.stroke(body, with: .color(sceneColor(ink)), style: StrokeStyle(lineWidth: bristleW, lineCap: .round, lineJoin: .round))
    }

    /// 円相の置き場所（右下。文字の行の裏をうっすら通る）
    @_optimize(none)
    static func ensoFrame(_ size: CGSize, compact: Bool) -> (center: CGPoint, radius: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        if compact {
            return (CGPoint(x: w * 0.8, y: h * 0.62), min(w, h) * 0.42)
        }
        return (CGPoint(x: w * 0.7, y: h * 0.64), min(w * 0.4, h * 0.24))
    }

    /// 動かない絵（和紙・円相・上の細い罫線）
    @_optimize(none)
    static func drawStill(_ ctx: GraphicsContext, size: CGSize, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        drawPaper(ctx, size: size, compact: compact)
        let f = ensoFrame(size, compact: compact)
        enso(ctx, center: f.center, radius: f.radius, start: 2.2, alpha: compact ? 0.07 : 0.1)
        let topY: Double = compact ? 6 : h * 0.065
        var top = Path()
        top.move(to: CGPoint(x: 24, y: topY))
        top.addLine(to: CGPoint(x: w - 24, y: topY))
        ctx.stroke(top, with: .color(sceneColor(hair, compact ? 0.6 : 0.85)), lineWidth: 0.5)
    }

    /// 障子越しの光（ごく淡い明るさのむらが、90秒ほどでゆっくり動く）
    @_optimize(none)
    static func drawLight(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let u: Double = t / 90 * 2 * Double.pi
        let cx: Double = w * (0.35 + 0.2 * sin(u))
        let cy: Double = h * (0.3 + 0.08 * cos(u * 0.7))
        let reach: Double = max(w, h)
        CritterDraw.glow(ctx, cx, cy, reach * 0.55, Color.white, 0.22)
        CritterDraw.glow(ctx, w - cx * 0.5, h * 0.9, reach * 0.5, sceneColor(0xE9E1CF), 0.12)
    }
}

/// 余白の全画面の背景
struct YohakuBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: geo.size, still: still)
            ZStack {
                Canvas { ctx, size in
                    YohakuScene.drawStill(ctx, size: size, compact: compact)
                }
                if !compact {
                    SceneClock(fps: 6, animated: animated, stillT: stillT) { t in
                        Canvas { ctx, size in
                            YohakuScene.drawLight(ctx, size: size, t: t)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// 余白のカード：白い紙を1枚置いたような面。髪の毛ほどの縁と、左上の短い墨の線
struct YohakuSheet: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let border: Color = sceneColor(0xE4E2DC)
        let mark: Color = sceneColor(YohakuScene.ink, 0.85)
        ZStack(alignment: .topLeading) {
            shape.fill(p.card)
            shape.strokeBorder(border, lineWidth: 0.6)
            if !light {
                Rectangle().fill(mark).frame(width: 18, height: 1)
                    .padding(.leading, 14)
            }
        }
        .shadow(color: sceneColor(0x4D473D, light ? 0.03 : 0.05), radius: light ? 2 : 10, x: 0, y: light ? 1 : 4)
    }
}

// MARK: - 住人：「いま」まで墨の線が伸び、綿毛が漂う。完了で朱の印を押す

extension CritterArt {
    @_optimize(none)
    static func yohaku(_ ctx: GraphicsContext, size: CGSize, k: CritterKnobs, layer: Layer) {
        let w: Double = Double(size.width)
        let lane: Double = laneY(size)
        let left: Double = 28
        let right: Double = w - 28
        let nowX: Double = left + (right - left) * max(0, min(1, k.day))
        switch layer {
        case .idle:
            // 一日の線（朝から「いま」まで墨が濃くなる）
            var rest = Path()
            rest.move(to: D.pt(left, lane))
            rest.addLine(to: D.pt(right, lane))
            ctx.stroke(rest, with: .color(sceneColor(0xE4E2DC)), lineWidth: 0.8)
            var done = Path()
            done.move(to: D.pt(left, lane))
            done.addLine(to: D.pt(nowX, lane))
            let g = Gradient(colors: [sceneColor(0xE2E0DA), sceneColor(0x8A877F), sceneColor(YohakuScene.ink)])
            ctx.stroke(done, with: .linearGradient(g, startPoint: D.pt(left, lane), endPoint: D.pt(nowX, lane)), lineWidth: 1)
            D.line(ctx, D.pt(nowX, lane - 5), D.pt(nowX, lane + 4), sceneColor(YohakuScene.ink, 0.9), 1)
            let label: Text = Text("いま").font(Font.system(size: 9, weight: .regular, design: .serif))
                .foregroundColor(sceneColor(0x5E5B55, 0.8))
            ctx.draw(label, at: D.pt(nowX, lane + 13), anchor: .center)
            // 綿毛（ゆっくり右へ漂う）
            let fx: Double = -20 + k.progress * (w + 40)
            let fy: Double = lane - 46 + sin(k.t * 0.3) * 6 + sin(k.progress * Double.pi * 2) * 6
            yohakuFluff(D.local(ctx, at: D.pt(fx, fy), scale: 1, angle: sin(k.t * 0.4) * 0.2))
        case .reaction:
            guard let r = k.react else { return }
            let sx: Double = w * 0.62
            let sy: Double = lane + 2
            let press: Double = D.ease(D.span(r, 0, 0.16))
            let scale: Double = 1.5 - 0.5 * press
            let alpha: Double = min(1, r * 7) * (1 - D.span(r, 0.72, 1))
            // にじむ輪
            let u: Double = D.span(r, 0.12, 0.7)
            if u > 0 && u < 1 {
                let rr: Double = 18 + u * 18
                let ring = CGRect(x: sx - rr, y: sy - rr, width: rr * 2, height: rr * 2)
                ctx.stroke(Path(ellipseIn: ring), with: .color(sceneColor(YohakuScene.shu, 0.35 * (1 - u))), lineWidth: 0.8)
            }
            var seal: GraphicsContext = D.local(ctx, at: D.pt(sx, sy), scale: scale, angle: -0.12)
            seal.opacity = alpha * (0.6 + 0.4 * press)
            let box = CGRect(x: -14, y: -14, width: 28, height: 28)
            seal.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(sceneColor(YohakuScene.shu, 0.92)))
            seal.stroke(Path(roundedRect: box.insetBy(dx: 2.2, dy: 2.2), cornerRadius: 2), with: .color(Color.white.opacity(0.55)), lineWidth: 0.7)
            let mark: Text = Text("済").font(Font.system(size: 16, weight: .bold, design: .serif)).foregroundColor(Color.white)
            seal.draw(mark, at: D.pt(0, 0.5), anchor: .center)
        }
    }

    /// 綿毛（細い放射状の毛と小さな種）
    static func yohakuFluff(_ c: GraphicsContext) {
        let color: Color = sceneColor(0x5E5B55, 0.5)
        for i in 0..<9 {
            let a: Double = -Double.pi + Double(i) / 8 * Double.pi
            let tip = D.pt(cos(a) * 7, sin(a) * 7)
            D.line(c, D.pt(0, 0), tip, color, 0.5)
            D.circle(c, tip.x, tip.y, 0.7, color)
        }
        D.line(c, D.pt(0, 0), D.pt(0, 6), color, 0.6)
        D.ellipse(c, 0, 7, 1.6, 3, sceneColor(0x4D473D, 0.6))
    }
}

/// ウィジェット：下の余白の細い線を、一日かけて「いま」まで墨が伸びる。先に朱の点
struct WidgetYohaku: View {
    let size: CGSize
    let k: CritterKnobs

    var body: some View {
        let w: CGFloat = size.width
        let y: CGFloat = CritterWidgetArt.laneY(size.height)
        let left: CGFloat = 12
        let span: CGFloat = max(1, w - 24)
        let day: CGFloat = CGFloat(max(0.02, min(1, k.day)))
        let nowX: CGFloat = left + span * day
        let inkW: CGFloat = max(1, nowX - left)
        let g = LinearGradient(colors: [sceneColor(0xE2E0DA), sceneColor(0x8A877F), sceneColor(YohakuScene.ink)],
                               startPoint: .leading, endPoint: .trailing)
        ZStack {
            Rectangle().fill(sceneColor(0xE4E2DC)).frame(width: span, height: 0.6).position(x: left + span / 2, y: y)
            Rectangle().fill(g).frame(width: inkW, height: 0.9).position(x: left + inkW / 2, y: y)
            Rectangle().fill(sceneColor(YohakuScene.ink, 0.85)).frame(width: 0.9, height: 7).position(x: nowX, y: y)
            Rectangle().fill(sceneColor(YohakuScene.shu, 0.9)).frame(width: 3, height: 3)
                .rotationEffect(Angle.degrees(45)).position(x: nowX, y: y - 5.5)
        }
    }
}
