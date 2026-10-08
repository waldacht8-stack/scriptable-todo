import Foundation
import WidgetKit

/// アプリ本体とウィジェットが同じデータを読み書きする場所（App Group の共有フォルダ）。
/// 段階0では「無料の Apple ID ＋ SideStore で App Group が使えるか」を確かめるため、
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

// MARK: - 段階0のデータ（検証用の最小限）

struct TodoItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var done: Bool = false
}

struct WakeState: Codable {
    var checkedInAt: Date?
    var nextAlarm: Date?
}

enum TodoData {
    static let file = "todos.json"

    static func all() -> [TodoItem] {
        SharedStore.load([TodoItem].self, from: file) ?? [
            TodoItem(title: "ウィジェットから完了してみる"),
            TodoItem(title: "アプリで追加してみる"),
        ]
    }

    static func save(_ items: [TodoItem]) { SharedStore.save(items, to: file) }

    static func toggle(id: String) {
        var items = all()
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].done.toggle() }
        save(items)
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
