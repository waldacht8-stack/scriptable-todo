import SwiftUI

// MARK: - 結晶：深い紺の夜に、氷の青と薄紫の結晶が浮かぶ。片付けるたびに一日の結晶の面がひとつ育ち、
// のこりの用事はまだ形にならないかけらとして漂う。四つ角の星がまたたき、面には光が差して流れる。
// 起床の画面では背の高い柱の結晶になり、朝が近づくほどきらめきが増える。
// 結晶・星・光の帯は TimelineView（15fps）の Canvas 1枚。完了の反応（かけらが飛んで面にはまる）は住人の層（CritterCrystalInk.swift）。

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

    static let stars: [Star] = {
        var rnd = SceneRandom(3407)
        var out: [Star] = []
        let tints: [UInt32] = [0xFFFFFF, 0xE9F7FF, 0xD9CCFF, 0xFFFFFF]
        for i in 0..<18 {
            out.append(Star(x: rnd.range(0.04, 0.96), y: rnd.range(0.03, 0.97), s: rnd.range(0.45, 1.0),
                            phase: rnd.range(0, 6.28), tint: tints[i % 4]))
        }
        return out
    }()

    struct Shard { let x: Double; let y: Double; let r: Double; let spin: Double; let phase: Double }

    /// のこりの用事のかけら（結晶のまわりを漂う）
    static let shards: [Shard] = {
        var rnd = SceneRandom(511)
        var out: [Shard] = []
        for _ in 0..<6 {
            out.append(Shard(x: rnd.range(-1.5, 1.5), y: rnd.range(-0.85, 0.85), r: rnd.range(0.12, 0.2),
                             spin: rnd.range(-0.3, 0.3), phase: rnd.range(0, 6.28)))
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

    @_optimize(none)
    static func twinkle(_ t: Double, _ phase: Double) -> Double {
        t == 0 ? 0.7 : 0.15 + 0.85 * (0.5 + 0.5 * sin(t * 2 * Double.pi / 2.8 + phase))
    }

    /// 空のまたたく星
    @_optimize(none)
    static func drawStars(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool, boost: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        for (i, st) in stars.enumerated() where !compact || i % 2 == 0 {
            let a: Double = twinkle(t, st.phase) * (0.55 + 0.45 * boost) * (compact ? 0.5 : 1)
            let r: Double = (compact ? 2.2 : 5) * st.s
            let x: Double = st.x * w
            let y: Double = st.y * h
            CritterDraw.glow(ctx, x, y, r * 2.2, sceneColor(0xBFE6FF), 0.35 * a)
            star(ctx, x, y, r, sceneColor(st.tint, a))
        }
    }

    /// 一日の結晶。done 面が育ち、次の面は金の点線で脈打ち、のこりは淡い点線
    @_optimize(none)
    static func drawCrystal(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool, count: WorldDayCount) {
        let f = frame(size, compact: compact)
        let c: CGPoint = f.center
        let s: Double = f.scale
        let filled: Int = min(facetTotal, max(0, count.done))
        let alpha: Double = compact ? 0.7 : 0.88
        // 芯の光
        CritterDraw.glow(ctx, Double(c.x), Double(c.y), s * 1.5, sceneColor(0x7FB8FF), 0.22 + 0.06 * Double(filled))
        // 育った面
        for k in 0..<filled {
            let i: Int = growOrder[k]
            let path: Path = facetPath(i, c: c, s: s)
            let pair: (UInt32, UInt32) = facetColors[k % facetColors.count]
            let a: CGPoint = point(c, s, rim[i])
            let b: CGPoint = point(c, s, rim[(i + 1) % rim.count])
            let g = Gradient(colors: [sceneColor(pair.0, alpha), sceneColor(pair.1, alpha)])
            ctx.fill(path, with: .linearGradient(g, startPoint: a, endPoint: b))
            ctx.stroke(path, with: .color(Color.white.opacity(compact ? 0.55 : 0.75)), lineWidth: 1)
        }
        // 面の光（育った面を順に白く光らせる）
        if filled > 0 {
            let slot: Double = t == 0 ? 0.5 : (t / 5).truncatingRemainder(dividingBy: Double(filled))
            let k: Int = min(filled - 1, Int(slot))
            let u: Double = slot - Double(k)
            let shine: Double = 0.1 + 0.5 * sin(u * Double.pi)
            ctx.fill(facetPath(growOrder[k], c: c, s: s), with: .color(Color.white.opacity(shine * 0.8)))
        }
        // 次の面
        if filled < facetTotal {
            let next: Path = facetPath(growOrder[filled], c: c, s: s)
            let pulse: Double = t == 0 ? 0.75 : 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 2 * Double.pi / 2.4))
            ctx.fill(next, with: .color(sceneColor(0xFFD27A, 0.12 * pulse)))
            let dash = StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [4, 3])
            ctx.stroke(next, with: .color(sceneColor(0xFFD27A, pulse)), style: dash)
        }
        // まだの面
        if filled + 1 < facetTotal {
            let dash = StrokeStyle(lineWidth: 1, lineJoin: .round, dash: [3, 4])
            for k in (filled + 1)..<facetTotal {
                ctx.stroke(facetPath(growOrder[k], c: c, s: s), with: .color(sceneColor(0xC8D7F0, 0.4)), style: dash)
            }
        }
        // 光の帯（結晶の上を斜めに流れる）
        if filled > 0 {
            var clip: GraphicsContext = ctx
            var outline = Path()
            for k in 0..<filled { outline.addPath(facetPath(growOrder[k], c: c, s: s)) }
            clip.clip(to: outline)
            let u: Double = t == 0 ? 0.35 : (t / 7).truncatingRemainder(dividingBy: 1)
            let x0: Double = Double(c.x) - s * 1.6 + u * s * 3.2
            let y0: Double = Double(c.y) - s
            var band = Path()
            band.move(to: CGPoint(x: x0, y: y0))
            band.addLine(to: CGPoint(x: x0 + s * 0.22, y: y0))
            band.addLine(to: CGPoint(x: x0 - s * 0.38, y: y0 + s * 2.1))
            band.addLine(to: CGPoint(x: x0 - s * 0.6, y: y0 + s * 2.1))
            band.closeSubpath()
            clip.fill(band, with: .color(Color.white.opacity(0.45)))
        }
        // 面の上の星
        let spots: [CGPoint] = [CGPoint(x: -0.33, y: -0.6), CGPoint(x: -0.6, y: 0.2), CGPoint(x: 0.06, y: -0.8), CGPoint(x: -0.18, y: 0.74)]
        for (i, u) in spots.enumerated() where !compact || i < 2 {
            let pt: CGPoint = point(c, s, u)
            let a: Double = twinkle(t, Double(i) * 1.7)
            star(ctx, Double(pt.x), Double(pt.y), (compact ? 4 : 6) * (1 - Double(i) * 0.12), sceneColor(0xFFFFFF, a))
        }
        // のこりの用事のかけら
        let left: Int = min(shards.count, max(0, count.open))
        for i in 0..<left {
            let sh: Shard = shards[i]
            let bob: Double = t == 0 ? 0 : sin(t * 0.5 + sh.phase) * 0.06
            let ox: Double = sh.x < 0 ? min(sh.x, -0.95) : max(sh.x, 0.95)
            let cx: Double = Double(c.x) + ox * s
            let cy: Double = Double(c.y) + (sh.y + bob) * s
            let r: Double = sh.r * s * (compact ? 1.3 : 1)
            let rot: Double = sh.spin * (t == 0 ? 1 : t * 0.3) + sh.phase
            shard(ctx, cx, cy, r, rot, alpha: 0.7)
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
        ctx.fill(path, with: .color(sceneColor(0x9FB4D8, 0.12 * alpha)))
        ctx.stroke(path, with: .color(sceneColor(0x9FB4D8, alpha)), lineWidth: 1.2)
    }

    /// 朝の近さ（0〜1。22時ごろから上がりはじめ、6時ごろにいちばん強い）
    @_optimize(none)
    static func morning(_ date: Date) -> Double {
        let day: Double = WorldMotion.dayFraction(date) * 24
        let until: Double = (30 - day).truncatingRemainder(dividingBy: 24)
        return max(0.15, min(1, 1 - until / 10))
    }

    /// 起床：背の高い柱の結晶。朝が近づくほど光が差しこみ、星が増える
    @_optimize(none)
    static func drawPrism(_ ctx: GraphicsContext, size: CGSize, t: Double, morning m: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let cx: Double = w * 0.5
        let hw: Double = min(w * 0.15, 64)
        let top: Double = h * 0.12
        let shoulder: Double = top + hw * 1.15
        let ridge: Double = shoulder + hw * 0.6
        let bottom: Double = h * 0.48
        let p0 = CGPoint(x: cx, y: top)
        let pl = CGPoint(x: cx - hw, y: shoulder)
        let pr = CGPoint(x: cx + hw, y: shoulder)
        let pm = CGPoint(x: cx, y: ridge)
        let bl = CGPoint(x: cx - hw, y: bottom - hw * 0.65)
        let br = CGPoint(x: cx + hw, y: bottom - hw * 0.65)
        let bm = CGPoint(x: cx, y: bottom)
        CritterDraw.glow(ctx, cx, (top + bottom) / 2, hw * 3.2, sceneColor(0x7FB8FF), 0.18 + 0.22 * m)
        var lid = Path()
        lid.addLines([p0, pr, pm, pl])
        lid.closeSubpath()
        var left = Path()
        left.addLines([pl, pm, bm, bl])
        left.closeSubpath()
        var right = Path()
        right.addLines([pm, pr, br, bm])
        right.closeSubpath()
        let lg = Gradient(colors: [sceneColor(0xE9F7FF, 0.92), sceneColor(0x6FB8E8, 0.92)])
        let rg = Gradient(colors: [sceneColor(0xD9CCFF, 0.92), sceneColor(0x6A5ACD, 0.92)])
        let tg = Gradient(colors: [sceneColor(0xFFFFFF, 0.95), sceneColor(0xBDE6FF, 0.95)])
        ctx.fill(left, with: .linearGradient(lg, startPoint: pl, endPoint: bm))
        ctx.fill(right, with: .linearGradient(rg, startPoint: pr, endPoint: bm))
        ctx.fill(lid, with: .linearGradient(tg, startPoint: p0, endPoint: pm))
        let rim: Color = Color.white.opacity(0.75)
        ctx.stroke(left, with: .color(rim), lineWidth: 1)
        ctx.stroke(right, with: .color(rim), lineWidth: 1)
        ctx.stroke(lid, with: .color(rim), lineWidth: 1)
        // 光の帯（朝が近いほど強い）
        var clip: GraphicsContext = ctx
        var body = Path()
        body.addPath(left)
        body.addPath(right)
        body.addPath(lid)
        clip.clip(to: body)
        let period: Double = 7 - 3 * m
        let u: Double = t == 0 ? 0.4 : (t / period).truncatingRemainder(dividingBy: 1)
        let y0: Double = top - hw + u * (bottom - top + hw * 2)
        var band = Path()
        band.move(to: CGPoint(x: cx - hw * 1.2, y: y0))
        band.addLine(to: CGPoint(x: cx + hw * 1.2, y: y0 - hw * 0.8))
        band.addLine(to: CGPoint(x: cx + hw * 1.2, y: y0 - hw * 0.5))
        band.addLine(to: CGPoint(x: cx - hw * 1.2, y: y0 + hw * 0.3))
        band.closeSubpath()
        clip.fill(band, with: .color(Color.white.opacity(0.25 + 0.4 * m)))
        // きらめき（朝が近いほど数が増える）
        let n: Int = 3 + Int(m * 9)
        var rnd = SceneRandom(77)
        for i in 0..<12 {
            let x: Double = cx + rnd.range(-1.5, 1.5) * hw
            let y: Double = rnd.range(top - hw * 0.4, bottom + hw * 0.2)
            let ph: Double = rnd.range(0, 6.28)
            guard i < n else { continue }
            let a: Double = twinkle(t, ph)
            star(ctx, x, y, 3.5 + 3 * m * (i % 3 == 0 ? 1 : 0.5), sceneColor(0xFFFFFF, a))
        }
    }
}

/// 結晶の全画面の背景
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
