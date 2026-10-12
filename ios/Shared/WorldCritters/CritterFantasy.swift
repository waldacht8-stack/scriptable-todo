import SwiftUI

// MARK: - 幻想的な世界観の住人（銀河の宇宙飛行士・霧の鹿と灯り・深海のクジラとチョウチンアンコウ・オーロラの狐）
// 輪郭は点の列をなめらかな曲線（Catmull-Rom）でつないだ Path で描き、グラデーション・やわらかい光・縁の光で立体と空気感を出す。
// ぼかしは使わない（光は放射状のグラデーション）。型推論が重くならないよう、式は型つきの let に分け、最適化を外す。

enum Fantasy {
    typealias D = CritterDraw

    // MARK: 道具

    @_optimize(none)
    static func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    /// 点の列をなめらかにつなぐ（closed なら閉じる）
    @_optimize(none)
    static func smooth(_ pts: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        let n: Int = pts.count
        guard n > 2 else { return path }
        path.move(to: pts[0])
        let segs: Int = closed ? n : n - 1
        for i in 0..<segs {
            let i0: Int = closed ? (i - 1 + n) % n : max(i - 1, 0)
            let i2: Int = closed ? (i + 1) % n : i + 1
            let i3: Int = closed ? (i + 2) % n : min(i + 2, n - 1)
            let p0: CGPoint = pts[i0]
            let p1: CGPoint = pts[i]
            let p2: CGPoint = pts[i2]
            let p3: CGPoint = pts[i3]
            let c1x: Double = Double(p1.x) + Double(p2.x - p0.x) / 6
            let c1y: Double = Double(p1.y) + Double(p2.y - p0.y) / 6
            let c2x: Double = Double(p2.x) - Double(p3.x - p1.x) / 6
            let c2y: Double = Double(p2.y) - Double(p3.y - p1.y) / 6
            path.addCurve(to: p2, control1: P(c1x, c1y), control2: P(c2x, c2y))
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// 点を c のまわりに a ラジアン回す
    @_optimize(none)
    static func rot(_ p: CGPoint, about c: CGPoint, by a: Double) -> CGPoint {
        let dx: Double = Double(p.x - c.x)
        let dy: Double = Double(p.y - c.y)
        let ca: Double = cos(a)
        let sa: Double = sin(a)
        let x: Double = Double(c.x) + dx * ca - dy * sa
        let y: Double = Double(c.y) + dx * sa + dy * ca
        return P(x, y)
    }

    @_optimize(none)
    static func rotAll(_ pts: [CGPoint], about c: CGPoint, by a: Double) -> [CGPoint] {
        pts.map { (p: CGPoint) -> CGPoint in rot(p, about: c, by: a) }
    }

    @_optimize(none)
    static func shift(_ pts: [CGPoint], _ dx: Double, _ dy: Double) -> [CGPoint] {
        pts.map { (p: CGPoint) -> CGPoint in P(Double(p.x) + dx, Double(p.y) + dy) }
    }

    @_optimize(none)
    static func seg(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    @_optimize(none)
    static func line3(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: c)
        return p
    }

    @_optimize(none)
    static func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        p.addLine(to: c)
        p.closeSubpath()
        return p
    }

    @_optimize(none)
    static func stroke(_ c: GraphicsContext, _ path: Path, _ color: Color, _ width: Double) {
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// 上から下へのグラデーションで塗る
    @_optimize(none)
    static func vfill(_ c: GraphicsContext, _ path: Path, _ colors: [Color], _ y0: Double, _ y1: Double) {
        let g = Gradient(colors: colors)
        c.fill(path, with: .linearGradient(g, startPoint: P(0, y0), endPoint: P(0, y1)))
    }

    /// 横長のやわらかい光（楕円の放射グラデーション）
    @_optimize(none)
    static func softEllipse(_ c: GraphicsContext, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ color: Color, _ alpha: Double) {
        guard rx > 0.1 && ry > 0.1 else { return }
        var e: GraphicsContext = c
        e.translateBy(x: cx, y: cy)
        e.scaleBy(x: rx / ry, y: 1)
        D.glow(e, 0, 0, ry, color, alpha)
    }

    /// 2つの節（肩→ひじ→手、腰→ひざ→足）。角度は真下から（正は +x の向き）
    struct Joint { let a: CGPoint; let b: CGPoint; let c: CGPoint }

    @_optimize(none)
    static func joint(_ base: CGPoint, _ a1: Double, _ l1: Double, _ a2: Double, _ l2: Double) -> Joint {
        let bx: Double = Double(base.x)
        let by: Double = Double(base.y)
        let jx: Double = bx + sin(a1) * l1
        let jy: Double = by + cos(a1) * l1
        let fx: Double = jx + sin(a2) * l2
        let fy: Double = jy + cos(a2) * l2
        return Joint(a: base, b: P(jx, jy), c: P(fx, fy))
    }

    /// 管のような手足（地の色の太い線＋光の側の細い線）
    @_optimize(none)
    static func tube(_ c: GraphicsContext, _ j: Joint, _ width: Double, _ base: Color, _ light: Color, _ dx: Double, _ dy: Double) {
        let path: Path = line3(j.a, j.b, j.c)
        stroke(c, path, base, width)
        stroke(c, path.offsetBy(dx: dx, dy: dy), light, width * 0.32)
    }

    /// 先が細くなる脚（上の節は太く、下の節は細い）
    @_optimize(none)
    static func leg(_ c: GraphicsContext, _ j: Joint, _ w1: Double, _ w2: Double, _ upper: Color, _ lower: Color) {
        stroke(c, seg(j.a, j.b), upper, w1)
        stroke(c, seg(j.b, j.c), lower, w2)
    }

    /// a→b に直角な向き（長さ 1）
    @_optimize(none)
    static func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let dx: Double = Double(b.x - a.x)
        let dy: Double = Double(b.y - a.y)
        let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
        return P(-dy / len, dx / len)
    }

    @_optimize(none)
    static func quad(_ a: CGPoint, _ n1: CGPoint, _ w1: Double, _ b: CGPoint, _ n2: CGPoint, _ w2: Double) -> Path {
        let ax: Double = Double(a.x)
        let ay: Double = Double(a.y)
        let bx: Double = Double(b.x)
        let by: Double = Double(b.y)
        let h1x: Double = Double(n1.x) * w1 / 2
        let h1y: Double = Double(n1.y) * w1 / 2
        let h2x: Double = Double(n2.x) * w2 / 2
        let h2y: Double = Double(n2.y) * w2 / 2
        var p = Path()
        p.move(to: P(ax + h1x, ay + h1y))
        p.addLine(to: P(bx + h2x, by + h2y))
        p.addLine(to: P(bx - h2x, by - h2y))
        p.addLine(to: P(ax - h1x, ay - h1y))
        p.closeSubpath()
        return p
    }

    /// 付け根が太く先が細い脚（塗りの台形を2つ。ひざは丸くつなぐ）
    @_optimize(none)
    static func taperLeg(_ c: GraphicsContext, _ j: Joint, _ wTop: Double, _ wKnee: Double, _ wFoot: Double,
                         _ upper: Color, _ lower: Color) {
        let n1: CGPoint = normal(j.a, j.b)
        let n2: CGPoint = normal(j.b, j.c)
        c.fill(quad(j.a, n1, wTop, j.b, n1, wKnee), with: .color(upper))
        D.circle(c, Double(j.a.x), Double(j.a.y), wTop / 2, upper)
        c.fill(quad(j.b, n2, wKnee, j.c, n2, wFoot), with: .color(lower))
        D.circle(c, Double(j.b.x), Double(j.b.y), wKnee / 2, lower)
    }

    /// 霧やもやの帯：やわらかい楕円のかたまりを横に並べ、t とともに流す（speed は 1秒あたりの pt。負なら左へ）
    @_optimize(none)
    static func fogBank(_ c: GraphicsContext, width w: Double, y: Double, height: Double, t: Double, speed: Double,
                        seed: UInt64, count: Int, color: Color, alpha: Double) {
        var rnd = SceneRandom(seed)
        let pad: Double = height * 2.2
        let span: Double = w + pad * 2
        for _ in 0..<count {
            let fx: Double = rnd.next()
            let fy: Double = rnd.range(-0.35, 0.35)
            let rx: Double = height * rnd.range(1.2, 2.2)
            let ry: Double = height * rnd.range(0.38, 0.6)
            let a: Double = alpha * rnd.range(0.55, 1)
            let raw: Double = fx * span + t * speed
            let wrapped: Double = raw.truncatingRemainder(dividingBy: span)
            let x: Double = (wrapped < 0 ? wrapped + span : wrapped) - pad
            let cy: Double = y + fy * height
            softEllipse(c, x, cy, rx, ry, color, a)
        }
    }

    /// 0〜1 の中の a〜b で、ふわっと上がって下がる山（外は 0）
    @_optimize(none)
    static func bump(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let k: Double = D.span(u, a, b)
        guard k > 0 && k < 1 else { return 0 }
        return sin(k * Double.pi)
    }

    // MARK: 銀河：宇宙飛行士（原点はおなか。高さ 50 くらい。光は左上の星雲から、縁の光は右下の桃色）

    @_optimize(none)
    static func astronaut(_ c: GraphicsContext, t: Double, halo: Bool = true) {
        let suit: Color = sceneColor(0xE6E7F5)
        let suitShade: Color = sceneColor(0xB4B8DA)
        let hi: Color = Color.white.opacity(0.9)
        if halo {
            D.glow(c, 0, -6, 46, sceneColor(0x9C86FF), 0.16)
        }
        // 背中の生命維持装置（左に少しのぞく）
        let pack = Path(roundedRect: CGRect(x: -13, y: -13.5, width: 19, height: 23), cornerRadius: 4.5)
        vfill(c, pack, [sceneColor(0xD3D6EE), sceneColor(0x7D82AD)], -13.5, 9.5)
        let packEdge = Path(roundedRect: CGRect(x: -11.6, y: -10.5, width: 3.6, height: 15), cornerRadius: 1.5)
        stroke(c, packEdge, sceneColor(0x6D7299, 0.55), 0.7)
        // 脚（ゆっくりぶらぶら。ひざを少し曲げる）
        let sway: Double = sin(t * 0.7)
        let legL: Joint = joint(P(-3.6, 6.5), 0.22 + sway * 0.1, 7.6, -0.3 + sway * 0.16, 7.4)
        let legR: Joint = joint(P(3.6, 6.5), -0.18 - sway * 0.08, 7.6, 0.42 - sway * 0.14, 7.2)
        tube(c, legR, 6.4, suitShade, Color.white.opacity(0.45), -1.3, -0.3)
        tube(c, legL, 6.6, suit, hi, -1.4, -0.3)
        boot(c, legR.c, sceneColor(0x7F84AE))
        boot(c, legL.c, sceneColor(0x8D92BA))
        // 胴
        let torso = Path(roundedRect: CGRect(x: -8.6, y: -10.5, width: 17.2, height: 18.5), cornerRadius: 6.5)
        let torsoG = Gradient(colors: [Color.white, suit, suitShade])
        c.fill(torso, with: .linearGradient(torsoG, startPoint: P(-7, -10), endPoint: P(8, 8)))
        let rimG = Gradient(colors: [sceneColor(0xFF9AD5, 0), sceneColor(0xFF9AD5, 0.7)])
        c.stroke(torso, with: .linearGradient(rimG, startPoint: P(0, -2), endPoint: P(9, 8)), lineWidth: 0.9)
        // 胸の操作盤と小さなランプ
        let panel = Path(roundedRect: CGRect(x: -5, y: -5, width: 10, height: 6.4), cornerRadius: 1.6)
        c.fill(panel, with: .color(sceneColor(0x4C517E)))
        let blink: Double = 0.5 + 0.5 * sin(t * 3.1)
        D.circle(c, -2.8, -1.8, 0.95, sceneColor(0xFF6B8A, 0.45 + 0.55 * blink))
        D.circle(c, 0, -1.8, 0.95, sceneColor(0x7DF9C0))
        D.circle(c, 2.8, -1.8, 0.95, sceneColor(0xFFD27A, 1 - 0.5 * blink))
        stroke(c, seg(P(-7.6, 5), P(7.6, 5)), sceneColor(0x8A8FB8, 0.7), 1.1)
        // 腕（左は下ろしてふわり、右は手をふる）
        let wave: Double = sin(t * 1.3)
        let armL: Joint = joint(P(-7.6, -6.5), -0.62 - wave * 0.06, 7, -0.2, 6.4)
        let armR: Joint = joint(P(7.6, -6.5), 2.05 + wave * 0.08, 6.8, 2.75 + wave * 0.32, 6)
        tube(c, armL, 5.4, suit, hi, -1.1, -0.6)
        tube(c, armR, 5.2, suit, hi, -1.1, -0.6)
        glove(c, armL.c)
        glove(c, armR.c)
        // 首の輪とヘルメット
        D.ellipse(c, 0, -11.2, 14.5, 4.6, sceneColor(0xB3B7D8))
        helmet(c, t: t, blink: blink)
    }

    @_optimize(none)
    static func boot(_ c: GraphicsContext, _ at: CGPoint, _ color: Color) {
        let x: Double = Double(at.x)
        let y: Double = Double(at.y)
        D.ellipse(c, x, y + 0.8, 7.6, 5.2, color)
        D.ellipse(c, x - 1, y - 0.2, 3.2, 1.6, Color.white.opacity(0.35))
    }

    @_optimize(none)
    static func glove(_ c: GraphicsContext, _ at: CGPoint) {
        let x: Double = Double(at.x)
        let y: Double = Double(at.y)
        D.circle(c, x, y, 2.8, sceneColor(0xC2C6E2))
        D.circle(c, x - 0.8, y - 0.8, 0.9, Color.white.opacity(0.7))
    }

    @_optimize(none)
    static func helmet(_ c: GraphicsContext, t: Double, blink: Double) {
        let hr: Double = 11
        let cy: Double = -20.5
        let shell = Path(ellipseIn: CGRect(x: -hr, y: cy - hr, width: hr * 2, height: hr * 2))
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: Color.white, location: 0),
            Gradient.Stop(color: sceneColor(0xE4E6F4), location: 0.5),
            Gradient.Stop(color: sceneColor(0x9EA3CA), location: 1),
        ]
        c.fill(shell, with: .radialGradient(Gradient(stops: stops), center: P(-3.8, cy - 4.5), startRadius: 0, endRadius: hr * 1.55))
        let rimG = Gradient(colors: [sceneColor(0xFF9AD5, 0), sceneColor(0xFF9AD5, 0.9)])
        c.stroke(shell, with: .linearGradient(rimG, startPoint: P(-4, cy - 6), endPoint: P(8, cy + 8)), lineWidth: 1.3)
        // バイザー
        let visorRect = CGRect(x: -7, y: cy - 6, width: 15.6, height: 11.8)
        let visor = Path(roundedRect: visorRect, cornerSize: CGSize(width: 6.6, height: 5.6), style: .continuous)
        vfill(c, visor, [sceneColor(0x353A78), sceneColor(0x15173C), sceneColor(0x0A0B22)], cy - 6, cy + 6)
        var vc: GraphicsContext = c
        vc.clip(to: visor)
        // 星雲の映り込み（下の方に桃・紫・水色の帯）
        var band = Path()
        band.move(to: P(-9, cy + 2.8))
        band.addQuadCurve(to: P(10, cy - 0.5), control: P(1, cy - 3.2))
        band.addLine(to: P(10, cy + 7))
        band.addLine(to: P(-9, cy + 7))
        band.closeSubpath()
        let neb = Gradient(colors: [sceneColor(0xFF7EC8, 0.6), sceneColor(0x8A6BFF, 0.5), sceneColor(0x6EE7FF, 0.5)])
        vc.fill(band, with: .linearGradient(neb, startPoint: P(-8, cy + 4), endPoint: P(9, cy + 1)))
        D.circle(vc, -3.4, cy - 1.6, 0.5, Color.white.opacity(0.85))
        D.circle(vc, 3.8, cy - 3.2, 0.42, Color.white.opacity(0.7))
        D.circle(vc, 5.6, cy + 0.2, 0.55, Color.white.opacity(0.8))
        // きらめき：7秒ごとに光の帯がバイザーを横切る
        let sweep: Double = (t / 7).truncatingRemainder(dividingBy: 1)
        let sweepK: Double = D.span(sweep, 0, 0.35)
        if sweepK > 0 && sweepK < 1 {
            let gx: Double = -10 + sweepK * 26
            let glintAlpha: Double = 0.42 * sin(sweepK * Double.pi)
            var glint = Path()
            glint.move(to: P(gx, cy - 7))
            glint.addLine(to: P(gx + 3.4, cy - 7))
            glint.addLine(to: P(gx - 1.6, cy + 7))
            glint.addLine(to: P(gx - 5, cy + 7))
            glint.closeSubpath()
            vc.fill(glint, with: .color(Color.white.opacity(glintAlpha)))
        }
        // いつものつや
        var arc = Path()
        arc.move(to: P(-5.6, cy + 0.5))
        arc.addQuadCurve(to: P(-1.5, cy - 4.8), control: P(-5.6, cy - 4.4))
        stroke(c, arc, Color.white.opacity(0.7), 1.2)
        D.circle(c, 2.6, cy - 4, 0.8, Color.white.opacity(0.9))
        c.stroke(visor, with: .color(sceneColor(0x8C91BD)), lineWidth: 0.9)
        // ヘルメットのランプ
        D.glow(c, -8.6, cy - 6.4, 5.5, sceneColor(0xFFE6A8), 0.35 + 0.4 * blink)
        D.circle(c, -8.6, cy - 6.4, 1.1, sceneColor(0xFFF2CF))
    }

    // MARK: 霧：鹿（左向き。足元が原点。肩の高さ 39・角の先まで 78 くらい）

    struct DeerPose {
        /// 歩きの位相（ラジアン）
        var walk: Double
        /// 頭を下げる 0〜1
        var headDown: Double
        /// 耳のぴくっ 0〜1
        var ear: Double
        /// しっぽのぴくっ 0〜1
        var tail: Double
        /// 白い息 0〜1（nil は出さない）
        var breath: Double?
        /// 灯りの向き（-1 = 左から、1 = 右から）と強さ
        var lightSide: Double
        var light: Double
    }

    static let deerTorso: [CGPoint] = [
        P(-17, -31), P(-14, -37), P(-6, -39.5), P(6, -38.5), P(16, -39), P(23, -36.5), P(25.5, -31),
        P(23.5, -25.5), P(17, -22), P(6, -21.5), P(-6, -22.5), P(-14, -24.5),
    ]

    static let deerNeck: [CGPoint] = [
        P(-15.5, -27.5), P(-20, -36), P(-23.5, -44), P(-26, -48.5), P(-31, -48.8), P(-35.5, -50), P(-37.2, -52.4),
        P(-35, -54.8), P(-29.5, -56.6), P(-25, -58), P(-21.5, -56.6), P(-17.5, -49), P(-12, -40), P(-8, -36),
    ]

    static let deerEar: [CGPoint] = [P(-23.6, -56.2), P(-20.4, -61.8), P(-15.6, -63.6), P(-19.4, -55.4)]

    static let deerBeam: [CGPoint] = [P(-24.6, -58), P(-25.6, -64), P(-23.2, -70.5), P(-18.2, -75), P(-13, -77)]
    static let deerTine1: [CGPoint] = [P(-25.2, -63), P(-29.6, -67.6), P(-31.2, -72)]
    static let deerTine2: [CGPoint] = [P(-22.4, -71.5), P(-23.4, -76.5), P(-23, -80)]
    static let deerTine3: [CGPoint] = [P(-17.6, -75.2), P(-16.8, -77.6), P(-16.4, -80)]

    @_optimize(none)
    static func deer(_ c: GraphicsContext, pose: DeerPose, near: Color, far: Color, belly: Color, rim: Color) {
        let bob: Double = sin(pose.walk * 2) * 0.5
        let pivot: CGPoint = P(-13, -33)
        let headA: Double = -pose.headDown * 1.15 + sin(pose.walk * 2 + 0.6) * 0.02
        let earA: Double = -pose.ear * 0.45
        let earPivot: CGPoint = P(-22, -56)
        // 歩き：後ろ近・前近・後ろ遠・前遠の順に 1/4 ずつずれる
        let legsFar: [(CGPoint, Double, Bool)] = [(P(20.5, -27.5), Double.pi, false), (P(-9.5, -26.5), Double.pi * 1.5, true)]
        let legsNear: [(CGPoint, Double, Bool)] = [(P(18, -27), 0, false), (P(-12.5, -26), Double.pi * 0.5, true)]
        for item in legsFar {
            let j: Joint = deerLeg(item.0, phase: pose.walk + item.1, front: item.2, bob: bob)
            taperLeg(c, j, item.2 ? 5.4 : 8, 2.6, 1.8, far, far)
            D.ellipse(c, Double(j.c.x), Double(j.c.y) - 0.6, 2.6, 1.6, far)
        }
        // 遠い側の角と耳
        let farBeam: [CGPoint] = shift(rotAll(deerBeam, about: pivot, by: headA), 2.8, 0.6 + bob)
        stroke(c, smooth(farBeam, closed: false), far, 1.5)
        // 首と頭
        let neckPts: [CGPoint] = shift(rotAll(deerNeck, about: pivot, by: headA), 0, bob)
        let neck: Path = smooth(neckPts, closed: true)
        vfill(c, neck, [near, belly], -60, -26)
        // 胴
        let torsoPts: [CGPoint] = shift(deerTorso, 0, bob)
        let torso: Path = smooth(torsoPts, closed: true)
        vfill(c, torso, [near, belly], -40, -21)
        // おしりの白い毛としっぽ
        softEllipse(c, 23.4, -31 + bob, 2.6, 4.2, sceneColor(0xE4DED2), 0.45)
        let tailA: Double = -pose.tail * 0.9
        let tailPts: [CGPoint] = shift(rotAll([P(23.5, -36.5), P(28.4, -35.2), P(27.4, -31), P(24.6, -32)], about: P(24, -35), by: tailA), 0, bob)
        c.fill(smooth(tailPts, closed: true), with: .color(near))
        // 灯りの縁の光（灯りのある側だけ）
        let side: Double = pose.lightSide
        let rimStart: CGPoint = P(side < 0 ? -38 : 27, -50)
        let rimEnd: CGPoint = P(side < 0 ? -2 : -8, -30)
        let rimG = Gradient(colors: [rim.opacity(0.8 * pose.light), rim.opacity(0)])
        let rimShade = GraphicsContext.Shading.linearGradient(rimG, startPoint: rimStart, endPoint: rimEnd)
        var outside: GraphicsContext = c
        outside.clip(to: torso, options: .inverse)
        outside.stroke(neck, with: rimShade, lineWidth: 1.1)
        c.stroke(torso, with: rimShade, lineWidth: 1.1)
        // 近い側の脚（付け根はおなかの色に溶けこむ）
        for item in legsNear {
            let j: Joint = deerLeg(item.0, phase: pose.walk + item.1, front: item.2, bob: bob)
            taperLeg(c, j, item.2 ? 6 : 9, 2.9, 2, belly, belly)
            D.ellipse(c, Double(j.c.x), Double(j.c.y) - 0.6, 2.8, 1.7, sceneColor(0x22292F, 0.9))
        }
        // 耳（ぴくっと動く）と近い側の角
        let farEar: [CGPoint] = shift(rotAll(rotAll(deerEar, about: earPivot, by: earA * 0.6), about: pivot, by: headA), 2, 0.4 + bob)
        c.fill(smooth(farEar, closed: true), with: .color(far))
        let ear: [CGPoint] = shift(rotAll(rotAll(deerEar, about: earPivot, by: earA), about: pivot, by: headA), 0, bob)
        c.fill(smooth(ear, closed: true), with: .color(near))
        let antlers: [[CGPoint]] = [deerBeam, deerTine1, deerTine2, deerTine3]
        for (i, a) in antlers.enumerated() {
            let pts: [CGPoint] = shift(rotAll(a, about: pivot, by: headA), 0, bob)
            stroke(c, smooth(pts, closed: false), near, i == 0 ? 1.9 : 1.3)
        }
        // 目と鼻
        let eye: CGPoint = rot(P(-30.2, -53.4), about: pivot, by: headA)
        let nose: CGPoint = rot(P(-36.4, -52.6), about: pivot, by: headA)
        D.circle(c, Double(eye.x), Double(eye.y) + bob, 0.95, sceneColor(0x161B20))
        D.circle(c, Double(eye.x) - 0.3, Double(eye.y) - 0.3 + bob, 0.35, Color.white.opacity(0.4 + 0.4 * pose.light))
        D.circle(c, Double(nose.x), Double(nose.y) + bob, 1.1, sceneColor(0x161B20, 0.9))
        // 冷たい朝の白い息
        if let b = pose.breath {
            breath(c, from: P(Double(nose.x) - 0.5, Double(nose.y) + 0.6 + bob), u: b, dir: -1)
        }
    }

    /// 鹿の1本の脚（phase で振る。前脚はひざを後ろへ、後ろ脚はかかとを前へたたむ）
    @_optimize(none)
    static func deerLeg(_ hip: CGPoint, phase: Double, front: Bool, bob: Double) -> Joint {
        let swing: Double = -0.3 * sin(phase)
        let lift: Double = max(0, cos(phase))
        let base: CGPoint = P(Double(hip.x), Double(hip.y) + bob)
        if front {
            let a2: Double = swing + 0.95 * lift
            return joint(base, swing, 12.5, a2, 14 - lift * 0.5)
        }
        let a1: Double = 0.24 + swing
        let a2: Double = -0.06 + swing * 0.6 - 0.55 * lift
        return joint(base, a1, 12, a2, 14.5 - lift * 0.5)
    }

    /// 白い息（u は 0〜1 の進み。dir は吐く向き -1 = 左）
    @_optimize(none)
    static func breath(_ c: GraphicsContext, from p: CGPoint, u: Double, dir: Double) {
        let px: Double = Double(p.x)
        let py: Double = Double(p.y)
        for i in 0..<3 {
            let ui: Double = u - Double(i) * 0.14
            guard ui > 0 && ui < 1 else { continue }
            let x: Double = px + dir * (ui * 10 + Double(i) * 1.2)
            let y: Double = py + ui * 1.4 - ui * ui * 3.2
            let r: Double = 1.6 + ui * 4.6
            D.glow(c, x, y, r, sceneColor(0xF4F7F8), 0.5 * (1 - ui) * (1 - ui))
        }
    }

    // MARK: 霧：吊るし灯籠（原点は柱の根もと。height は柱の高さ。灯りの中心を返す）

    @_optimize(none)
    static func lanternLamp(height H: Double, swing: Double) -> CGPoint {
        let hx: Double = 12.5
        let hy: Double = -H
        let lx: Double = hx - sin(swing) * 10.5
        let ly: Double = hy + cos(swing) * 10.5
        return P(lx, ly)
    }

    @_optimize(none)
    static func lantern(_ c: GraphicsContext, height H: Double, swing: Double, flicker: Double, t: Double, halo: Bool = true) {
        let iron: Color = sceneColor(0x2B333B, 0.9)
        let warm: Color = sceneColor(0xFFC27A)
        let lamp: CGPoint = lanternLamp(height: H, swing: swing)
        let lx: Double = Double(lamp.x)
        let ly: Double = Double(lamp.y)
        let bright: Double = 0.82 + 0.18 * flicker
        if halo {
            // 霧の中にひろがる光（奥）と地面の光だまり
            D.glow(c, lx, ly, 78, warm, 0.26 * bright)
            softEllipse(c, lx - 2, 0, 50, 9, warm, 0.34 * bright)
            // 光の円すい（霧に差しこむ）
            var cone = Path()
            cone.move(to: P(lx - 3.5, ly + 6))
            cone.addLine(to: P(lx + 3.5, ly + 6))
            cone.addLine(to: P(lx + 26, 0))
            cone.addLine(to: P(lx - 30, 0))
            cone.closeSubpath()
            vfill(c, cone, [warm.opacity(0.22 * bright), warm.opacity(0)], ly + 6, 2)
        }
        // 柱と曲がった腕
        stroke(c, seg(P(0, 0), P(0, -H * 0.55)), iron, 2.6)
        stroke(c, seg(P(0, -H * 0.55), P(0, -H)), iron, 2)
        let crook: [CGPoint] = [P(0, -H), P(1.6, -H - 5), P(7, -H - 7.4), P(11.6, -H - 5), P(12.5, -H - 1)]
        stroke(c, smooth(crook, closed: false), iron, 1.6)
        stroke(c, seg(P(0.9, -H * 0.2), P(0.9, -H)), warm.opacity(0.35 * bright), 0.6)
        D.ellipse(c, 0, 0.4, 7, 2.4, iron)
        // 吊り下げた灯り（振り子のように揺れる）
        var lc: GraphicsContext = c
        lc.translateBy(x: 12.5, y: -H)
        lc.rotate(by: Angle.radians(-swing))
        stroke(lc, seg(P(0, 0), P(0, 4)), iron, 0.8)
        let roof: Path = smooth([P(-5.6, 7), P(-2.2, 4), P(2.2, 4), P(5.6, 7)], closed: true)
        lc.fill(roof, with: .color(iron))
        D.circle(lc, 0, 3.6, 1, iron)
        let glass = Path(roundedRect: CGRect(x: -4.2, y: 7, width: 8.4, height: 9.4), cornerRadius: 1.8)
        let gStops: [Gradient.Stop] = [
            Gradient.Stop(color: sceneColor(0xFFF6DC), location: 0),
            Gradient.Stop(color: sceneColor(0xFFC56E), location: 0.55),
            Gradient.Stop(color: sceneColor(0xD27E34), location: 1),
        ]
        lc.fill(glass, with: .radialGradient(Gradient(stops: gStops), center: P(0, 11.8), startRadius: 0, endRadius: 7))
        // 炎（ゆらぐ）
        let tip: Double = 8.6 - flicker * 0.9
        var flame = Path()
        flame.move(to: P(0, tip))
        flame.addQuadCurve(to: P(1.3, 12.2), control: P(1.7, 10))
        flame.addQuadCurve(to: P(-1.3, 12.2), control: P(0, 13.6))
        flame.addQuadCurve(to: P(0, tip), control: P(-1.7, 10))
        flame.closeSubpath()
        lc.fill(flame, with: .color(Color.white.opacity(0.92)))
        // 枠
        for x in [-4.2, 0.0, 4.2] {
            stroke(lc, seg(P(x, 7), P(x, 16.4)), iron.opacity(x == 0 ? 0.45 : 0.9), x == 0 ? 0.5 : 0.8)
        }
        let foot: Path = smooth([P(-4.8, 16.2), P(4.8, 16.2), P(3, 17.8), P(-3, 17.8)], closed: true)
        lc.fill(foot, with: .color(iron))
        guard halo else { return }
        // 手前の熱い光
        D.glow(c, lx, ly + 1.5, 17, sceneColor(0xFFD9A0), 0.55 * bright)
        // 灯りのまわりを舞う小さな虫・火の粉
        for i in 0..<1 {
            let fi: Double = Double(i)
            let mx: Double = lx + cos(t * (1.3 + fi * 0.4) + fi * 2.1) * (9 + fi * 3)
            let my: Double = ly - 2 + sin(t * (1.9 + fi * 0.3) + fi) * (5 + fi)
            D.circle(c, mx, my, 0.65, sceneColor(0xFFE7BC, 0.75))
        }
    }

    // MARK: 深海：クジラ（左向き。長さ L。原点はからだの真ん中。t で尾びれ・胸びれが動き、haze で水の色にかすむ）

    static let whaleS: [Double] = [0, 0.03, 0.08, 0.16, 0.26, 0.38, 0.5, 0.62, 0.72, 0.8, 0.87, 0.93, 1.0]
    static let whaleTop: [Double] = [0.012, 0.046, 0.074, 0.096, 0.106, 0.104, 0.092, 0.073, 0.054, 0.038, 0.026, 0.019, 0.016]
    static let whaleBot: [Double] = [0.02, 0.062, 0.094, 0.116, 0.123, 0.114, 0.095, 0.069, 0.047, 0.031, 0.021, 0.016, 0.014]

    struct WhaleFrame {
        let L: Double
        let beat: Double
        func x(_ s: Double) -> Double { -L / 2 + s * 0.86 * L }
        func y(_ s: Double) -> Double {
            let k: Double = max(0, s - 0.4)
            return beat * 0.06 * L * k * k / 0.36 - beat * 0.008 * L * (1 - s)
        }
        var tailAngle: Double { beat * 0.24 }
    }

    @_optimize(none)
    static func whale(_ c: GraphicsContext, t: Double, length L: Double, haze: Double, finSweep: Double = 0) {
        let beat: Double = sin(t * 0.85)
        let f = WhaleFrame(L: L, beat: beat)
        let n: Int = whaleS.count
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for i in 0..<n {
            let s: Double = whaleS[i]
            let x: Double = f.x(s)
            let y: Double = f.y(s)
            top.append(P(x, y - whaleTop[i] * L))
            bottom.append(P(x, y + whaleBot[i] * L))
        }
        let nose: CGPoint = P(f.x(0) - 0.012 * L, f.y(0) + 0.004 * L)
        var outline: [CGPoint] = [nose]
        outline.append(contentsOf: top)
        outline.append(contentsOf: bottom.reversed())
        let body: Path = smooth(outline, closed: true)
        let back: Color = sceneColor(0x12344F)
        let mid: Color = sceneColor(0x225878)
        let bellyC: Color = sceneColor(0x86B4C6)
        let water: Color = sceneColor(0x0A3556)
        // 遠い側の胸びれ（からだの後ろ）
        let finBase: CGPoint = P(f.x(0.27), f.y(0.27) + 0.07 * L)
        let finA: Double = 0.86 - finSweep + 0.18 * sin(t * 0.7 + 0.6)
        pectoral(c, at: P(Double(finBase.x) + 0.03 * L, Double(finBase.y) - 0.02 * L), angle: finA + 0.28, length: 0.19 * L,
                 colors: [sceneColor(0x2A5672), sceneColor(0x143149)])
        // 尾びれ
        let tailEnd: CGPoint = P(f.x(1), f.y(1))
        fluke(c, at: tailEnd, angle: f.tailAngle * 1.7, size: 0.16 * L, flex: beat, colors: [back, mid])
        // からだ（上は濃く、おなかは明るい）
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: back, location: 0),
            Gradient.Stop(color: mid, location: 0.48),
            Gradient.Stop(color: bellyC, location: 0.86),
            Gradient.Stop(color: sceneColor(0xA6CDDA), location: 1),
        ]
        c.fill(body, with: .linearGradient(Gradient(stops: stops), startPoint: P(0, -0.11 * L), endPoint: P(0, 0.125 * L)))
        var bc: GraphicsContext = c
        bc.clip(to: body)
        // おなかのうね（のどの溝）
        for i in 0..<5 {
            let fi: Double = Double(i)
            let s0: Double = 0.03 + fi * 0.012
            let s1: Double = 0.34 - fi * 0.025
            let off: Double = 0.05 + fi * 0.014
            var g = Path()
            g.move(to: P(f.x(s0), f.y(s0) + off * L))
            g.addQuadCurve(to: P(f.x(s1), f.y(s1) + (off + 0.012) * L), control: P(f.x((s0 + s1) / 2), f.y(0.2) + (off + 0.03) * L))
            bc.stroke(g, with: .color(sceneColor(0x2F5F7A, 0.45)), lineWidth: 0.7)
        }
        // 上から差す光（背中のつやと、ゆれる光の斑）
        let sheen = Gradient(colors: [sceneColor(0xCFF3FF, 0.32), sceneColor(0xCFF3FF, 0)])
        bc.fill(body, with: .linearGradient(sheen, startPoint: P(0, -0.11 * L), endPoint: P(0, -0.04 * L)))
        for i in 0..<5 {
            let fi: Double = Double(i)
            let s: Double = 0.12 + fi * 0.15 + 0.03 * sin(t * 0.6 + fi * 1.7)
            let dx: Double = f.x(min(0.95, s))
            let dy: Double = f.y(min(0.95, s)) - 0.075 * L
            let a: Double = 0.1 + 0.08 * sin(t * 1.1 + fi * 2.3)
            softEllipse(bc, dx, dy, 0.05 * L, 0.014 * L, sceneColor(0xDDF8FF), a)
        }
        // 水の色にかすむ（遠い）
        if haze > 0 {
            bc.fill(body, with: .color(water.opacity(haze)))
        }
        // 口・目・小さなこぶ
        var mouth = Path()
        mouth.move(to: P(f.x(0.01), f.y(0.01) + 0.012 * L))
        mouth.addQuadCurve(to: P(f.x(0.21), f.y(0.21) + 0.036 * L), control: P(f.x(0.1), f.y(0.1) + 0.05 * L))
        stroke(c, mouth, sceneColor(0x0C2236, 0.55 * (1 - haze * 0.6)), 0.8)
        let ex: Double = f.x(0.19)
        let ey: Double = f.y(0.19) + 0.018 * L
        D.ellipse(c, ex, ey, 0.016 * L, 0.011 * L, sceneColor(0x081626, 1 - haze * 0.5))
        D.circle(c, ex - 0.003 * L, ey - 0.003 * L, 0.0028 * L, Color.white.opacity(0.7 * (1 - haze)))
        for i in 0..<4 {
            let fi: Double = Double(i)
            let s: Double = 0.03 + fi * 0.03
            D.circle(c, f.x(s), f.y(s) - (0.03 + fi * 0.012) * L, 0.004 * L, sceneColor(0xA9CBD8, 0.35 * (1 - haze)))
        }
        // 背びれ
        let dS: Double = 0.7
        let dTop: Double = f.y(dS) - 0.05 * L
        let dorsal: Path = smooth([P(f.x(dS - 0.04), dTop + 0.006 * L), P(f.x(dS + 0.03), dTop - 0.024 * L),
                                   P(f.x(dS + 0.05), dTop - 0.02 * L), P(f.x(dS + 0.06), dTop + 0.008 * L)], closed: true)
        c.fill(dorsal, with: .color(back))
        if haze > 0 { c.fill(dorsal, with: .color(water.opacity(haze))) }
        // 近い側の胸びれ（長い。ゆっくりあおぐ）
        pectoral(c, at: finBase, angle: finA, length: 0.23 * L,
                 colors: [sceneColor(0x86B0C2), sceneColor(0x2C5F7E)])
        if haze > 0 {
            var hc: GraphicsContext = c
            hc.opacity = haze
            pectoral(hc, at: finBase, angle: finA, length: 0.23 * L, colors: [water, water])
        }
    }

    /// 胸びれ（at が付け根。angle は +x からの向き）
    @_optimize(none)
    static func pectoral(_ c: GraphicsContext, at base: CGPoint, angle: Double, length F: Double, colors: [Color]) {
        let w: Double = F * 0.1
        let pts: [CGPoint] = [P(0, -w), P(0.35 * F, -w * 1.2), P(0.8 * F, -w * 0.55), P(F, w * 0.2), P(0.75 * F, w * 0.9),
                              P(0.3 * F, w * 1.25), P(0, w)]
        var fc: GraphicsContext = c
        fc.translateBy(x: base.x, y: base.y)
        fc.rotate(by: Angle.radians(angle))
        let fin: Path = smooth(pts, closed: true)
        fc.fill(fin, with: .linearGradient(Gradient(colors: colors), startPoint: P(0, -w), endPoint: P(0, w * 1.2)))
        var edge = Path()
        edge.move(to: P(0.05 * F, -w * 1.05))
        edge.addQuadCurve(to: P(0.92 * F, -w * 0.1), control: P(0.55 * F, -w * 1.2))
        fc.stroke(edge, with: .color(Color.white.opacity(0.22)), lineWidth: 0.7)
    }

    /// 尾びれ（at が付け根。angle は傾き。flex で上下の葉がしなる）
    @_optimize(none)
    static func fluke(_ c: GraphicsContext, at base: CGPoint, angle: Double, size F: Double, flex: Double, colors: [Color]) {
        let up: Double = 1 + 0.16 * flex
        let dn: Double = 1 - 0.16 * flex
        let pts: [CGPoint] = [
            P(-0.04 * F, -0.09 * F), P(0.32 * F, -0.4 * F * up), P(0.66 * F, -0.8 * F * up), P(0.52 * F, -0.28 * F * up),
            P(0.44 * F, 0), P(0.52 * F, 0.28 * F * dn), P(0.66 * F, 0.8 * F * dn), P(0.32 * F, 0.4 * F * dn), P(-0.04 * F, 0.09 * F),
        ]
        var fc: GraphicsContext = c
        fc.translateBy(x: base.x, y: base.y)
        fc.rotate(by: Angle.radians(angle))
        let tail: Path = smooth(pts, closed: true)
        fc.fill(tail, with: .linearGradient(Gradient(colors: colors), startPoint: P(0, -0.8 * F), endPoint: P(0, 0.8 * F)))
    }

    // MARK: 深海：チョウチンアンコウ（右向き。長さ 42 くらい。原点はからだ。glow は提灯の明るさ 0〜1）

    static let anglerBody: [CGPoint] = [
        P(13, -4), P(9, -10), P(2, -13.5), P(-6, -12), P(-12, -7.5), P(-17, -3), P(-17, 2.5), P(-11, 7.5),
        P(-2, 11), P(8, 10.5), P(15.5, 5.5), P(12.5, 2.4), P(6, 0.6), P(11, -1.6),
    ]

    @_optimize(none)
    static func angler(_ c: GraphicsContext, t: Double, glow: Double) {
        let skin: Color = sceneColor(0x1B3648)
        let dark: Color = sceneColor(0x0A1823)
        let lure: Color = sceneColor(0x7DF9E6)
        let bob: Double = sin(t * 1.3) * 1.2
        let esca: CGPoint = P(19 + sin(t * 0.9) * 1.5, -21 + bob)
        let ex: Double = Double(esca.x)
        let ey: Double = Double(esca.y)
        // 提灯の大きな光（奥）
        D.glow(c, ex, ey, 34, lure, 0.18 + glow * 0.22)
        // 尾びれと口の中
        let tail: Path = smooth([P(-16, -2.4), P(-25, -9.5), P(-23, 0), P(-25, 9.5), P(-16, 2.4)], closed: true)
        c.fill(tail, with: .color(dark))
        for y in [-5.5, 0.0, 5.5] {
            stroke(c, seg(P(-17, y * 0.3), P(-23.5, y)), skin.opacity(0.8), 0.5)
        }
        let mouthIn: Path = smooth([P(13, -4), P(11, -1.6), P(6, 0.6), P(12.5, 2.4), P(15.5, 5.5)], closed: true)
        c.fill(mouthIn, with: .color(sceneColor(0x04080D)))
        // からだ
        let body: Path = smooth(anglerBody, closed: true)
        vfill(c, body, [skin, dark], -13, 11)
        var bc: GraphicsContext = c
        bc.clip(to: body)
        let lit = Gradient(colors: [lure.opacity(0.55 * glow + 0.2), lure.opacity(0)])
        bc.fill(body, with: .radialGradient(lit, center: esca, startRadius: 0, endRadius: 30))
        var rnd = SceneRandom(31)
        for _ in 0..<9 {
            let x: Double = rnd.range(-14, 8)
            let y: Double = rnd.range(-10, 8)
            D.circle(bc, x, y, rnd.range(0.35, 0.7), sceneColor(0x7FB2C6, 0.25))
        }
        c.stroke(body, with: .color(sceneColor(0x3C7A96, 0.55)), lineWidth: 0.6)
        // 歯（上あごは下向き、下あごは上向き）
        let upper: [(Double, Double)] = [(12.2, -3.2), (10.4, -2.4), (8.6, -1.4)]
        for (x, y) in upper {
            c.fill(tri(P(x - 0.6, y), P(x + 0.6, y), P(x, y + 2.2)), with: .color(Color.white.opacity(0.85)))
        }
        let lower: [(Double, Double)] = [(14.4, 4.4), (12.4, 2.8), (10.2, 2.0), (8.2, 1.4)]
        for (x, y) in lower {
            c.fill(tri(P(x - 0.6, y), P(x + 0.6, y), P(x, y - 2.4)), with: .color(Color.white.opacity(0.85)))
        }
        // 胸びれ・背のとげ
        let fan: Path = smooth([P(-2, 3.4), P(-8.4, 7.4 + bob * 0.4), P(-6.6, 10.4), P(-1.5, 6.8)], closed: true)
        c.fill(fan, with: .color(skin.opacity(0.9)))
        stroke(c, seg(P(-4, -12.6), P(-7.2, -17.4)), skin, 0.8)
        stroke(c, seg(P(-8.2, -10.6), P(-11.4, -14.4)), skin, 0.7)
        // 目（提灯の光が映る）
        D.circle(c, 6.4, -6.4, 2.3, sceneColor(0xBFE9F0, 0.85))
        D.circle(c, 6.8, -6.4, 1.4, sceneColor(0x050B10))
        D.circle(c, 7.4, -7, 0.5, lure.opacity(0.6 + 0.4 * glow))
        // 竿と提灯
        var rod = Path()
        rod.move(to: P(3, -13.4))
        rod.addQuadCurve(to: esca, control: P(6.5, -29 + bob * 0.5))
        stroke(c, rod, sceneColor(0x2C5A72), 0.9)
        D.glow(c, ex, ey, 11, lure, 0.45 + glow * 0.4)
        D.circle(c, ex, ey, 2.4, sceneColor(0xBFFFF4, 0.95))
        D.circle(c, ex - 0.6, ey - 0.6, 0.9, Color.white)
    }

    // MARK: オーロラ：狐（右向き。足元が原点）

    static let foxRunBody: [CGPoint] = [
        P(15, -15.5), P(9, -21.5), P(-4, -20.5), P(-14, -20.5), P(-18.5, -16.5), P(-15, -12), P(-6, -12.8), P(4, -11),
        P(12, -10.6),
    ]
    static let foxRunHead: [CGPoint] = [
        P(10, -21), P(16.5, -25), P(21, -24.4), P(26.4, -21.2), P(29.4, -19.6), P(24.6, -17), P(18.6, -15.4), P(13.4, -14),
    ]

    /// 走る狐（run はかけ足の位相。長さ 60 くらい）
    @_optimize(none)
    static func foxRun(_ c: GraphicsContext, run: Double, rim: Color) {
        let fur: Color = sceneColor(0xFF9752)
        let furDark: Color = sceneColor(0xC85A26)
        let sock: Color = sceneColor(0x3B2216)
        let stretch: Double = cos(run) * 0.06
        let bob: Double = -abs(sin(run)) * 1.6
        // 足：前2本・後ろ2本が対になって伸び縮み
        let legs: [(CGPoint, Double, Bool, Bool)] = [
            (P(-12, -15), Double.pi + 0.5, false, false), (P(9, -15), 0.5, true, false),
            (P(-14, -15), Double.pi, false, true), (P(11, -15), 0, true, true),
        ]
        for item in legs {
            let ph: Double = run + item.1
            let a1: Double = (item.2 ? 0.55 : -0.55) * sin(ph) * (1 + stretch * 4)
            let bend: Double = item.2 ? -0.9 * max(0, -cos(ph)) : 0.8 * max(0, cos(ph))
            let base: CGPoint = P(Double(item.0.x) * (1 + stretch), Double(item.0.y) + bob)
            let j: Joint = joint(base, a1, 7.6, a1 + bend, 8)
            let nearLeg: Bool = item.3
            let top: Double = item.2 ? 5.6 : 7.4
            taperLeg(c, j, nearLeg ? top : top * 0.9, 2.6, 2, nearLeg ? fur : furDark, nearLeg ? sock : sceneColor(0x2A1810))
        }
        // しっぽ（ふさふさ。先は白）
        let sw: Double = sin(run * 0.5) * 2
        let tailPts: [CGPoint] = [P(-15, -19.5 + bob), P(-25, -24 + sw), P(-36, -23 + sw * 1.4), P(-41, -20 + sw * 1.6),
                                  P(-35, -16.4 + sw), P(-25, -14.6 + sw * 0.5), P(-16, -14.6 + bob)]
        let tail: Path = smooth(tailPts, closed: true)
        vfill(c, tail, [fur, furDark], -25, -14)
        var tc: GraphicsContext = c
        tc.clip(to: tail)
        D.ellipse(tc, -40 + 0, -19.8 + sw * 1.5, 11, 9, Color.white.opacity(0.95))
        // 胴と頭
        let bodyPts: [CGPoint] = foxRunBody.map { (p: CGPoint) -> CGPoint in P(Double(p.x) * (1 + stretch), Double(p.y) + bob) }
        let body: Path = smooth(bodyPts, closed: true)
        vfill(c, body, [fur, furDark], -22, -11)
        let headPts: [CGPoint] = shift(foxRunHead, stretch * 12, bob)
        let head: Path = smooth(headPts, closed: true)
        vfill(c, head, [fur, furDark], -25, -15)
        // 白いあごと胸
        let chin: Path = smooth(shift([P(27, -18.6), P(19, -15.6), P(13.6, -14.4), P(15.6, -17.4), P(22, -18.8)], stretch * 12, bob), closed: true)
        c.fill(chin, with: .color(Color.white.opacity(0.9)))
        // 耳
        let hx: Double = stretch * 12
        let earFar: Path = smooth(shift([P(14.8, -24), P(15.6, -31.5), P(19.2, -24.8)], hx + 1.6, bob), closed: true)
        c.fill(earFar, with: .color(furDark))
        let ear: Path = smooth(shift([P(15.4, -24), P(16.2, -32.6), P(20.4, -24.6)], hx, bob), closed: true)
        c.fill(ear, with: .color(fur))
        c.fill(smooth(shift([P(16.4, -25), P(16.8, -30), P(19, -25.2)], hx, bob), closed: true), with: .color(sock.opacity(0.8)))
        // 鼻と目
        D.circle(c, 29.2 + hx, -19.8 + bob, 1.1, sceneColor(0x1A100C))
        D.ellipse(c, 21.6 + hx, -21.4 + bob, 2, 1.2, sceneColor(0x1A100C))
        D.circle(c, 21.2 + hx, -21.8 + bob, 0.35, Color.white.opacity(0.8))
        // オーロラの縁の光（背中側）
        let rimG = Gradient(colors: [rim.opacity(0.75), rim.opacity(0)])
        let rimS = GraphicsContext.Shading.linearGradient(rimG, startPoint: P(0, -26), endPoint: P(0, -17))
        c.stroke(body, with: rimS, lineWidth: 1)
        var outside: GraphicsContext = c
        outside.clip(to: body, options: .inverse)
        outside.stroke(head, with: rimS, lineWidth: 1)
        outside.stroke(tail, with: rimS, lineWidth: 1)
    }

    static let foxSitBody: [CGPoint] = [
        P(10.5, 0), P(8.6, -8), P(7.6, -16), P(3.4, -22), P(-2.6, -20.6), P(-7, -14.5), P(-12.4, -6.5), P(-12.8, 0),
    ]
    static let foxSitHead: [CGPoint] = [
        P(-0.6, -24.6), P(2, -29), P(8, -29.8), P(13, -28), P(15.4, -26.4), P(10.4, -23.6), P(5, -21.6),
    ]

    /// 座ってオーロラを見上げる狐（高さ 34 くらい。look で頭を上げる、tail でしっぽの先が揺れる）
    @_optimize(none)
    static func foxSit(_ c: GraphicsContext, look: Double, tail: Double, ear: Double, puff: Double?, rim: Color) {
        let fur: Color = sceneColor(0xFF9752)
        let furDark: Color = sceneColor(0xC85A26)
        let sock: Color = sceneColor(0x3B2216)
        let pivot: CGPoint = P(3, -22)
        let headA: Double = -0.18 - look * 0.22
        // しっぽ（前に巻く）
        let tw: Double = tail * 1.6
        let tailPts: [CGPoint] = [P(-11.6, -4.6), P(-16.4, -1.4), P(-12.4, 2.8), P(0, 3.2), P(9.6, 2 + tw * 0.3),
                                  P(13.4, -0.4 + tw), P(9.6, -1.4 + tw * 0.4), P(-1, -0.6)]
        // 後ろの前脚
        stroke(c, seg(P(9.4, -9), P(10.6, -0.8)), sock.opacity(0.85), 2.2)
        let body: Path = smooth(foxSitBody, closed: true)
        vfill(c, body, [fur, furDark], -22, 0)
        softEllipse(c, 7.2, -13, 2.6, 5.4, Color.white, 0.85)
        // 手前の前脚
        stroke(c, seg(P(6.6, -9.4), P(7.4, -0.8)), fur, 2.8)
        stroke(c, seg(P(7.3, -4.4), P(7.6, -0.6)), sock, 2.6)
        let tailPath: Path = smooth(tailPts, closed: true)
        vfill(c, tailPath, [fur, furDark], -5, 3)
        var tc: GraphicsContext = c
        tc.clip(to: tailPath)
        D.ellipse(tc, 12.4, -0.2 + tw * 0.6, 8, 6, Color.white.opacity(0.95))
        // 頭と耳
        let head: Path = smooth(rotAll(foxSitHead, about: pivot, by: headA), closed: true)
        let earA: Double = -ear * 0.35
        let earFarPts: [CGPoint] = rotAll([P(4.6, -28.6), P(7.4, -35.4), P(8.8, -28.6)], about: pivot, by: headA)
        c.fill(smooth(earFarPts, closed: true), with: .color(furDark))
        vfill(c, head, [fur, furDark], -30, -21)
        let earPts: [CGPoint] = rotAll(rotAll([P(1.2, -27.6), P(1.6, -35.6), P(5.6, -28.8)], about: P(3, -28), by: earA), about: pivot, by: headA)
        c.fill(smooth(earPts, closed: true), with: .color(fur))
        let cheek: [CGPoint] = rotAll([P(13.6, -25.6), P(8, -22.8), P(4.6, -21.8), P(6.6, -24.6)], about: pivot, by: headA)
        c.fill(smooth(cheek, closed: true), with: .color(Color.white.opacity(0.9)))
        let nose: CGPoint = rot(P(15.2, -26.6), about: pivot, by: headA)
        let eye: CGPoint = rot(P(8.6, -27), about: pivot, by: headA)
        D.circle(c, Double(nose.x), Double(nose.y), 1, sceneColor(0x1A100C))
        D.ellipse(c, Double(eye.x), Double(eye.y), 1.9, 1.1, sceneColor(0x1A100C))
        D.circle(c, Double(eye.x) + 0.3, Double(eye.y) - 0.3, 0.32, Color.white.opacity(0.85))
        // オーロラの縁の光
        let rimG = Gradient(colors: [rim.opacity(0.8), rim.opacity(0)])
        let rimS = GraphicsContext.Shading.linearGradient(rimG, startPoint: P(-6, -32), endPoint: P(4, -12))
        var outside: GraphicsContext = c
        outside.clip(to: head, options: .inverse)
        outside.stroke(body, with: rimS, lineWidth: 1)
        c.stroke(head, with: rimS, lineWidth: 1)
        if let b = puff {
            breath(c, from: P(Double(nose.x) + 0.6, Double(nose.y) + 0.4), u: b, dir: 1)
        }
    }
}

// MARK: - 銀河：ロケット（右向き。原点は胴の真ん中。長さ 44 くらい。boost 0〜1 で炎が明るく長くなる）

extension Fantasy {
    static let rocketBody: [CGPoint] = [
        P(22, 0), P(14, -5.2), P(2, -7), P(-12, -6.6), P(-16, -5.6), P(-16, 5.6), P(-12, 6.6), P(2, 7), P(14, 5.2),
    ]

    @_optimize(none)
    static func rocket(_ c: GraphicsContext, t: Double, boost: Double, halo: Bool = true) {
        let flicker: Double = 0.5 + 0.25 * sin(t * 23) + 0.25 * sin(t * 37 + 1.3)
        let plumeLen: Double = 14 + 6 * flicker + boost * 22
        rocketExhaust(c, t: t, boost: boost)
        rocketPlume(c, length: plumeLen, flicker: flicker, boost: boost, halo: halo)
        // 尾の翼（上下）と真ん中の翼
        let finColor: Color = sceneColor(0xB8475C)
        let finShade: Color = sceneColor(0x7E2E44)
        let topFin: Path = smooth([P(-6, -6.4), P(-15, -12.5), P(-19, -12), P(-16, -5.4)], closed: true)
        let botFin: Path = smooth([P(-6, 6.4), P(-15, 12.5), P(-19, 12), P(-16, 5.4)], closed: true)
        vfill(c, topFin, [finColor, finShade], -12.5, -5.4)
        vfill(c, botFin, [finShade, sceneColor(0x5A2032)], 5.4, 12.5)
        // ノズル
        let nozzle: Path = tri(P(-16, -3.8), P(-20.5, -4.8), P(-20.5, 4.8))
        c.fill(nozzle, with: .color(sceneColor(0x3E4260)))
        c.fill(tri(P(-16, -3.8), P(-20.5, 4.8), P(-16, 3.8)), with: .color(sceneColor(0x2E3150)))
        // 胴（上が明るく下が暗い。上のふちに星雲の桃色の光）
        let body: Path = smooth(rocketBody, closed: true)
        let hull = Gradient(stops: [
            Gradient.Stop(color: sceneColor(0xF2F2FA), location: 0),
            Gradient.Stop(color: sceneColor(0xC4C7DE), location: 0.55),
            Gradient.Stop(color: sceneColor(0x6F7399), location: 1),
        ])
        c.fill(body, with: .linearGradient(hull, startPoint: P(0, -7), endPoint: P(0, 7)))
        var bc: GraphicsContext = c
        bc.clip(to: body)
        // 先の赤い円すいと、胴の帯
        let cone = Gradient(colors: [sceneColor(0xE0667A), sceneColor(0x8E3048)])
        bc.fill(Path(CGRect(x: 13, y: -8, width: 10, height: 16)), with: .linearGradient(cone, startPoint: P(0, -6), endPoint: P(0, 6)))
        bc.fill(Path(CGRect(x: -9, y: -8, width: 2.2, height: 16)), with: .color(sceneColor(0x8A8FB8, 0.55)))
        // 下の影（からだの丸み）
        let under = Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.22)])
        bc.fill(body, with: .linearGradient(under, startPoint: P(0, 1), endPoint: P(0, 7)))
        let rim = Gradient(colors: [sceneColor(0xFF9AD5, 0.85), sceneColor(0xFF9AD5, 0)])
        c.stroke(body, with: .linearGradient(rim, startPoint: P(0, -7), endPoint: P(0, -1)), lineWidth: 1)
        // 窓
        let win = Path(ellipseIn: CGRect(x: 1.6, y: -3.6, width: 6.8, height: 6.8))
        let glass = Gradient(colors: [sceneColor(0x6E8CFF), sceneColor(0x1A1F55)])
        c.fill(win, with: .radialGradient(glass, center: P(4, -1.8), startRadius: 0, endRadius: 4.6))
        c.stroke(win, with: .color(sceneColor(0x8A8FB8)), lineWidth: 1)
        D.circle(c, 3.6, -1.8, 0.9, Color.white.opacity(0.8))
    }

    /// 炎（やわらかくゆらぐ。根もとは白く、先は橙で消える）
    @_optimize(none)
    static func rocketPlume(_ c: GraphicsContext, length L: Double, flicker: Double, boost: Double, halo: Bool) {
        let x0: Double = -20.5
        if halo {
            D.glow(c, x0 - L * 0.35, 0, 12 + L * 0.5, sceneColor(0xFFB060), 0.22 + 0.12 * flicker + boost * 0.25)
        }
        let outer: Path = smooth([P(x0, -3.6), P(x0 - L * 0.45, -3), P(x0 - L, 0), P(x0 - L * 0.45, 3), P(x0, 3.6)], closed: true)
        let og = Gradient(stops: [
            Gradient.Stop(color: sceneColor(0xFFE2A0, 0.95), location: 0),
            Gradient.Stop(color: sceneColor(0xFF9A4A, 0.7), location: 0.45),
            Gradient.Stop(color: sceneColor(0xFF6A5A, 0), location: 1),
        ])
        c.fill(outer, with: .linearGradient(og, startPoint: P(x0, 0), endPoint: P(x0 - L, 0)))
        let coreL: Double = L * 0.5
        let core: Path = smooth([P(x0, -1.8), P(x0 - coreL * 0.5, -1.4), P(x0 - coreL, 0), P(x0 - coreL * 0.5, 1.4), P(x0, 1.8)], closed: true)
        let cg = Gradient(colors: [Color.white.opacity(0.95), sceneColor(0xFFF0C8, 0)])
        c.fill(core, with: .linearGradient(cg, startPoint: P(x0, 0), endPoint: P(x0 - coreL, 0)))
    }

    /// うすい排気の粒（うしろへ流れて広がり、消える）
    @_optimize(none)
    static func rocketExhaust(_ c: GraphicsContext, t: Double, boost: Double) {
        for i in 0..<6 {
            let fi: Double = Double(i)
            let u: Double = (t * 0.8 + fi / 6).truncatingRemainder(dividingBy: 1)
            let x: Double = -26 - u * (34 + boost * 20)
            let y: Double = sin(fi * 2.3 + u * 4) * (1 + u * 5)
            let r: Double = 1.2 + u * 4
            D.glow(c, x, y, r, sceneColor(0xD8D2F0), 0.32 * (1 - u))
        }
    }
}
