import SwiftUI

// MARK: - 墨流し：生成りの紙（水面）に、墨と藍（ときどき朱）の細い輪が浮かぶ。輪は間隔も太さも不ぞろいで、水の流れでいびつにゆがむ。
// ごくゆっくり回り、流れに合わせて漂う。TODO の画面では文字の多い真ん中を避けて左下と右の端に。片付けるたびに小さなしずくが増える。
// 起床の画面では見出しより下に大きな輪が広がり、朝に向けて輪の間が開く（見出しの裏には入れない）。
// 輪は TimelineView（10fps）の Canvas 1枚で、ゆがみは sin の重ね合わせ（ぼかしは使わない）。紙の繊維は墨の上に重ねる。
// 完了の反応（しずくが落ちて輪に広がる）は住人の層（CritterCrystalInk.swift）。

enum InkScene {
    static let indigo: UInt32 = 0x233A6B
    static let vermilion: UInt32 = 0xC8412A
    static let sumi: UInt32 = 0x2B2B30
    static let paper: UInt32 = 0xF5EEDF

    /// 輪の色（墨・藍・朱）
    enum Tone { case sumi, indigo, red }

    struct Ring { let r: Double; let width: Double; let tone: Tone; let phase: Double; let wob: Double }
    struct Drop { let x: Double; let y: Double; let scale: Double; let reverse: Bool; let delay: Double; let rings: [Ring] }

    /// 輪の組（中心からの比。幅は pt）。間隔も太さも少しずつ不ぞろい。朱は withRed のときだけ、まれに入る
    @_optimize(none)
    static func rings(_ seed: UInt64, count: Int, withRed: Bool) -> [Ring] {
        var rnd = SceneRandom(seed)
        var out: [Ring] = []
        var r: Double = 0.025
        for i in 0..<count {
            r += rnd.range(0.018, 0.036)
            let pick: Double = rnd.next()
            let tone: Tone = (withRed && i % 5 == 3) ? .red : (pick < 0.55 ? .sumi : .indigo)
            let width: Double = rnd.range(0.6, 1.5)
            let phase: Double = rnd.range(0, 6.28)
            let wob: Double = rnd.range(0.02, 0.06)
            out.append(Ring(r: r, width: width, tone: tone, phase: phase, wob: wob))
        }
        return out
    }

    /// 画面の模様（下絵の2つと、今日片付けた数だけ増える小さなしずく）。文字の多い真ん中を避けて、左下と右の端に
    static let base: [Drop] = [
        Drop(x: 0.08, y: 0.84, scale: 1.0, reverse: false, delay: 0, rings: rings(11, count: 9, withRed: true)),
        Drop(x: 0.97, y: 0.44, scale: 0.75, reverse: true, delay: 40, rings: rings(23, count: 8, withRed: false)),
    ]

    static let extra: [Drop] = {
        var rnd = SceneRandom(905)
        var out: [Drop] = []
        for i in 0..<6 {
            let x: Double = rnd.range(0.12, 0.88)
            let y: Double = rnd.range(0.55, 0.86)
            let scale: Double = rnd.range(0.32, 0.48)
            let delay: Double = rnd.range(0, 90)
            out.append(Drop(x: x, y: y, scale: scale, reverse: i % 2 == 0, delay: delay,
                            rings: rings(UInt64(41 + i), count: 6, withRed: i % 3 == 1)))
        }
        return out
    }()

    /// 水の流れのゆがみ（墨流しのたゆたい。波長の違う3つの流れを重ねる。ゆっくり）
    @_optimize(none)
    static func flow(_ x: Double, _ y: Double, t: Double, amp: Double) -> CGPoint {
        let fx: Double = sin(y * 0.019 + t * 0.045) * amp + sin(x * 0.011 - t * 0.03 + 1.3) * amp * 0.6
            + sin((x + y) * 0.033 + t * 0.02 + 0.4) * amp * 0.25
        let fy: Double = cos(x * 0.016 - t * 0.04) * amp + sin(y * 0.009 + t * 0.025 + 2.1) * amp * 0.6
            + cos((x - y) * 0.029 - t * 0.018) * amp * 0.25
        return CGPoint(x: x + fx, y: y + fy)
    }

    /// ゆがんだ輪を1本描く
    @_optimize(none)
    static func ringPath(cx: Double, cy: Double, r: Double, twist: Double, t: Double, amp: Double) -> Path {
        ringPath(cx: cx, cy: cy, r: r, twist: twist, t: t, amp: amp, wob: 0.05, phase: 0)
    }

    /// ゆがんだ輪（wob は輪そのもののいびつさ、phase はいびつさの向き）
    @_optimize(none)
    static func ringPath(cx: Double, cy: Double, r: Double, twist: Double, t: Double, amp: Double, wob: Double, phase: Double) -> Path {
        var path = Path()
        let steps: Int = max(28, min(84, Int(r / 2.2)))
        for s in 0...steps {
            let th: Double = Double(s) / Double(steps) * 2 * Double.pi
            let k: Double = 1 + wob * sin(th * 2 + phase) + wob * 0.6 * sin(th * 3 - twist * 1.7 + phase * 0.5)
                + wob * 0.3 * sin(th * 7 + phase * 1.3)
            let x0: Double = cx + cos(th + twist) * r * k
            let y0: Double = cy + sin(th + twist) * r * k
            let q: CGPoint = flow(x0, y0, t: t, amp: amp)
            if s == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }

    static func color(_ tone: Tone, _ a: Double) -> Color {
        switch tone {
        case .sumi: return sceneColor(sumi, a)
        case .indigo: return sceneColor(indigo, a * 0.95)
        case .red: return sceneColor(vermilion, a * 0.85)
        }
    }

    /// 墨の輪を1本描く。細い線に、ところどころ墨のたまった太いところ（破線を少しずらして重ねる）
    @_optimize(none)
    static func strokeRing(_ ctx: GraphicsContext, _ path: Path, ring: Ring, alpha: Double, scale: Double) {
        let c: Color = color(ring.tone, alpha)
        let lw: Double = ring.width * scale
        ctx.stroke(path, with: .color(c), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        let pool = StrokeStyle(lineWidth: lw * 1.9, lineCap: .round, lineJoin: .round,
                               dash: [26, 14, 44, 9, 17, 31], dashPhase: ring.phase * 20)
        ctx.stroke(path, with: .color(color(ring.tone, alpha * 0.5)), style: pool)
    }

    /// 墨の輪の組を1つ描く（ごくゆっくり回り、水の流れでゆがむ）
    @_optimize(none)
    static func drawDrop(_ ctx: GraphicsContext, _ d: Drop, size: CGSize, t: Double, alpha: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let unit: Double = min(w, h * 0.62) * d.scale * (compact ? 2.2 : 1)
        let cx: Double = d.x * w
        let cy: Double = d.y * h
        let spinPeriod: Double = d.reverse ? -420 : 360
        let twist: Double = t * 2 * Double.pi / spinPeriod
        let amp: Double = compact ? 3 : 8
        for (i, ring) in d.rings.enumerated() where !compact || i % 2 == 0 {
            let r: Double = ring.r * unit
            let path: Path = ringPath(cx: cx, cy: cy, r: r, twist: twist + Double(i) * 0.3, t: t + d.delay, amp: amp,
                                      wob: ring.wob, phase: ring.phase)
            strokeRing(ctx, path, ring: ring, alpha: alpha, scale: compact ? 0.8 : 1)
        }
    }

    /// 画面の模様（count.done だけ小さなしずくを足す）
    @_optimize(none)
    static func drawPattern(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool, done: Int) {
        let alpha: Double = compact ? 0.15 : 0.24   // 文字が読みやすいよう淡く（ウィジェットは文字が多いのでさらに淡く）
        for d in base {
            drawDrop(ctx, d, size: size, t: t, alpha: alpha, compact: compact)
        }
        let n: Int = min(extra.count, max(0, done))
        for i in 0..<n where i < 3 {
            drawDrop(ctx, extra[i], size: size, t: t, alpha: alpha * 0.85, compact: compact)
        }
    }

    /// 紙の繊維（うっすら。止まった模様。墨の上にも重ねて、紙に染みたように見せる）
    @_optimize(none)
    static func drawFibers(_ ctx: GraphicsContext, size: CGSize) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        var rnd = SceneRandom(613)
        var light = Path()
        for i in 0..<34 {
            let x: Double = rnd.next() * w
            let y: Double = rnd.next() * h
            let len: Double = rnd.range(10, 34)
            let ang: Double = rnd.range(-3.1, 3.1)
            let bend: Double = rnd.range(-4, 4)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len),
                              control: CGPoint(x: x + cos(ang) * len * 0.5 - sin(ang) * bend, y: y + sin(ang) * len * 0.5 + cos(ang) * bend))
            if i % 3 == 0 {
                light.addPath(path)
            } else {
                ctx.stroke(path, with: .color(sceneColor(0x8A7A5C, 0.07)), lineWidth: 0.5)
            }
        }
        ctx.stroke(light, with: .color(Color.white.opacity(0.45)), lineWidth: 0.8)
    }

    /// 起床：見出しより下に、大きな墨流しの輪が静かに広がる。朝が近いほど輪の間が開く。見出しの裏には入れない
    @_optimize(none)
    static func drawWake(_ ctx: GraphicsContext, size: CGSize, t: Double, morning m: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        // 見出し（日付・題・2つのボタン）の下端より下だけに描き、上のふちはふっと消す
        let top: Double = max(h * 0.235, 160)
        let fadeH: Double = 36
        var layer: GraphicsContext = ctx
        layer.clipToLayer { mask in
            let stops: [Gradient.Stop] = [
                Gradient.Stop(color: Color.black.opacity(0), location: 0),
                Gradient.Stop(color: Color.black, location: 1),
            ]
            mask.fill(Path(CGRect(x: 0, y: top, width: w, height: fadeH)),
                      with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: top + fadeH)))
            mask.fill(Path(CGRect(x: 0, y: top + fadeH, width: w, height: max(0, h - top - fadeH))), with: .color(Color.black))
        }
        let cx: Double = w * 0.5
        let cy: Double = h * 0.6
        let inner: Double = min(w * 0.08, 34)
        let gap: Double = (11 + 5 * m) * min(1.4, w / 300)
        let twist: Double = t * 2 * Double.pi / 360
        var rnd = SceneRandom(1201)
        var r: Double = inner
        for i in 0..<11 {
            r += gap * rnd.range(0.7, 1.3)
            let tone: Tone = i % 6 == 4 ? .red : (rnd.next() < 0.55 ? .sumi : .indigo)
            let ring = Ring(r: r, width: rnd.range(0.7, 1.6), tone: tone, phase: rnd.range(0, 6.28), wob: rnd.range(0.02, 0.05))
            let path: Path = ringPath(cx: cx, cy: cy, r: r, twist: twist + Double(i) * 0.3, t: t, amp: 6 + 3 * m,
                                      wob: ring.wob, phase: ring.phase)
            strokeRing(layer, path, ring: ring, alpha: 0.32 * (1 - Double(i) * 0.03), scale: 1)
        }
    }
}

/// 墨流しの全画面の背景
struct InkBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.worldWakeScene) private var wake
    @State private var done: Int = 0

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            let w: CGFloat = size.width
            let h: CGFloat = size.height
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            let shownDone: Int = animated ? done : WorldDayCount.now().done
            let wakeMode: Bool = wake && !compact
            ZStack {
                LinearGradient(colors: [sceneColor(0xF7F1E4), sceneColor(0xEFE5D0)], startPoint: .top, endPoint: .bottom)
                // 墨はゆっくりしか動かないので 10fps で足りる
                SceneClock(fps: 10, animated: animated, stillT: stillT) { t in
                    Canvas { ctx, s in
                        if wakeMode {
                            InkScene.drawWake(ctx, size: s, t: t, morning: CrystalScene.morning(Date()))
                        } else {
                            InkScene.drawPattern(ctx, size: s, t: t, compact: compact, done: shownDone)
                        }
                    }
                }
                Canvas { ctx, s in InkScene.drawFibers(ctx, size: s) }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
        .onAppear { if !still { done = WorldDayCount.now().done } }
        .onReceive(NotificationCenter.default.publisher(for: .worldTodoCompleted)) { _ in
            // しずくが広がりきったころに模様へ加える
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { done = WorldDayCount.now().done }
        }
    }
}

// 墨流しのカード：生成りの和紙に藍の細い縁
struct InkCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        ZStack {
            shape.fill(p.card.opacity(light ? 0.92 : 1))
            shape.strokeBorder(sceneColor(InkScene.indigo, light ? 0.45 : 0.7), lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0x5A4E3C, light ? 0.06 : 0.1), radius: light ? 2 : 6, y: light ? 1 : 3)
    }
}
