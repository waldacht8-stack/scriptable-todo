import Foundation
import UserNotifications
import EventKit
import SwiftUI

// MARK: - 通知（期限前・朝の一覧・夜の残り）。［完了］［10分後に再通知］はアプリを開かずに処理する

final class TodoNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TodoNotifier()
    static let category = "todo-item"
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        let done = UNNotificationAction(identifier: "done", title: "完了", options: [])
        let snooze = UNNotificationAction(identifier: "snooze", title: "10分後に再通知", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [done, snooze], intentIdentifiers: [])])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// TODO の通知を全部作り直す（todo- で始まるものだけ。起床・習慣・集中の通知には触らない）
    func reschedule(_ items: [TodoItem], settings s: AppSettings) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("todo-") })
        let now = Date.now
        let open = TodoData.sorted(items.filter { !$0.done })
        var requests: [UNNotificationRequest] = []

        // 期限前
        if let minutes = s.remindMinutes {
            for t in open where !t.isAllDay {
                guard let due = t.due else { continue }
                let at = due.addingTimeInterval(TimeInterval(-minutes * 60))
                guard at > now else { continue }
                let c = UNMutableNotificationContent()
                c.title = minutes == 0 ? "期限です：\(t.title)" : "あと\(minutes >= 60 ? "\(minutes / 60)時間" : "\(minutes)分")：\(t.title)"
                c.body = "\(JP.time(due))〜　長押しで［完了］［10分後に再通知］"
                c.sound = .default
                c.categoryIdentifier = Self.category
                c.userInfo = ["id": t.id]
                requests.append(request("todo-remind-\(t.id)", c, at))
            }
        }
        // 朝の一覧・夜の残り（今日から3日分）
        for day in 0..<3 {
            let base = Calendar.current.date(byAdding: .day, value: day, to: Calendar.current.startOfDay(for: now))!
            if let h = s.morningHour, let at = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: base), at > now {
                let list = todayItems(at: at, open)
                if !list.isEmpty { requests.append(summary("todo-morning-\(day)", "今日のTODO \(list.count)件", list, at)) }
            }
            if let h = s.eveningHour, let at = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: base), at > now {
                let list = todayItems(at: at, open)
                if !list.isEmpty { requests.append(summary("todo-evening-\(day)", "今日の残り \(list.count)件", list, at)) }
            }
        }
        // スヌーズ
        for t in open {
            guard let until = snoozes[t.id], until > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = "もう一度：\(t.title)"
            c.body = DueText.label(t)
            c.sound = .default
            c.categoryIdentifier = Self.category
            c.userInfo = ["id": t.id]
            requests.append(request("todo-snooze-\(t.id)", c, until))
        }
        for r in requests.prefix(60) { try? await center.add(r) }
    }

    /// その時刻の時点で「今日やること」（期限切れ＋その日の期限＋期限なし）
    private func todayItems(at: Date, _ open: [TodoItem]) -> [TodoItem] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: at))!
        return open.filter { ($0.due ?? at) < end }
    }

    private func summary(_ id: String, _ title: String, _ list: [TodoItem], _ at: Date) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = list.prefix(4).map { "・\(JP.clock($0, none: "")) \($0.title)".replacingOccurrences(of: "・ ", with: "・") }.joined(separator: "\n")
            + (list.count > 4 ? "\nほか\(list.count - 4)件" : "")
        c.sound = .default
        return request(id, c, at)
    }

    private func request(_ id: String, _ c: UNNotificationContent, _ at: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    // スヌーズの予定（アプリが閉じていても覚えておく）
    private var snoozes: [String: Date] {
        get { SharedStore.load([String: Date].self, from: "todo-snoozes.json") ?? [:] }
        set { SharedStore.save(newValue, to: "todo-snoozes.json") }
    }

    // 通知のボタン（アプリは前に出ない）
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["id"] as? String else { return }
        switch response.actionIdentifier {
        case "done":
            var items = TodoData.all()
            if let i = items.firstIndex(where: { $0.id == id }) {
                TodoActions.complete(&items, at: i)
                TodoData.save(items)
            }
        case "snooze":
            var s = snoozes
            s[id] = Date.now.addingTimeInterval(600)
            snoozes = s
        default: break
        }
        await reschedule(TodoData.all(), settings: SettingsData.load())
        await MainActor.run { NotificationCenter.default.post(name: .todoDataChanged, object: nil) }
    }

    // アプリを開いているときも通知を表示する
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension Notification.Name {
    static let todoDataChanged = Notification.Name("todoDataChanged")
}

// MARK: - カレンダー（iOS カレンダーの予定を TODO に取り込む／TODO を予定として登録）

@MainActor
enum CalendarSync {
    static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter(\.allowsContentModifications)
    }

    static func allCalendarTitles() -> [String] {
        store.calendars(for: .event).map(\.title)
    }

    /// 予定を取り込み、未完了の取り込み済み TODO を最新の内容に合わせる
    static func importEvents(into items: inout [TodoItem], settings s: AppSettings) {
        guard s.calendarImport, authorized else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: s.lookaheadDays, to: start) else { return }
        let calendars = store.calendars(for: .event).filter { !s.excludeCalendars.contains($0.title) }
        guard !calendars.isEmpty else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars))
            .filter { $0.startDate >= start }
        var seen = Set<String>()
        for ev in events {
            let key = (ev.eventIdentifier ?? UUID().uuidString) + "@" + ISO8601DateFormatter().string(from: ev.startDate)
            seen.insert(key)
            if let i = items.firstIndex(where: { $0.eventID == key }) {
                if !items[i].done {
                    items[i].title = ev.title ?? items[i].title
                    items[i].due = ev.startDate
                    items[i].allDay = ev.isAllDay
                }
            } else if !dismissed.contains(key) {
                items.append(TodoItem(title: ev.title ?? "（無題の予定）", due: ev.startDate, allDay: ev.isAllDay,
                                      eventID: key, calendarTitle: ev.calendar.title))
            }
        }
        // 範囲内で消えた予定の未完了 TODO は消す
        items.removeAll { t in
            guard let key = t.eventID, !t.done, let due = t.due, due >= start, due < end else { return false }
            return !seen.contains(key)
        }
    }

    /// TODO を予定として登録し、取り込み済みとして結び付ける
    static func addEvent(for item: inout TodoItem, calendarTitle: String?) -> Bool {
        guard authorized, let due = item.due else { return false }
        let ev = EKEvent(eventStore: store)
        ev.title = item.title
        ev.startDate = due
        ev.endDate = item.isAllDay ? due : due.addingTimeInterval(3600)
        ev.isAllDay = item.isAllDay
        ev.notes = item.note
        ev.calendar = writableCalendars().first { $0.title == calendarTitle } ?? store.defaultCalendarForNewEvents
        do {
            try store.save(ev, span: .thisEvent)
            item.eventID = (ev.eventIdentifier ?? UUID().uuidString) + "@" + ISO8601DateFormatter().string(from: due)
            item.calendarTitle = ev.calendar.title
            return true
        } catch {
            return false
        }
    }

    /// アプリで削除した取り込み済みの予定は、次から取り込まない
    static var dismissed: Set<String> {
        get { Set(SharedStore.load([String].self, from: "todo-dismissed.json") ?? []) }
        set { SharedStore.save(Array(newValue), to: "todo-dismissed.json") }
    }
}

// MARK: - バックアップ（「ファイル」アプリ → このiPhone内 → ひより に毎日保存）と復元・移行

struct BackupFile: Codable {
    var version = 1
    var createdAt = Date.now
    var todos: [TodoItem]
    var settings: AppSettings
}

enum Backup {
    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("バックアップ")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 1日1回、自動で保存（14日分を残す）
    static func autoBackupIfNeeded() {
        var s = SettingsData.load()
        if let last = s.lastBackup, Calendar.current.isDateInToday(last) { return }
        _ = write()
        s.lastBackup = .now
        SettingsData.save(s)
    }

    @discardableResult
    static func write() -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        let url = folder.appendingPathComponent("ひより-\(f.string(from: .now)).json")
        guard let data = try? JSONEncoder.iso.encode(BackupFile(todos: TodoData.all(), settings: SettingsData.load())) else { return nil }
        try? data.write(to: url, options: .atomic)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for old in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(14) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    /// バックアップ、または Scriptable 版の todo-data.json を読み込む。戻り値は取り込んだ件数
    static func restore(from url: URL, into items: inout [TodoItem]) throws -> Int {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let b = try? JSONDecoder.iso.decode(BackupFile.self, from: data) {
            items = b.todos
            SettingsData.save(b.settings)
            return b.todos.count
        }
        return try importScriptable(data, into: &items)
    }

    /// Scriptable 版（todo-data.json）の形式から取り込む。同じ id はとばす
    static func importScriptable(_ data: Data, into items: inout [TodoItem]) throws -> Int {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let todos = root["todos"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ v: Any?) -> Date? {
            guard let s = v as? String else { return nil }
            return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        var count = 0
        let existing = Set(items.map(\.id))
        for t in todos {
            guard let id = t["id"] as? String, !existing.contains(id), let title = t["title"] as? String else { continue }
            let rule: String? = (t["repeat"] as? String).flatMap { RepeatRule(rawValue: $0)?.rawValue }
            items.append(TodoItem(id: id, title: title, done: t["done"] as? Bool ?? false, due: date(t["due"]),
                                  allDay: t["allDay"] as? Bool, important: t["important"] as? Bool, doneAt: date(t["doneAt"]),
                                  note: (t["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }, repeatRule: rule))
            count += 1
        }
        return count
    }
}
