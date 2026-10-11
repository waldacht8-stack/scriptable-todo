import Foundation
import UserNotifications

// TODO の見返し（1日3回：朝＝起床アラームの「止める」かチェックインの直後・昼12時・夜21時）。
// 日曜の夜は週1回の棚卸し（期限なし・7日以上前からあるもの）も足す。
// 保存先：review-log.json（済んだ見返し・TODO を初めて見た日）、review-settings.json（時刻など）。
// 通知の識別子は review- で始める（TODO・起床の通知には触らない）。

// MARK: - 見返しの枠

enum ReviewSlot: String, Codable, CaseIterable, Identifiable {
    case morning, noon, night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .morning: "朝"
        case .noon: "昼"
        case .night: "夜"
        }
    }

    var title: String { "\(name)の見返し" }

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .noon: "sun.max.fill"
        case .night: "moon.stars.fill"
        }
    }
}

/// 見返しの設定（時刻は 0時からの分）
struct ReviewSettings: Codable, Hashable {
    /// 見返しの通知を出す
    var on = true
    /// 朝（起床アラームを止めなかった日・アラームの無い日）
    var morningMinute = 8 * 60 + 30
    var noonMinute = 12 * 60
    var nightMinute = 21 * 60
    /// 30分たっても開かなければ、もう一度知らせる
    var renotify = true
    /// 棚卸しの曜日（日曜=0 … 土曜=6）
    var weeklyDay = 0

    init() {}

    init(from decoder: Decoder) throws {
        let d = ReviewSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = (try? c.decodeIfPresent(Bool.self, forKey: .on)) ?? d.on
        morningMinute = (try? c.decodeIfPresent(Int.self, forKey: .morningMinute)) ?? d.morningMinute
        noonMinute = (try? c.decodeIfPresent(Int.self, forKey: .noonMinute)) ?? d.noonMinute
        nightMinute = (try? c.decodeIfPresent(Int.self, forKey: .nightMinute)) ?? d.nightMinute
        renotify = (try? c.decodeIfPresent(Bool.self, forKey: .renotify)) ?? d.renotify
        weeklyDay = (try? c.decodeIfPresent(Int.self, forKey: .weeklyDay)) ?? d.weeklyDay
    }

    func minute(_ slot: ReviewSlot) -> Int {
        switch slot {
        case .morning: morningMinute
        case .noon: noonMinute
        case .night: nightMinute
        }
    }
}

/// 1日分の見返し（キーは ReviewSlot.rawValue）
struct ReviewDay: Codable, Hashable {
    /// 済ませた時刻
    var done: [String: Date] = [:]
    /// 開いた時刻（開いたら再通知はしない）
    var opened: [String: Date] = [:]
    /// 見返した TODO
    var reviewed: [String: [String]] = [:]
    /// 朝の見返しが始まった時刻（起床アラームの「止める」・チェックイン）
    var morningAt: Date? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = (try? c.decodeIfPresent([String: Date].self, forKey: .done)) ?? [:]
        opened = (try? c.decodeIfPresent([String: Date].self, forKey: .opened)) ?? [:]
        reviewed = (try? c.decodeIfPresent([String: [String]].self, forKey: .reviewed)) ?? [:]
        morningAt = try? c.decodeIfPresent(Date.self, forKey: .morningAt)
    }

    func isDone(_ s: ReviewSlot) -> Bool { done[s.rawValue] != nil }
    var allDone: Bool { ReviewSlot.allCases.allSatisfy { isDone($0) } }
}

struct ReviewLog: Codable, Hashable {
    /// yyyy-MM-dd（朝4時で日を区切る）→ その日の見返し
    var days: [String: ReviewDay] = [:]
    /// TODO を初めて見た時刻（作成日の代わり。「3日以上前から」「7日以上前から」に使う）
    var seen: [String: Date] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? c.decodeIfPresent([String: ReviewDay].self, forKey: .days)) ?? [:]
        seen = (try? c.decodeIfPresent([String: Date].self, forKey: .seen)) ?? [:]
    }

    func day(_ key: String) -> ReviewDay { days[key] ?? ReviewDay() }
}

enum ReviewStore {
    static let logFile = "review-log.json"
    static let settingsFile = "review-settings.json"

    static func log() -> ReviewLog { SharedStore.load(ReviewLog.self, from: logFile) ?? ReviewLog() }
    static func save(_ l: ReviewLog) { SharedStore.save(l, to: logFile) }
    static func settings() -> ReviewSettings { SharedStore.load(ReviewSettings.self, from: settingsFile) ?? ReviewSettings() }
    static func save(_ s: ReviewSettings) { SharedStore.save(s, to: settingsFile) }

    /// TODO を初めて見た時刻を覚える。消えた TODO と、60日より前の見返しの記録は忘れる。変わったときだけ保存
    static func noteSeen(_ items: [TodoItem], now: Date = .now) {
        var l = log()
        let before = l
        l.seen = ReviewLogic.updatedSeen(l.seen, items: items, now: now)
        if let limit = Calendar.current.date(byAdding: .day, value: -60, to: now) {
            let k = WakeLogic.key(limit)
            l.days = l.days.filter { $0.key >= k }
        }
        if l != before { save(l) }
    }

    static func update(_ key: String, _ change: (inout ReviewDay) -> Void) {
        var l = log()
        var d = l.day(key)
        change(&d)
        l.days[key] = d
        save(l)
    }
}

// MARK: - 判定（副作用なし。テストする）

enum ReviewLogic {
    /// 朝4時までは前の日の夜とみなす
    static let dayStartHour = 4
    /// 再通知までの分
    static let renotifyMinutes = 30
    /// 「忘れそうな1件」：これより前からある TODO
    static let forgottenDays = 3
    /// 棚卸し：これより前からある TODO
    static let staleDays = 7
    /// 1回の見返しで出す枚数（30秒ほどで終わるように）
    static let maxCards: [ReviewSlot: Int] = [.morning: 6, .noon: 6, .night: 8]
    static let maxWeekly = 6

    static var cal: Calendar { Calendar.current }

    /// 見返しの日（0時〜4時は前の日）
    static func reviewDay(_ now: Date) -> Date {
        cal.startOfDay(for: now.addingTimeInterval(TimeInterval(-dayStartHour * 3600)))
    }

    static func key(_ now: Date) -> String { WakeLogic.key(reviewDay(now)) }

    static func addDays(_ n: Int, _ d: Date) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }

    /// その日の枠の始まり。朝は「止める」・チェックインの時刻、なければ設定の時刻
    static func start(_ slot: ReviewSlot, on day: Date, settings s: ReviewSettings, log d: ReviewDay?) -> Date {
        if slot == .morning, let at = d?.morningAt { return at }
        return cal.date(byAdding: .minute, value: s.minute(slot), to: day) ?? day
    }

    /// 手で始めるときの枠：夜の時刻を過ぎていれば夜、昼を過ぎていれば昼、それより前は朝
    static func slot(at now: Date, settings s: ReviewSettings) -> ReviewSlot {
        let day = reviewDay(now)
        if now >= start(.night, on: day, settings: s, log: nil) || day < cal.startOfDay(for: now) { return .night }
        if now >= start(.noon, on: day, settings: s, log: nil) { return .noon }
        return .morning
    }

    /// 今やる見返し（今の枠の時刻を過ぎて、まだ済んでいない）
    static func due(now: Date, settings s: ReviewSettings, log: ReviewLog) -> ReviewSlot? {
        let slot = slot(at: now, settings: s)
        let d = log.day(key(now))
        if d.isDone(slot) { return nil }
        return now >= start(slot, on: reviewDay(now), settings: s, log: d) ? slot : nil
    }

    /// 「前回の見返しがまだです」：今の枠の1つ前（朝なら前の日の夜）が済んでいない。
    /// まだ一度も見返していない人には出さない
    static func previousMissed(before slot: ReviewSlot, now: Date, log: ReviewLog) -> ReviewSlot? {
        let today = key(now)
        guard log.days.contains(where: { $0.key < today && !$0.value.done.isEmpty }) else { return nil }
        switch slot {
        case .morning:
            let y = WakeLogic.key(addDays(-1, reviewDay(now)))
            return log.day(y).isDone(.night) ? nil : .night
        case .noon:
            return log.day(today).isDone(.morning) ? nil : .morning
        case .night:
            return log.day(today).isDone(.noon) ? nil : .noon
        }
    }

    /// 連続日数（3回とも済ませた日が続いた数。今日がまだ途中なら昨日から数える）
    static func streak(_ log: ReviewLog, now: Date) -> Int {
        var day = reviewDay(now)
        if !log.day(WakeLogic.key(day)).allDone { day = addDays(-1, day) }
        var n = 0
        while n < 1000, log.day(WakeLogic.key(day)).allDone {
            n += 1
            day = addDays(-1, day)
        }
        return n
    }

    // MARK: 期限内の完了（今週）

    /// 今週の月曜
    static func weekStart(_ now: Date) -> Date {
        let today = cal.startOfDay(for: now)
        let w = cal.component(.weekday, from: today)   // 日曜 = 1
        let back = (w + 5) % 7
        return addDays(-back, today)
    }

    /// 期限の締め切り（終日なら、その日の終わり）
    static func deadline(_ t: TodoItem) -> Date? {
        guard let due = t.due else { return nil }
        return t.isAllDay ? addDays(1, cal.startOfDay(for: due)) : due
    }

    /// 今週が期限の TODO のうち、期限までに完了した数と、数えた数（期限が来たもの・完了したもの）
    static func onTime(_ items: [TodoItem], now: Date) -> (onTime: Int, total: Int) {
        let ws = weekStart(now)
        let we = addDays(7, ws)
        var ok = 0
        var total = 0
        for t in items {
            guard let due = t.due, due >= ws, due < we, let dl = deadline(t) else { continue }
            if t.done {
                total += 1
                if let at = t.doneAt, at <= dl { ok += 1 }
            } else if dl <= now {
                total += 1
            }
        }
        return (ok, total)
    }

    /// 期限内の完了率（%）。数えるものが無ければ nil
    static func onTimePercent(_ items: [TodoItem], now: Date) -> Int? {
        let r = onTime(items, now: now)
        guard r.total > 0 else { return nil }
        return Int((Double(r.onTime) / Double(r.total) * 100).rounded())
    }

    // MARK: 初めて見た日・忘れそうな1件

    static func updatedSeen(_ seen: [String: Date], items: [TodoItem], now: Date) -> [String: Date] {
        let ids = Set(items.map(\.id))
        var s = seen.filter { ids.contains($0.key) }
        for t in items where s[t.id] == nil { s[t.id] = now }
        return s
    }

    /// 3日以上前からある未完了の TODO から、日ごとに順番に1件
    static func forgotten(_ items: [TodoItem], seen: [String: Date], now: Date) -> TodoItem? {
        let limit = now.addingTimeInterval(TimeInterval(-forgottenDays * 86400))
        let cands = items.filter { t in !t.done && (seen[t.id].map { $0 <= limit } ?? false) }.sorted { $0.id < $1.id }
        guard !cands.isEmpty else { return nil }
        let dayNumber = Int((reviewDay(now).timeIntervalSinceReferenceDate / 86400).rounded())
        let c = cands.count
        return cands[((dayNumber % c) + c) % c]
    }

    /// 今夜が棚卸しの日か
    static func isWeekly(now: Date, settings s: ReviewSettings) -> Bool {
        WakeLogic.weekday(reviewDay(now)) == s.weeklyDay
    }

    /// 夜の「今週」：週末（土曜。明日から数えるので、今日にはならない）
    static func thisWeekDay(from now: Date) -> Date {
        let tomorrow = addDays(1, cal.startOfDay(for: now))
        let w = cal.component(.weekday, from: tomorrow)   // 日曜 = 1 … 土曜 = 7
        if w == 7 || w == 1 { return tomorrow }
        return addDays(7 - w, tomorrow)
    }

    // MARK: 見返しのカード

    enum CardKind: String, Hashable {
        case overdue      // 期限切れ
        case today        // 今日
        case afternoon    // 今日の午後
        case unfinished   // 今日の残り（夜）
        case noDue        // 期限なし（棚卸し）
        case stale        // 7日以上前から（棚卸し）
        case forgotten    // 忘れそうな1件

        var label: String {
            switch self {
            case .overdue: "期限切れ"
            case .today: "今日"
            case .afternoon: "午後まで"
            case .unfinished: "今日の残り"
            case .noDue: "棚卸し・期限なし"
            case .stale: "棚卸し・7日以上前から"
            case .forgotten: "忘れそうな1件"
            }
        }
    }

    struct Card: Identifiable, Hashable {
        let item: TodoItem
        let kind: CardKind
        var id: String { item.id }
    }

    struct Plan: Hashable {
        var slot: ReviewSlot
        var cards: [Card]
        /// 夜：明日の最初の3件
        var preview: [TodoItem]
        var weekly: Bool
        /// 出しきれなかった数
        var more: Int
    }

    static func plan(_ slot: ReviewSlot, items: [TodoItem], seen: [String: Date], now: Date, weekly: Bool) -> Plan {
        let day = reviewDay(now)
        let end = addDays(1, day)
        let noon = cal.date(byAdding: .hour, value: 12, to: day) ?? day
        let open = TodoData.sorted(items.filter { !$0.done })
        let todays = open.filter { ($0.due ?? .distantFuture) < end }
        let cap = maxCards[slot] ?? 6
        var all: [Card] = todays.map { (t: TodoItem) -> Card in
            let kind: CardKind
            if t.isOverdue(now) && slot != .night { kind = .overdue }
            else if slot == .night { kind = .unfinished }
            else if slot == .noon, !t.isAllDay, let due = t.due, due >= noon { kind = .afternoon }
            else { kind = .today }
            return Card(item: t, kind: kind)
        }
        var more = max(0, all.count - cap)
        all = Array(all.prefix(cap))
        var isWeekly = false
        if slot == .night && weekly {
            isWeekly = true
            let staleLimit = now.addingTimeInterval(TimeInterval(-staleDays * 86400))
            let taken = Set(all.map(\.id))
            let extra = open.filter { t in
                guard !taken.contains(t.id), !todays.contains(where: { $0.id == t.id }) else { return false }
                if t.due == nil { return true }
                return seen[t.id].map { $0 <= staleLimit } ?? false
            }
            more += max(0, extra.count - maxWeekly)
            all += extra.prefix(maxWeekly).map { Card(item: $0, kind: $0.due == nil ? .noDue : .stale) }
        }
        if let f = forgotten(items, seen: seen, now: now), !all.contains(where: { $0.id == f.id }) {
            all.append(Card(item: f, kind: .forgotten))
        }
        let preview: [TodoItem] = slot == .night
            ? Array(open.filter { t in guard let due = t.due else { return false }; return due >= end && due < addDays(1, end) }.prefix(3))
            : []
        return Plan(slot: slot, cards: all, preview: preview, weekly: isWeekly, more: more)
    }

    // MARK: 通知の予定

    struct Notice: Hashable {
        let id: String
        let slot: ReviewSlot
        let at: Date
        let again: Bool
        let day: String
    }

    /// 今日と明日の見返しの通知（済んだ枠は除く。開いていなければ30分後にもう一度）
    static func notices(now: Date, settings s: ReviewSettings, log: ReviewLog) -> [Notice] {
        guard s.on else { return [] }
        var out: [Notice] = []
        for i in 0..<2 {
            let day = addDays(i, reviewDay(now))
            let k = WakeLogic.key(day)
            let d = log.day(k)
            for slot in ReviewSlot.allCases where !d.isDone(slot) {
                let at = start(slot, on: day, settings: s, log: d)
                if at > now {
                    out.append(Notice(id: "review-\(slot.rawValue)-\(k)", slot: slot, at: at, again: false, day: k))
                }
                let again = at.addingTimeInterval(TimeInterval(renotifyMinutes * 60))
                if s.renotify, d.opened[slot.rawValue] == nil, again > now {
                    out.append(Notice(id: "review-\(slot.rawValue)-\(k)-again", slot: slot, at: again, again: true, day: k))
                }
            }
        }
        return out.sorted { $0.at < $1.at }
    }
}

// MARK: - ウィジェット向けの読み出し（ウィジェット担当はこれを読むだけ）

/// 見返しの状態
struct ReviewState: Hashable {
    var morningDone: Bool
    var noonDone: Bool
    var nightDone: Bool
    /// 次の見返しの時刻と枠（今やるものがあれば、その次）
    var nextAt: Date?
    var nextSlot: ReviewSlot?
    /// 今やる見返し（時刻を過ぎて、まだ済んでいない）
    var dueSlot: ReviewSlot?
    /// 連続日数（3回とも済ませた日）
    var streak: Int
    /// 今やる見返しで、まだ見ていない TODO の数
    var unreviewedCount: Int
    /// 今週の期限内の完了率（%）
    var onTimePercent: Int?

    func isDone(_ s: ReviewSlot) -> Bool {
        switch s {
        case .morning: morningDone
        case .noon: noonDone
        case .night: nightDone
        }
    }

    static func load(now: Date = .now) -> ReviewState {
        make(log: ReviewStore.log(), settings: ReviewStore.settings(), items: TodoData.all(), now: now)
    }

    static func make(log: ReviewLog, settings s: ReviewSettings, items: [TodoItem], now: Date) -> ReviewState {
        let k = ReviewLogic.key(now)
        let d = log.day(k)
        let due = ReviewLogic.due(now: now, settings: s, log: log)
        var next: (ReviewSlot, Date)? = nil
        for i in 0..<2 where next == nil {
            let day = ReviewLogic.addDays(i, ReviewLogic.reviewDay(now))
            let dd = log.day(WakeLogic.key(day))
            for slot in ReviewSlot.allCases where !dd.isDone(slot) {
                let at = ReviewLogic.start(slot, on: day, settings: s, log: dd)
                if at > now { next = (slot, at); break }
            }
        }
        var unreviewed = 0
        if let due {
            let plan = ReviewLogic.plan(due, items: items, seen: log.seen, now: now,
                                        weekly: due == .night && ReviewLogic.isWeekly(now: now, settings: s))
            let seenIDs = Set(d.reviewed[due.rawValue] ?? [])
            unreviewed = plan.cards.filter { !seenIDs.contains($0.id) }.count
        }
        return ReviewState(morningDone: d.isDone(.morning), noonDone: d.isDone(.noon), nightDone: d.isDone(.night),
                           nextAt: next?.1, nextSlot: next?.0, dueSlot: due,
                           streak: ReviewLogic.streak(log, now: now), unreviewedCount: unreviewed,
                           onTimePercent: ReviewLogic.onTimePercent(items, now: now))
    }
}

// MARK: - 操作（アプリと AppIntent から呼ぶ）

enum ReviewActions {
    private static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// 見返しの通知を作り直す（review- で始まるものだけ）
    static func reschedule(now: Date = .now) async {
        if isDemo { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("review-") })
        let s = ReviewStore.settings()
        let log = ReviewStore.log()
        let items = TodoData.all()
        for n in ReviewLogic.notices(now: now, settings: s, log: log) {
            let content = Self.content(n.slot, again: n.again, at: n.at, items: items, log: log, settings: s)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: n.at)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
        }
    }

    private static func content(_ slot: ReviewSlot, again: Bool, at: Date, items: [TodoItem],
                                log: ReviewLog, settings s: ReviewSettings) -> UNMutableNotificationContent {
        let weekly = slot == .night && ReviewLogic.isWeekly(now: at, settings: s)
        let plan = ReviewLogic.plan(slot, items: items, seen: log.seen, now: at, weekly: weekly)
        let c = UNMutableNotificationContent()
        c.title = again ? "前回の見返しがまだです" : "\(slot.title)・30秒"
        let count = plan.cards.count
        let what: String
        switch slot {
        case .morning: what = count == 0 ? "今日のTODOはありません。開いて確認だけ" : "今日のTODO \(count)件"
        case .noon: what = count == 0 ? "残りはありません。開いて確認だけ" : "残りと午後のTODO \(count)件"
        case .night: what = weekly ? "今日の残りと、週1回の棚卸し \(count)件" : (count == 0 ? "今日の残りはありません" : "今日の残り \(count)件")
        }
        c.body = again ? "\(slot.title)：\(what)" : "\(what)。右で確認、左で明日へ"
        c.sound = .default
        c.threadIdentifier = "review"
        c.userInfo = ["review": slot.rawValue]
        return c
    }

    /// 朝の見返しを始める（起床アラームの「止める」・チェックインの直後）。notify なら、すぐ通知する
    static func morningTriggered(now: Date = .now, notify: Bool) async {
        let k = ReviewLogic.key(now)
        let d = ReviewStore.log().day(k)
        guard d.morningAt == nil, !d.isDone(.morning) else { return }
        ReviewStore.update(k) { $0.morningAt = now }
        await reschedule(now: now)
        guard notify, !isDemo, ReviewStore.settings().on else { return }
        let s = ReviewStore.settings()
        let log = ReviewStore.log()
        let c = content(.morning, again: false, at: now, items: TodoData.all(), log: log, settings: s)
        c.title = "おはようございます・朝の見返し"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "review-morning-\(k)", content: c, trigger: trigger))
    }

    /// 見返しを開いた（再通知を取り消す）
    static func opened(_ slot: ReviewSlot, now: Date = .now) async {
        let k = ReviewLogic.key(now)
        ReviewStore.update(k) { d in
            if d.opened[slot.rawValue] == nil { d.opened[slot.rawValue] = now }
        }
        await reschedule(now: now)
    }

    /// 1件見た
    static func reviewed(_ slot: ReviewSlot, id: String, now: Date = .now) {
        let k = ReviewLogic.key(now)
        ReviewStore.update(k) { d in
            var ids = d.reviewed[slot.rawValue] ?? []
            if !ids.contains(id) { ids.append(id) }
            d.reviewed[slot.rawValue] = ids
        }
    }

    /// 見返しを済ませた
    static func finished(_ slot: ReviewSlot, now: Date = .now) async {
        let k = ReviewLogic.key(now)
        ReviewStore.update(k) { d in
            d.done[slot.rawValue] = now
            if d.opened[slot.rawValue] == nil { d.opened[slot.rawValue] = now }
        }
        await reschedule(now: now)
    }
}
