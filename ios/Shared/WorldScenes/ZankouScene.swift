import SwiftUI

// MARK: - 残光：黒い画面に、片付けた用事が長時間露光の光の筋として残り、一日分たまっていく
// 筋の高さは完了した時刻（朝は上・夜は下）。色は琥珀・空色・桃色・金色の順。筋の先に光の頭があり、ときどき光が筋をなぞる。
// 遠くでは星の軌跡（細い弧）がゆっくり回る。完了すると、新しい筋が左から光って伸びる（TodoStore.complete の通知）。
// 光は太さと濃さの違う線を重ねて出す（ぼかしは使わない）。文字は中身の側にあり、筋は背景なので文字にはかからない。

enum ZankouScene {
    /// 筋の色（始まりの色・終わりの色）
    static let tints: [(UInt32, UInt32)] = [(0xFF9A3D, 0xFFB45C), (0x7FD8FF, 0x9FE4FF), (0xFF6A8A, 0xFF8FA6), (0xFFE08A, 0xFFE9A8)]

    /// 一日の中の位置（0〜1）を、筋の高さ（画面の比）にする。5時〜24時を上 9%〜下 66% に並べる
    static func streakY(_ day: Double) -> Double {
        let k: Double = max(0, min(1, (day * 24 - 5) / 19))
        return 0.09 + k * 0.57
    }

    /// i 本目の筋の形（毎回同じ）
    @_optimize(none)
    static func streakPath(_ i: Int, day: Double, size: CGSize, lane: Bool = false) -> Path {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        var rnd = SceneRandom(UInt64(400 + i * 13))
        // lane（ウィジェット）：下の余白（中身の外側の 16pt）の中だけ。高さは時刻で h-9.5〜h-5.5、うねりは小さく
        let laneY: Double = h - 9.5 + 4 * max(0, min(1, (day * 24 - 5) / 19))
        let y0: Double = lane ? laneY : streakY(day) * h
        let endX: Double = w * rnd.range(0.55, 0.96)
        let rise: Double = lane ? rnd.range(-1, 1) : h * rnd.range(-0.05, 0.03)
        let bend: Double = lane ? rnd.range(0.8, 1.6) : h * rnd.range(0.025, 0.05)
        var path = Path()
        path.move(to: CGPoint(x: -20, y: y0))
        let c1 = CGPoint(x: endX * 0.3, y: y0 - bend)
        let c2 = CGPoint(x: endX * 0.6, y: y0 + bend + rise * 0.5)
        let end = CGPoint(x: endX, y: y0 + rise)
        path.addCurve(to: end, control1: c1, control2: c2)
        return path
    }

    /// 星の軌跡の弧（画面の外の右上を中心に回る）
    struct Trail { let r: Double; let start: Double; let len: Double; let alpha: Double; let warm: Bool }

    static let trails: [Trail] = {
        var rnd = SceneRandom(1717)
        var out: [Trail] = []
        for _ in 0..<44 {
            out.append(Trail(r: rnd.range(0.25, 1.5), start: rnd.range(0, 6.28), len: rnd.range(0.25, 0.9),
                             alpha: rnd.range(0.05, 0.2), warm: rnd.next() > 0.7))
        }
        return out
    }()

    /// 1本の筋を光らせて描く。reveal は伸びる途中（0〜1）、shine は光がなぞる位置（nil なら無し）
    @_optimize(none)
    static func drawStreak(_ ctx: GraphicsContext, path full: Path, tint: (UInt32, UInt32), reveal: Double, shine: Double?, bright: Double, thin: Bool = false) {
        // thin（ウィジェットの下の余白）：光の幅と頭の光を小さくして、余白からはみ出さない
        let wideW: CGFloat = thin ? 6 : 16
        let midW: CGFloat = thin ? 3 : 6
        let coreW: CGFloat = thin ? 1.2 : 1.8
        let headR: Double = thin ? 4.5 : 22
        let dotR: Double = thin ? 1.4 : 2.2
        let path: Path = reveal >= 1 ? full : full.trimmedPath(from: 0, to: max(0.001, reveal))
        let box: CGRect = full.boundingRect
        let a = CGPoint(x: box.minX, y: box.midY)
        let b = CGPoint(x: box.maxX, y: box.midY)
        let c0: Color = sceneColor(tint.0)
        let c1: Color = sceneColor(tint.1)
        let wide = GraphicsContext.Shading.linearGradient(Gradient(colors: [c0.opacity(0), c1.opacity(0.16 * bright)]), startPoint: a, endPoint: b)
        let mid = GraphicsContext.Shading.linearGradient(Gradient(colors: [c0.opacity(0), c1.opacity(0.4 * bright)]), startPoint: a, endPoint: b)
        let core = GraphicsContext.Shading.linearGradient(Gradient(colors: [c0.opacity(0), c1.opacity(0.95 * bright)]), startPoint: a, endPoint: b)
        ctx.stroke(path, with: wide, style: StrokeStyle(lineWidth: wideW, lineCap: .round))
        ctx.stroke(path, with: mid, style: StrokeStyle(lineWidth: midW, lineCap: .round))
        ctx.stroke(path, with: core, style: StrokeStyle(lineWidth: coreW, lineCap: .round))
        // 光の頭
        if let head = path.currentPoint {
            CritterDraw.glow(ctx, Double(head.x), Double(head.y), headR, c1, 0.55 * bright)
            CritterDraw.circle(ctx, Double(head.x), Double(head.y), dotR, Color.white.opacity(0.9 * bright))
        }
        // 光がなぞる
        if let s = shine, reveal >= 1 {
            let from: Double = max(0, s - 0.12)
            let seg: Path = full.trimmedPath(from: from, to: max(from + 0.001, s))
            ctx.stroke(seg, with: .color(Color.white.opacity(0.55 * bright)), style: StrokeStyle(lineWidth: thin ? 1.6 : 2.4, lineCap: .round))
            ctx.stroke(seg, with: .color(c1.opacity(0.25 * bright)), style: StrokeStyle(lineWidth: thin ? 4 : 9, lineCap: .round))
        }
    }

    /// 全体を描く。days は完了した時刻（一日の中の位置）。reveal は最後の筋の伸び（反応。1 なら伸びきり）
    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, days: [Double], reveal: Double, compact: Bool, lane: Bool = false) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let base = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [sceneColor(0x0A0A0F), sceneColor(0x0B0910), sceneColor(0x07070C)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h))
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: base)
        // 下の方に、ほのかな暖かい残り火
        CritterDraw.glow(ctx, w * 0.5, h * 1.02, w * 0.95, sceneColor(0xFF9A3D), 0.12)
        CritterDraw.glow(ctx, w * 0.1, h * 0.05, w * 0.6, sceneColor(0x7FD8FF), 0.05)
        // 星の軌跡（ゆっくり回る）
        let pivot = CGPoint(x: w * 1.08, y: -h * 0.06)
        let spin: Double = t / 260
        let count: Int = compact ? 18 : trails.count
        for tr in trails.prefix(count) {
            let r: Double = tr.r * h
            let start: Double = tr.start + spin
            var arc = Path()
            arc.addArc(center: pivot, radius: r, startAngle: Angle.radians(start), endAngle: Angle.radians(start + tr.len), clockwise: false)
            let c: Color = tr.warm ? sceneColor(0xFFD9A0, tr.alpha) : sceneColor(0xC9C4D8, tr.alpha)
            ctx.stroke(arc, with: .color(c), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
        // 光の筋（古い順。最後の1本がいちばん新しい）
        let n: Int = days.count
        for (i, d) in days.enumerated() {
            let path: Path = streakPath(i, day: d, size: size, lane: lane)
            let tint: (UInt32, UInt32) = tints[i % tints.count]
            let last: Bool = i == n - 1
            let r: Double = last ? reveal : 1
            let period: Double = 9 + Double(i % 4) * 2.3
            let shine: Double? = t == 0 ? nil : ((t / period + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)) * 1.3
            let age: Double = Double(n - 1 - i)
            let bright: Double = max(0.55, 1 - age * 0.06)
            drawStreak(ctx, path: path, tint: tint, reveal: r, shine: shine.map { min(1, $0) }, bright: bright, thin: lane)
        }
    }

    /// 今日完了した時刻（一日の中の位置）。古い順。now より後のものは入れない
    static func doneDays(_ now: Date) -> [Double] {
        let cal: Calendar = Calendar.current
        let start: Date = cal.startOfDay(for: now)
        let all: [TodoItem] = TodoData.all()
        var out: [Double] = []
        for item in all where item.done {
            guard let at = item.doneAt, cal.isDate(at, inSameDayAs: now), at <= now else { continue }
            let f: Double = at.timeIntervalSince(start) / 86400
            out.append(f)
        }
        out.sort()
        return out
    }
}

/// 残光の全画面の背景（アプリ。完了で新しい筋が伸びる）
struct ZankouBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。WorldMotion.sceneTime から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var days: [Double] = []
    @State private var reactAt: Date? = nil

    var body: some View {
        GeometryReader { geo in
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: geo.size, still: still)
                && WorldMotion.fixedPhase == nil
            SceneClock(fps: 15, animated: animated, stillT: shownT) { t in
                let now: Date = Date()
                let reveal: Double = revealAt(now)
                Canvas { ctx, size in
                    ZankouScene.draw(ctx, size: size, t: t, days: shownDays, reveal: reveal, compact: compact)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .worldTodoCompleted)) { _ in react() }
    }

    /// 止まった絵（画面写真の -motionphase・ウィジェット）の時刻
    private var shownT: Double {
        if let f = WorldMotion.fixedPhase { return 1 + f * 2400 }
        return stillT
    }

    /// 画面写真の -motionreact では、最後に1本足して伸びる途中を描く
    private var shownDays: [Double] {
        if WorldMotion.fixedReaction { return days + [WorldMotion.dayFraction(Date())] }
        return days
    }

    private func revealAt(_ now: Date) -> Double {
        if WorldMotion.fixedReaction { return 0.62 }
        guard let start = reactAt else { return 1 }
        let k: Double = now.timeIntervalSince(start) / 1.6
        return k >= 1 ? 1 : CritterDraw.ease(max(0, k))
    }

    private func reload() {
        days = ZankouScene.doneDays(Date())
    }

    private func react() {
        // 保存が終わってから読み直す。読めなくても今の時刻で1本足す
        let before: Int = days.count
        let now: Date = Date()
        let f: Double = WorldMotion.dayFraction(now)
        days = days + [f]
        reactAt = (reduceMotion || still) ? nil : now
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let fresh: [Double] = ZankouScene.doneDays(Date())
            if fresh.count > before { days = fresh }
        }
    }
}

/// 残光のウィジェットの背景（止まった絵。entry.date の時刻までに完了した分の筋を描く）
struct ZankouWidgetBackdrop: View {
    let p: Palette
    var stillT: Double = 0

    var body: some View {
        let now: Date = ZankouWidgetBackdrop.date(stillT)
        let days: [Double] = ZankouScene.doneDays(now)
        Canvas { ctx, size in
            ZankouScene.draw(ctx, size: size, t: stillT, days: days, reveal: 1, compact: true, lane: true)
        }
        .allowsHitTesting(false)
    }

    /// WorldMotion.sceneTime の値から、今日のその時刻に戻す
    static func date(_ stillT: Double) -> Date {
        let start: Date = Calendar.current.startOfDay(for: Date())
        let f: Double = max(0, min(1, (stillT - 1) / 2400))
        return start.addingTimeInterval(f * 86400)
    }
}

/// 残光のカード：暗い板に、琥珀色の光の縁とほのかな残り火
struct ZankouCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let fill = LinearGradient(colors: [sceneColor(0x1E1A24), p.card, sceneColor(0x110E15)],
                                  startPoint: .top, endPoint: .bottom)
        let rim = LinearGradient(colors: [sceneColor(0xFFD9A0, 0.6), sceneColor(0xFFB347, 0.18), sceneColor(0xFF8FA6, 0.3)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        let ember = LinearGradient(colors: [sceneColor(0xFFB347, 0.12), Color.clear],
                                   startPoint: .top, endPoint: .center)
        ZStack {
            shape.fill(fill)
            shape.fill(ember)
            shape.strokeBorder(rim, lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0xFFAA50, light ? 0.22 : 0.3), radius: light ? 5 : 14)
    }
}
