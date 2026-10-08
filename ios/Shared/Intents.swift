import AppIntents
import WidgetKit

/// ウィジェット上のボタンで TODO の完了を切り替える（アプリは開かない）
struct ToggleTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "TODOを完了"

    @Parameter(title: "TODO")
    var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        TodoData.toggle(id: id)
        return .result()
    }
}

/// ウィジェット上のボタンで起床チェックイン（アプリは開かない）
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "起床チェックイン"

    func perform() async throws -> some IntentResult {
        WakeData.checkIn()
        return .result()
    }
}
