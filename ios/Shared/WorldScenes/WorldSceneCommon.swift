import SwiftUI

// MARK: - 世界観の背景の共通部品（地層・銀河・空・霧・深海）
// 画面ではゆっくり動き、ウィジェット・設定の見本・「視差効果を減らす」では止まった絵になる。
// 動きは TimelineView（低いフレームレート）か repeatForever の簡単なアニメーションだけ。1つずつの重いぼかしは使わない。

/// 0xRRGGBB から色を作る（世界観の背景・カードの飾りの色）
func sceneColor(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

/// 決まった並びの乱数（星・砂粒などの位置を毎回同じにする）
struct SceneRandom {
    private var state: UInt64

    init(_ seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    /// 0〜1
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits: UInt64 = (state >> 33) & 0x7FFF_FFFF
        return Double(bits) / Double(0x7FFF_FFFF)
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

/// 時計つきの描画。animated が false なら t = 0 の止まった絵を1枚だけ描く
struct SceneClock<Content: View>: View {
    let fps: Double
    let animated: Bool
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / fps)) { ctx in
                content(ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            content(0)
        }
    }
}

/// 左右にゆっくり行き来する（霧の層など）。止まっているときは真ん中
struct SceneDrift: ViewModifier {
    let animated: Bool
    let distance: CGFloat
    let duration: Double
    var reverse: Bool = false
    @State private var on: Bool = false

    func body(content: Content) -> some View {
        let start: CGFloat = reverse ? distance : -distance
        let x: CGFloat = animated ? (on ? -start : start) : 0
        return content
            .offset(x: x)
            .onAppear {
                guard animated else { return }
                let anim: Animation = Animation.easeInOut(duration: duration).repeatForever(autoreverses: true)
                withAnimation(anim) { on = true }
            }
    }
}

/// 明るさがゆっくり脈打つ（光の筋など）
struct ScenePulse: ViewModifier {
    let animated: Bool
    let low: Double
    let high: Double
    let duration: Double
    var delay: Double = 0
    @State private var on: Bool = false

    func body(content: Content) -> some View {
        let shown: Double = animated ? (on ? high : low) : (low + high) / 2
        return content
            .opacity(shown)
            .onAppear {
                guard animated else { return }
                let anim: Animation = Animation.easeInOut(duration: duration).repeatForever(autoreverses: true).delay(delay)
                withAnimation(anim) { on = true }
            }
    }
}

/// ゆっくり回り続ける（銀河の腕）
struct SceneSpin: ViewModifier {
    let animated: Bool
    let period: Double
    @State private var on: Bool = false

    func body(content: Content) -> some View {
        let angle: Double = animated && on ? 360 : 0
        return content
            .rotationEffect(Angle.degrees(angle))
            .onAppear {
                guard animated else { return }
                let anim: Animation = Animation.linear(duration: period).repeatForever(autoreverses: false)
                withAnimation(anim) { on = true }
            }
    }
}

extension View {
    func sceneDrift(_ animated: Bool, distance: CGFloat, duration: Double, reverse: Bool = false) -> some View {
        modifier(SceneDrift(animated: animated, distance: distance, duration: duration, reverse: reverse))
    }

    func scenePulse(_ animated: Bool, low: Double, high: Double, duration: Double, delay: Double = 0) -> some View {
        modifier(ScenePulse(animated: animated, low: low, high: high, duration: duration, delay: delay))
    }

    func sceneSpin(_ animated: Bool, period: Double) -> some View {
        modifier(SceneSpin(animated: animated, period: period))
    }
}

/// 背景を動かすか。「視差効果を減らす」がオン、または小さな見本（設定のサムネイル）なら止める
enum SceneMotion {
    static func animated(reduceMotion: Bool, size: CGSize, still: Bool) -> Bool {
        !still && !reduceMotion && size.width > 220
    }
}
