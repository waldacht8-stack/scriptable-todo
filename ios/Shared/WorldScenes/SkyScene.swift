import SwiftUI

// MARK: - 空：背景はいまの時刻の空（明け方・昼・夕方・夜）。やわらかな雲がゆっくり流れる
// 天気は、起床の画面が保存した天気（wake-weather.json、6時間以内）が読めればそれで雲の量と灰色を決める。読めなければ時刻だけ。
// 色の組（文字の色など）も時刻で変わる（夜は暗い色合い）。画面写真用に起動引数 -skyhour <0〜23> で時刻を決められる。

enum SkyPhase: String {
    case dawn, day, dusk, night

    /// いまの時刻の空
    static func current(_ date: Date = .now) -> SkyPhase {
        let args: [String] = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-skyhour"), i + 1 < args.count, let h = Int(args[i + 1]) {
            return at(minutes: h * 60 + 10)
        }
        let c: DateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
        return at(minutes: (c.hour ?? 12) * 60 + (c.minute ?? 0))
    }

    static func at(minutes m: Int) -> SkyPhase {
        switch m {
        case (4 * 60 + 30)..<(7 * 60): return .dawn
        case (7 * 60)..<(16 * 60 + 30): return .day
        case (16 * 60 + 30)..<(18 * 60 + 30): return .dusk
        default: return .night
        }
    }

    var isNight: Bool { self == .night }

    /// 空のグラデーション（上から下へ）
    var colors: [Color] {
        switch self {
        case .dawn: [sceneColor(0xB7C1EC), sceneColor(0xD9C6E2), sceneColor(0xF5CDBE), sceneColor(0xFFE3BC)]
        case .day: [sceneColor(0x8EC2EE), sceneColor(0xA9D2F2), sceneColor(0xCDE5F7), sceneColor(0xEEF6FC)]
        case .dusk: [sceneColor(0xC2B4E4), sceneColor(0xE6B4C4), sceneColor(0xF4B28E), sceneColor(0xFFD49C)]
        case .night: [sceneColor(0x090F2A), sceneColor(0x121A42), sceneColor(0x1D2552), sceneColor(0x2A2F5E)]
        }
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
        let count: Int = min(clouds.count, 3 + Int(mood.clouds * 4.5))
        let cloudColor: Color
        switch phase {
        case .night: cloudColor = sceneColor(0x8C95C8, 0.16 + mood.clouds * 0.12)
        case .dusk: cloudColor = sceneColor(0xFFF1EA, 0.55 + mood.clouds * 0.2)
        case .dawn: cloudColor = sceneColor(0xFFF6F2, 0.55 + mood.clouds * 0.2)
        case .day: cloudColor = Color.white.opacity(0.62 + mood.clouds * 0.25)
        }
        for c in clouds.prefix(count) {
            let cw: Double = w * 0.62 * c.scale * (compact ? 1.2 : 1)
            let span: Double = w + cw
            let x: Double = (c.x * span + t * c.speed * w).truncatingRemainder(dividingBy: span) - cw / 2
            drawCloud(ctx, at: CGPoint(x: x, y: c.y * h), width: cw, color: cloudColor, seed: c.seed)
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
        GeometryReader { geo in
            let size: CGSize = geo.size
            let animated: Bool = SceneMotion.animated(reduceMotion: reduceMotion, size: size, still: still)
            ZStack {
                LinearGradient(colors: phase.colors, startPoint: .top, endPoint: .bottom)
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

    /// 太陽・月の光（昼は右上、明け方は左下の地平、夕方は右下の地平、夜は月）
    @ViewBuilder
    private func light(_ phase: SkyPhase, size: CGSize) -> some View {
        let w: CGFloat = size.width
        switch phase {
        case .day:
            glow(sceneColor(0xFFF6D6, 0.95), at: UnitPoint(x: 0.95, y: 0.02), r: w * 0.75)
        case .dawn:
            glow(sceneColor(0xFFE0B0, 0.9), at: UnitPoint(x: 0.15, y: 1.0), r: w * 1.0)
        case .dusk:
            glow(sceneColor(0xFFC27A, 0.85), at: UnitPoint(x: 0.85, y: 1.0), r: w * 1.05)
        case .night:
            ZStack {
                glow(sceneColor(0xDDE4FF, 0.28), at: UnitPoint(x: 0.6, y: 0.07), r: w * 0.5)
                Circle().fill(sceneColor(0xF4F1E4)).frame(width: 26, height: 26)
                    .overlay(Circle().fill(sceneColor(0x121A42)).frame(width: 22, height: 22).offset(x: 7, y: -4))
                    .position(x: w * 0.6, y: size.height * 0.07)
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
