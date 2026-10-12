import SwiftUI

// MARK: - 空：背景はいまの時刻の空（明け方・昼・夕方・夜）。やわらかな雲がゆっくり流れる
// 天気は、起床の画面が保存した天気（wake-weather.json、6時間以内）が読めればそれで雲の量と灰色を決める。読めなければ時刻だけ。
// 色の組（文字の色など）も時刻で変わる（夜は暗い色合い）。画面写真用に起動引数 -skyhour <0〜23> で時刻を決められる。

enum SkyPhase: String {
    case dawn, day, dusk, night

    /// いまの時刻の空
    @_optimize(none)
    static func current(_ date: Date = .now) -> SkyPhase {
        let args: [String] = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-skyhour"), i + 1 < args.count, let h = Int(args[i + 1]) {
            return at(minutes: h * 60 + 10)
        }
        let c: DateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
        return at(minutes: (c.hour ?? 12) * 60 + (c.minute ?? 0))
    }

    @_optimize(none)
    static func at(minutes m: Int) -> SkyPhase {
        switch m {
        case (4 * 60 + 30)..<(7 * 60): return .dawn
        case (7 * 60)..<(16 * 60 + 30): return .day
        case (16 * 60 + 30)..<(18 * 60 + 30): return .dusk
        default: return .night
        }
    }

    var isNight: Bool { self == .night }

    /// 一日の中の分（0〜1440。-skyhour があればその時刻の 10 分）
    @_optimize(none)
    static func minuteOfDay(_ date: Date = .now) -> Double {
        let args: [String] = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-skyhour"), i + 1 < args.count, let h = Int(args[i + 1]) {
            return Double(h * 60 + 10)
        }
        let c: DateComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h: Double = Double(c.hour ?? 12)
        let m: Double = Double(c.minute ?? 0)
        let s: Double = Double(c.second ?? 0)
        return h * 60 + m + s / 60
    }

    /// 空のグラデーションの色（上から下へ。0xRRGGBB）
    var hexes: [UInt32] {
        switch self {
        case .dawn: [0xB7C1EC, 0xD9C6E2, 0xF5CDBE, 0xFFE3BC]
        case .day: [0x8EC2EE, 0xA9D2F2, 0xCDE5F7, 0xEEF6FC]
        case .dusk: [0xC2B4E4, 0xE6B4C4, 0xF4B28E, 0xFFD49C]
        case .night: [0x090F2A, 0x121A42, 0x1D2552, 0x2A2F5E]
        }
    }

    /// 空のグラデーション（上から下へ）
    var colors: [Color] { hexes.map { (v: UInt32) -> Color in sceneColor(v) } }

    /// 時刻でゆっくり移り変わる空の色。昼は朝の色から昼の青へ、午後は夕方の色へ少しずつ寄る。
    /// 明け方と夕方も、その時間の中で少しずつ明るさが変わる。夜との境は文字の色が変わるので混ぜない
    @_optimize(none)
    static func blendedColors(minutes m: Double) -> [Color] {
        let phase: SkyPhase = at(minutes: Int(m))
        let a: [UInt32]
        let b: [UInt32]
        let k: Double
        switch phase {
        case .day:
            if m < 8.5 * 60 {
                a = SkyPhase.dawn.hexes; b = SkyPhase.day.hexes; k = 0.35 + 0.65 * max(0, (m - 420) / 90)
            } else if m > 14.5 * 60 {
                a = SkyPhase.day.hexes; b = SkyPhase.dusk.hexes; k = 0.55 * min(1, (m - 870) / 120)
            } else {
                a = SkyPhase.day.hexes; b = SkyPhase.day.hexes; k = 0
            }
            return mix(a, b, k)
        case .dawn:
            a = SkyPhase.dawn.hexes; b = SkyPhase.day.hexes; k = 0.3 * max(0, (m - 270) / 150)
            return mix(a, b, k)
        case .dusk:
            a = SkyPhase.day.hexes; b = SkyPhase.dusk.hexes; k = 0.6 + 0.4 * min(1, max(0, (m - 990) / 60))
            return mix(a, b, k)
        case .night:
            return phase.colors
        }
    }

    @_optimize(none)
    static func mix(_ a: [UInt32], _ b: [UInt32], _ k: Double) -> [Color] {
        var out: [Color] = []
        let kk: Double = max(0, min(1, k))
        for i in 0..<min(a.count, b.count) {
            out.append(mixColor(a[i], b[i], kk))
        }
        return out
    }

    @_optimize(none)
    static func mixColor(_ a: UInt32, _ b: UInt32, _ k: Double) -> Color {
        let ar: Double = Double((a >> 16) & 0xFF)
        let ag: Double = Double((a >> 8) & 0xFF)
        let ab: Double = Double(a & 0xFF)
        let br: Double = Double((b >> 16) & 0xFF)
        let bg: Double = Double((b >> 8) & 0xFF)
        let bb: Double = Double(b & 0xFF)
        let r: Double = (ar + (br - ar) * k) / 255
        let g: Double = (ag + (bg - ag) * k) / 255
        let bl: Double = (ab + (bb - ab) * k) / 255
        return Color(red: r, green: g, blue: bl)
    }

    /// この時刻の色の組。文字/背景・文字/カード・onAccent/accent はどれも 4.5:1 以上
    var palette: Palette {
        switch self {
        case .day:
            return Palette(background: colors, card: sceneColor(0xF7FBFF), text: sceneColor(0x0F2A44), sub: sceneColor(0x2B4560),
                           accent: sceneColor(0x174E7C), overdue: sceneColor(0x9A2C14), onAccent: .white,
                           fontDesign: .rounded, radius: 28, scheme: .light, world: .sky)
        case .dawn:
            return Palette(background: colors, card: sceneColor(0xFFFAF6), text: sceneColor(0x2A1F3D), sub: sceneColor(0x4E3E5C),
                           accent: sceneColor(0x7E3245), overdue: sceneColor(0x8F2A12), onAccent: .white,
                           fontDesign: .rounded, radius: 28, scheme: .light, world: .sky)
        case .dusk:
            return Palette(background: colors, card: sceneColor(0xFFF8F2), text: sceneColor(0x2A1A2E), sub: sceneColor(0x4D3446),
                           accent: sceneColor(0x6E2B48), overdue: sceneColor(0x8A2810), onAccent: .white,
                           fontDesign: .rounded, radius: 28, scheme: .light, world: .sky)
        case .night:
            return Palette(background: colors, card: sceneColor(0x1E2A55), text: sceneColor(0xEEF2FF), sub: sceneColor(0xBAC3E8),
                           accent: sceneColor(0xFFD27A), overdue: sceneColor(0xFFA98A), onAccent: sceneColor(0x1A1A33),
                           fontDesign: .rounded, radius: 28, scheme: .dark, world: .sky)
        }
    }
}

/// 起床の画面が保存した天気から、雲の量（0〜1）と雨かどうかだけを読む（軽い。10分ごとに読み直す）
enum SkyWeather {
    private struct Peek: Decodable {
        let fetchedAt: Date
        let code: Int
    }

    struct Mood { let clouds: Double; let rain: Bool }

    private static var cached: (at: Date, mood: Mood)?

    @_optimize(none)
    static func current(_ now: Date = .now) -> Mood {
        if let c = cached, now.timeIntervalSince(c.at) < 600 { return c.mood }
        var mood = Mood(clouds: 0.25, rain: false)
        if !ProcessInfo.processInfo.arguments.contains("-demo"),
           let w = SharedStore.load(Peek.self, from: "wake-weather.json"),
           now.timeIntervalSince(w.fetchedAt) < 6 * 3600 {
            mood = moodFor(code: w.code)
        }
        cached = (now, mood)
        return mood
    }

    @_optimize(none)
    static func moodFor(code: Int) -> Mood {
        switch code {
        case 0: return Mood(clouds: 0.1, rain: false)
        case 1: return Mood(clouds: 0.25, rain: false)
        case 2: return Mood(clouds: 0.55, rain: false)
        case 3, 45, 48: return Mood(clouds: 0.9, rain: false)
        case 51...67, 80...82, 95...99: return Mood(clouds: 1, rain: true)
        case 71...77, 85, 86: return Mood(clouds: 0.85, rain: false)
        default: return Mood(clouds: 0.25, rain: false)
        }
    }
}

enum SkyScene {
    struct Cloud { let y: Double; let x: Double; let scale: Double; let speed: Double; let seed: UInt64 }

    static let clouds: [Cloud] = [
        Cloud(y: 0.13, x: 0.1, scale: 1.0, speed: 0.006, seed: 1),
        Cloud(y: 0.31, x: 0.75, scale: 0.8, speed: 0.009, seed: 2),
        Cloud(y: 0.52, x: 0.35, scale: 1.15, speed: 0.005, seed: 3),
        Cloud(y: 0.7, x: 0.9, scale: 0.9, speed: 0.008, seed: 4),
        Cloud(y: 0.86, x: 0.2, scale: 1.3, speed: 0.004, seed: 5),
        Cloud(y: 0.22, x: 0.45, scale: 0.7, speed: 0.011, seed: 6),
        Cloud(y: 0.42, x: 0.05, scale: 0.95, speed: 0.007, seed: 7),
    ]

    /// 夜の星
    static let stars: [CGPoint] = {
        var rnd = SceneRandom(404)
        var out: [CGPoint] = []
        for _ in 0..<46 { out.append(CGPoint(x: rnd.next(), y: rnd.range(0, 0.7))) }
        return out
    }()

    /// 1つの雲（ふちのやわらかい楕円を重ねる。ぼかしは使わない）
    @_optimize(none)
    static func drawCloud(_ ctx: GraphicsContext, at c: CGPoint, width: Double, color: Color, seed: UInt64) {
        var rnd = SceneRandom(seed)
        let puffs: Int = 5
        for i in 0..<puffs {
            let fx: Double = Double(i) / Double(puffs - 1) - 0.5
            let pw: Double = width * rnd.range(0.38, 0.55)
            let ph: Double = pw * rnd.range(0.55, 0.75)
            let px: Double = c.x + fx * width * 0.62
            let py: Double = c.y - (0.25 - abs(fx)) * ph * 0.7 + rnd.range(-3, 3)
            let center = CGPoint(x: px, y: py)
            let shade = GraphicsContext.Shading.radialGradient(
                Gradient(stops: [Gradient.Stop(color: color, location: 0), Gradient.Stop(color: color.opacity(0.55), location: 0.55),
                                 Gradient.Stop(color: color.opacity(0), location: 1)]),
                center: center, startRadius: 0, endRadius: pw / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: px - pw / 2, y: py - ph / 2, width: pw, height: ph)), with: shade)
        }
    }

    /// 遠くのすじ雲（いちばんゆっくり流れる）
    static let cirrus: [Cloud] = [
        Cloud(y: 0.08, x: 0.3, scale: 1.1, speed: 0.0022, seed: 21),
        Cloud(y: 0.18, x: 0.8, scale: 0.9, speed: 0.0028, seed: 22),
        Cloud(y: 0.36, x: 0.1, scale: 1.0, speed: 0.0018, seed: 23),
        Cloud(y: 0.6, x: 0.6, scale: 0.8, speed: 0.0025, seed: 24),
    ]

    /// 手前の大きな雲（いちばん速く流れる。うすく）
    static let nearClouds: [Cloud] = [
        Cloud(y: 0.62, x: 0.2, scale: 1.7, speed: 0.016, seed: 31),
        Cloud(y: 0.95, x: 0.75, scale: 1.9, speed: 0.013, seed: 32),
    ]

    @_optimize(none)
    static func draw(_ ctx: GraphicsContext, size: CGSize, t: Double, phase: SkyPhase, mood: SkyWeather.Mood, compact: Bool) {
        let w: Double = Double(size.width)
        let h: Double = Double(size.height)
        if phase.isNight {
            for (i, s) in stars.enumerated() where !compact || i % 2 == 0 {
                let tw: Double = t == 0 ? 0.6 : 0.4 + 0.4 * sin(t * 1.3 + Double(i))
                let r: Double = i % 7 == 0 ? 1.3 : 0.8
                let rect = CGRect(x: s.x * w - r, y: s.y * h - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(tw * (1 - mood.clouds * 0.6))))
            }
        }
        if !compact {
            // 太陽・月は時刻で空を弧を描いて進む（雲の奥）
            let minutes: Double = SkyPhase.minuteOfDay(Date())
            drawSunMoon(ctx, w: w, h: h, minutes: minutes, phase: phase, mood: mood)
        }
        let cloudColor: Color
        switch phase {
        case .night: cloudColor = sceneColor(0x8C95C8, 0.16 + mood.clouds * 0.12)
        case .dusk: cloudColor = sceneColor(0xFFF1EA, 0.55 + mood.clouds * 0.2)
        case .dawn: cloudColor = sceneColor(0xFFF6F2, 0.55 + mood.clouds * 0.2)
        case .day: cloudColor = Color.white.opacity(0.62 + mood.clouds * 0.25)
        }
        // 奥：すじ雲（ゆっくり）
        if !compact {
            for c in cirrus {
                let cw: Double = w * 0.7 * c.scale
                let x: Double = wrapX(c.x, t: t, speed: c.speed, w: w, cw: cw)
                drawCirrus(ctx, at: CGPoint(x: x, y: c.y * h), width: cw, color: cloudColor.opacity(0.55), seed: c.seed)
            }
        }
        // 中：ふつうの雲
        let count: Int = min(clouds.count, 3 + Int(mood.clouds * 4.5))
        for c in clouds.prefix(count) {
            let cw: Double = w * 0.62 * c.scale * (compact ? 1.2 : 1)
            let x: Double = wrapX(c.x, t: t, speed: c.speed, w: w, cw: cw)
            drawCloud(ctx, at: CGPoint(x: x, y: c.y * h), width: cw, color: cloudColor, seed: c.seed)
        }
        guard !compact else { return }
        // 飛行機と飛行機雲（ときどき。夜は住人の層が灯りの点滅する飛行機を描くので出さない。止まった絵でも出さない）
        if t != 0 && !phase.isNight {
            drawPlane(ctx, w: w, h: h, t: t, night: phase.isNight)
        }
        // 手前：大きくうすい雲（速く流れて、奥行きが出る）
        for c in nearClouds {
            let cw: Double = w * 0.62 * c.scale
            let x: Double = wrapX(c.x, t: t, speed: c.speed, w: w, cw: cw)
            drawCloud(ctx, at: CGPoint(x: x, y: c.y * h), width: cw, color: cloudColor.opacity(0.3), seed: c.seed)
        }
    }

    @_optimize(none)
    static func wrapX(_ x0: Double, t: Double, speed: Double, w: Double, cw: Double) -> Double {
        let span: Double = w + cw
        let raw: Double = (x0 * span + t * speed * w).truncatingRemainder(dividingBy: span)
        return raw - cw / 2
    }

    /// すじ雲（横に長くうすい帯を3本ずらして重ねる）
    @_optimize(none)
    static func drawCirrus(_ ctx: GraphicsContext, at c: CGPoint, width: Double, color: Color, seed: UInt64) {
        var rnd = SceneRandom(seed)
        let cx: Double = Double(c.x)
        let cy: Double = Double(c.y)
        for _ in 0..<3 {
            let dx: Double = rnd.range(-0.2, 0.2) * width
            let dy: Double = rnd.range(-6, 6)
            let rx: Double = width * rnd.range(0.3, 0.45)
            let ry: Double = rnd.range(2.5, 4.5)
            var e: GraphicsContext = ctx
            e.translateBy(x: cx + dx, y: cy + dy)
            e.rotate(by: Angle.radians(rnd.range(-0.06, 0.04)))
            e.scaleBy(x: rx / ry, y: 1)
            let g = Gradient(stops: [Gradient.Stop(color: color, location: 0), Gradient.Stop(color: color.opacity(0), location: 1)])
            e.fill(Path(ellipseIn: CGRect(x: -ry, y: -ry, width: ry * 2, height: ry * 2)),
                   with: .radialGradient(g, center: .zero, startRadius: 0, endRadius: ry))
        }
    }

    /// 太陽（5時〜19時に左下から右下へ弧を描く）と月（18時半〜4時半）
    @_optimize(none)
    static func drawSunMoon(_ ctx: GraphicsContext, w: Double, h: Double, minutes m: Double, phase: SkyPhase, mood: SkyWeather.Mood) {
        let dim: Double = 1 - mood.clouds * 0.55
        if phase.isNight {
            let since: Double = m >= 1110 ? m - 1110 : m + 330
            let f: Double = max(0, min(1, since / 600))
            let x: Double = w * (0.1 + 0.8 * f)
            let y: Double = h * (0.3 - 0.22 * sin(f * Double.pi))
            CritterDraw.glow(ctx, x, y, w * 0.5, sceneColor(0xDDE4FF), 0.26 * dim)
            CritterDraw.glow(ctx, x, y, 30, sceneColor(0xF4F1E4), 0.3 * dim)
            let disc = Path(ellipseIn: CGRect(x: x - 13, y: y - 13, width: 26, height: 26))
            let bite = Path(ellipseIn: CGRect(x: x - 4, y: y - 15, width: 22, height: 22))
            var mc: GraphicsContext = ctx
            mc.clip(to: bite, options: .inverse)
            mc.fill(disc, with: .color(sceneColor(0xF4F1E4, 0.95)))
            CritterDraw.circle(mc, x - 6, y + 3, 1.6, sceneColor(0xD9D4C2, 0.8))
            CritterDraw.circle(mc, x - 4, y - 5, 1.1, sceneColor(0xD9D4C2, 0.7))
            return
        }
        let f: Double = max(0, min(1, (m - 300) / 840))
        let x: Double = w * (0.08 + 0.84 * f)
        let y: Double = h * (0.34 - 0.27 * sin(f * Double.pi))
        let low: Double = 1 - sin(f * Double.pi)
        let warm: UInt32 = low > 0.55 ? 0xFFCB8A : 0xFFF2CC
        CritterDraw.glow(ctx, x, y, w * 0.85, sceneColor(warm), 0.75 * dim)
        CritterDraw.glow(ctx, x, y, 44, sceneColor(0xFFFBEA), 0.6 * dim)
        let core = Gradient(colors: [sceneColor(0xFFFFF6), sceneColor(0xFFF0B8), sceneColor(warm)])
        let disc = Path(ellipseIn: CGRect(x: x - 14, y: y - 14, width: 28, height: 28))
        var sc: GraphicsContext = ctx
        sc.opacity = 0.35 + 0.65 * dim
        sc.fill(disc, with: .radialGradient(core, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 14))
    }

    /// 飛行機と飛行機雲（40秒ごとに 22秒かけて高いところを横切る。向きは交互）
    @_optimize(none)
    static func drawPlane(_ ctx: GraphicsContext, w: Double, h: Double, t: Double, night: Bool) {
        let period: Double = 40
        let cycle: Double = floor(t / period)
        let ph: Double = t - cycle * period
        let dur: Double = 22
        guard ph < dur + 6 else { return }
        var rnd = SceneRandom(UInt64(max(0, cycle)) &+ 5)
        let y: Double = h * rnd.range(0.07, 0.2)
        let dir: Double = Int(cycle) % 2 == 0 ? 1 : -1
        let k: Double = min(1, ph / dur)
        let x0: Double = dir > 0 ? -30 : w + 30
        let x: Double = x0 + dir * k * (w + 60)
        let climb: Double = -k * 10
        let px: Double = x
        let py: Double = y + climb
        // 飛行機雲：機体のうしろへ、古いほど太くうすく
        let fade: Double = ph > dur ? 1 - (ph - dur) / 6 : 1
        let trailA: Double = (night ? 0.16 : 0.55) * fade
        let len: Double = min(170, abs(px - x0))
        let headX: Double = px - dir * 5
        let tailX: Double = px - dir * len
        let tailY: Double = py + len * 10 / (w + 60)
        let head: CGPoint = CGPoint(x: headX, y: py)
        let tail: CGPoint = CGPoint(x: tailX, y: tailY)
        let thin = Gradient(colors: [Color.white.opacity(trailA), Color.white.opacity(0)])
        let wide = Gradient(colors: [Color.white.opacity(trailA * 0.25), Color.white.opacity(trailA * 0.18), Color.white.opacity(0)])
        // 広がったうすい帯と、2本の細い線（エンジンの数）
        var spread = Path()
        spread.move(to: head)
        spread.addLine(to: tail)
        ctx.stroke(spread, with: .linearGradient(wide, startPoint: head, endPoint: tail), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        for off in [-1.1, 1.1] {
            var p = Path()
            p.move(to: CGPoint(x: headX, y: py + off))
            p.addLine(to: CGPoint(x: tailX, y: tailY + off * 1.8))
            ctx.stroke(p, with: .linearGradient(thin, startPoint: head, endPoint: tail), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }
        guard ph < dur else { return }
        // 機体（小さく）
        var c: GraphicsContext = ctx
        c.translateBy(x: px, y: py)
        c.scaleBy(x: dir, y: 1)
        let body: Color = night ? sceneColor(0x6C75A8) : sceneColor(0xF8FAFF)
        var fuselage = Path()
        fuselage.move(to: CGPoint(x: -6, y: 0))
        fuselage.addLine(to: CGPoint(x: 6, y: 0))
        c.stroke(fuselage, with: .color(body), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        var wing = Path()
        wing.move(to: CGPoint(x: 1, y: 0))
        wing.addLine(to: CGPoint(x: -2.5, y: 4))
        wing.move(to: CGPoint(x: 1, y: 0))
        wing.addLine(to: CGPoint(x: -1.5, y: -2.6))
        wing.move(to: CGPoint(x: -5, y: 0))
        wing.addLine(to: CGPoint(x: -6.5, y: -2.4))
        c.stroke(wing, with: .color(body), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        let blink: Bool = (t * 1.2).truncatingRemainder(dividingBy: 1) < 0.18
        if blink {
            CritterDraw.glow(c, 0, 1, 4, night ? sceneColor(0xFF6B6B) : Color.white, 0.9)
        }
    }
}

/// 空の全画面の背景
struct SkyBackdrop: View {
    let p: Palette
    var still: Bool = false
    var compact: Bool = false
    /// 止まった絵の時刻（ウィジェット用。entry.date から）
    var stillT: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phase: SkyPhase = SkyPhase.current()
        let mood: SkyWeather.Mood = SkyWeather.current()
        let minutes: Double = SkyPhase.minuteOfDay()
        let skyColors: [Color] = compact ? phase.colors : SkyPhase.blendedColors(minutes: minutes)
        GeometryReader { geo in
            let size: CGSize = geo.size
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            ZStack {
                LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
                light(phase, size: size)
                if mood.clouds > 0.5 && !phase.isNight {
                    // くもり・雨は空全体を少し灰色に
                    let veil: Double = (mood.clouds - 0.5) * (mood.rain ? 0.7 : 0.5)
                    sceneColor(0x9AA6B2, veil)
                }
                SceneClock(fps: 15, animated: animated, stillT: stillT) { t in
                    Canvas { ctx, s in
                        SkyScene.draw(ctx, size: s, t: t, phase: phase, mood: mood, compact: compact)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    /// 太陽・月の光。画面では太陽と月は Canvas が時刻の弧に描くので、ここは明け方・夕方の地平の光だけ。
    /// ウィジェット（compact）は止まった絵なので、昼は右上・夜は月をここで描く
    @ViewBuilder
    private func light(_ phase: SkyPhase, size: CGSize) -> some View {
        let w: CGFloat = size.width
        switch phase {
        case .day:
            if compact {
                glow(sceneColor(0xFFF6D6, 0.95), at: UnitPoint(x: 0.95, y: 0.02), r: w * 0.75)
            }
        case .dawn:
            glow(sceneColor(0xFFE0B0, 0.9), at: UnitPoint(x: 0.15, y: 1.0), r: w * 1.0)
        case .dusk:
            glow(sceneColor(0xFFC27A, 0.85), at: UnitPoint(x: 0.85, y: 1.0), r: w * 1.05)
        case .night:
            if compact {
                ZStack {
                    glow(sceneColor(0xDDE4FF, 0.28), at: UnitPoint(x: 0.6, y: 0.07), r: w * 0.5)
                    Circle().fill(sceneColor(0xF4F1E4)).frame(width: 26, height: 26)
                        .overlay(Circle().fill(sceneColor(0x121A42)).frame(width: 22, height: 22).offset(x: 7, y: -4))
                        .position(x: w * 0.6, y: size.height * 0.07)
                }
            }
        }
    }

    private func glow(_ c: Color, at center: UnitPoint, r: CGFloat) -> some View {
        RadialGradient(colors: [c, c.opacity(0.35), c.opacity(0)], center: center, startRadius: 0, endRadius: r)
    }
}

/// 空のカード：雲のようにやわらかい白い板と、まわりのうすい光の輪
struct SkyCloudCard: View {
    let p: Palette
    var radius: CGFloat? = nil
    var light: Bool = false

    var body: some View {
        let r: CGFloat = radius ?? p.radius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let night: Bool = p.scheme == .dark
        let halo: Color = night ? Color.white.opacity(0.07) : Color.white.opacity(0.3)
        let shadow: Color = night ? Color.black.opacity(0.3) : sceneColor(0x285A8C, 0.16)
        ZStack {
            if !light {
                shape.inset(by: -6).fill(halo.opacity(0.4))
                shape.inset(by: -3).fill(halo)
            }
            shape.fill(p.card.opacity(light ? (night ? 0.9 : 0.93) : 1))
            if night {
                shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .shadow(color: shadow, radius: light ? 4 : 16, x: 0, y: light ? 2 : 10)
    }
}
