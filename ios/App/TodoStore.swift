import SwiftUI
import WidgetKit

/// 画面が使う TODO の状態。保存は SharedStore（ウィジェットと共有）に行う。
@MainActor
final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = []
    @Published var theme: AppTheme = .focus
    @Published var layout: TodayLayout = .focus

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") { TodoData.save(TodoData.demo()) }
        var s = SettingsData.load()
        if let v = Self.arg("-theme", args) { s.theme = v }
        if let v = Self.arg("-layout", args) { s.layout = v }
        if args.contains("-theme") || args.contains("-layout") { SettingsData.save(s) }
        reload()
    }

    private static func arg(_ name: String, _ args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func reload() {
        items = TodoData.all()
        let s = SettingsData.load()
        theme = AppTheme.from(s.theme)
        layout = TodayLayout.from(s.layout)
    }

    /// 未完了（期限切れ → 期限が近い順 → 期限なし。重要は先頭）
    var open: [TodoItem] { TodoData.sorted(items.filter { !$0.done }) }

    var overdue: [TodoItem] { open.filter { $0.isOverdue() } }

    var doneToday: [TodoItem] {
        items.filter { $0.done && ($0.doneAt.map { Calendar.current.isDateInToday($0) } ?? false) }
    }

    var nextTimed: TodoItem? {
        open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > .now }.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func complete(_ item: TodoItem) {
        update(item.id) { $0.done = true; $0.doneAt = .now }
    }

    func uncomplete(_ item: TodoItem) {
        update(item.id) { $0.done = false; $0.doneAt = nil }
    }

    /// 明日へ延期（期限なしは明日の終日にする）
    func postpone(_ item: TodoItem) {
        update(item.id) {
            let base = $0.due ?? Calendar.current.startOfDay(for: .now)
            $0.due = Calendar.current.date(byAdding: .day, value: 1, to: base)
            if item.due == nil { $0.allDay = true }
        }
    }

    func toggleImportant(_ item: TodoItem) {
        update(item.id) { $0.important = !$0.isImportant }
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        TodoData.save(items)
    }

    func add(_ title: String, due: Date? = nil, allDay: Bool = false) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(TodoItem(title: t, due: due, allDay: allDay ? true : nil))
        TodoData.save(items)
    }

    func setTheme(_ t: AppTheme) {
        theme = t
        var s = SettingsData.load()
        s.theme = t.rawValue
        SettingsData.save(s) // ウィジェットもすぐ描き直す
    }

    func setLayout(_ l: TodayLayout) {
        layout = l
        var s = SettingsData.load()
        s.layout = l.rawValue
        SettingsData.save(s)
    }

    private func update(_ id: String, _ change: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        TodoData.save(items)
    }
}
