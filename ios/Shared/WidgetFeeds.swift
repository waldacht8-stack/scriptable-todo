import Foundation

// MARK: - ウィジェットが読むだけの共有データ（リリース4）
//
// 見返し・見張り・家計簿の本当の型（ReviewState / WakeWatchState / KakeiboSummary）は、
// それぞれの担当が別の枝で作っている。この枝だけでもビルドできるよう、ウィジェット側は
// App Group の JSON を直接読む小さな型を持つ（名前は本物とぶつからないよう *Feed にしている）。
// 統合のときは、持ち主の型が下の JSON を書き出す（または、この Feed を持ち主の型から作る）ようにそろえる。
//
// 統合後（リリース4）：見返しは ReviewState.load()、見張りは WakeWatchState.load() から Feed を作る
// （review-state.json は無い。wake-watch.json は持ち主の WakeWatchRecord で、下の形とは違う）。
// 相談は持ち主の ConsultWidgetFeed を読み、気分の番号を直す。家計簿・情報は下の JSON をそのまま読む。
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
//   "month": "2026-10",               // 周期の呼び名の月（給料日 25 日なら 9/25〜10/24 が「10月分」）
//   "spent": 32400,                   // 周期の支出（円・整数）
//   "income": 210000,                 // 周期の収入（円・整数）
//   "cycleStart": "2026-09-25",       // 周期の最初の日（給料日。土日・祝日なら前の営業日）
//   "cycleEnd": "2026-10-22",         // 周期の最後の日（含む）。今日がこの外なら支出・収入 0 として扱う
//   "payday": 25,                     // 給料日（1〜31。なしは null で暦の月）。「給料日まであと◯日」に使う
//   "topCategories": [                // 周期の支出の多い分類（多い順。中サイズに上位3つ。任意）
//     { "name": "食費", "amount": 12800 }
//   ]
// }
//
// consult-widget.json（相談。情報・相談の担当が書く）
// {
//   "day": "2026-10-11",              // この状態の日（yyyy-MM-dd）。今日でなければ気分は未記録・1日1枚はまだ
//   "todayMood": 1,                   // 今日の気分（ConsultMood の番号：0 最高・1 いい・2 ふつう・3 いまいち・4 つらい。未記録なら省略）
//   "dayCardWritten": false,          // 今日の「1日1枚」を書いたか
//   "streakDays": 5                   // 気分を記録した連続日数
// }
// ※ 持ち主が実際に書くのは ConsultWidgetFeed（Shared/ConsultIntents.swift。todayMood は点数 5 最高〜1 つらい）。
//    ConsultFeed.load() がそれを読み、上の番号（0 最高〜4 つらい）に直す。
// ※ 気分のボタンは LogMoodIntent(level:)。level は点数（5 最高〜1 つらい）なので、ボタンは ConsultMood の score を渡す
//
// info-widget.json（情報。情報の担当が書く）
// {
//   "headlines": [                    // 未読の話題の見出し（新しい順。ウィジェットは先頭の 2〜3 件）
//     { "title": "…", "source": "はてな", "topic": "猫", "colorIndex": 0 }   // colorIndex は InfoTopicColor の番号（0 強調色・1 青・2 オレンジ・3 緑・4 ピンク・5 紫・6 青緑）
//   ],
//   "splat": {                        // スプラトゥーン3 のいまのステージ（任意）
//     "endsAt": "2026-10-11T15:00:00+09:00",   // いまの時間帯が終わる（次に切り替わる）時刻
//     "regular": "ユノハナ大渓谷",              // レギュラーマッチのステージ（「・」区切りで2つでもよい）
//     "bankara": "ヤガラ市場",                  // バンカラマッチ
//     "x": "マテガイ放水路"                     // Xマッチ
//   },
//   "steamSale": { "title": "…", "discount": 75 }   // Steam のセール（任意。discount は割引率 %）
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

    private enum CodingKeys: String, CodingKey {
        case day, morningDone, noonDone, nightDone, nextReviewAt, streak, unreviewedCount
    }

    /// 持ち主の ReviewState（Shared/ReviewData.swift。review-log.json などから now の時点で作る）から作る
    static func load(now: Date = .now) -> ReviewFeed {
        let s: ReviewState = ReviewState.load(now: now)
        return ReviewFeed(day: WidgetFeedDay.key(now), morningDone: s.morningDone, noonDone: s.noonDone,
                          nightDone: s.nightDone, nextReviewAt: s.nextAt, streak: s.streak,
                          unreviewedCount: s.unreviewedCount)
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

    static let none = WakeWatchFeed(watching: false)

    private enum CodingKeys: String, CodingKey {
        case watching, stoppedAt, steps, requiredSteps, nextWatchAt, lastWatchAt
    }

    /// 持ち主の WakeWatchState（Shared/WakeWatch.swift。wake-watch.json の WakeWatchRecord から作る）から作る。
    /// 見張りが無ければ「見張りなし」
    static func load(now: Date = .now) -> WakeWatchFeed {
        let s: WakeWatchState = WakeWatchState.load(now: now)
        guard s.isWatching else { return none }
        let last: Date? = WakeWatchStore.active(now: now)?.alarms.map(\.at).max()
        return WakeWatchFeed(watching: true, stoppedAt: s.stopAt, steps: s.steps, requiredSteps: s.requiredSteps,
                             nextWatchAt: s.nextWatchAt, lastWatchAt: last)
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

/// 家計簿の周期（給料日から次の給料日の前の日まで）の合計
struct KakeiboFeed: Codable, Equatable {
    var month: String? = nil            // 周期の呼び名の月（「10月分」の 2026-10）
    var spent: Int? = nil
    var income: Int? = nil
    var cycleStart: String? = nil       // yyyy-MM-dd
    var cycleEnd: String? = nil         // yyyy-MM-dd（最後の日を含む）
    var payday: Int? = nil              // 給料日（なしは暦の月）
    var topCategories: [Category]? = nil
    var isSample: Bool = false

    struct Category: Codable, Equatable, Hashable {
        var name: String
        var amount: Int
    }

    static let file = "kakeibo-summary.json"

    private enum CodingKeys: String, CodingKey {
        case month, spent, income, cycleStart, cycleEnd, payday, topCategories
    }

    /// ファイルの周期が、いまの周期か（前の版のファイル＝周期の日付なし、は暦の月で比べる）
    func isCurrent(_ now: Date) -> Bool {
        if let a = cycleStart, let b = cycleEnd {
            let today: String = WidgetFeedDay.key(now)
            return a <= today && today <= b
        }
        return month == nil || month == WidgetFeedDay.monthKey(now)
    }

    /// いまの周期（ファイルが古くても、給料日から決める）
    func cycle(_ now: Date) -> KakeiboCycle.Period { KakeiboCycle.period(containing: now, payday: payday) }

    /// 「10月分の支出」
    func title(_ now: Date) -> String { cycle(now).title + "の支出" }

    /// いまの周期の分類の上位（違う周期なら空）
    func categories(_ now: Date) -> [Category] {
        guard isCurrent(now) else { return [] }
        return (topCategories ?? []).sorted { $0.amount > $1.amount }
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
        let c = KakeiboCycle.period(containing: now, payday: 25)
        return KakeiboFeed(month: WidgetFeedDay.monthKey(c.label), spent: 32400, income: 210000,
                           cycleStart: WidgetFeedDay.key(c.start), cycleEnd: WidgetFeedDay.key(c.lastDay), payday: 25,
                           topCategories: [Category(name: "食費", amount: 12800), Category(name: "日用品", amount: 6400),
                                           Category(name: "交通", amount: 4200), Category(name: "サブスク", amount: 3900)])
    }

    /// いまの周期の支出（違う周期のファイルなら 0）
    func spentNow(_ now: Date) -> Int { isCurrent(now) ? max(0, spent ?? 0) : 0 }

    /// いまの周期の収入（違う周期のファイルなら 0）
    func incomeNow(_ now: Date) -> Int { isCurrent(now) ? max(0, income ?? 0) : 0 }

    /// 残り（収入 − 支出）
    func leftNow(_ now: Date) -> Int { incomeNow(now) - spentNow(now) }

    /// 次の給料日まであと何日（給料日なしは nil、今日なら 0）
    func daysToPayday(_ now: Date) -> Int? { KakeiboCycle.daysToPayday(now: now, payday: payday) }

    /// 周期の進み（0〜1。ロック画面の輪）
    func elapsedFraction(_ now: Date) -> Double {
        let c = cycle(now)
        let total: Double = c.end.timeIntervalSince(c.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(c.start) / total))
    }

    /// 「給料日まであと3日」「今日は給料日」（給料日なしは「月末まであと◯日」）
    func paydayText(_ now: Date) -> String {
        if let d = daysToPayday(now) { return d == 0 ? "今日は給料日" : "給料日まであと\(d)日" }
        let c = cycle(now)
        let left: Int = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: c.end).day ?? 0
        return "月末まであと\(max(0, left))日"
    }
}

/// 相談：今日の気分と「1日1枚」
struct ConsultFeed: Codable, Equatable {
    var day: String? = nil
    var todayMood: Int? = nil
    var dayCardWritten: Bool? = nil
    var streakDays: Int? = nil
    var isSample: Bool = false

    static let file = "consult-widget.json"

    private enum CodingKeys: String, CodingKey {
        case day, todayMood, dayCardWritten, streakDays
    }

    /// 持ち主（ConsultWidgetSync）が書く consult-widget.json を読み、点数（5〜1）を ConsultMood の番号（0〜4）に直す
    static func load(now: Date = .now) -> ConsultFeed {
        guard let w = ConsultWidgetSync.load() else {
            var d = demo(now: now)
            d.isSample = true
            return d
        }
        let mood: Int? = w.todayMood.map { ConsultMood.from(score: $0).rawValue }
        return ConsultFeed(day: w.day, todayMood: mood, dayCardWritten: w.dayCardWritten, streakDays: w.streakDays)
    }

    /// 見本：今日は「いい」、1日1枚はまだ、5日連続
    static func demo(now: Date = .now) -> ConsultFeed {
        ConsultFeed(day: WidgetFeedDay.key(now), todayMood: 1, dayCardWritten: false, streakDays: 5)
    }

    private func isToday(_ now: Date) -> Bool { day == nil || day == WidgetFeedDay.key(now) }

    /// 今日の気分（0 最高〜4 つらい。未記録なら nil）
    func mood(_ now: Date) -> Int? {
        guard isToday(now), let m = todayMood, (0...4).contains(m) else { return nil }
        return m
    }

    func cardWritten(_ now: Date) -> Bool { isToday(now) && (dayCardWritten ?? false) }

    /// 夕方（18時）以降で、今日の1枚がまだか
    func cardDue(_ now: Date) -> Bool {
        Calendar.current.component(.hour, from: now) >= 18 && !cardWritten(now)
    }
}

/// 気分の印（相談の ConsultMood と同じ番号・名前・アイコン。ウィジェットからはアプリの型が見えないため別に持つ）
enum WidgetMood {
    static let titles: [String] = ["最高", "いい", "ふつう", "いまいち", "つらい"]
    static let symbols: [String] = ["sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.drizzle.fill", "cloud.heavyrain.fill"]

    static func title(_ level: Int) -> String { titles[max(0, min(4, level))] }
    static func symbol(_ level: Int) -> String { symbols[max(0, min(4, level))] }
}

/// 情報：未読の見出し・スプラトゥーンのステージ・Steam のセール
struct InfoFeed: Codable, Equatable {
    struct Headline: Codable, Equatable, Hashable {
        var title: String
        var source: String? = nil
        var topic: String? = nil
        var colorIndex: Int? = nil
    }

    struct Splat: Codable, Equatable {
        var endsAt: Date? = nil
        var regular: String? = nil
        var bankara: String? = nil
        var x: String? = nil
    }

    struct SteamSale: Codable, Equatable {
        var title: String
        var discount: Int? = nil
    }

    var headlines: [Headline]? = nil
    var splat: Splat? = nil
    var steamSale: SteamSale? = nil
    var isSample: Bool = false
    /// 情報 › ゲームの並びで Steam がスプラトゥーンより前（保存しない。読むときに設定から決める）
    var steamFirst: Bool = false

    static let file = "info-widget.json"

    private enum CodingKeys: String, CodingKey {
        case headlines, splat, steamSale
    }

    static func load(now: Date = .now) -> InfoFeed {
        let settings: AppSettings = SettingsData.load()
        guard let f = SharedStore.load(InfoFeed.self, from: file) else {
            var d = demo(now: now)
            d.isSample = true
            return d.applyingGames(settings)
        }
        return f.applyingGames(settings)
    }

    /// 情報 › ゲームの設定を当てる：オフにしたゲームは消し、並びの順を覚える
    func applyingGames(_ s: AppSettings) -> InfoFeed {
        var out: InfoFeed = self
        if !s.isGameShown(.splatoon) { out.splat = nil }
        if !s.isGameShown(.steam) { out.steamSale = nil }
        let order: [GameItem] = s.gameOrderItems
        let steamAt: Int = order.firstIndex(of: .steam) ?? 0
        let splatAt: Int = order.firstIndex(of: .splatoon) ?? 0
        out.steamFirst = steamAt < splatAt
        return out
    }

    /// 見本：一般的な話題の見出し3件、次の切り替わりは次の奇数時、Steam のセール
    static func demo(now: Date = .now) -> InfoFeed {
        let cal = Calendar.current
        let h: Int = cal.component(.hour, from: now)
        let nextOdd: Int = h % 2 == 0 ? h + 1 : h + 2
        let ends: Date = cal.date(byAdding: .hour, value: nextOdd, to: cal.startOfDay(for: now)) ?? now
        return InfoFeed(
            headlines: [
                Headline(title: "保護猫カフェが駅前にオープン、譲渡会も毎月開催", source: "Google ニュース", topic: "猫", colorIndex: 0),
                Headline(title: "新しい iPhone のバッテリー持ちを1週間試した", source: "はてな", topic: "iPhone", colorIndex: 1),
                Headline(title: "秋のキャンプ場、予約が取りやすい穴場まとめ", source: "Bluesky", topic: "キャンプ", colorIndex: 3),
            ],
            splat: Splat(endsAt: ends, regular: "ユノハナ大渓谷・ヤガラ市場", bankara: "マテガイ放水路", x: "ナメロウ金属"),
            steamSale: SteamSale(title: "秋のセール：インディーゲーム", discount: 75))
    }

    var shownHeadlines: [Headline] { headlines ?? [] }

    /// いまのステージ（終わっていれば nil）
    func currentSplat(_ now: Date) -> Splat? {
        guard let s = splat else { return nil }
        if let e = s.endsAt, e <= now { return nil }
        return s
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
