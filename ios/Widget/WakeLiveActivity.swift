import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// 出発までのカウントダウンと次のルーティン（ロック画面・ダイナミックアイランド）

struct WakeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WakeActivityAttributes.self) { context in
            WakeActivityLockView(state: context.state, p: AppTheme.current())
                .activityBackgroundTint(AppTheme.current().card)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("出発 \(JP.time(context.state.departure))", systemImage: "figure.walk.departure")
                        .font(.caption.weight(.bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WakeCountdownText(departure: context.state.departure)
                        .font(.title3.weight(.heavy)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.nextStep.map { "次：\($0)" } ?? "出発準備OK").font(.headline).lineLimit(1)
                        Spacer(minLength: 0)
                        if let id = context.state.nextStepID {
                            Button(intent: WakeRoutineStepIntent(id: id)) {
                                Label("完了", systemImage: "checkmark")
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.walk.departure")
            } compactTrailing: {
                WakeCountdownText(departure: context.state.departure).monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "figure.walk.departure")
            }
        }
    }
}

struct WakeCountdownText: View {
    let departure: Date
    var body: some View {
        let now = Date()
        Text(timerInterval: now...max(now, departure), countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}

struct WakeActivityLockView: View {
    let state: WakeActivityAttributes.ContentState
    let p: Palette

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("出発 \(JP.time(state.departure)) まで").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                WakeCountdownText(departure: state.departure)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 40, weight: .heavy, design: p.fontDesign)).monospacedDigit()
                    .foregroundStyle(p.text)
                Text("ルーティン \(state.stepsDone)/\(state.stepsTotal)・残り\(state.routineMinutesLeft)分")
                    .font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text(state.nextStep ?? "出発準備OK").font(.headline).foregroundStyle(p.text).lineLimit(2)
                    .multilineTextAlignment(.trailing)
                if let id = state.nextStepID {
                    Button(intent: WakeRoutineStepIntent(id: id)) {
                        Label("完了", systemImage: "checkmark").font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(p.accent, in: Capsule())
                            .foregroundStyle(p.onAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .fontDesign(p.fontDesign)
    }
}
