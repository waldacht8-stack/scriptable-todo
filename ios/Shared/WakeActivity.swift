import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// 出発までのカウントダウンと朝のルーティンのライブアクティビティ（ロック画面・ダイナミックアイランド）。
// 表示は ios/Widget/WakeLiveActivity.swift。

#if canImport(ActivityKit)
struct WakeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var departure: Date
        var nextStepID: String?
        var nextStep: String?
        var stepsDone: Int
        var stepsTotal: Int
        var routineMinutesLeft: Int
    }

    var title: String
}
#endif

enum WakeActivityControl {
    #if canImport(ActivityKit)
    /// 今の状態からライブアクティビティの内容を作る（出発がない・過ぎたら nil）
    static func content(now: Date) -> WakeActivityAttributes.ContentState? {
        let s = WakeStore.settings()
        let st = WakeStore.state()
        guard WakeLogic.checkedIn(st, now: now) != nil,
              let dep = WakeLogic.departure(now: now, settings: s), dep > now else { return nil }
        let remaining = WakeLogic.remainingRoutine(settings: s, state: st)
        return WakeActivityAttributes.ContentState(
            departure: dep, nextStepID: remaining.first?.id, nextStep: remaining.first?.name,
            stepsDone: s.routine.count - remaining.count, stepsTotal: s.routine.count,
            routineMinutesLeft: remaining.map(\.minutes).reduce(0, +))
    }
    #endif

    /// 出発前なら表示を始めるか更新し、出発後・チェックイン前なら終える
    static func sync(now: Date = .now) async {
        #if canImport(ActivityKit)
        let activities = Activity<WakeActivityAttributes>.activities
        guard let state = content(now: now) else {
            for a in activities { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let ac = ActivityContent(state: state, staleDate: state.departure.addingTimeInterval(5 * 60))
        if activities.isEmpty {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: WakeActivityAttributes(title: "出発まで"), content: ac, pushType: nil)
        } else {
            for a in activities { await a.update(ac) }
        }
        #endif
    }
}
