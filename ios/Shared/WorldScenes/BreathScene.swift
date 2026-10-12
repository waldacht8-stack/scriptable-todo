import SwiftUI

// MARK: - 呼吸：やわらかな色のかたまりが3つ、ゆっくり呼吸している（落ち着いているときは12秒で一息、吸う4割・吐く6割）。期限が近いほど少し速く、色が深くなる
// かたまりはぼかしを使わず、ふちが溶けるように落ちる放射状のグラデーションを、傾けた楕円にして描く（毎フレーム軽い）。
// 「近さ」は次の期限までの時間（6時間以上先なら 0、期限を過ぎていれば 1）。急に速さが跳ねないよう 6段に丸める。
// 大きなカードのまわりには、吐く息に合わせて1本の輪が広がる（カードの外側だけ）。起床の画面では見出しの横に夜の青の息の円（吸う4秒・吐く6秒）。
// 完了すると、ひと息大きく吸って吐く（TodoStore.complete の通知）。

enum BreathScene {
    /// かたまり（位置は比・半径は幅に対する比）。squash は縦のつぶれ、tilt は傾き（丸すぎないように）
    struct Blob { let x: Double; let y: Double; let r: Double; let calm: UInt32; let deep: UInt32; let alpha: Double; let phase: Double; let squash: Double; let tilt: Double }

    static let blobs: [Blob] = [
        Blob(x: 0.06, y: 0.1, r: 0.78, calm: 0xFFC2B0, deep: 0xF27A58, alpha: 0.78, phase: 0, squash: 0.82, tilt: 0.5),
        Blob(x: 1.0, y: 0.5, r: 0.72, calm: 0xCDB8FF, deep: 0xA88BF0, alpha: 0.58, phase: 2.1, squash: 0.74, tilt: -0.7),
        Blob(x: 0.34, y: 0.96, r: 0.66, calm: 0xFFE1A6, deep: 0xFFB57A, alpha: 0.6, phase: 4.2, squash: 0.8, tilt: 0.2),
    ]

    /// 2つの色の間（k = 0 で a、1 で b）
    static func mix(_ a: UInt32, _ b: UInt32, _ k: Double, _ alpha: Double = 1) -> Color {
        let ar: Double = Double((a >> 16) & 0xFF)
        let ag: Double = Double((a >> 8) & 0xFF)
        let ab: Double = Double(a & 0xFF)
        let br: Double = Double((b >> 16) & 0xFF)
        let bg: Double = Double((b >> 8) & 0xFF)
        let bb: Double = Double(b & 0xFF)
        let r: Double = (ar + (br - ar) * k) / 255
        let g: Double = (ag + (bg - ag) * k) / 255
        let bl: Double = (ab + (bb - ab) * k) / 255
        return Color(red: r, green: g, blue: bl, opacity: alpha)
    }

    /// 一息の長さ（秒）。近さ 0 で 12秒（落ち着いた呼吸）、1 で 8秒
    static func period(_ urgency: Double) -> Double { 12 - 4 * urgency }

    /// 吸って吐く（0〜1。吸う 4割・吐く 6割。どちらも始まりと終わりがゆっくり）
    static func breath(_ t: Double, period: Double) -> Double {
        let u: Double = (t / period).truncatingRemainder(dividingBy: 1)
        if u < 0.4 {
            return 0.5 - 0.5 * cos(Double.pi * u / 0.4)
        }
        return 0.5 + 0.5 * cos(Double.pi * (u - 0.4) / 0.6)
    }

    /// やわらかな光のかたまりの濃さの落ち方（ぼかしたように、ふちが溶ける）
    static func softStops(_ c: (Double) -> Color) -> [Gradient.Stop] {
        [
            Gradient.Stop(color: c(1), location: 0),
            Gradient.Stop(color: c(0.86), location: 0.2),
            Gradient.Stop(color: c(0.58), location: 0.4),
            Gradient.Stop(color: c(0.28), location: 0.6),
            Gradient.Stop(color: c(0.08), location: 0.8),
            Gradient.Stop(color: c(0), location: 1),
        ]
    }

    // MARK: 近さ（次の期限までの時間）

    /// 読み直しは 30秒に1回まで（ファイルを毎フレーム読まない）
    private static var cachedAt: Date = .distantPast
    private static var cachedDue: Date? = nil

    static func nextDue(_ now: Date) -> Date? {
        if abs(now.timeIntervalSince(cachedAt)) < 30 { return cachedDue }
        let all: [TodoItem] = TodoData.all()
        var best: Date? = nil
        for item in all where !item.done && !item.isAllDay {
            guard let due = item.due else { continue }
            if due < now.addingTimeInterval(-6 * 3600) { continue }   // ずっと前の期限切れは数えない
            if let cur = best, cur <= due { continue }
            best = due
        }
        cachedAt = now
        cachedDue = best
        return best
    }

    /// 次の期限が来たら強制的に読み直す（完了のあと）
    static func invalidate() { cachedAt = .distantPast }

    /// 近さ 0〜1（6段に丸める）
    static func urgency(_ now: Date) -> Double {
        guard let due = nextDue(now) else { return 0 }
        let mins: Double = due.timeIntervalSince(now) / 60
        let raw: Double = max(0, min(1, 1 - mins / 360))
        return (raw * 5).rounded() / 5
    }

    /// 全体を描く。b は息（0〜1）、urgency は近さ、boost は完了の深呼吸（0〜1）
    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, b: Double, urgency: Double, boost: Double, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let base = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [sceneColor(0xF7F0F4), sceneColor(0xF6ECF1), sceneColor(0xF3E8F0)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h))
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: base)
        let deep: Double = urgency * 0.7
        for (i, bl) in blobs.enumerated() {
            // かたまりごとに少しずれて呼吸し、ごくゆっくり漂う（形もわずかに変わる）
            let lag: Double = 0.5 + 0.5 * sin(t * 0.13 + bl.phase)
            let swell: Double = 1 + 0.06 * b + 0.02 * lag + 0.08 * boost
            let r: Double = bl.r * w * swell
            let dx: Double = sin(t / 41 + bl.phase) * w * 0.03
            let dy: Double = cos(t / 53 + bl.phase * 1.3) * h * 0.015
            let cx: Double = bl.x * w + dx
            let cy: Double = bl.y * h + dy
            let a: Double = bl.alpha * (0.88 + 0.12 * b)
            let k: Double = i == 0 ? deep : deep * 0.6
            let calm: UInt32 = bl.calm
            let deepC: UInt32 = bl.deep
            let stops: [Gradient.Stop] = softStops { f in mix(calm, deepC, k, a * f) }
            var blob: GraphicsContext = ctx
            blob.translateBy(x: cx, y: cy)
            blob.rotate(by: Angle.radians(bl.tilt + 0.15 * sin(t / 61 + bl.phase)))
            blob.scaleBy(x: 1, y: bl.squash + 0.04 * sin(t / 37 + bl.phase))
            let shade = GraphicsContext.Shading.radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: r)
            blob.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: shade)
        }
        // 全体をうっすら白で包む（文字の読みやすさのため。濃い色でも本文は 4.5:1 以上）
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(0.14)))
    }
}

// 呼吸の全画面の背景
struct BreathBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。WorldMotion.sceneTime から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reactAt: Date? = nil

    var body: some View {
        GeometryReader { geo in
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: geo.size, still: still)
                && WorldMotion.fixedPhase == nil
            SceneClock(fps: 15, animated: animated, stillT: shownT) { t in
                let live: Bool = animated || shownT == 0
                let now: Date = live ? Date() : ZankouWidgetBackdrop.date(shownT)
                let u: Double = BreathScene.urgency(now)
                let b: Double = animated ? BreathScene.breath(t, period: BreathScene.period(u)) : stillBreath
                let boost: Double = boostAt(Date())
                Canvas { ctx, size in
                    BreathScene.draw(ctx, size: size, t: t, b: b, urgency: u, boost: boost, compact: compact)
                }
            }
        }
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .worldTodoCompleted)) { _ in
            BreathScene.invalidate()
            if !reduceMotion && !still { reactAt = Date() }
        }
    }

    private var shownT: Double {
        if let f = WorldMotion.fixedPhase { return 1 + f * 2400 }
        return stillT
    }

    /// 止まった絵の息（15分ごとに吸う・吐くの途中が変わる）
    private var stillBreath: Double {
        if shownT == 0 { return 0.5 }
        return 0.5 + 0.5 * sin(shownT * 0.9)
    }

    /// 完了の深呼吸（2.4秒）
    private func boostAt(_ now: Date) -> Double {
        if WorldMotion.fixedReaction { return 0.8 }
        guard let start = reactAt else { return 0 }
        let k: Double = now.timeIntervalSince(start) / 2.4
        guard k >= 0 && k < 1 else { return 0 }
        return sin(k * Double.pi)
    }
}

/// 呼吸のカード：やわらかな白い面（不透明。後ろのカードの文字が透けないように）
struct BreathCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let fill = LinearGradient(colors: [Color.white, p.card, sceneColor(0xFBF1F2)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            shape.fill(fill)
            shape.strokeBorder(Color.white.opacity(0.9), lineWidth: light ? 0.8 : 1)
        }
        .shadow(color: sceneColor(0xDC5A3C, light ? 0.1 : 0.16), radius: light ? 5 : 16, x: 0, y: light ? 2 : 8)
    }
}

//// いちばん前のカードのまわりの輪（吐く息に合わせて1本だけ外へ広がって消える。Homes の FocusCard が先頭の1枚にだけ敷く）
struct BreathRings: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animated: Bool { !reduceMotion && WorldMotion.fixedPhase == nil }

    var body: some View {
        SceneClock(fps: 15, animated: animated, stillT: 0) { t in
            let u: Double = BreathScene.urgency(Date())
            let period: Double = BreathScene.period(u)
            let color: Color = BreathScene.mix(0xFFB59A, 0xD65434, u)
            // 吸いきったところで現れ、吐く間に広がって消える
            let phase: Double = animated ? (t / period).truncatingRemainder(dividingBy: 1) : 0.6
            let k: Double = max(0, (phase - 0.4) / 0.6)
            let shown: Double = phase < 0.4 ? 0 : (1 - k) * 0.4
            let grow: CGFloat = CGFloat(CritterDraw.ease(k)) * 12
            RoundedRectangle(cornerRadius: radius + grow, style: .continuous)
                .stroke(color.opacity(shown), lineWidth: 1)
                .padding(-grow)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 起床の見出しの横：夜の青の、息の円。4秒かけて吸い（ふくらむ）、6秒かけて吐く（しぼむ）
struct BreathWakeCircle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animated: Bool = !reduceMotion && WorldMotion.fixedPhase == nil
        GeometryReader { geo in
            let size: CGSize = geo.size
            SceneClock(fps: 20, animated: animated) { t in
                let b: Double = animated ? BreathScene.breath(t, period: 10) : 0.7
                Canvas { ctx, s in
                    BreathWakeCircle.draw(ctx, size: s, b: b)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, b: Double) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        let big: Double = min(h * 0.47, (w - 16) / 2)
        guard big >= 12 else { return }
        let cx: Double = w - 10 - big
        let cy: Double = h / 2
        let r: Double = big * (0.6 + 0.4 * b)
        // 吸いきったときの大きさの目安（ごく淡い輪）
        let guide = CGRect(x: cx - big, y: cy - big, width: big * 2, height: big * 2)
        ctx.stroke(Path(ellipseIn: guide), with: .color(sceneColor(0x26346E, 0.14)), lineWidth: 0.8)
        // まわりのやわらかな光（吸うほど広がる）
        CritterDraw.glow(ctx, cx, cy, r * 1.45, sceneColor(0x2B3A7A), 0.12 + 0.12 * b)
        // 円そのもの（ふちが溶けるように。少し左上が明るい）
        let soft: Double = r * 1.12
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: sceneColor(0x34488C, 0.95), location: 0),
            Gradient.Stop(color: sceneColor(0x26346E, 0.93), location: 0.55),
            Gradient.Stop(color: sceneColor(0x1D2758, 0.8), location: 0.82),
            Gradient.Stop(color: sceneColor(0x1D2758, 0), location: 1),
        ]
        let center = CGPoint(x: cx - r * 0.12, y: cy - r * 0.14)
        let shade = GraphicsContext.Shading.radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: soft)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - soft, y: cy - soft, width: soft * 2, height: soft * 2)), with: shade)
        CritterDraw.glow(ctx, cx - r * 0.3, cy - r * 0.35, r * 0.55, Color.white, 0.1)
    }
}
