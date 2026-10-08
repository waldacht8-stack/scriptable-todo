import Foundation
import ActivityKit
import AppIntents

// 集中タイマーのライブアクティビティ（ロック画面・ダイナミックアイランド）。
// 表示は ios/Widget/FocusTimerLiveActivity.swift。

struct FocusTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String        // FocusPhase の rawValue
        var title: String
        var endAt: Date          // 動いているときの終わる時刻
        var total: Double        // セッションの長さ（秒）
        var remaining: Double    // 一時停止中の残り秒
        var paused: Bool
    }

    var name: String = "集中"
}

enum FocusTimerLive {
    static func content(_ s: FocusTimerState, now: Date = .now) -> FocusTimerAttributes.ContentState {
        let left = s.left(at: now) ?? 0
        return FocusTimerAttributes.ContentState(
            phase: s.phase.rawValue,
            title: s.title.isEmpty ? s.phase.name : s.title,
            endAt: s.isPaused ? now.addingTimeInterval(left) : (s.endAt ?? now),
            total: max(1, s.total),
            remaining: left,
            paused: s.isPaused)
    }

    /// タイマーの状態に合わせて、ライブアクティビティを始める・更新する・終える
    static func sync(_ s: FocusTimerState) async {
        let current = Activity<FocusTimerAttributes>.activities
        guard s.isRunning else {
            for a in current { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let c = ActivityContent(state: content(s), staleDate: s.isPaused ? nil : s.endAt)
        if let a = current.first {
            await a.update(c)
            for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity<FocusTimerAttributes>.request(attributes: FocusTimerAttributes(), content: c, pushType: nil)
        }
    }
}

/// ライブアクティビティのボタン：一時停止・再開
struct FocusTimerPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "集中タイマーを一時停止・再開"

    init() {}

    func perform() async throws -> some IntentResult {
        let s = FocusTimerEngine.togglePause()
        await FocusTimerLive.sync(s)
        return .result()
    }
}

/// ライブアクティビティのボタン：終了
struct FocusTimerStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "集中タイマーを終了"

    init() {}

    func perform() async throws -> some IntentResult {
        let s = FocusTimerEngine.stop()
        await FocusTimerLive.sync(s)
        return .result()
    }
}
