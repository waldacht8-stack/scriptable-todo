import SwiftUI

// MARK: - 墨流し：生成りの紙（水面）に、藍と朱の墨の輪が浮かぶ。輪は水の流れでゆがみ（墨流しの模様）、
// ゆっくり渦を巻きながら広がっては戻る。片付けるたびにしずくが増え、一日ぶんの模様が重なっていく。
// 起床の画面では時刻のまわりに輪が広がり、朝に向けて大きく渦を巻く。
// 輪はすべて TimelineView（15fps）の Canvas 1枚で、ゆがみは sin の重ね合わせ（ぼかし・フィルターは使わない）。
// 完了の反応（しずくが落ちて輪に広がる）は住人の層（CritterCrystalInk.swift）。

enum InkScene {
    static let indigo: UInt32 = 0x233A6B
    static let vermilion: UInt32 = 0xC8412A
    static let paper: UInt32 = 0xF5EEDF

    struct Ring { let dx: Double; let dy: Double; let r: Double; let width: Double; let red: Bool }
    struct Drop { let x: Double; let y: Double; let scale: Double; let reverse: Bool; let delay: Double; let rings: [Ring] }

    /// 輪の組（中心からの比。幅は pt）
    static func rings(_ seed: UInt64, count: Int, red: Bool) -> [Ring] {
        var rnd = SceneRandom(seed)
        var out: [Ring] = []
        let widths: [Double] = [5, 2, 2.5, 4, 1.5, 1.5, 3, 1.2, 2.5]
        for i in 0..<count {
            let r: Double = 0.11 + Double(i) * 0.12
            let isRed: Bool = (i % 3 == 2) != red
            out.append(Ring(dx: rnd.range(-0.04, 0.04), dy: rnd.range(-0.04, 0.04), r: r,
                            width: widths[i % widths.count], red: isRed))
        }
        return out
    }

    /// 画面の模様（下絵の3つと、今日片付けた数だけ増える小さなしずく）
    static let base: [Drop] = [
        Drop(x: 0.33, y: 0.25, scale: 1.0, reverse: false, delay: 0, rings: rings(11, count: 8, red: false)),
        Drop(x: 0.72, y: 0.37, scale: 0.85, reverse: true, delay: 3, rings: rings(23, count: 7, red: true)),
        Drop(x: 0.73, y: 0.15, scale: 0.55, reverse: false, delay: 6, rings: rings(37, count: 5, red: false)),
    ]

    static let extra: [Drop] = {
        var rnd = SceneRandom(905)
        var out: [Drop] = []
        for i in 0..<6 {
            out.append(Drop(x: rnd.range(0.12, 0.88), y: rnd.range(0.08, 0.9), scale: rnd.range(0.32, 0.5),
                            reverse: i % 2 == 0, delay: rnd.range(0, 9), rings: rings(UInt64(41 + i), count: 4, red: i % 2 == 1)))
        }
        return out
    }()

    /// 水の流れのゆがみ（墨流しのたゆたい）
    static func flow(_ x: Double, _ y: Double, t: Double, amp: Double) -> CGPoint {
        let fx: Double = sin(y * 0.021 + t * 0.11) * amp + sin(x * 0.013 - t * 0.07 + 1.3) * amp * 0.5
        let fy: Double = cos(x * 0.018 - t * 0.09) * amp + sin(y * 0.011 + t * 0.05 + 2.1) * amp * 0.5
        return CGPoint(x: x + fx, y: y + fy)
    }

    /// ゆがんだ輪を1本描く
    static func ringPath(cx: Double, cy: Double, r: Double, twist: Double, t: Double, amp: Double) -> Path {
        var path = Path()
        let steps: Int = max(24, min(72, Int(r / 2.4)))
        for s in 0...steps {
            let th: Double = Double(s) / Double(steps) * 2 * Double.pi
            let wob: Double = 1 + 0.05 * sin(th * 3 + twist) + 0.03 * sin(th * 5 - twist * 1.7)
            let x0: Double = cx + cos(th + twist) * r * wob
            let y0: Double = cy + sin(th + twist) * r * wob
            let q: CGPoint = flow(x0, y0, t: t, amp: amp)
            if s == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }

    /// 墨の輪の組を1つ描く（渦を巻き、広がっては戻る）
    @_optimize(none)
    static func drawDrop(_ ctx: GraphicsContext, _ d: Drop, size: CGSize, t: Double, alpha: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let unit: Double = min(w, h * 0.62) * d.scale
        let cx: Double = d.x * w
        let cy: Double = d.y * h
        let spinPeriod: Double = d.reverse ? -110 : 80
        let twist: Double = t * 2 * Double.pi / spinPeriod
        let spread: Double = t == 0 ? 1 : 0.995 + 0.055 * sin((t + d.delay) * 2 * Double.pi / 18)
        let amp: Double = compact ? 3 : 7
        for (i, ring) in d.rings.enumerated() where !compact || i % 2 == 0 {
            let r: Double = ring.r * unit * spread
            let path: Path = ringPath(cx: cx + ring.dx * unit, cy: cy + ring.dy * unit, r: r,
                                      twist: twist + Double(i) * 0.6, t: t + d.delay, amp: amp)
            let color: Color = sceneColor(ring.red ? vermilion : indigo, alpha * (ring.red ? 0.8 : 0.72))
            let lw: Double = ring.width * (compact ? 0.7 : 1)
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
    }

    /// 画面の模様（count.done だけ小さなしずくを足す）
    @_optimize(none)
    static func drawPattern(_ ctx: GraphicsContext, size: CGSize, t: Double, compact: Bool, done: Int) {
        let alpha: Double = compact ? 0.42 : 0.55
        for d in base {
            drawDrop(ctx, d, size: size, t: t, alpha: alpha, compact: compact)
        }
        let n: Int = min(extra.count, max(0, done))
        for i in 0..<n where !compact || i < 3 {
            drawDrop(ctx, extra[i], size: size, t: t, alpha: alpha * 0.9, compact: compact)
        }
    }

    /// 紙の繊維（うっすら。止まった模様）
    @_optimize(none)
    static func drawFibers(_ ctx: GraphicsContext, size: CGSize) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        var rnd = SceneRandom(613)
        for _ in 0..<26 {
            let x: Double = rnd.next() * w
            let y: Double = rnd.next() * h
            let len: Double = rnd.range(10, 30)
            let ang: Double = rnd.range(-0.5, 0.5)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len),
                              control: CGPoint(x: x + len * 0.5, y: y + rnd.range(-4, 4)))
            ctx.stroke(path, with: .color(sceneColor(0x8A7A5C, 0.1)), lineWidth: 0.6)
        }
    }

    /// 起床：時刻のまわりに輪が広がる。朝が近いほど大きく広がり、速く渦を巻く
    @_optimize(none)
    static func drawWake(_ ctx: GraphicsContext, size: CGSize, t: Double, morning m: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let cx: Double = w * 0.5
        let cy: Double = h * 0.36
        let inner: Double = min(w * 0.25, 96)
        let gap: Double = (9 + 6 * m) * min(1.4, w / 300)
        let twist: Double = t * 2 * Double.pi / (90 - 40 * m)
        let breathe: Double = t == 0 ? 0 : sin(t * 2 * Double.pi / 12) * 3
        let widths: [Double] = [5, 2, 2, 4, 3, 1.5, 3, 1.5, 2.5]
        for i in 0..<9 {
            let r: Double = inner + 10 + Double(i) * gap + breathe * Double(i) / 9
            let red: Bool = i % 3 == 1
            let a: Double = (red ? 0.75 : 0.68) * (1 - Double(i) * 0.05)
            let path: Path = ringPath(cx: cx, cy: cy, r: r, twist: twist + Double(i) * 0.5, t: t, amp: 5 + 3 * m)
            ctx.stroke(path, with: .color(sceneColor(red ? vermilion : indigo, a)),
                       style: StrokeStyle(lineWidth: widths[i], lineCap: .round, lineJoin: .round))
        }
        // 時刻の下はまっさらな紙にしておく（文字にかからないように）
        let disc = CGRect(x: cx - inner, y: cy - inner, width: inner * 2, height: inner * 2)
        ctx.fill(Path(ellipseIn: disc), with: .color(sceneColor(paper)))
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
                Canvas { ctx, s in InkScene.drawFibers(ctx, size: s) }
                SceneClock(fps: 15, animated: animated, stillT: stillT) { t in
                    Canvas { ctx, s in
                        if wakeMode {
                            InkScene.drawWake(ctx, size: s, t: t, morning: CrystalScene.morning(Date()))
                        } else {
                            InkScene.drawPattern(ctx, size: s, t: t, compact: compact, done: shownDone)
                        }
                    }
                }
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

/// 墨流しのカード：生成りの和紙に藍の細い縁
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
