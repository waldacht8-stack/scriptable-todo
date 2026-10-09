import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// 集中タイマーのライブアクティビティの見た目（ロック画面とダイナミックアイランド）

struct FocusTimerLiveActivity: Widget {
    static var palette: Palette { AppTheme.current() }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusTimerAttributes.self) { context in
            FocusTimerLockView(state: context.state, stale: context.isStale, p: Self.palette)
                .activityBackgroundTint(Self.palette.card)
                .activitySystemActionForegroundColor(Self.palette.text)
        } dynamicIsland: { context in
            let s = context.state
            let p = AppTheme.current()
            let phase = FocusPhase(rawValue: s.phase) ?? .focus
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(phase.name, systemImage: phase.icon)
                        .font(.caption.weight(.bold)).foregroundStyle(p.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusTimerCountdown(state: s, stale: context.isStale)
                        .font(.title2.weight(.heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                        FocusTimerBar(state: s, stale: context.isStale).tint(p.accent)
                        FocusTimerButtons(state: s, color: p.accent, text: .white)
                    }
                }
            } compactLeading: {
                Image(systemName: phase.icon).foregroundStyle(p.accent)
            } compactTrailing: {
                FocusTimerCountdown(state: s, stale: context.isStale)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
                    .foregroundStyle(p.accent)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(p.accent)
            }
            .keylineTint(p.accent)
        }
    }
}

/// 残り時間（動いているときは自動で進む）
struct FocusTimerCountdown: View {
    let state: FocusTimerAttributes.ContentState
    let stale: Bool

    var body: some View {
        if state.paused {
            Text(FocusTimerLiveFormat.clock(state.remaining))
        } else if stale || state.endAt <= Date() {
            Text("終了")
        } else {
            Text(timerInterval: state.endAt.addingTimeInterval(-state.total)...state.endAt, countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct FocusTimerBar: View {
    let state: FocusTimerAttributes.ContentState
    let stale: Bool

    var body: some View {
        if state.paused || stale || state.endAt <= Date() {
            ProgressView(value: stale ? 0 : max(0, min(1, state.remaining / state.total)))
        } else {
            ProgressView(timerInterval: state.endAt.addingTimeInterval(-state.total)...state.endAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
    }
}

struct FocusTimerButtons: View {
    let state: FocusTimerAttributes.ContentState
    let color: Color
    let text: Color

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: FocusTimerPauseIntent()) {
                Label(state.paused ? "再開" : "一時停止", systemImage: state.paused ? "play.fill" : "pause.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(color.opacity(0.25), in: Capsule())
                    .foregroundStyle(text)
            }
            .buttonStyle(.plain)
            Button(intent: FocusTimerStopIntent()) {
                Label("終了", systemImage: "stop.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(text.opacity(0.12), in: Capsule())
                    .foregroundStyle(text)
            }
            .buttonStyle(.plain)
        }
    }
}

/// ロック画面の表示
struct FocusTimerLockView: View {
    let state: FocusTimerAttributes.ContentState
    let stale: Bool
    let p: Palette

    var body: some View {
        let phase = FocusPhase(rawValue: state.phase) ?? .focus
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: phase.icon).font(.title3.weight(.bold)).foregroundStyle(p.accent)
                    .frame(width: 42, height: 42).background(p.accent.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.name + (state.paused ? "・一時停止中" : "")).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    Text(state.title).font(.headline).foregroundStyle(p.text).lineLimit(1)
                }
                Spacer(minLength: 4)
                FocusTimerCountdown(state: state, stale: stale)
                    .font(.system(size: 34, weight: .heavy, design: p.fontDesign)).monospacedDigit()
                    .foregroundStyle(p.text)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            FocusTimerBar(state: state, stale: stale).tint(p.accent)
            FocusTimerButtons(state: state, color: p.accent, text: p.text)
        }
        .padding(16)
        .fontDesign(p.fontDesign)
    }
}

enum FocusTimerLiveFormat {
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
