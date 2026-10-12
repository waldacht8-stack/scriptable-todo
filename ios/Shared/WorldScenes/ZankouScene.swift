import SwiftUI

// MARK: - 残光：黒い画面に、片付けた用事が長時間露光の光の筋として残り、一日分たまっていく
// 筋の高さは完了した時刻（朝は上・夜は下）。色は琥珀・空色・桃色・金色の順。写真のライトペインティングのように、細くくっきりした芯にやわらかなにじみ。
// 筋は新しい8本まで（多すぎると落ち着かない）。起床の画面では、見出しの横にアラームの時刻を光の線で書く（ZankouWakeTime）。
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

    //// 星の軌跡の弧（画面の外の右上を中心に回る）
    struct Trail { let r: Double; let start: Double; let len: Double; let alpha: Double; let warm: Bool }

    static let trails: [Trail] = {
        var rnd = SceneRandom(1717)
        var out: [Trail] = []
        for _ in 0..<16 {
            let r: Double = rnd.range(0.3, 1.5)
            let start: Double = rnd.range(0, 6.28)
            let len: Double = rnd.range(0.2, 0.6)
            let alpha: Double = rnd.range(0.04, 0.12)
            out.append(Trail(r: r, start: start, len: len, alpha: alpha, warm: rnd.next() > 0.75))
        }
        return out
    }()

    /// 画面に描く筋の数の上限（古い筋は描かない。多すぎると落ち着かない）
    static let maxStreaks: Int = 8

    /// 1本の筋を、長時間露光の光の線として描く。細くくっきりした芯と、やわらかな光のにじみ。
    /// reveal は伸びる途中（0〜1）。光を点けたところから明るく、消したところで少し細る
    @_optimize(none)
    static func drawStreak(_ ctx: GraphicsContext, path full: Path, tint: (UInt32, UInt32), reveal: Double, bright: Double, thin: Bool = false) {
        // thin（ウィジェットの下の余白）：にじみを小さくして、余白からはみ出さない
        let haloW: CGFloat = thin ? 3.5 : 7
        let glowW: CGFloat = thin ? 1.6 : 2.6
        let coreW: CGFloat = thin ? 0.8 : 1.1
        let path: Path = reveal >= 1 ? full : full.trimmedPath(from: 0, to: max(0.001, reveal))
        let box: CGRect = full.boundingRect
        let a = CGPoint(x: box.minX, y: box.midY)
        let b = CGPoint(x: box.maxX, y: box.midY)
        let c0: Color = sceneColor(tint.0)
        let c1: Color = sceneColor(tint.1)
        let hot: Color = BreathScene.mix(tint.1, 0xFFFFFF, 0.7)
        func along(_ color: Color, _ alpha: Double) -> GraphicsContext.Shading {
            let stops: [Gradient.Stop] = [
                Gradient.Stop(color: color.opacity(0), location: 0),
                Gradient.Stop(color: color.opacity(alpha), location: 0.14),
                Gradient.Stop(color: color.opacity(alpha), location: 0.82),
                Gradient.Stop(color: color.opacity(alpha * 0.55), location: 1),
            ]
            return GraphicsContext.Shading.linearGradient(Gradient(stops: stops), startPoint: a, endPoint: b)
        }
        ctx.stroke(path, with: along(c0, 0.07 * bright), style: StrokeStyle(lineWidth: haloW, lineCap: .round))
        ctx.stroke(path, with: along(c1, 0.3 * bright), style: StrokeStyle(lineWidth: glowW, lineCap: .round))
        ctx.stroke(path, with: along(hot, 0.95 * bright), style: StrokeStyle(lineWidth: coreW, lineCap: .round))
        // 伸びている途中だけ、先に小さな光の点
        if reveal < 1, let head = path.currentPoint {
            CritterDraw.glow(ctx, Double(head.x), Double(head.y), thin ? 3 : 8, c1, 0.5 * bright)
            CritterDraw.circle(ctx, Double(head.x), Double(head.y), thin ? 0.8 : 1.3, Color.white.opacity(0.9 * bright))
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
        // 下の方に、遠い街の灯りのようなほのかな暖かさ
        CritterDraw.glow(ctx, w * 0.5, h * 1.05, w * 0.95, sceneColor(0xFF9A3D), 0.08)
        // 星の軌跡（ごくゆっくり回る）
        let pivot = CGPoint(x: w * 1.08, y: -h * 0.06)
        let spin: Double = t / 300
        let count: Int = compact ? 8 : trails.count
        for tr in trails.prefix(count) {
            let r: Double = tr.r * h
            let start: Double = tr.start + spin
            var arc = Path()
            arc.addArc(center: pivot, radius: r, startAngle: Angle.radians(start), endAngle: Angle.radians(start + tr.len), clockwise: false)
            let c: Color = tr.warm ? sceneColor(0xFFD9A0, tr.alpha) : sceneColor(0xC9C4D8, tr.alpha)
            ctx.stroke(arc, with: .color(c), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
        }
        // 光の筋（古い順。最後の1本がいちばん新しい。新しい maxStreaks 本だけ）
        let n: Int = days.count
        let first: Int = max(0, n - maxStreaks)
        for i in first..<max(first, n) {
            let d: Double = days[i]
            let path: Path = streakPath(i, day: d, size: size, lane: lane)
            let tint: (UInt32, UInt32) = tints[i % tints.count]
            let last: Bool = i == n - 1
            let r: Double = last ? reveal : 1
            let age: Double = Double(n - 1 - i)
            let bright: Double = max(0.5, 1 - age * 0.07)
            drawStreak(ctx, path: path, tint: tint, reveal: r, bright: bright, thin: lane)
        }
    }

    // MARK: 起床：アラームの時刻を、光で空中に書いた文字（ライトペインティング）にする

    /// 数字の一筆書き（幅 0.56・高さ 1 の枠の中の点。なめらかにつないで描く）
    static let glyphs: [Character: [CGPoint]] = {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        var zero: [CGPoint] = []
        for i in 0...24 {
            let a: Double = -Double.pi / 2 + Double(i) / 24 * 2 * Double.pi
            zero.append(p(0.28 + cos(a) * 0.26, 0.5 + sin(a) * 0.5))
        }
        return [
            "0": zero,
            "1": [p(0.14, 0.2), p(0.32, 0.02), p(0.32, 0.02), p(0.32, 1.0)],
            "2": [p(0.04, 0.22), p(0.14, 0.04), p(0.3, 0), p(0.46, 0.06), p(0.52, 0.22), p(0.46, 0.42), p(0.04, 1.0), p(0.04, 1.0), p(0.56, 1.0)],
            "3": [p(0.04, 0.1), p(0.2, 0), p(0.4, 0.02), p(0.5, 0.14), p(0.48, 0.3), p(0.3, 0.45), p(0.22, 0.46), p(0.4, 0.5),
                  p(0.54, 0.66), p(0.52, 0.86), p(0.36, 0.99), p(0.16, 0.99), p(0.02, 0.9)],
            "4": [p(0.42, 1.0), p(0.42, 0.0), p(0.42, 0.0), p(0.02, 0.68), p(0.02, 0.68), p(0.56, 0.68)],
            "5": [p(0.5, 0), p(0.1, 0), p(0.1, 0), p(0.06, 0.44), p(0.22, 0.38), p(0.4, 0.4), p(0.53, 0.55), p(0.54, 0.78),
                  p(0.42, 0.95), p(0.24, 1.0), p(0.04, 0.92)],
            "6": [p(0.46, 0.04), p(0.3, 0), p(0.12, 0.12), p(0.04, 0.4), p(0.04, 0.7), p(0.12, 0.92), p(0.28, 1.0), p(0.44, 0.95),
                  p(0.53, 0.78), p(0.5, 0.6), p(0.36, 0.5), p(0.2, 0.52), p(0.07, 0.64)],
            "7": [p(0.02, 0), p(0.56, 0), p(0.56, 0), p(0.2, 1.0)],
            "8": [p(0.28, 0.47), p(0.1, 0.36), p(0.06, 0.18), p(0.16, 0.04), p(0.28, 0), p(0.42, 0.04), p(0.5, 0.18), p(0.46, 0.36),
                  p(0.28, 0.47), p(0.08, 0.6), p(0.04, 0.8), p(0.14, 0.96), p(0.28, 1.0), p(0.44, 0.96), p(0.54, 0.8), p(0.48, 0.6), p(0.28, 0.47)],
            "9": [p(0.5, 0.38), p(0.38, 0.48), p(0.2, 0.48), p(0.06, 0.36), p(0.04, 0.18), p(0.16, 0.03), p(0.32, 0), p(0.46, 0.08),
                  p(0.52, 0.3), p(0.5, 0.62), p(0.4, 0.9), p(0.24, 1.0), p(0.08, 0.94)],
        ]
    }()

    /// 点の列を、角を丸めた1本の線にする（中点を通る2次曲線）
    @_optimize(none)
    static func smooth(_ pts: [CGPoint], origin: CGPoint, scale: Double) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        func q(_ u: CGPoint) -> CGPoint {
            CGPoint(x: Double(origin.x) + Double(u.x) * scale, y: Double(origin.y) + Double(u.y) * scale)
        }
        path.move(to: q(pts[0]))
        if pts.count == 2 {
            path.addLine(to: q(pts[1]))
            return path
        }
        for i in 1..<(pts.count - 1) {
            let a: CGPoint = q(pts[i])
            let b: CGPoint = q(pts[i + 1])
            let mid = CGPoint(x: (Double(a.x) + Double(b.x)) / 2, y: (Double(a.y) + Double(b.y)) / 2)
            path.addQuadCurve(to: mid, control: a)
        }
        path.addLine(to: q(pts[pts.count - 1]))
        return path
    }

    /// 時刻の文字の幅（高さ 1 に対して）
    @_optimize(none)
    static func timeWidth(_ text: String) -> Double {
        var x: Double = 0
        for ch in text { x += ch == ":" ? 0.34 : 0.76 }
        return max(0, x - 0.18)
    }

    /// 時刻を光の線で書く。左上 origin・文字の高さ height。glow は光のにじみの強さ（ゆっくり息をする）
    @_optimize(none)
    static func drawTime(_ ctx: GraphicsContext, text: String, origin: CGPoint, height: Double, glow: Double) {
        var x: Double = Double(origin.x)
        let y: Double = Double(origin.y)
        var strokes = Path()
        var dots: [CGPoint] = []
        for ch in text {
            if ch == ":" {
                dots.append(CGPoint(x: x + height * 0.08, y: y + height * 0.32))
                dots.append(CGPoint(x: x + height * 0.08, y: y + height * 0.74))
                x += height * 0.34
                continue
            }
            if let g = glyphs[ch] {
                strokes.addPath(smooth(g, origin: CGPoint(x: x, y: y), scale: height))
            }
            x += height * 0.76
        }
        // 書き終えたあと、下をすっと払う光（筆記体の終わりのように）
        let right: Double = x - height * 0.18
        var swash = Path()
        swash.move(to: CGPoint(x: Double(origin.x) - height * 0.2, y: y + height * 1.28))
        swash.addCurve(to: CGPoint(x: right + height * 0.5, y: y + height * 1.12),
                       control1: CGPoint(x: Double(origin.x) + height * 0.6, y: y + height * 1.42),
                       control2: CGPoint(x: right - height * 0.4, y: y + height * 1.3))
        let amber: Color = sceneColor(0xFFB347)
        let hot: Color = sceneColor(0xFFF1DC)
        let lw: Double = max(1, height / 22)
        let paths: [(Path, Double)] = [(strokes, 1), (swash, 0.55)]
        for (path, k) in paths {
            ctx.stroke(path, with: .color(amber.opacity(0.1 * glow * k)), style: StrokeStyle(lineWidth: lw * 7, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(amber.opacity(0.38 * glow * k)), style: StrokeStyle(lineWidth: lw * 2.6, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(hot.opacity(0.95 * k)), style: StrokeStyle(lineWidth: lw * 1.1, lineCap: .round, lineJoin: .round))
        }
        for d in dots {
            CritterDraw.glow(ctx, Double(d.x), Double(d.y), lw * 5, amber, 0.45 * glow)
            CritterDraw.circle(ctx, Double(d.x), Double(d.y), lw * 1.1, hot)
        }
    }

// 今日完了した時刻（一日の中の位置）。古い順。now より後のものは入れない
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
        let rim = LinearGradient(colors: [sceneColor(0xFFD9A0, 0.45), sceneColor(0xFFB347, 0.12), sceneColor(0xFF8FA6, 0.2)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        let ember = LinearGradient(colors: [sceneColor(0xFFB347, 0.12), Color.clear],
                                   startPoint: .top, endPoint: .center)
        ZStack {
            shape.fill(fill)
            shape.fill(ember)
            shape.strokeBorder(rim, lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0xFFAA50, light ? 0.16 : 0.18), radius: light ? 5 : 12)
    }
}

/// 起床の見出しの横：次のアラームの時刻を、光で空中に書いた文字にする（文字の横の空いたところだけ。狭ければ描かない）
struct ZankouWakeTime: View {
    let alarm: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            let text: String = ZankouWakeTime.text(alarm)
            SceneClock(fps: 8, animated: !reduceMotion && WorldMotion.fixedPhase == nil) { t in
                Canvas { ctx, s in
                    ZankouWakeTime.draw(ctx, size: s, text: text, t: t)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 「6:30」の形（24時間）
    static func text(_ d: Date?) -> String {
        guard let d else { return "" }
        let cal: Calendar = Calendar.current
        let h: Int = cal.component(.hour, from: d)
        let m: Int = cal.component(.minute, from: d)
        let mm: String = m < 10 ? "0\(m)" : "\(m)"
        return "\(h):" + mm
    }

    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, text: String, t: Double) {
        guard !text.isEmpty else { return }
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        // 右の歯車との間を少しあけ、縦は見出しの真ん中に（払いの線の分だけ上へ）
        let rel: Double = ZankouScene.timeWidth(text)
        let gh: Double = min(h * 0.5, (w - 20) / max(1, rel + 0.9))
        guard gh >= 14 else { return }
        let width: Double = rel * gh
        let x0: Double = w - 10 - width - gh * 0.55
        let y0: Double = (h - gh * 1.35) / 2
        // にじみはゆっくり息をする（8秒）
        let glow: Double = t == 0 ? 0.9 : 0.85 + 0.15 * sin(t * 2 * Double.pi / 8)
        ZankouScene.drawTime(ctx, text: text, origin: CGPoint(x: x0, y: y0), height: gh, glow: glow)
    }
}

/// 起床の見出しの横に置く世界観の絵（残光は光の時刻、呼吸は息の円）。ほかの世界観ではただの空き（Spacer）
struct WorldWakeHeaderArt: View {
    let p: Palette
    let alarm: Date?

    var body: some View {
        switch p.world {
        case .zankou:
            ZankouWakeTime(alarm: alarm).frame(maxWidth: .infinity).frame(height: 56).layoutPriority(-1)
        case .breath:
            BreathWakeCircle().frame(maxWidth: .infinity).frame(height: 56).layoutPriority(-1)
        default:
            Spacer(minLength: 0)
        }
    }
}
