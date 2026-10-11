import AppIntents
import WidgetKit

/// 起床チェックイン。ウィジェットのボタンとアラーム画面の「起きた！」から呼ぶ。
/// LiveActivityIntent なので、アプリを前に出さずにアプリの中で動き、アラームを取り消せる。
struct WakeCheckInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "起きた！（起床チェックイン）"
    static var description = IntentDescription("今日の残りのアラームを止めて、起床を記録します。")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WakeActions.checkIn(at: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// ルーティンの次の項目を完了にする（ウィジェットのボタン）
struct WakeRoutineStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "ルーティンを1つ進める"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "項目")
    var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        await WakeWatchActions.poll()   // ボタンのついでに、見張りの歩数も確かめる
        var state = WakeStore.state()
        if state.routineDone.contains(id) {
            state.routineDone.removeAll { $0 == id }
        } else {
            state.routineDone.append(id)
        }
        WakeStore.save(state)
        await WakeActivityControl.sync()
        return .result()
    }
}

// MARK: - 起床の見張り（Shared/WakeWatch.swift）

/// 元の起床アラームの「止める」。音を止めてから見張りを始める（失敗しても元のアラームは残る）
struct WakeStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "起床アラームを止める"
    static var description = IntentDescription("今のアラームを止めて、二度寝の見張りを始めます。")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "アラーム")
    var alarmID: String
    @Parameter(title: "回")
    var stage: Int
    @Parameter(title: "日")
    var day: String

    init() {}
    init(alarmID: String, stage: Int, day: String) {
        self.alarmID = alarmID
        self.stage = stage
        self.day = day
    }

    func perform() async throws -> some IntentResult {
        WakeAlarmStop.stop(alarmID)
        await WakeWatchActions.originalStopped(stage: stage, day: day, now: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// 見張りのアラームの「止める」。歩いていなければ3分後にまた鳴る
struct WakeWatchStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "見張りのアラームを止める"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "アラーム")
    var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        WakeAlarmStop.stop(alarmID)
        await WakeWatchActions.watchStopped(now: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// 見張りのアラームの「歩いて止める」。アプリを開いて、歩数（30歩）か計算で止める画面を出す
struct WakeWatchWalkIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "歩いて止める"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "アラーム")
    var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        WakeAlarmStop.stop(alarmID)
        await WakeWatchActions.walkRequested(now: .now)
        return .result()
    }
}
