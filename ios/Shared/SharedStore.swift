import Foundation
import WidgetKit

/// アプリ本体とウィジェットが同じデータを読み書きする場所（App Group の共有フォルダ）。
///
/// SideStore（無料の Apple ID）は、アプリが指定した App Group の名前を、署名したアカウント用の名前
/// （例：group.com.todoapp.shared.XXXXXXXXXX）に書き換えて登録することがある。
/// そのため、まずアプリに同梱されたプロファイル（embedded.mobileprovision）から実際に許可された
/// App Group の名前を読み取り、それで共有フォルダを開く。見つからなければ元の名前を試す。
enum SharedStore {
    static let baseGroupID = "group.com.todoapp.shared"

    /// 実際に使える App Group の名前（プロファイルから読み取ったもの、なければ元の名前）
    static let groupID: String = {
        let candidates = ProvisioningGroups.read().filter { $0.hasPrefix(baseGroupID) || $0.contains("todoapp") } + [baseGroupID]
        for id in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil {
            return id
        }
        return baseGroupID
    }()

    /// App Group の共有フォルダ。取れなければ nil（＝ウィジェットとデータを共有できない）
    static var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static var isGroupAvailable: Bool { groupURL != nil }

    /// 画面の「状態」に出す説明（うまくいかないときの手がかり）
    static var diagnosis: String {
        let found = ProvisioningGroups.read()
        return "使用中: \(groupID)\nプロファイル: " + (found.isEmpty ? "（App Group の記載なし）" : found.joined(separator: ", "))
    }

    private static var baseURL: URL {
        groupURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func url(_ name: String) -> URL { baseURL.appendingPathComponent(name) }

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

/// アプリ（またはウィジェット）に同梱されたプロファイルから App Group の名前を読む
enum ProvisioningGroups {
    static func read() -> [String] {
        var bundleURL = Bundle.main.bundleURL
        // ウィジェット（.appex）から呼ばれたときは、自分のプロファイル → 親アプリのプロファイルの順に探す
        var urls = [bundleURL.appendingPathComponent("embedded.mobileprovision")]
        if bundleURL.pathExtension == "appex" {
            bundleURL = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            urls.append(bundleURL.appendingPathComponent("embedded.mobileprovision"))
        }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { continue }
            let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
            guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let ent = plist["Entitlements"] as? [String: Any],
                  let groups = ent["com.apple.security.application-groups"] as? [String] else { continue }
            if !groups.isEmpty { return groups }
        }
        return []
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

// MARK: - TODO のデータ

struct TodoItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
    var due: Date? = nil
    var allDay: Bool? = nil
    var important: Bool? = nil
    var doneAt: Date? = nil
    var note: String? = nil
    var repeatRule: String? = nil        // daily / weekdays / weekly / monthly
    var eventID: String? = nil           // カレンダー由来の予定の識別子
    var calendarTitle: String? = nil

    var isImportant: Bool { important ?? false }
    var isAllDay: Bool { allDay ?? false }
    var isCalendar: Bool { eventID != nil }

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
    var theme: String = "focus"     // 色合い（AppTheme）
    var layout: String = "focus"    // 「今日」の画面構成（TodayLayout）
    // TODO の通知（nil は送らない）
    var remindMinutes: Int? = 30    // 期限の何分前
    var morningHour: Int? = 7       // 朝の一覧
    var eveningHour: Int? = 20      // 夜の残り
    // カレンダー
    var calendarImport: Bool = true
    var lookaheadDays: Int = 45
    var excludeCalendars: [String] = ["日本の祝日", "祝日", "誕生日", "Birthdays", "Japanese Holidays", "Holidays in Japan"]
    var lastBackup: Date? = nil

    init() {}

    // 項目が増えても古い設定ファイルを読めるように、無い項目は既定値にする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? d.theme
        layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? d.layout
        remindMinutes = c.contains(.remindMinutes) ? try c.decodeIfPresent(Int.self, forKey: .remindMinutes) : d.remindMinutes
        morningHour = c.contains(.morningHour) ? try c.decodeIfPresent(Int.self, forKey: .morningHour) : d.morningHour
        eveningHour = c.contains(.eveningHour) ? try c.decodeIfPresent(Int.self, forKey: .eveningHour) : d.eveningHour
        calendarImport = try c.decodeIfPresent(Bool.self, forKey: .calendarImport) ?? d.calendarImport
        lookaheadDays = try c.decodeIfPresent(Int.self, forKey: .lookaheadDays) ?? d.lookaheadDays
        excludeCalendars = try c.decodeIfPresent([String].self, forKey: .excludeCalendars) ?? d.excludeCalendars
        lastBackup = try c.decodeIfPresent(Date.self, forKey: .lastBackup)
    }

    // nil（オフ）を「項目なし」と区別して保存する
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(theme, forKey: .theme)
        try c.encode(layout, forKey: .layout)
        try c.encode(remindMinutes, forKey: .remindMinutes)
        try c.encode(morningHour, forKey: .morningHour)
        try c.encode(eveningHour, forKey: .eveningHour)
        try c.encode(calendarImport, forKey: .calendarImport)
        try c.encode(lookaheadDays, forKey: .lookaheadDays)
        try c.encode(excludeCalendars, forKey: .excludeCalendars)
        try c.encodeIfPresent(lastBackup, forKey: .lastBackup)
    }

    enum CodingKeys: String, CodingKey {
        case theme, layout, remindMinutes, morningHour, eveningHour, calendarImport, lookaheadDays, excludeCalendars, lastBackup
    }
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
            if items[i].done {
                items[i].done = false
                items[i].doneAt = nil
            } else {
                TodoActions.complete(&items, at: i) // 繰り返しなら次の回もできる
            }
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
            TodoItem(title: "ゴミ出し", done: true, due: at(0, 8), doneAt: at(0, 8, 5), repeatRule: "weekly"),
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
