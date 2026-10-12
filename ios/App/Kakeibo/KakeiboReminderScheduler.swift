import SwiftUI
import UserNotifications

/// 明細の取り込みのお知らせ（ローカル通知。識別子は kakeibo-import- で始める）。
/// アプリが前に出たとき・家計簿の設定や記録が変わったときに、いったん全部消して予約し直す
enum KakeiboReminderScheduler {
    static let prefix = "kakeibo-import-"

    /// 見本（-demo）のときは通知を触らない
    private static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static func reschedule(now: Date = .now) async {
        guard !isDemo else { return }
        let settings = KakeiboData.settings()
        let entries = KakeiboData.entries()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old: [String] = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard settings.reminder.enabled else { return }
        let dues = KakeiboReminders.dues(settings: settings, entries: entries)
        guard !dues.isEmpty else { return }
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        for r in requests(dues, settings: settings.reminder, now: now) {
            try? await center.add(r)
        }
    }

    /// 予約する通知（期限の日の決めた時刻。もう過ぎた期限は出し直さず、35 日めの通知だけ残す）
    static func requests(_ dues: [KakeiboReminders.Due], settings: KakeiboReminderSettings, now: Date) -> [UNNotificationRequest] {
        var out: [UNNotificationRequest] = []
        for d in dues {
            if let at = fireDate(d.due, settings: settings, now: now) {
                out.append(request(id: prefix + d.institution.rawValue, d, at: at))
            }
            if d.reason != .fallback, d.fallback > d.due, let at = fireDate(d.fallback, settings: settings, now: now) {
                var late = d
                late.reason = .fallback
                out.append(request(id: prefix + d.institution.rawValue + "-late", late, at: at))
            }
        }
        return out
    }

    /// その日の決めた時刻（もう過ぎていれば nil）
    static func fireDate(_ day: Date, settings: KakeiboReminderSettings, now: Date) -> Date? {
        let cal = Calendar.current
        let at: Date = cal.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day) ?? day
        return at > now ? at : nil
    }

    private static func request(id: String, _ d: KakeiboReminders.Due, at: Date) -> UNNotificationRequest {
        let text = KakeiboReminders.message(d)
        let c = UNMutableNotificationContent()
        c.title = text.title
        c.body = text.body
        c.sound = .default
        c.userInfo = ["kakeiboURL": KakeiboReminders.link(d.institution).absoluteString]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }
}

/// 「取り込む」の行き先（通知・ウィジェットの hiyori://kakeibo?import=jcb）。家計簿の画面が受け取って取り込みを開く
@MainActor
final class KakeiboImportLink: ObservableObject {
    static let shared = KakeiboImportLink()
    @Published var pending: KakeiboInstitution?

    /// hiyori://kakeibo?import=… なら受け取って true
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let i = KakeiboReminders.institution(from: url) else { return false }
        pending = i
        return true
    }

    /// 通知を押したとき（TodoNotifier から）。家計簿のタブも開く
    func open(_ url: URL) {
        guard receive(url) else { return }
        NotificationCenter.default.post(name: .openKakeiboTab, object: nil)
    }
}

extension Notification.Name {
    /// 家計簿のタブを開く（取り込みのお知らせを押した）
    static let openKakeiboTab = Notification.Name("openKakeiboTab")
}
