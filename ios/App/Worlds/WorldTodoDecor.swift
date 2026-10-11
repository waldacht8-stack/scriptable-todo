import SwiftUI

// MARK: - 世界観ごとの TODO の意味づけ（TODO の画面があとで取り入れる部品）
// どれも、その世界観のときだけ効き、ほかの世界観では何もしない。なので TODO の画面は条件なしで付けてよい。
//   霧：期限が遠いほど霧の奥にかすむ（.mistDepth(for:)）
//   深海：期限までの日数を「水深」で出す（DeepSeaDepthLabel）
//   地層：期限を過ぎて古くなるほど下の濃い層の色になる（.strataBand(for:)）。TodoItem に作成日がないので、期限からの経過で「古さ」を決める

enum WorldTodoScene {
    /// 期限までの日数（小数。過ぎていれば負。期限なしは nil）
    static func daysUntilDue(_ t: TodoItem, now: Date = .now) -> Double? {
        guard let due = t.due else { return nil }
        return due.timeIntervalSince(now) / 86400
    }

    /// 深海：期限までの深さ（m）。いま〜今日は浅く、明日で約 40m、2か月先で約 800m
    static func depthMeters(_ t: TodoItem, now: Date = .now) -> Int? {
        guard let d = daysUntilDue(t, now: now) else { return nil }
        if d <= 0 { return 0 }
        if d < 1 {
            return max(1, Int((d * 24 * 1.25).rounded()))
        }
        let m: Double = 40 * pow(d, 0.73)
        let step: Double = m < 200 ? 5 : (m < 1000 ? 50 : 100)
        return min(10000, Int((m / step).rounded() * step))
    }

    /// 深海：「水深 40m」
    static func depthLabel(_ t: TodoItem, now: Date = .now) -> String? {
        guard let m = depthMeters(t, now: now) else { return nil }
        return m == 0 ? "水面" : "水深 \(m)m"
    }

    /// 霧：かすみの強さ（0 = くっきり、1 = いちばん奥）。期限なしは奥
    static func mistAmount(_ t: TodoItem, now: Date = .now) -> Double {
        guard let d = daysUntilDue(t, now: now) else { return 0.8 }
        return max(0, min(1, (d - 0.5) / 10))
    }

    /// 地層：古さ（0 = 新しい上の層、1 = いちばん下の古い層）。期限を過ぎた日数で沈む
    static func strataAge(_ t: TodoItem, now: Date = .now) -> Double {
        guard let d = daysUntilDue(t, now: now) else { return 0.2 }
        if d >= 0 { return max(0, 0.3 - d * 0.05) }
        return min(1, 0.4 + (-d) / 7 * 0.6)
    }

    /// 地層：その古さの層の色（行の下に敷く。文字が読めるよう淡く）
    static func strataTint(_ t: TodoItem, now: Date = .now) -> Color {
        let age: Double = strataAge(t, now: now)
        let colors: [Color] = [sceneColor(0xEEDFC6), sceneColor(0xE1C79A), sceneColor(0xC99A62), sceneColor(0x8E5F36)]
        let i: Int = min(colors.count - 1, Int(age * Double(colors.count - 1) + 0.5))
        return colors[i].opacity(0.35 + age * 0.2)
    }
}

/// 霧：期限が遠いほどぼかして薄くする
private struct MistDepthModifier: ViewModifier {
    @Environment(\.palette) private var p
    let item: TodoItem

    func body(content: Content) -> some View {
        if p.world == .mist && !item.done {
            let a: Double = WorldTodoScene.mistAmount(item)
            content
                .blur(radius: CGFloat(a * 2.4))
                .opacity(1 - a * 0.45)
        } else {
            content
        }
    }
}

/// 地層：古さの層の色を下に敷く
private struct StrataBandModifier: ViewModifier {
    @Environment(\.palette) private var p
    let item: TodoItem

    func body(content: Content) -> some View {
        if p.world == .strata {
            let shape = RoundedRectangle(cornerRadius: max(6, p.radius - 6), style: .continuous)
            content.background(shape.fill(WorldTodoScene.strataTint(item)))
        } else {
            content
        }
    }
}

extension View {
    /// 霧の世界観で、期限が遠い用事ほど霧の奥にかすませる（ほかの世界観では何もしない）
    func mistDepth(for item: TodoItem) -> some View { modifier(MistDepthModifier(item: item)) }

    /// 地層の世界観で、古い用事ほど濃い層の色を敷く（ほかの世界観では何もしない）
    func strataBand(for item: TodoItem) -> some View { modifier(StrataBandModifier(item: item)) }
}

/// 深海の世界観で「水深 40m」を出す（ほかの世界観では何も出さない）
struct DeepSeaDepthLabel: View {
    @Environment(\.palette) private var p
    let item: TodoItem

    var body: some View {
        if p.world == .deepsea, let label = WorldTodoScene.depthLabel(item) {
            Text(label).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(p.accent)
        }
    }
}
