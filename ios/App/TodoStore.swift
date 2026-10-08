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

    /// 完了（繰り返しなら次の回もできる）
    func complete(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        TodoActions.complete(&items, at: i)
        saveAndNotify()
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
        if let key = item.eventID { CalendarSync.dismissed.insert(key) } // 取り込んだ予定は再取り込みしない
        items.removeAll { $0.id == item.id }
        saveAndNotify()
    }

    func add(_ title: String, due: Date? = nil, allDay: Bool = false, note: String? = nil,
             repeatRule: String? = nil, important: Bool = false, toCalendar: String? = nil) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var item = TodoItem(title: t, due: due, allDay: allDay ? true : nil, important: important ? true : nil,
                            note: (note?.isEmpty ?? true) ? nil : note, repeatRule: repeatRule)
        if let cal = toCalendar { _ = CalendarSync.addEvent(for: &item, calendarTitle: cal.isEmpty ? nil : cal) }
        items.append(item)
        saveAndNotify()
    }

    /// アプリを開いたとき：カレンダーの取り込み・通知の予約し直し・自動バックアップ
    func refreshServices() async {
        let s = SettingsData.load()
        if s.calendarImport && !CalendarSync.authorized { _ = await CalendarSync.requestAccess() }
        var list = TodoData.all()
        CalendarSync.importEvents(into: &list, settings: s)
        items = list
        TodoData.save(list)
        await TodoNotifier.shared.requestAuthorization()
        await TodoNotifier.shared.reschedule(list, settings: s)
        Backup.autoBackupIfNeeded()
    }

    private func saveAndNotify() {
        TodoData.save(items)
        let snapshot = items
        Task { await TodoNotifier.shared.reschedule(snapshot, settings: SettingsData.load()) }
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
        saveAndNotify()
    }
}
