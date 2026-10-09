import SwiftUI
import UIKit

// スプラトゥーンらしい見た目の部品。色はこの画面だけの決まった色（暗い下地＋ネオンのインク）。
// 文字は下地とのコントラスト 4.5:1 以上になる組み合わせだけ使う（ネオン色の上は暗い文字）。

enum SplatInk {
    static let base = Color(red: 0x17 / 255, green: 0x13 / 255, blue: 0x1F / 255)       // #17131F
    static let panel = Color(red: 0x24 / 255, green: 0x1E / 255, blue: 0x31 / 255)      // #241E31
    static let panelHi = Color(red: 0x30 / 255, green: 0x28 / 255, blue: 0x42 / 255)    // #302842
    static let lime = Color(red: 0xEA / 255, green: 0xFF / 255, blue: 0x3D / 255)       // #EAFF3D
    static let purple = Color(red: 0x7B / 255, green: 0x2F / 255, blue: 0xF7 / 255)     // #7B2FF7（面だけ。文字には使わない）
    static let lavender = Color(red: 0xA9 / 255, green: 0x7B / 255, blue: 0xFF / 255)   // #A97BFF（負けの滴・文字にも可）
    static let orange = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x1A / 255)     // #FF7A1A
    static let mint = Color(red: 0x3D / 255, green: 0xF5 / 255, blue: 0xC0 / 255)       // #3DF5C0
    static let sky = Color(red: 0x5C / 255, green: 0xC8 / 255, blue: 0xFF / 255)        // #5CC8FF
    static let pink = Color(red: 0xFF / 255, green: 0x6F / 255, blue: 0xCF / 255)       // #FF6FCF
    static let salmon = Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0x7A / 255)     // #FF9A7A
    static let text = Color.white
    static let sub = Color(red: 0xC4 / 255, green: 0xBC / 255, blue: 0xD6 / 255)        // #C4BCD6（下地に対して約10:1）
    static let ink = Color(red: 0x14 / 255, green: 0x10 / 255, blue: 0x1C / 255)        // ネオン色の上の文字

    static func mode(_ m: SplatMode) -> Color {
        switch m {
        case .regular: return lime
        case .bankaraChallenge, .bankaraOpen: return orange
        case .x: return mint
        case .event: return pink
        case .festOpen, .festChallenge: return sky
        }
    }

    /// stat.ink の lobby の key から
    static func lobby(_ key: String) -> Color {
        if key.hasPrefix("regular") { return lime }
        if key.hasPrefix("bankara") { return orange }
        if key.hasPrefix("xmatch") { return mint }
        if key.hasPrefix("event") { return pink }
        if key.hasPrefix("splatfest") { return sky }
        return sub
    }

    static func lobbyShort(_ key: String, fallback: String) -> String {
        switch key {
        case "regular": return "レギュラー"
        case "bankara_challenge": return "チャレンジ"
        case "bankara_open": return "オープン"
        case "xmatch": return "Xマッチ"
        case "event": return "イベント"
        case "splatfest_open", "splatfest_challenge": return "フェス"
        case "private": return "プライベート"
        default: return fallback.isEmpty ? "バトル" : fallback
        }
    }
}

/// 太く傾いた見出しの文字
enum SplatFont {
    static func display(_ style: Font.TextStyle = .title) -> Font {
        Font.system(style, design: .rounded).weight(.black).italic()
    }

    static func display(size: CGFloat) -> Font {
        Font.system(size: size, weight: .black, design: .rounded).italic()
    }
}

extension View {
    /// 少し右に傾ける（スプラらしい勢い）
    func splatSkew(_ amount: CGFloat = 0.12) -> some View {
        transformEffect(CGAffineTransform(a: 1, b: 0, c: -amount, d: 1, tx: 0, ty: 0))
    }
}

/// モードの色の札（暗い文字で読みやすく）
struct SplatChip: View {
    let text: String
    let color: Color
    var small = false

    var body: some View {
        let font: Font = small ? .caption2.weight(.heavy) : .caption.weight(.heavy)
        Text(text)
            .font(font)
            .foregroundStyle(SplatInk.ink)
            .lineLimit(1)
            .padding(.horizontal, small ? 6 : 9)
            .padding(.vertical, small ? 2 : 4)
            .background(color, in: Capsule())
    }
}

/// インクの滴の形（上がとがり、下が丸い）
struct InkDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = w / 2
        let cy = h - r
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + cy),
                   control1: CGPoint(x: rect.midX + r * 0.35, y: rect.minY + h * 0.25),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + cy - r * 0.55))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + cy), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.minX, y: rect.minY + cy - r * 0.55),
                   control2: CGPoint(x: rect.midX - r * 0.35, y: rect.minY + h * 0.25))
        p.closeSubpath()
        return p
    }
}

/// 勝ち（ライム）・負け（むらさき）の滴。中に W / L
struct InkDroplet: View {
    let win: Bool?
    var size: CGFloat = 22

    var body: some View {
        let color: Color = win == true ? SplatInk.lime : (win == false ? SplatInk.lavender : SplatInk.sub)
        let label = win == true ? "W" : (win == false ? "L" : "-")
        ZStack {
            InkDropShape().fill(color)
            Text(label)
                .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                .foregroundStyle(SplatInk.ink)
                .offset(y: size * 0.16)
        }
        .frame(width: size, height: size * 1.3)
        .accessibilityLabel(win == true ? "勝ち" : (win == false ? "負け" : "引き分け"))
    }
}

/// 背景のインクのしみ（ぼかした丸）
struct InkBlobBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                SplatInk.base
                Circle().fill(SplatInk.purple.opacity(0.55))
                    .frame(width: w * 0.9).blur(radius: 60)
                    .offset(x: w * 0.45, y: -w * 0.35)
                Circle().fill(SplatInk.lime.opacity(0.22))
                    .frame(width: w * 0.7).blur(radius: 70)
                    .offset(x: -w * 0.45, y: w * 0.5)
                Circle().fill(SplatInk.purple.opacity(0.35))
                    .frame(width: w * 0.6).blur(radius: 60)
                    .offset(x: -w * 0.3, y: w * 1.4)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
    }
}

/// カードの角のインクしみ（小さな飾り）
struct InkSplash: View {
    var color: Color = SplatInk.lime
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: size, height: size)
            Circle().fill(color).frame(width: size * 0.35).offset(x: size * 0.55, y: size * 0.3)
            Circle().fill(color).frame(width: size * 0.2).offset(x: size * 0.25, y: size * 0.62)
            Circle().fill(color).frame(width: size * 0.16).offset(x: -size * 0.5, y: size * 0.45)
        }
    }
}

// MARK: - 画像（公開 JSON が示すステージ・ブキの画像だけ。メモリと端末に保存して使い回す）

final class SplatImageCache {
    static let shared = SplatImageCache()
    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("splat-img", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 200
    }

    private func file(_ url: URL) -> URL {
        // 画像の URL は中身のハッシュを含むので、最後の部分をそのまま名前にする
        let name = url.lastPathComponent.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent(name)
    }

    func cached(_ url: URL) -> UIImage? {
        if let img = memory.object(forKey: url.absoluteString as NSString) { return img }
        guard let data = try? Data(contentsOf: file(url)), let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: url.absoluteString as NSString)
        return img
    }

    func load(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue(SplatAPI.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              (res as? HTTPURLResponse)?.statusCode ?? 200 < 300,
              let img = UIImage(data: data) else { return nil }
        try? data.write(to: file(url), options: .atomic)
        memory.setObject(img, forKey: url.absoluteString as NSString)
        return img
    }
}

/// 画像（読み込み前・見本のときは名前入りのインクの絵）
struct SplatImage: View {
    let url: String?
    var name: String = ""
    var fill = true

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                let img = Image(uiImage: image).resizable()
                if fill { img.scaledToFill() } else { img.scaledToFit() }
            } else {
                SplatPlaceholder(name: name)
            }
        }
        .task(id: url) {
            guard let s = url, let u = URL(string: s) else { image = nil; return }
            if let c = SplatImageCache.shared.cached(u) { image = c; return }
            image = await SplatImageCache.shared.load(u)
        }
    }
}

/// 画像がないときの代わり（名前から色を決めたインクの模様）
struct SplatPlaceholder: View {
    let name: String

    var body: some View {
        let palette: [Color] = [SplatInk.purple, SplatInk.mint, SplatInk.orange, SplatInk.lime, SplatInk.sky, SplatInk.pink]
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let c1 = palette[h % palette.count]
        let c2 = palette[(h / 7 + 2) % palette.count]
        GeometryReader { geo in
            let w = geo.size.width, hgt = geo.size.height
            ZStack {
                SplatInk.panelHi
                Circle().fill(c1.opacity(0.85)).frame(width: w * 0.8).offset(x: -w * 0.3, y: -hgt * 0.25)
                Circle().fill(c2.opacity(0.75)).frame(width: w * 0.55).offset(x: w * 0.35, y: hgt * 0.3)
                Circle().fill(c1.opacity(0.85)).frame(width: w * 0.12).offset(x: w * 0.1, y: hgt * 0.05)
            }
            .frame(width: w, height: hgt)
            .clipped()
        }
    }
}

// MARK: - 時間の表示

enum SplatTime {
    /// あと 1:23:45 / 12:34
    static func remaining(_ to: Date, now: Date = .now) -> String {
        let s = max(0, Int(to.timeIntervalSince(now)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h >= 24 { return "\(h / 24)日\(h % 24)時間" }
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func range(_ a: Date, _ b: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(a, inSameDayAs: b) || b.timeIntervalSince(a) <= 4 * 3600 {
            return "\(dayPrefix(a))\(JP.time(a))〜\(JP.time(b))"
        }
        return "\(JP.date(a)) \(JP.time(a))〜\(JP.date(b)) \(JP.time(b))"
    }

    static func dayPrefix(_ d: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "明日 " }
        return JP.date(d) + " "
    }

    static func ago(_ d: Date, now: Date = .now) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "たった今" }
        if s < 3600 { return "\(s / 60)分前" }
        if s < 86400 { return "\(s / 3600)時間前" }
        return JP.date(d)
    }
}

// MARK: - 動き（「視差効果を減らす」がオンのときは動かさない）

/// 勝ち負けの滴の列。結果が届いたら、ひとつずつ「ぺちゃっ」と弾んで現れる
struct SplatDropletRow: View {
    let results: [Bool?]
    var size: CGFloat = 22
    var spacing: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        let key = results.map { $0 == true ? "w" : ($0 == false ? "l" : "d") }.joined()
        HStack(spacing: spacing) {
            ForEach(Array(results.enumerated()), id: \.offset) { i, r in
                let visible = reduceMotion || i < shown
                InkDroplet(win: r, size: size)
                    .scaleEffect(visible ? 1 : 0.2, anchor: .bottom)
                    .opacity(visible ? 1 : 0)
            }
        }
        .onAppear { play() }
        .onChange(of: key) { _, _ in play() }
    }

    private func play() {
        guard !reduceMotion else { shown = results.count; return }
        shown = 0
        for i in 0..<results.count {
            let anim: Animation = .spring(response: 0.32, dampingFraction: 0.45).delay(Double(i) * 0.07)
            withAnimation(anim) { shown = max(shown, i + 1) }
        }
    }
}

/// 現れるときに少しぐらっと揺れて、決まった傾きに落ち着く
struct SplatWobble: ViewModifier {
    let angle: Double
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    func body(content: Content) -> some View {
        let start = angle + (angle >= 0 ? -5 : 5)
        let current = (settled || reduceMotion) ? angle : start
        content
            .rotationEffect(.degrees(current))
            .onAppear {
                guard !reduceMotion, !settled else { return }
                let anim: Animation = .interpolatingSpring(stiffness: 170, damping: 7).delay(delay)
                withAnimation(anim) { settled = true }
            }
    }
}

extension View {
    func splatWobble(_ angle: Double, delay: Double = 0) -> some View {
        modifier(SplatWobble(angle: angle, delay: delay))
    }
}

/// 次の切り替えまでの残り時間（数字がくるっと入れ替わる）
struct SplatCountdown: View {
    let to: Date
    var font: Font = .title3.weight(.heavy)
    var color: Color = SplatInk.lime

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let text = SplatTime.remaining(to, now: ctx.date)
            let anim: Animation? = reduceMotion ? nil : .snappy(duration: 0.3)
            Text(text)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: true))
                .animation(anim, value: text)
        }
    }
}
