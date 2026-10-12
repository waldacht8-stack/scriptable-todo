import SwiftUI
import WidgetKit

// MARK: - 世界観の小さな住人（地層のモグラ・銀河の宇宙飛行士・空の鳥と紙飛行機・霧の鹿・深海のクジラ・オーロラの狐）
// どれも図形（Path）だけで描く。画像は使わない。
// アプリ：背景の上・中身の下に描く（カードや文字を隠さない）。画面の下の方（「完了」の行とタブバーの間あたり）を通り道にする。
//         TimelineView（15fps）でゆっくり動き、TODO を完了すると小さく反応する（TodoStore.complete が通知を送る）。
//         「視差効果を減らす」がオンなら止まった絵にして、反応はふわっと出て消えるだけにする。
// ウィジェット：動き続けられないので、15分ごとのタイムラインの entry.date から位置を決めた止まった絵を描く
//         （WidgetKit がその間を世界観の動き方でつなぐ）。ぼかしは使わず、1匹あたり図形は数個だけ。
// 画面写真用：起動引数 -motionphase 0〜1 で位置を固定し、-motionreact で完了の反応の途中を描く。

extension Notification.Name {
    /// TODO を1件完了した（世界観の住人が反応する）
    static let worldTodoCompleted = Notification.Name("worldTodoCompleted")
}

enum WorldMotion {
    /// 画面写真用の固定の位相（-motionphase 0〜1）
    static let fixedPhase: Double? = {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-motionphase"), i + 1 < args.count, let v = Double(args[i + 1]) else { return nil }
        return max(0, min(1, v))
    }()

    /// 画面写真用：完了の反応の途中を描く（-motionreact）
    static let fixedReaction: Bool = ProcessInfo.processInfo.arguments.contains("-motionreact")

    /// TODO を完了したことを知らせる（TodoStore.complete から）
    static func postCompleted() {
        NotificationCenter.default.post(name: .worldTodoCompleted, object: nil)
    }

    /// 一日の中の位置（0 = 0時、1 = 24時）
    static func dayFraction(_ d: Date) -> Double {
        if let f = fixedPhase { return f }
        let start: Date = Calendar.current.startOfDay(for: d)
        return max(0, min(1, d.timeIntervalSince(start) / 86400))
    }

    /// period 秒で一巡する位相（0〜1）。0時からの経過で決める（ウィジェットの15分ごとの絵が少しずつ進む）
    static func cycle(_ d: Date, period: Double) -> Double {
        if let f = fixedPhase { return f }
        let start: Date = Calendar.current.startOfDay(for: d)
        let s: Double = d.timeIntervalSince(start)
        return (s / period).truncatingRemainder(dividingBy: 1)
    }

    /// ウィジェットの背景の時刻（雲・砂粒・霧などを15分ごとに少し進める）
    static func sceneTime(_ d: Date) -> Double { 1 + dayFraction(d) * 2400 }

    /// 住人がいる世界観か（「なし」にはいない）
    static func hasCritters(_ w: World) -> Bool {
        switch w {
        case .none: false
        case .zankou, .breath: false   // 住人はいない。背景の光の筋・かたまりが完了に反応する
        default: true
        }
    }
}

private struct WorldCrittersKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// 背景に世界観の住人を描くか（RootView のタブの画面だけ true。設定の見本や小さなサムネイルには出さない）
    var worldCritters: Bool {
        get { self[WorldCrittersKey.self] }
        set { self[WorldCrittersKey.self] = newValue }
    }
}

/// 住人の絵に渡す値
struct CritterKnobs {
    /// 秒（小さな揺れ・羽ばたき）
    var t: Double
    /// 0〜1：横切る位置など（一巡）
    var progress: Double
    /// 0〜1：一日の位置（トンネルの長さ・太陽・時計）
    var day: Double
    /// 0〜1：完了の反応の進み（nil は反応なし）
    var react: Double?
    /// 今日の完了の数（結晶の面の位置などに使う。なければ 0）
    var count: Int = 0
    /// 暗い色合いか
    var dark: Bool
}

// MARK: - アプリ：背景の住人の層

/// WorldBackground が重ねる住人の層（中身の下）。世界観ごとの絵は CritterArt
struct WorldCritterLayer: View {
    let p: Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 最後に完了した時刻（反応の始まり）
    @State private var reactAt: Date? = nil
    /// 「視差効果を減らす」のときの反応の濃さ（ふわっと出て消える）
    @State private var fade: Double = 0

    var body: some View {
        GeometryReader { geo in
            let size: CGSize = geo.size
            if size.width > 220 {
                layer(size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .worldTodoCompleted)) { _ in react() }
    }

    private var still: Bool { reduceMotion || WorldMotion.fixedPhase != nil }

    @ViewBuilder
    private func layer(_ size: CGSize) -> some View {
        let world: World = p.world
        let dark: Bool = p.scheme == .dark
        if still {
            let phase: Double = WorldMotion.fixedPhase ?? 0.5
            let period: Double = CritterArt.period(world)
            // 画面写真の反応つきは、住人も反応の途中の姿で描く（モグラが2匹にならないように）
            let baseReact: Double? = WorldMotion.fixedReaction ? 0.45 : nil
            let base = CritterKnobs(t: phase * period, progress: phase, day: phase, react: baseReact, dark: dark)
            let reactKnobs = CritterKnobs(t: phase * period, progress: phase, day: phase, react: 0.45, dark: dark)
            let showReact: Double = WorldMotion.fixedReaction ? 1 : fade
            ZStack {
                Canvas { ctx, s in CritterArt.drawApp(world, ctx, size: s, k: base, layer: .idle) }
                Canvas { ctx, s in CritterArt.drawApp(world, ctx, size: s, k: reactKnobs, layer: .reaction) }
                    .opacity(showReact)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { tl in
                let now: Date = tl.date
                let t: Double = now.timeIntervalSinceReferenceDate
                let period: Double = CritterArt.period(world)
                let progress: Double = (t / period).truncatingRemainder(dividingBy: 1)
                let k = CritterKnobs(t: t, progress: progress, day: WorldMotion.dayFraction(now),
                                     react: reaction(at: now, world: world), dark: dark)
                Canvas { ctx, s in
                    CritterArt.drawApp(world, ctx, size: s, k: k, layer: .idle)
                    CritterArt.drawApp(world, ctx, size: s, k: k, layer: .reaction)
                }
            }
        }
    }

    /// 反応の進み（0〜1。終わっていれば nil）
    private func reaction(at now: Date, world: World) -> Double? {
        guard let start = reactAt else { return nil }
        let r: Double = now.timeIntervalSince(start) / CritterArt.reactionDuration(world)
        return r >= 0 && r < 1 ? r : nil
    }

    private func react() {
        if still {
            withAnimation(.easeIn(duration: 0.2)) { fade = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.8)) { fade = 0 }
            }
        } else {
            reactAt = Date()
        }
    }
}

// MARK: - ウィジェット：背景の住人（止まった絵。entry.date で位置が変わる）

/// WidgetWorldBackground が重ねる住人。phase を渡すと、時刻の代わりにその位相で描く（見本の画面用）
struct WidgetWorldCritters: View {
    let p: Palette
    let date: Date
    var phase: Double? = nil
    /// ウィジェットの余白（住人はこの外側の帯だけを通る）
    @Environment(\.widgetContentMargins) private var margins: EdgeInsets

    var body: some View {
        GeometryReader { geo in
            CritterWidgetArt.view(p, size: geo.size, knobs: knobs(), margins: margins)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(p.world.widgetAnimation, value: phaseKey)
    }

    /// 描き直しの目印（位相が変わったら世界観の動き方でつなぐ）
    private var phaseKey: Double { phase ?? WorldMotion.dayFraction(date) }

    private func knobs() -> CritterKnobs {
        let world: World = p.world
        let period: Double = CritterWidgetArt.period(world)
        let progress: Double = phase ?? WorldMotion.cycle(date, period: period)
        let day: Double = phase ?? WorldMotion.dayFraction(date)
        return CritterKnobs(t: 0, progress: progress, day: day, react: nil, dark: p.scheme == .dark)
    }
}

// MARK: - 描くための小さな道具

enum CritterDraw {
    /// (at) を原点に、scale 倍・angle 回転・左右反転した座標で描く
    static func local(_ ctx: GraphicsContext, at p: CGPoint, scale: Double, angle: Double = 0, flip: Bool = false) -> GraphicsContext {
        var c: GraphicsContext = ctx
        c.translateBy(x: p.x, y: p.y)
        if angle != 0 { c.rotate(by: Angle.radians(angle)) }
        let sx: Double = flip ? -scale : scale
        c.scaleBy(x: sx, y: scale)
        return c
    }

    static func ellipse(_ c: GraphicsContext, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ color: Color) {
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        c.fill(Path(ellipseIn: rect), with: .color(color))
    }

    static func circle(_ c: GraphicsContext, _ cx: Double, _ cy: Double, _ r: Double, _ color: Color) {
        ellipse(c, cx, cy, r * 2, r * 2, color)
    }

    static func line(_ c: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: Double) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    static func curve(_ c: GraphicsContext, _ a: CGPoint, _ control: CGPoint, _ b: CGPoint, _ color: Color, _ width: Double) {
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    static func polygon(_ c: GraphicsContext, _ pts: [CGPoint], _ color: Color) {
        guard let first = pts.first else { return }
        var path = Path()
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        c.fill(path, with: .color(color))
    }

    /// やわらかい光（放射状のグラデーション。ぼかしは使わない）
    static func glow(_ c: GraphicsContext, _ cx: Double, _ cy: Double, _ r: Double, _ color: Color, _ alpha: Double) {
        let center = CGPoint(x: cx, y: cy)
        let stops: [Gradient.Stop] = [
            Gradient.Stop(color: color.opacity(alpha), location: 0),
            Gradient.Stop(color: color.opacity(alpha * 0.4), location: 0.45),
            Gradient.Stop(color: color.opacity(0), location: 1),
        ]
        let shade = GraphicsContext.Shading.radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: r)
        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        c.fill(Path(ellipseIn: rect), with: shade)
    }

    static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    /// CGFloat のまま点を作る（ウィジェットの小さな絵の中心など）
    static func cpt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// 0〜1 の中で、a〜b の区間の進み（外は 0 か 1）
    static func span(_ r: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (r - a) / (b - a))) }

    /// ゆっくり始まりゆっくり終わる
    static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// 弾んで落ち着く（0→1。少し行き過ぎて戻る）
    static func bounce(_ x: Double) -> Double {
        let c: Double = max(0, min(1, x))
        let decay: Double = exp(-5 * c)
        let wave: Double = cos(c * 10)
        return 1 - decay * wave
    }
}
