import SwiftUI

// 集中タイマーの動き：なめらかに減っていく文字盤と、集中を終えたときのお祝い（テーマごとに違う）

/// 文字盤の輪。動いている間は1秒ごとではなく、なめらかに減る（「動きを減らす」では1秒ごと）
struct FocusDialRing: View {
    let state: FocusTimerState
    let now: Date
    let color: Color
    let line: CGFloat
    let smooth: Bool

    var body: some View {
        let running: Bool = state.isRunning && !state.isPaused
        if running && smooth {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                ring(fraction(at: context.date))
            }
        } else {
            ring(fraction(at: now))
        }
    }

    /// 残りの割合（止まっているときは満タン）
    private func fraction(at date: Date) -> Double {
        guard state.isRunning else { return 1 }
        let total: Double = max(1, state.total)
        let left: Double = state.left(at: date) ?? total
        return max(0, min(1, left / total))
    }

    private func ring(_ f: Double) -> some View {
        let style: StrokeStyle = StrokeStyle(lineWidth: line, lineCap: .round)
        let track: Color = color.opacity(0.14)
        return ZStack {
            Circle().stroke(track, lineWidth: line)
            Circle()
                .trim(from: 0, to: f)
                .stroke(color, style: style)
                .rotationEffect(.degrees(-90))
                .opacity(f > 0 ? 1 : 0)
        }
    }
}

/// お祝いの中身
struct FocusCelebrationInfo: Equatable {
    var minutes: Int
    var title: String
    var stays: Bool        // 画面確認用：自動で閉じない
}

/// 集中を1回終えたときのお祝い。テーマの動き方（MotionStyle）で見た目を変える
/// - きびきび：印がはずむ／ゆったり：光の輪が広がる／弾む：粒がはじける／控えめ：「済」の判子
struct FocusCelebrationView: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let info: FocusCelebrationInfo
    let onClose: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Rectangle().fill(p.text.opacity(0.18)).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            card
                .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("集中できました。\(info.minutes)分")
        .accessibilityAddTraits(.isModal)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(motion.tap) { shown = true } }
        }
        .task {
            guard !info.stays else { return }
            try? await Task.sleep(for: .seconds(2.6))
            onClose()
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            ZStack {
                if !reduceMotion { effect }
                mark
            }
            .frame(width: 120, height: 120)
            Text("集中できました").font(.system(size: 24, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
            Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(action: onClose) {
                Text("閉じる").font(.headline).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(p.card, in: RoundedRectangle(cornerRadius: p.radius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    private var detail: String {
        info.title.isEmpty ? "\(info.minutes)分、おつかれさまでした" : "「\(info.title)」に\(info.minutes)分"
    }

    /// 真ん中の印
    @ViewBuilder
    private var mark: some View {
        switch motion {
        case .gentle:
            // 手帳：朱色の「済」の判子を押す
            Text("済").font(.system(size: 46, weight: .heavy, design: .serif)).foregroundStyle(p.accent)
                .frame(width: 82, height: 82)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(p.accent, lineWidth: 4))
                .rotationEffect(.degrees(-8))
                .scaleEffect(shown ? 1 : 1.5)
                .opacity(shown ? 1 : 0)
        default:
            Image(systemName: motion == .smooth ? "sparkles" : "checkmark.seal.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(p.accent)
                .symbolEffect(.bounce, value: shown)
                .symbolEffectsRemoved(reduceMotion)
                .scaleEffect(shown ? 1 : 0.6)
        }
    }

    /// 印のまわりの動き
    @ViewBuilder
    private var effect: some View {
        switch motion {
        case .smooth:
            // ナイト：やわらかな光の輪が2つ広がって消える
            ForEach(0..<2, id: \.self) { i in
                Circle().stroke(p.accent.opacity(0.5), lineWidth: 2)
                    .scaleEffect(shown ? 1.5 + Double(i) * 0.3 : 0.4)
                    .opacity(shown ? 0 : 0.9)
                    .animation(.smooth(duration: 1.6).delay(Double(i) * 0.25), value: shown)
            }
        case .bouncy:
            // 朝焼け：粒がまわりにはじける
            ForEach(0..<12, id: \.self) { i in
                burstDot(i)
            }
        case .snappy:
            // クリーン：輪が一度だけ広がる
            Circle().fill(p.accent.opacity(0.14))
                .scaleEffect(shown ? 1 : 0.3)
        case .gentle:
            EmptyView()
        }
    }

    private func burstDot(_ i: Int) -> some View {
        let angle: Double = Double(i) / 12 * 2 * .pi
        let distance: CGFloat = shown ? 62 : 8
        let dx: CGFloat = CGFloat(cos(angle)) * distance
        let dy: CGFloat = CGFloat(sin(angle)) * distance
        let colors: [Color] = [p.accent, p.overdue, p.sub]
        return Circle().fill(colors[i % colors.count])
            .frame(width: i % 2 == 0 ? 9 : 6, height: i % 2 == 0 ? 9 : 6)
            .offset(x: dx, y: dy)
            .opacity(shown ? 0.85 : 0)
            .animation(.spring(duration: 0.7, bounce: 0.45).delay(0.05), value: shown)
    }
}
