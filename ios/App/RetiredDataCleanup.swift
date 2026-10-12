import Foundation
import UserNotifications

/// なくした機能（習慣・集中）の記録を、起動したときに1回だけ消す（リリース6。コードも記録も消してよいと確認済み）
enum RetiredDataCleanup {
    /// 済んだかどうかの印（アプリ本体の UserDefaults）
    static let doneKey = "cleanup.habitFocus.v1"

    /// App Group の共有フォルダに残っている、習慣（habit-*）と集中（focus-*）のファイル
    static let files: [String] = [
        "habit-list.json", "habit-log.json",
        "focus-settings.json", "focus-state.json", "focus-sessions.json",
    ]

    /// 予約が残っているかもしれない通知の接頭辞（習慣のリマインダーと、集中の終わりの通知）
    static let notificationPrefixes: [String] = ["habit-", "focus-end"]

    static func runOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let fm: FileManager = FileManager.default
        for name in files {
            let url: URL = SharedStore.url(name)
            if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
        }
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()
        let prefixes: [String] = notificationPrefixes
        center.getPendingNotificationRequests { reqs in
            let ids: [String] = reqs.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
        center.getDeliveredNotifications { list in
            let ids: [String] = list.map(\.request.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
        defaults.set(true, forKey: doneKey)
    }
}
