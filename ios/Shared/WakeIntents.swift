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
