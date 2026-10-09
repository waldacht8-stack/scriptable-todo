import SwiftUI
import WidgetKit

/// 画面が使う TODO の状態。保存は SharedStore（ウィジェットと共有）に行う。
@MainActor
final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = []
    @Published var theme: AppTheme = .focus
    @Published var layout: TodayLayout = .focus
    /// 各構成に今日完了したTODOも出すか（設定に保存。目のボタンで切り替え）
    @Published var showDone = false
    /// 直前の完了・延期・削除を取り消すための記録（しばらく「元に戻す」を出す）
    @Published var undo: UndoInfo?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") { TodoData.save(args.contains("-demomany") ? Self.manyDemo() : TodoData.demo()) }
        var s = SettingsData.load()
        if let v = Self.arg("-theme", args) { s.theme = v }
        if let v = Self.arg("-layout", args) { s.layout = v }
        // 見本データのときは -showdone の有無で決める（前の撮影の設定を持ち越さない）
        if args.contains("-demo") || args.contains("-showdone") { s.showDone = args.contains("-showdone") }
        if args.contains("-theme") || args.contains("-layout") || args.contains("-showdone") || args.contains("-demo") { SettingsData.save(s) }
        reload()
    }

    /// 画面確認用：件数が多く題名が長い見本（-demo -demomany。一般的な内容のみ）
    private static func manyDemo(now: Date = .now) -> [TodoItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: (dayOffset * 24 + h) * 60 + m, to: today) ?? today
        }
        var list = TodoData.demo(now: now)
        list.append(TodoItem(title: "来月の旅行に持っていく物のリストを作って、足りない物を買いに行く", due: at(0, 20)))
        list.append(TodoItem(title: "毎朝のストレッチ", due: at(0, 0), allDay: true, repeatRule: "daily"))
        list.append(TodoItem(title: "期限の過ぎた手続き", due: at(-3, 0), allDay: true))
        let names = ["洗濯物をたたむ", "植物に水をやる", "メールを返信する", "本を読む", "電球を替える", "靴を磨く",
                     "写真を整理する", "冷蔵庫の中を片付ける", "郵便物を確認する", "週末の献立を考える", "自転車の空気を入れる",
                     "部屋の模様替えを考える", "古い服を寄付する", "引き出しを整理する"]
        for (i, n) in names.enumerated() {
            list.append(TodoItem(title: n, due: i % 3 == 0 ? nil : at(i % 4, 9 + i % 10)))
        }
        return list
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
        showDone = s.showDone
    }

    /// 未完了（期限切れ → 期限が近い順 → 期限なし。重要は先頭）
    var open: [TodoItem] { TodoData.sorted(items.filter { !$0.done }) }

    var overdue: [TodoItem] { open.filter { $0.isOverdue() } }

    /// 今日完了したもの（完了した順）
    var doneToday: [TodoItem] {
        items.filter { $0.done && ($0.doneAt.map { Calendar.current.isDateInToday($0) } ?? false) }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
    }

    /// 画面に出す今日の完了（目のボタンがオフなら空）
    var shownDone: [TodoItem] { showDone ? doneToday : [] }

    var nextTimed: TodoItem? {
        open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > .now }.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    /// 完了（繰り返しなら次の回もできる）
    func complete(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }), !items[i].done else { return }
        let before = items
        TodoActions.complete(&items, at: i)
        remember("「\(item.title)」を完了しました", before: before)
        saveAndNotify()
    }

    /// 未完了に戻す。繰り返しで次の回ができていたら、その回は消す（二重にならないように）
    func uncomplete(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }), items[i].done else { return }
        let old = items[i]
        if old.repeatRule != nil, !old.isCalendar, let next = old.nextOccurrence(now: old.doneAt ?? .now),
           let j = items.firstIndex(where: { $0.id != old.id && !$0.done && $0.title == old.title
                                            && $0.repeatRule == old.repeatRule && $0.due == next }) {
            items.remove(at: j)
        }
        update(item.id) { $0.done = false; $0.doneAt = nil }
    }

    /// 明日へ延期（期限なしは明日の終日。期限切れは時刻をそのままに明日へ。先の期限は1日あと）
    func postpone(_ item: TodoItem) {
        let before = items
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        update(item.id) {
            guard let due = $0.due else {
                $0.due = tomorrow
                $0.allDay = true
                return
            }
            let h = cal.component(.hour, from: due), m = cal.component(.minute, from: due)
            let sameTimeTomorrow = cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow) ?? tomorrow
            let oneDayLater = cal.date(byAdding: .day, value: 1, to: due) ?? due
            $0.due = max(oneDayLater, sameTimeTomorrow)
        }
        remember("「\(item.title)」を明日に延期しました", before: before)
    }

    /// 期限の移し先（長押しメニュー・かんばん）
    enum DueMove { case today, tomorrow, nextWeek, noDue }

    /// 期限を移す。時刻つきなら時刻はそのまま、日だけ変える
    func move(_ item: TodoItem, to target: DueMove) {
        let before = items
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let day: Date?
        switch target {
        case .today: day = today
        case .tomorrow: day = cal.date(byAdding: .day, value: 1, to: today)
        case .nextWeek: day = DueChoice.nextMonday(from: today)
        case .noDue: day = nil
        }
        update(item.id) {
            guard let day else {
                $0.due = nil
                $0.allDay = nil
                $0.repeatRule = nil
                return
            }
            if let due = $0.due, !$0.isAllDay {
                let h = cal.component(.hour, from: due), m = cal.component(.minute, from: due)
                $0.due = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            } else {
                $0.due = day
                $0.allDay = true
            }
        }
        let name: String
        switch target {
        case .today: name = "今日"
        case .tomorrow: name = "明日"
        case .nextWeek: name = "来週"
        case .noDue: name = "期限なし"
        }
        remember(target == .noDue ? "「\(item.title)」を期限なしにしました" : "「\(item.title)」を\(name)に移しました", before: before)
    }

    /// 編集の保存（カレンダー由来でも中身はこのアプリで変えられる）
    func save(_ edited: TodoItem) {
        update(edited.id) { $0 = edited }
    }

    /// 直前の操作を取り消す。変わった項目だけを元に戻し、その間にできた項目（繰り返しの次の回）は消す
    func undoLast() {
        guard let u = undo else { return }
        items.removeAll { u.addedIDs.contains($0.id) }
        for old in u.before where u.changedIDs.contains(old.id) {
            if let i = items.firstIndex(where: { $0.id == old.id }) { items[i] = old } else { items.append(old) }
        }
        if let key = u.dismissedKey { CalendarSync.dismissed.remove(key) }
        undo = nil
        saveAndNotify()
    }

    /// 操作の前後を比べて、取り消しに必要な分だけ覚えておく
    private func remember(_ message: String, before: [TodoItem], dismissedKey: String? = nil) {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let changed = old.keys.filter { now[$0] != old[$0] }
        let added = now.keys.filter { old[$0] == nil }
        undo = UndoInfo(message: message, before: before.filter { changed.contains($0.id) },
                        changedIDs: Set(changed), addedIDs: Set(added), dismissedKey: dismissedKey)
    }

    func toggleImportant(_ item: TodoItem) {
        update(item.id) { $0.important = !$0.isImportant }
    }

    func delete(_ item: TodoItem) {
        let before = items
        if let key = item.eventID { CalendarSync.dismissed.insert(key) } // 取り込んだ予定は再取り込みしない
        items.removeAll { $0.id == item.id }
        remember("「\(item.title)」を削除しました", before: before, dismissedKey: item.eventID)
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

    /// 今日完了したTODOを各構成に出すかどうか
    func setShowDone(_ on: Bool) {
        showDone = on
        var s = SettingsData.load()
        s.showDone = on
        SettingsData.save(s)
    }

    private func update(_ id: String, _ change: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        saveAndNotify()
    }
}

/// 「元に戻す」に必要な記録
struct UndoInfo: Identifiable {
    /// 「元に戻す」を出しておく秒数
    static let seconds: Double = 8

    let id = UUID()
    let message: String
    /// 操作前の、変わった項目
    let before: [TodoItem]
    let changedIDs: Set<String>
    /// 操作でできた項目（繰り返しの次の回など）
    let addedIDs: Set<String>
    /// 削除で「再取り込みしない」にしたカレンダーの予定
    let dismissedKey: String?
}
