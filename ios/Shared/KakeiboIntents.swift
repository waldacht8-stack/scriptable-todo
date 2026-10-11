import AppIntents
import Foundation
import UserNotifications

/// ショートカットの「取引」オートメーションから呼ぶ：Apple Pay の支払いを家計簿に記録する（アプリは開かない）。
/// 金額は文字で受け取る（「¥1,234」「1,234円」「1234」のどれでも読む。iD・QUICPay では空で届くことがある）。
struct RecordKakeiboExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "日和に支出を記録"
    static var description = IntentDescription("Apple Pay などで払った金額・お店・カードを、日和の家計簿に記録します。アプリは開きません。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "金額")
    var amount: String?

    @Parameter(title: "お店")
    var merchant: String?

    @Parameter(title: "カード")
    var card: String?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = KakeiboRecorder.recordPayment(amountText: amount, merchant: merchant, card: card)
        let message: String = result.message
        return .result(dialog: "\(message)")
    }
}

/// Apple Pay（ショートカット）からの1件を記録する。アプリの「テストで1件送る」も同じ道を通る
enum KakeiboRecorder {
    struct Result {
        var entry: KakeiboEntry?
        var duplicate: Bool
        var message: String
    }

    /// 「¥1,234」「1,234 円」「JP¥1,234.00」などから円の整数を取り出す（読めなければ nil）
    static func parseAmount(_ text: String?) -> Int? {
        guard let text else { return nil }
        let s = text.precomposedStringWithCompatibilityMapping
        var digits = ""
        var started = false
        for ch in s {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
                started = true
            } else if ch == "," && started {
                continue
            } else if started {
                break   // 小数点（.00）やその後ろは使わない
            }
        }
        guard let v = Int(digits), v > 0 else { return nil }
        return v
    }

    @discardableResult
    static func recordPayment(amountText: String?, merchant: String?, card: String?, isTest: Bool = false, now: Date = .now) -> Result {
        let amount = parseAmount(amountText)
        let store = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cardName = (card ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = KakeiboData.settings()
        let category = KakeiboRules.suggest(store, kind: .expense, settings: settings)
        var entry = KakeiboEntry(date: now, amount: amount ?? 0, kind: .expense, category: category,
                                 memo: store.isEmpty ? "Apple Pay" : store, source: .applePay,
                                 card: cardName.isEmpty ? nil : cardName,
                                 dedupeKey: KakeiboDedupe.key(date: now, amount: amount ?? 0, kind: .expense, text: store))
        if amount == nil { entry.needsAmount = true }
        if isTest { entry.isTest = true }

        // オートメーションが同じ支払いで2回動いたときは、2分以内の同じ1件を入れない
        let added: Bool = KakeiboData.update { list in
            let twice = list.contains { e in
                e.source == .applePay && e.amount == entry.amount && e.memo == entry.memo
                    && abs(e.createdAt.timeIntervalSince(now)) < 120 && e.isTest == entry.isTest
            }
            if twice { return false }
            list.insert(entry, at: 0)
            return true
        }
        if isTest {
            var s = KakeiboData.settings()
            s.applePayTested = true
            KakeiboData.saveSettings(s)
        }
        NotificationCenter.default.post(name: .kakeiboDataChanged, object: nil)

        guard added else { return Result(entry: nil, duplicate: true, message: "同じ支払いはすでに記録してあります") }
        let place = store.isEmpty ? "お店の名前なし" : store
        if let amount {
            return Result(entry: entry, duplicate: false, message: "\(place) ・ \(KakeiboFormat.yen(amount)) 円を記録しました")
        }
        notifyMissingAmount(place: place)
        return Result(entry: entry, duplicate: false, message: "\(place) の支払いを記録しました。金額は日和で入れてください")
    }

    /// 金額が届かなかったときの通知（通知を許可しているときだけ出る）
    private static func notifyMissingAmount(place: String) {
        let content = UNMutableNotificationContent()
        content.title = "金額を入れてください"
        content.body = "\(place) の支払いは金額が届きませんでした。日和の家計簿で金額だけ入れられます"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "kakeibo-amount-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
