import SwiftUI

// MARK: - 結晶：深い紺の夜に、氷の青と薄紫の結晶が浮かぶ。片付けるたびに一日の結晶の面がひとつ育ち、
// のこりの用事はまだ形にならないかけら（3つまで）として漂う。面は左上からの光で明るさが決まり、暗い面には向こうの面を通った光がうっすら映る。
// 光の向きはごくゆっくり振れ、照り返しの面が少しずつ移る。きらめきはときどき角に1つだけ、鋭く短く光る。
// 起床の画面では背の高い柱の結晶になり（見出しの下から）、朝が近づくほど光が強くなる。
// 結晶・星は TimelineView（15fps）の Canvas 1枚。完了の反応（かけらが飛んで面にはまる）は住人の層（CritterCrystalInk.swift）。

/// 今日の用事の数（結晶の面・墨の模様の数に使う）。画面では開いたときと完了したときに数え直す
struct WorldDayCount: Equatable {
    var done: Int = 0
    var open: Int = 0

    @_optimize(none)
    static func now(_ date: Date = .now) -> WorldDayCount {
        let cal: Calendar = Calendar.current
        let all: [TodoItem] = TodoData.all()
        let end: Date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
        var c = WorldDayCount()
        for item in all {
            if item.done {
                let today: Bool = item.doneAt.map { cal.isDate($0, inSameDayAs: date) } ?? false
                if today { c.done += 1 }
            } else {
                let due: Date = item.due ?? date
                if due < end { c.open += 1 }
            }
        }
        return c
    }
}

private struct WorldWakeSceneKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// 起床の画面の背景か（結晶は柱の結晶、墨流しは時刻のまわりの輪に描き替える）
    var worldWakeScene: Bool {
        get { self[WorldWakeSceneKey.self] }
        set { self[WorldWakeSceneKey.self] = newValue }
    }
}

enum CrystalScene {
    static let facetTotal: Int = 7

    /// 結晶のまわりの7つの角（中心からの比。上から時計回り）
    static let rim: [CGPoint] = [
        CGPoint(x: 0, y: -0.86), CGPoint(x: 0.32, y: -0.72), CGPoint(x: 0.56, y: -0.4),
        CGPoint(x: 0.48, y: 0.52), CGPoint(x: 0, y: 0.96), CGPoint(x: -0.48, y: 0.52), CGPoint(x: -0.56, y: -0.4),
    ]

    /// 面が育つ順（rim[i] と rim[i+1] と中心の三角）
    static let growOrder: [Int] = [6, 0, 5, 4, 1, 2, 3]

    /// 面の色（左上から右下への2色）
    static let facetColors: [(UInt32, UInt32)] = [
        (0xE9F7FF, 0x7FD4F5), (0x9FE8FF, 0xF4FBFF), (0xD9CCFF, 0x8F7BE8), (0xB9A8FF, 0x5E8BE0),
    ]

    struct Star { let x: Double; let y: Double; let s: Double; let phase: Double; let tint: UInt32 }

    /// 遠くの星（小さな点だけ。四つ角の光は出さない）
    static let stars: [Star] = {
        var rnd = SceneRandom(3407)
        var out: [Star] = []
        let tints: [UInt32] = [0xFFFFFF, 0xE9F7FF, 0xD9CCFF, 0xFFFFFF]
        for i in 0..<10 {
            let x: Double = rnd.range(0.04, 0.96)
            let y: Double = rnd.range(0.03, 0.97)
            let s: Double = rnd.range(0.5, 1.0)
            let phase: Double = rnd.range(0, 6.28)
            out.append(Star(x: x, y: y, s: s, phase: phase, tint: tints[i % 4]))
        }
        return out
    }()

    struct Shard { let x: Double; let y: Double; let r: Double; let spin: Double; let phase: Double }

    /// のこりの用事のかけら（結晶のまわりを漂う。多くても3つ）
    static let shards: [Shard] = {
        var rnd = SceneRandom(511)
        var out: [Shard] = []
        for _ in 0..<3 {
            let x: Double = rnd.range(-1.5, 1.5)
            let y: Double = rnd.range(-0.7, 0.7)
            let r: Double = rnd.range(0.1, 0.14)
            let spin: Double = rnd.range(-0.15, 0.15)
            let phase: Double = rnd.range(0, 6.28)
            out.append(Shard(x: x, y: y, r: r, spin: spin, phase: phase))
        }
        return out
    }()

    /// 結晶の中心と大きさ（住人の層の反応も同じ場所を使う）
    @_optimize(none)
    static func frame(_ size: CGSize, compact: Bool) -> (center: CGPoint, scale: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        if compact {
            let s: Double = min(w * 0.2, h * 0.36)
            return (CGPoint(x: w - s * 0.9, y: h * 0.42), s)
        }
        // 見出しのボタンとフォーカスのカードを避けて、「完了」の行とタブバーの間（左寄り）に置く
        let s: Double = min(w * 0.13, h * 0.072)
        return (CGPoint(x: w * 0.42, y: h * 0.785), s)
    }

    @_optimize(none)
    static func point(_ c: CGPoint, _ s: Double, _ u: CGPoint) -> CGPoint {
        CGPoint(x: Double(c.x) + Double(u.x) * s, y: Double(c.y) + Double(u.y) * s)
    }

    @_optimize(none)
    static func facetPath(_ i: Int, c: CGPoint, s: Double) -> Path {
        let a: CGPoint = point(c, s, rim[i])
        let b: CGPoint = point(c, s, rim[(i + 1) % rim.count])
        var path = Path()
        path.move(to: c)
        path.addLine(to: a)
        path.addLine(to: b)
        path.closeSubpath()
        return path
    }

    /// 四つ角の星
    @_optimize(none)
    static func star(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ color: Color) {
        let k: Double = r * 0.2
        var path = Path()
        path.move(to: CGPoint(x: x, y: y - r))
        path.addLine(to: CGPoint(x: x + k, y: y - k))
        path.addLine(to: CGPoint(x: x + r, y: y))
        path.addLine(to: CGPoint(x: x + k, y: y + k))
        path.addLine(to: CGPoint(x: x, y: y + r))
        path.addLine(to: CGPoint(x: x - k, y: y + k))
        path.addLine(to: CGPoint(x: x - r, y: y))
        path.addLine(to: CGPoint(x: x - k, y: y - k))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    /// 鋭いきらめき（細く長い十字の光と、小さな芯）。強さ a（0〜1）
    @_optimize(none)
    static func glint(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ a: Double) {
        guard a > 0.01 else { return }
        var rays = Path()
        rays.move(to: CGPoint(x: x - r, y: y))
        rays.addLine(to: CGPoint(x: x + r, y: y))
        rays.move(to: CGPoint(x: x, y: y - r * 0.8))
        rays.addLine(to: CGPoint(x: x, y: y + r * 0.8))
        let fade = Gradient(stops: [
            Gradient.Stop(color: Color.white.opacity(0), location: 0),
            Gradient.Stop(color: Color.white.opacity(a), location: 0.5),
            Gradient.Stop(color: Color.white.opacity(0), location: 1),
        ])
        ctx.stroke(rays, with: .radialGradient(fade, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r),
                   style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        CritterDraw.glow(ctx, x, y, r * 0.35, sceneColor(0xE9F7FF), 0.6 * a)
        CritterDraw.circle(ctx, x, y, 0.9, Color.white.opacity(a))
    }

    /// きらめきの強さ。period 秒に一度だけ、0.8秒ほど光る（ほとんどの時間は消えている）
    @_optimize(none)
    static func glintAt(_ t: Double, period: Double, offset: Double) -> Double {
        if t == 0 { return offset < 0.5 ? 0.85 : 0 }
        let u: Double = ((t / period) + offset).truncatingRemainder(dividingBy: 1)
        let len: Double = 0.8 / period
        guard u < len else { return 0 }
        return sin(u / len * Double.pi)
    }

    @_optimize(none)
    static func twinkle(_ t: Double, _ phase: Double) -> Double {
        t == 0 ? 0.7 : 0.6 + 0.4 * (0.5 + 0.5 * sin(t * 2 * Double.pi / 7 + phase))
    }

    /// 空の星（小さな点。ゆっくり明るさが揺れる）
    @_optimize(none)
    static func drawStars(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool, boost: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        var dots = Path()
        var bright = Path()
        for (i, st) in stars.enumerated() where !compact || i % 2 == 0 {
            let r: Double = (compact ? 0.6 : 0.9) * st.s
            let x: Double = st.x * w
            let y: Double = st.y * h
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            if twinkle(t, st.phase) > 0.85 { bright.addEllipse(in: rect) } else { dots.addEllipse(in: rect) }
        }
        let a: Double = (0.45 + 0.3 * boost) * (compact ? 0.6 : 1)
        ctx.fill(dots, with: .color(sceneColor(0xDCE8FF, a * 0.7)))
        ctx.fill(bright, with: .color(sceneColor(0xFFFFFF, a)))
    }

    /// 光の向き（左上から。ごくゆっくり振れて、面の明るさと照り返しが少しずつ移る）
    @_optimize(none)
    static func lightAngle(_ t: Double) -> Double {
        -2.25 + 0.3 * sin(t / 23)
    }

    /// 面の明るさ（拡散 0〜1・照り返し 0〜1）。面の向き（中心から外への角度）と光の向きから
    @_optimize(none)
    static func facetLight(_ mid: Double, light: Double) -> (diffuse: Double, spec: Double) {
        let c: Double = cos(mid - light)
        let diffuse: Double = 0.25 + 0.75 * max(0, c * 0.5 + 0.5)
        let spec: Double = pow(max(0, c), 14)
        return (diffuse, spec)
    }

    /// 一日の結晶。done 面が育ち（光の向きで明るさの違う氷の面）、次の面は細い点線、のこりはごく淡い線
    @_optimize(none)
    static func drawCrystal(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool, count: WorldDayCount) {
        let f = frame(size, compact: compact)
        let c: CGPoint = f.center
        let s: Double = f.scale
        let filled: Int = min(facetTotal, max(0, count.done))
        let light: Double = lightAngle(t)
        // 芯の光（控えめ）
        CritterDraw.glow(ctx, Double(c.x), Double(c.y), s * 1.4, sceneColor(0x7FB8FF), 0.1 + 0.025 * Double(filled))
        var outline = Path()
        var brightest: Int = -1
        var bestSpec: Double = 0
        for k in 0..<filled {
            let i: Int = growOrder[k]
            let path: Path = facetPath(i, c: c, s: s)
            outline.addPath(path)
            let a: CGPoint = point(c, s, rim[i])
            let b: CGPoint = point(c, s, rim[(i + 1) % rim.count])
            let mx: Double = (Double(a.x) + Double(b.x)) / 2
            let my: Double = (Double(a.y) + Double(b.y)) / 2
            let mid: Double = atan2(my - Double(c.y), mx - Double(c.x))
            let lit = facetLight(mid, light: light)
            if lit.spec > bestSpec { bestSpec = lit.spec; brightest = i }
            // 面の色：暗い氷の青から、光を受けた淡い青へ。ふち（外側）ほど明るい（浅い角度の照り返し）
            let inner: Color = BreathScene.mix(0x1E3F78, 0xBFE3FF, lit.diffuse * 0.75, 0.9)
            let outer: Color = BreathScene.mix(0x2E5C9A, 0xEAF7FF, min(1, lit.diffuse + 0.12), 0.92)
            let g = Gradient(colors: [inner, outer])
            ctx.fill(path, with: .linearGradient(g, startPoint: c, endPoint: CGPoint(x: mx, y: my)))
            // 屈折：暗い面ほど、向こう側の面を通った光がうっすら映る（内側の小さな三角）
            let back: Double = (1 - lit.diffuse) * 0.16
            if back > 0.02 {
                let gx: Double = (Double(c.x) + Double(a.x) + Double(b.x)) / 3
                let gy: Double = (Double(c.y) + Double(a.y) + Double(b.y)) / 3
                var tri = Path()
                tri.move(to: CGPoint(x: gx + (Double(a.x) - gx) * 0.45, y: gy + (Double(a.y) - gy) * 0.45))
                tri.addLine(to: CGPoint(x: gx + (Double(b.x) - gx) * 0.55, y: gy + (Double(b.y) - gy) * 0.55))
                tri.addLine(to: CGPoint(x: gx + (Double(c.x) - gx) * 0.3, y: gy + (Double(c.y) - gy) * 0.3))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(sceneColor(0xD9F1FF, back)))
            }
            // 照り返し（光の正面を向いた面だけ白くなる）
            if lit.spec > 0.02 {
                ctx.fill(path, with: .color(Color.white.opacity(0.5 * lit.spec)))
            }
        }
        // 面の境の稜線（髪の毛ほど）と、外のふち
        if filled > 0 {
            ctx.stroke(outline, with: .color(Color.white.opacity(compact ? 0.25 : 0.32)), lineWidth: 0.6)
        }
        // 分光：いちばん照り返す面のふちに、ごく淡い虹色の線
        if brightest >= 0 && bestSpec > 0.15 {
            let a: CGPoint = point(c, s, rim[brightest])
            let b: CGPoint = point(c, s, rim[(brightest + 1) % rim.count])
            var edge = Path()
            edge.move(to: a)
            edge.addLine(to: b)
            let prism = Gradient(colors: [sceneColor(0x9FF3FF, 0.5 * bestSpec), sceneColor(0xFFB8E6, 0.5 * bestSpec), sceneColor(0xFFF0A8, 0.5 * bestSpec)])
            ctx.stroke(edge, with: .linearGradient(prism, startPoint: a, endPoint: b), lineWidth: 1.2)
        }
        // 次の面（細い点線がゆっくり明るくなったり暗くなったり）
        if filled < facetTotal {
            let next: Path = facetPath(growOrder[filled], c: c, s: s)
            let pulse: Double = t == 0 ? 0.7 : 0.55 + 0.25 * sin(t * 2 * Double.pi / 5)
            let dash = StrokeStyle(lineWidth: 0.9, lineJoin: .round, dash: [3, 3])
            ctx.stroke(next, with: .color(sceneColor(0xFFD27A, 0.6 * pulse)), style: dash)
        }
        // まだの面（ごく淡い）
        if filled + 1 < facetTotal {
            var rest = Path()
            for k in (filled + 1)..<facetTotal { rest.addPath(facetPath(growOrder[k], c: c, s: s)) }
            ctx.stroke(rest, with: .color(sceneColor(0xC8D7F0, 0.18)), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round, dash: [2, 4]))
        }
        // きらめき（照り返しのいちばん強い角に、ときどき1つだけ）
        if filled > 0 {
            let corner: Int = brightest >= 0 ? brightest : growOrder[0]
            let pt: CGPoint = point(c, s, rim[corner])
            let a: Double = glintAt(t, period: 6.5, offset: 0.2)
            glint(ctx, Double(pt.x), Double(pt.y), compact ? 6 : 11, a)
        }
        // のこりの用事のかけら（小さく、ゆっくり漂う）
        let left: Int = min(shards.count, max(0, count.open))
        for i in 0..<left {
            let sh: Shard = shards[i]
            let bob: Double = t == 0 ? 0 : sin(t * 0.25 + sh.phase) * 0.05
            let ox: Double = sh.x < 0 ? min(sh.x, -0.95) : max(sh.x, 0.95)
            let cx: Double = Double(c.x) + ox * s
            let cy: Double = Double(c.y) + (sh.y + bob) * s
            let r: Double = sh.r * s * (compact ? 1.3 : 1)
            let rot: Double = sh.phase + sh.spin * (t == 0 ? 1 : sin(t * 0.1))
            shard(ctx, cx, cy, r, rot, alpha: 0.45)
        }
    }

    /// 形になっていないかけら（四角を崩した輪郭）
    @_optimize(none)
    static func shard(_ ctx: GraphicsContext, _ cx: Double, _ cy: Double, _ r: Double, _ rot: Double, alpha: Double) {
        let pts: [(Double, Double)] = [(-0.9, 0.4), (-0.1, -1.0), (0.9, -0.3), (0.4, 1.0)]
        var path = Path()
        for (i, p) in pts.enumerated() {
            let x: Double = p.0 * cos(rot) - p.1 * sin(rot)
            let y: Double = p.0 * sin(rot) + p.1 * cos(rot)
            let q = CGPoint(x: cx + x * r, y: cy + y * r)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(sceneColor(0x9FB4D8, 0.1 * alpha)))
        ctx.stroke(path, with: .color(sceneColor(0x9FB4D8, alpha)), lineWidth: 0.8)
    }

    /// 朝の近さ（0〜1。22時ごろから上がりはじめ、6時ごろにいちばん強い）
    @_optimize(none)
    static func morning(_ date: Date) -> Double {
        let day: Double = WorldMotion.dayFraction(date) * 24
        let until: Double = (30 - day).truncatingRemainder(dividingBy: 24)
        return max(0.15, min(1, 1 - until / 10))
    }

    /// 起床：背の高い柱の結晶。光を受ける左の面・影の右の面・明るい頂き。朝が近づくほど光が強く、きらめきが少し増える
    @_optimize(none)
    static func drawPrism(_ ctx: GraphicsContext, size: CGSize, t: Double, morning m: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let cx: Double = w * 0.5
        let hw: Double = min(w * 0.15, 64)
        let top: Double = h * 0.165
        let shoulder: Double = top + hw * 1.15
        let ridge: Double = shoulder + hw * 0.6
        let bottom: Double = h * 0.5
        let p0 = CGPoint(x: cx, y: top)
        let pl = CGPoint(x: cx - hw, y: shoulder)
        let pr = CGPoint(x: cx + hw, y: shoulder)
        let pm = CGPoint(x: cx, y: ridge)
        let bl = CGPoint(x: cx - hw, y: bottom - hw * 0.65)
        let br = CGPoint(x: cx + hw, y: bottom - hw * 0.65)
        let bm = CGPoint(x: cx, y: bottom)
        CritterDraw.glow(ctx, cx, (top + bottom) / 2, hw * 3, sceneColor(0x7FB8FF), 0.1 + 0.14 * m)
        var lid = Path()
        lid.addLines([p0, pr, pm, pl])
        lid.closeSubpath()
        var left = Path()
        left.addLines([pl, pm, bm, bl])
        left.closeSubpath()
        var right = Path()
        right.addLines([pm, pr, br, bm])
        right.closeSubpath()
        let lg = Gradient(colors: [sceneColor(0xCFEAFF, 0.88), sceneColor(0x5E9CD6, 0.86)])
        let rg = Gradient(colors: [sceneColor(0x6F7CC0, 0.86), sceneColor(0x283266, 0.86)])
        let tg = Gradient(colors: [sceneColor(0xF4FBFF, 0.9), sceneColor(0xA9D3F0, 0.9)])
        ctx.fill(left, with: .linearGradient(lg, startPoint: pl, endPoint: bm))
        ctx.fill(right, with: .linearGradient(rg, startPoint: pr, endPoint: bm))
        ctx.fill(lid, with: .linearGradient(tg, startPoint: p0, endPoint: pm))
        // 屈折：影の面に、向こうの面を通った光が細く映る
        var refr = Path()
        refr.move(to: CGPoint(x: cx + hw * 0.2, y: ridge + hw * 0.3))
        refr.addLine(to: CGPoint(x: cx + hw * 0.55, y: ridge + hw * 0.1))
        refr.addLine(to: CGPoint(x: cx + hw * 0.5, y: bottom - hw * 1.2))
        refr.addLine(to: CGPoint(x: cx + hw * 0.25, y: bottom - hw * 0.9))
        refr.closeSubpath()
        ctx.fill(refr, with: .color(sceneColor(0xBFE3FF, 0.1 + 0.08 * m)))
        let rim: Color = Color.white.opacity(0.4)
        var edges = Path()
        edges.addPath(left)
        edges.addPath(right)
        edges.addPath(lid)
        ctx.stroke(edges, with: .color(rim), lineWidth: 0.7)
        // 光を受けた面の照り返し（ごくゆっくり上下する）
        var clip: GraphicsContext = ctx
        clip.clip(to: left)
        let u: Double = t == 0 ? 0.4 : 0.5 + 0.5 * sin(t * 2 * Double.pi / 14)
        let y0: Double = shoulder + u * (bottom - shoulder - hw)
        let sheen = Gradient(stops: [
            Gradient.Stop(color: Color.white.opacity(0), location: 0),
            Gradient.Stop(color: Color.white.opacity(0.18 + 0.2 * m), location: 0.5),
            Gradient.Stop(color: Color.white.opacity(0), location: 1),
        ])
        clip.fill(Path(CGRect(x: cx - hw, y: y0 - hw * 0.6, width: hw, height: hw * 1.2)),
                  with: .linearGradient(sheen, startPoint: CGPoint(x: cx, y: y0 - hw * 0.6), endPoint: CGPoint(x: cx, y: y0 + hw * 0.6)))
        // きらめき（角にだけ、ひとつずつ。朝が近いほど数が増える）
        let corners: [CGPoint] = [p0, pl, pm, bl]
        let n: Int = 1 + Int(m * 3)
        for i in 0..<min(n, corners.count) {
            let a: Double = glintAt(t, period: 7, offset: Double(i) / Double(max(1, n)))
            glint(ctx, Double(corners[i].x), Double(corners[i].y), 9 + 4 * m, a)
        }
    }
}

// 結晶の全画面の背景
struct CrystalBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.worldWakeScene) private var wake
    @State private var count: WorldDayCount = WorldDayCount()

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            let w: CGFloat = size.width
            let h: CGFloat = size.height
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            let shown: WorldDayCount = animated ? count : WorldDayCount.now()
            let wakeMode: Bool = wake && !compact
            ZStack {
                LinearGradient(colors: [sceneColor(0x1E2840), sceneColor(0x0F1420)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [sceneColor(0x26335A, 0.9), sceneColor(0x0F1420, 0)],
                               center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: max(w, h) * 0.7)
                SceneClock(fps: 15, animated: animated, stillT: stillT) { t in
                    Canvas { ctx, s in
                        if wakeMode {
                            let m: Double = CrystalScene.morning(Date())
                            CrystalScene.drawStars(ctx, size: s, t: t, compact: compact, boost: m)
                            CrystalScene.drawPrism(ctx, size: s, t: t, morning: m)
                        } else {
                            CrystalScene.drawStars(ctx, size: s, t: t, compact: compact, boost: 0.6)
                            // ウィジェットは結晶を描かない（文字に重ならないように。星だけ）
                            if !compact { CrystalScene.drawCrystal(ctx, size: s, t: t, compact: false, count: shown) }
                        }
                    }
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
        .onAppear { if !still { count = WorldDayCount.now() } }
        .onReceive(NotificationCenter.default.publisher(for: .worldTodoCompleted)) { _ in
            // 反応（かけらが飛んで面にはまる）が終わるころに面を育てる
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { count = WorldDayCount.now() }
        }
    }
}

/// 結晶のカード：紺の板に氷の縁
struct CrystalCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let sheen = LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.01)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
        let rim = LinearGradient(colors: [sceneColor(0xE9F7FF, 0.5), sceneColor(0x8F7BE8, 0.3)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            shape.fill(p.card.opacity(light ? 0.85 : 1))
            shape.fill(sheen)
            shape.strokeBorder(rim, lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0x7FD4F5, light ? 0.12 : 0.16), radius: light ? 4 : 10)
    }
}
