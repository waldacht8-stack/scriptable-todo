import AppIntents
import WidgetKit

/// ウィジェット上のボタンで習慣をチェック（アプリは開かない）
struct CheckHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "習慣をチェック"

    @Parameter(title: "習慣")
    var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        HabitData.tap(id: id)
        return .result()
    }
}
