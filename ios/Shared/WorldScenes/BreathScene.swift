import SwiftUI

// MARK: - 呼吸：やわらかな色のかたまりが、ゆっくり呼吸している。期限が近いほど鼓動が速く、色が深くなる
// かたまりはぼかしを使わず、放射状のグラデーションの丸で描く（毎フレーム軽い）。
// 「近さ」は次の期限までの時間（6時間以上先なら 0、期限を過ぎていれば 1）。急に速さが跳ねないよう 6段に丸める。
// 大きなカードのまわりには、同じ速さで広がる輪（カードの外側だけ。中の文字にはかからない）。
// 完了すると、ひと息大きく吸って吐く（TodoStore.complete の通知）。

enum BreathScene {
    /// かたまり（位置は比・半径は幅に対する比）
    struct Blob { let x: Double; let y: Double; let r: Double; let calm: UInt32; let deep: UInt32; let alpha: Double; let phase: Double }

    static let blobs: [Blob] = [
        Blob(x: 0.08, y: 0.08, r: 0.62, calm: 0xFFC2B0, deep: 0xF27A58, alpha: 0.85, phase: 0),
        Blob(x: 1.02, y: 0.44, r: 0.6, calm: 0xCDB8FF, deep: 0xA88BF0, alpha: 0.7, phase: 1.3),
        Blob(x: 0.42, y: 0.92, r: 0.58, calm: 0xFFE1A6, deep: 0xFFB57A, alpha: 0.7, phase: 2.4),
        Blob(x: 0.86, y: 0.06, r: 0.34, calm: 0xFFD9C9, deep: 0xFF9A7E, alpha: 0.55, phase: 3.6),
        Blob(x: 0.0, y: 0.6, r: 0.4, calm: 0xE6DDFF, deep: 0xC4B0FF, alpha: 0.5, phase: 4.7),
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

    /// 一息の長さ（秒）。近さ 0 で 10秒、1 で 4秒
    static func period(_ urgency: Double) -> Double { 10 - 6 * urgency }

    /// 吸って吐く（0〜1。吸う 4割・吐く 6割）
    static func breath(_ t: Double, period: Double) -> Double {
        let u: Double = (t / period).truncatingRemainder(dividingBy: 1)
        if u < 0.4 {
            return CritterDraw.ease(u / 0.4)
        }
        return 1 - CritterDraw.ease((u - 0.4) / 0.6)
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
        let deep: Double = urgency * 0.75
        let count: Int = compact ? 3 : blobs.count
        for (i, bl) in blobs.prefix(count).enumerated() {
            // かたまりごとに少しずれて呼吸し、ゆっくり漂う
            let own: Double = 0.5 + 0.5 * sin(t * 0.21 + bl.phase)
            let swell: Double = 1 + 0.1 * b + 0.04 * own + 0.12 * boost
            let r: Double = bl.r * w * swell
            let dx: Double = sin(t / 17 + bl.phase) * w * 0.04
            let dy: Double = cos(t / 23 + bl.phase * 1.3) * h * 0.02
            let cx: Double = bl.x * w + dx
            let cy: Double = bl.y * h + dy
            let a: Double = bl.alpha * (0.82 + 0.18 * b)
            let k: Double = i == 0 ? deep : deep * 0.6
            let c0: Color = mix(bl.calm, bl.deep, k, a)
            let c1: Color = mix(bl.calm, bl.deep, k, a * 0.45)
            let c2: Color = mix(bl.calm, bl.deep, k, 0)
            let center = CGPoint(x: cx, y: cy)
            let stops: [Gradient.Stop] = [
                Gradient.Stop(color: c0, location: 0),
                Gradient.Stop(color: c1, location: 0.5),
                Gradient.Stop(color: c2, location: 1),
            ]
            let shade = GraphicsContext.Shading.radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: r)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: shade)
        }
        // 全体をうっすら白で包む（文字の読みやすさのため。濃い色でも本文は 4.5:1 以上）
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(0.14)))
    }
}

/// 呼吸の全画面の背景
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

/// いちばん前のカードのまわりの輪（カードの外側へ広がって消える。Homes の FocusCard が先頭の1枚にだけ敷く）
struct BreathRings: View {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animated: Bool { !reduceMotion && WorldMotion.fixedPhase == nil }

    var body: some View {
        SceneClock(fps: 15, animated: animated, stillT: 0) { t in
            let u: Double = BreathScene.urgency(Date())
            let period: Double = BreathScene.period(u)
            let color: Color = BreathScene.mix(0xFFB59A, 0xD65434, u)
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let k: Double = animated ? ((t / period + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)) : 0.35 + Double(i) * 0.3
                    let grow: CGFloat = CGFloat(k) * 14
                    let alpha: Double = (1 - k) * 0.5
                    RoundedRectangle(cornerRadius: radius + grow, style: .continuous)
                        .stroke(color.opacity(alpha), lineWidth: 1.5)
                        .padding(-grow)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
