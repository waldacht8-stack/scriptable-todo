import Foundation
import WidgetKit

/// アプリ本体とウィジェットが同じデータを読み書きする場所（App Group の共有フォルダ）。
/// 共有フォルダが取れないときはアプリ専用のフォルダに置き、その状態を画面に出す。
enum SharedStore {
    static let groupID = "group.com.todoapp.shared"

    /// App Group の共有フォルダ。取れなければ nil（＝ウィジェットとデータを共有できない）
    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static var isGroupAvailable: Bool { groupURL != nil }

    private static var baseURL: URL {
        groupURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func url(_ name: String) -> URL { baseURL.appendingPathComponent(name) }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder.iso.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder.iso.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

// MARK: - データ

struct TodoItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
    // 段階1で追加。古いデータには無いので省略可能にしておく
    var due: Date? = nil
    var allDay: Bool? = nil
    var important: Bool? = nil
    var doneAt: Date? = nil

    var isImportant: Bool { important ?? false }
    var isAllDay: Bool { allDay ?? false }

    func isOverdue(_ now: Date = .now) -> Bool {
        guard !done, let due else { return false }
        return isAllDay ? due < Calendar.current.startOfDay(for: now) : due < now
    }
}

struct WakeState: Codable {
    var checkedInAt: Date?
    var nextAlarm: Date?
}

/// アプリ全体の設定（ウィジェットも読む）
struct AppSettings: Codable {
    var theme: String = "sky"
}

enum TodoData {
    static let file = "todos.json"

    static func all() -> [TodoItem] {
        SharedStore.load([TodoItem].self, from: file) ?? []
    }

    static func save(_ items: [TodoItem]) { SharedStore.save(items, to: file) }

    static func toggle(id: String) {
        var items = all()
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].done.toggle()
            items[i].doneAt = items[i].done ? .now : nil
        }
        save(items)
    }

    /// 期限切れ → 期限が近い順 → 期限なし。重要は先頭
    static func sorted(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { a, b in
            if a.isImportant != b.isImportant { return a.isImportant }
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title < b.title
            }
        }
    }

    /// 画面確認用の見本データ（起動引数 -demo のとき）
    static func demo(now: Date = .now) -> [TodoItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: (dayOffset * 24 + h) * 60 + m, to: today)!
        }
        return [
            TodoItem(title: "市役所に書類を提出", due: at(-1, 17)),
            TodoItem(title: "歯医者", due: at(0, 14), important: true),
            TodoItem(title: "牛乳と卵を買う", due: at(0, 18)),
            TodoItem(title: "請求書を確認"),
            TodoItem(title: "ゴミ出し", done: true, due: at(0, 8), doneAt: at(0, 8, 5)),
            TodoItem(title: "美容院", due: at(1, 11)),
            TodoItem(title: "車検の見積もり", due: at(5, 0), allDay: true),
        ]
    }
}

enum WakeData {
    static let file = "wake.json"

    static func state() -> WakeState { SharedStore.load(WakeState.self, from: file) ?? WakeState() }

    static func save(_ s: WakeState) { SharedStore.save(s, to: file) }

    static func checkIn(at date: Date = .now) {
        var s = state()
        s.checkedInAt = date
        save(s)
    }
}

enum SettingsData {
    static let file = "settings.json"

    static func load() -> AppSettings { SharedStore.load(AppSettings.self, from: file) ?? AppSettings() }

    static func save(_ s: AppSettings) { SharedStore.save(s, to: file) }
}
