import SwiftUI

// MARK: - 余白：生成りの紙に細い線と広い余白。遠くで円相がゆっくり回り、墨のしずくが静かに輪を広げる
// 飾りはどれもごく薄く、文字の裏で邪魔をしない。住人の層は「いま」まで墨の線が伸び、綿毛が漂う。完了で朱の印を押す。

enum YohakuScene {
    static let ink: UInt32 = 0x1A1A18
    static let hair: UInt32 = 0xD6D4CE
    static let shu: UInt32 = 0xB4461E

    /// 紙の繊維（位置は比。毎回同じ）
    struct Fiber { let x: Double; let y: Double; let len: Double; let angle: Double }

    static let fibers: [Fiber] = {
        var rnd = SceneRandom(53)
        var out: [Fiber] = []
        for _ in 0..<44 {
            out.append(Fiber(x: rnd.next(), y: rnd.next(), len: rnd.range(4, 11), angle: rnd.range(-0.5, 0.5)))
        }
        return out
    }()

    /// 円相（筆で描いた丸）。始まりは太く、終わりはかすれて細くなる
    static func enso(_ ctx: GraphicsContext, center: CGPoint, radius: Double, start: Double, alpha: Double) {
        let pieces: Int = 14
        let sweep: Double = Double.pi * 1.82
        for i in 0..<pieces {
            let f0: Double = Double(i) / Double(pieces)
            let f1: Double = Double(i + 1) / Double(pieces)
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: Angle.radians(start + sweep * f0),
                       endAngle: Angle.radians(start + sweep * f1 + 0.02), clockwise: false)
            let width: Double = 7 * (1 - f0 * 0.82)
            let a: Double = alpha * (1 - f0 * 0.6)
            ctx.stroke(arc, with: .color(sceneColor(ink, a)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let rect = CGRect(origin: .zero, size: size)
        let paper = Gradient(colors: [sceneColor(0xFBF8F2), sceneColor(0xF4F1EA)])
        ctx.fill(Path(rect), with: .linearGradient(paper, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        // 紙の繊維
        let fiberCount: Int = compact ? 16 : fibers.count
        for f in fibers.prefix(fiberCount) {
            let x: Double = f.x * w
            let y: Double = f.y * h
            let dx: Double = cos(f.angle) * f.len
            let dy: Double = sin(f.angle) * f.len
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x + dx, y: y + dy))
            ctx.stroke(line, with: .color(sceneColor(0x8A877F, 0.07)), lineWidth: 0.6)
        }
        // 遠くの円相（右下。ゆっくり回る）
        let r: Double = min(w, h) * (compact ? 0.42 : 0.36)
        let center = CGPoint(x: w * 0.74, y: h * (compact ? 0.62 : 0.58))
        enso(ctx, center: center, radius: r, start: -1.9 + t / 80, alpha: compact ? 0.045 : 0.05)
        // 墨のしずくの輪（14秒ごとにどこかで1つ）
        let cycle: Double = t / 14
        let index: Int = Int(cycle)
        let frac: Double = cycle - Double(index)
        var rnd = SceneRandom(UInt64(max(0, index)) &+ 7)
        let px: Double = w * rnd.range(0.12, 0.88)
        let py: Double = h * rnd.range(0.18, 0.78)
        for ring in 0..<2 {
            let u: Double = max(0, frac - Double(ring) * 0.18)
            guard u > 0 else { continue }
            let rr: Double = 6 + u * (compact ? 26 : 46)
            let a: Double = 0.11 * (1 - u)
            let ringRect = CGRect(x: px - rr, y: py - rr * 0.42, width: rr * 2, height: rr * 0.84)
            ctx.stroke(Path(ellipseIn: ringRect), with: .color(sceneColor(ink, a)), lineWidth: 0.7)
        }
        // 上の細い罫線と、右の縦の細い線
        let topY: Double = compact ? 6 : h * 0.065
        var top = Path()
        top.move(to: CGPoint(x: 24, y: topY))
        top.addLine(to: CGPoint(x: w - 24, y: topY))
        ctx.stroke(top, with: .color(sceneColor(hair, compact ? 0.6 : 0.9)), lineWidth: 0.5)
        if !compact {
            var side = Path()
            side.move(to: CGPoint(x: w - 12, y: h * 0.12))
            side.addLine(to: CGPoint(x: w - 12, y: h * 0.44))
            ctx.stroke(side, with: .color(sceneColor(hair, 0.7)), lineWidth: 0.5)
            let dot = CGRect(x: w - 14, y: h * 0.12 - 6, width: 4, height: 4)
            ctx.fill(Path(dot), with: .color(sceneColor(shu, 0.55)))
        }
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
            SceneClock(fps: 15, animated: animated, stillT: stillT) { t in
                Canvas { ctx, size in
                    YohakuScene.draw(ctx, size: size, t: t, compact: compact)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 余白のカード：白い紙を1枚置いたような面。髪の毛ほどの縁と、左上の短い墨の線
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
            let fy: Double = lane - 46 + sin(k.t * 0.45) * 10 + sin(k.progress * Double.pi * 2) * 8
            yohakuFluff(D.local(ctx, at: D.pt(fx, fy), scale: 1, angle: sin(k.t * 0.6) * 0.3))
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
