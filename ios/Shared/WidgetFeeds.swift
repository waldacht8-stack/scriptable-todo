import Foundation

// MARK: - ウィジェットが読むだけの共有データ（リリース4）
//
// 見返し・見張り・家計簿の本当の型（ReviewState / WakeWatchState / KakeiboSummary）は、
// それぞれの担当が別の枝で作っている。この枝だけでもビルドできるよう、ウィジェット側は
// App Group の JSON を直接読む小さな型を持つ（名前は本物とぶつからないよう *Feed にしている）。
// 統合のときは、持ち主の型が下の JSON を書き出す（または、この Feed を持ち主の型から作る）ようにそろえる。
//
// 日付はすべて ISO 8601（例 "2026-10-11T21:00:00+09:00"。JSONDecoder.iso で読む）。どの項目も省略できる。
//
// review-state.json（見返し。TODO・起床の担当が書く）
// {
//   "day": "2026-10-11",              // この状態の日（yyyy-MM-dd）。今日でなければ朝・昼・夜は未として扱う
//   "morningDone": true,              // 朝の見返しが済んだか
//   "noonDone": true,                 // 昼の見返しが済んだか
//   "nightDone": false,               // 夜の見返しが済んだか
//   "nextReviewAt": "2026-10-11T21:00:00+09:00",   // 次の見返しの時刻
//   "streak": 12,                     // 見返しの連続日数
//   "unreviewedCount": 3              // まだ見返していない TODO の数
// }
//
// wake-watch.json（起床の見張り。TODO・起床の担当が書く）
// {
//   "watching": true,                 // 見張り中か（アラームを止めてから、歩いて解除するまで）
//   "stoppedAt": "2026-10-11T07:08:00+09:00",      // アラームを止めた時刻
//   "steps": 37,                      // 止めてからの歩数
//   "requiredSteps": 100,             // 解除に必要な歩数
//   "nextWatchAt": "2026-10-11T07:18:00+09:00",    // 次の見張り（歩かなければまた鳴る時刻）
//   "lastWatchAt": "2026-10-11T07:28:00+09:00"     // 最後の見張りの時刻（任意）
// }
//
// kakeibo-summary.json（家計簿。家計簿の担当が書く）
// {
//   "month": "2026-10",               // 集計した月（yyyy-MM）。今月でなければ支出 0 として扱う
//   "spent": 32400,                   // 今月の支出（円・整数）
//   "budget": 50000,                  // 今月の予算（円。未設定なら省略）
//   "remaining": 17600                // 予算の残り（円。省略なら budget - spent）
// }
//
// ファイルが無いときは見本のデータを返し、isSample を true にする（ウィジェットに「見本」と小さく出す）。

/// 見返しの状態
struct ReviewFeed: Codable, Equatable {
    var day: String? = nil
    var morningDone: Bool? = nil
    var noonDone: Bool? = nil
    var nightDone: Bool? = nil
    var nextReviewAt: Date? = nil
    var streak: Int? = nil
    var unreviewedCount: Int? = nil
    /// ファイルが無く、見本を出しているか（JSON には書かない）
    var isSample: Bool = false

    static let file = "review-state.json"

    private enum CodingKeys: String, CodingKey {
        case day, morningDone, noonDone, nightDone, nextReviewAt, streak, unreviewedCount
    }

    static func load(now: Date = .now) -> ReviewFeed {
        guard let f = SharedStore.load(ReviewFeed.self, from: file) else {
            var d = demo(now: now)
            d.isSample = true
            return d
        }
        return f
    }

    /// 見本：朝と昼は済み、夜の見返しは 21:00（夜より後なら明日の朝 7:00）
    static func demo(now: Date = .now) -> ReviewFeed {
        let cal = Calendar.current
        let hour: Int = cal.component(.hour, from: now)
        let today: Date = cal.startOfDay(for: now)
        let tomorrow: Date = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let next: Date
        if hour < 12 {
            next = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today) ?? now
        } else if hour < 21 {
            next = cal.date(bySettingHour: 21, minute: 0, second: 0, of: today) ?? now
        } else {
            next = cal.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? now
        }
        return ReviewFeed(day: WidgetFeedDay.key(now), morningDone: true, noonDone: hour >= 12,
                          nightDone: hour >= 22, nextReviewAt: next, streak: 12, unreviewedCount: hour >= 22 ? 0 : 3)
    }

    /// 今日の分か（違う日のファイルなら、朝・昼・夜は未）
    func isToday(_ now: Date) -> Bool { day == nil || day == WidgetFeedDay.key(now) }

    /// 朝・昼・夜の済み／未（今日でなければすべて未）
    func done(_ now: Date) -> [Bool] {
        guard isToday(now) else { return [false, false, false] }
        return [morningDone ?? false, noonDone ?? false, nightDone ?? false]
    }

    /// 次の見返し（過ぎていれば nil）
    func next(after now: Date) -> Date? {
        guard let t = nextReviewAt, t > now else { return nil }
        return t
    }
}

/// 起床の見張りの状態
struct WakeWatchFeed: Codable, Equatable {
    var watching: Bool? = nil
    var stoppedAt: Date? = nil
    var steps: Int? = nil
    var requiredSteps: Int? = nil
    var nextWatchAt: Date? = nil
    var lastWatchAt: Date? = nil
    var isSample: Bool = false

    static let file = "wake-watch.json"
    static let none = WakeWatchFeed(watching: false)

    private enum CodingKeys: String, CodingKey {
        case watching, stoppedAt, steps, requiredSteps, nextWatchAt, lastWatchAt
    }

    /// ファイルが無ければ「見張りなし」の見本（見張り中の見本は、ふだんの画面を隠してしまうので出さない）
    static func load() -> WakeWatchFeed {
        guard let f = SharedStore.load(WakeWatchFeed.self, from: file) else {
            var d = none
            d.isSample = true
            return d
        }
        return f
    }

    /// 見本：7:08 に止めて、100歩のうち 37歩。次の見張りは 10分後
    static func demo(now: Date = .now) -> WakeWatchFeed {
        let stopped: Date = now.addingTimeInterval(-4 * 60)
        return WakeWatchFeed(watching: true, stoppedAt: stopped, steps: 37, requiredSteps: 100,
                             nextWatchAt: stopped.addingTimeInterval(10 * 60), lastWatchAt: stopped.addingTimeInterval(20 * 60))
    }

    /// いま見張り中か（止めてから3時間を過ぎたファイルは古いとみなす）
    func isWatching(_ now: Date) -> Bool {
        guard watching ?? false else { return false }
        if let s = stoppedAt, now.timeIntervalSince(s) > 3 * 3600 { return false }
        return true
    }

    var stepCount: Int { max(0, steps ?? 0) }
    var stepGoal: Int { max(1, requiredSteps ?? 100) }
    var stepsLeft: Int { max(0, stepGoal - stepCount) }
    var fraction: Double { min(1, Double(stepCount) / Double(stepGoal)) }
}

/// 家計簿の今月の合計
struct KakeiboFeed: Codable, Equatable {
    var month: String? = nil
    var spent: Int? = nil
    var budget: Int? = nil
    var remaining: Int? = nil
    var isSample: Bool = false

    static let file = "kakeibo-summary.json"

    private enum CodingKeys: String, CodingKey {
        case month, spent, budget, remaining
    }

    static func load(now: Date = .now) -> KakeiboFeed {
        guard let f = SharedStore.load(KakeiboFeed.self, from: file) else {
            var d = demo(now: now)
            d.isSample = true
            return d
        }
        return f
    }

    static func demo(now: Date = .now) -> KakeiboFeed {
        KakeiboFeed(month: WidgetFeedDay.monthKey(now), spent: 32400, budget: 50000, remaining: 17600)
    }

    /// 今月の支出（違う月のファイルなら 0）
    func spentThisMonth(_ now: Date) -> Int {
        guard month == nil || month == WidgetFeedDay.monthKey(now) else { return 0 }
        return max(0, spent ?? 0)
    }

    /// 予算の残り（予算が無ければ nil）
    func remainingThisMonth(_ now: Date) -> Int? {
        guard let b = budget, b > 0 else { return nil }
        if month == nil || month == WidgetFeedDay.monthKey(now), let r = remaining { return r }
        return b - spentThisMonth(now)
    }

    /// 予算に対する支出の割合（0〜1。予算が無ければ nil）
    func usedFraction(_ now: Date) -> Double? {
        guard let b = budget, b > 0 else { return nil }
        return min(1, Double(spentThisMonth(now)) / Double(b))
    }
}

/// 日・月の文字（yyyy-MM-dd / yyyy-MM）と、金額・残り時間の表示
enum WidgetFeedDay {
    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = pattern
        return f
    }
    private static let dayF = fmt("yyyy-MM-dd")
    private static let monthF = fmt("yyyy-MM")
    private static let yen: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    static func key(_ d: Date) -> String { dayF.string(from: d) }
    static func monthKey(_ d: Date) -> String { monthF.string(from: d) }

    /// 「¥32,400」
    static func yenText(_ v: Int) -> String {
        let s: String = yen.string(from: NSNumber(value: abs(v))) ?? "\(abs(v))"
        return (v < 0 ? "-¥" : "¥") + s
    }

    /// 「あと 2時間」「あと 40分」「あと 1時間30分」（minutes 以下は分まで）
    static func untilText(_ to: Date, from now: Date) -> String {
        let mins: Int = max(0, Int((to.timeIntervalSince(now) / 60).rounded(.up)))
        if mins < 60 { return "あと\(mins)分" }
        let h: Int = mins / 60
        let m: Int = mins % 60
        if m == 0 || h >= 3 { return "あと\(h)時間" }
        return "あと\(h)時間\(m)分"
    }

    /// 「7時間30分」（眠れる時間など）
    static func durationText(_ seconds: TimeInterval) -> String {
        let mins: Int = max(0, Int(seconds / 60))
        let h: Int = mins / 60
        let m: Int = mins % 60
        if h == 0 { return "\(m)分" }
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }
}
