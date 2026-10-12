import Foundation

// 起床のデータと判定（アプリ本体・ウィジェットの両方で使う）。
// 保存先：wake-settings.json（設定）、wake-state.json（その日の状態）、wake-sessions.json（起床記録）

/// 曜日ごとの設定（時刻は 0時からの分）
struct WakeDay: Codable, Hashable {
    var on: Bool
    var wake: Int
    var departure: Int?

    init(on: Bool = true, wake: Int = 420, departure: Int? = nil) {
        self.on = on; self.wake = wake; self.departure = departure
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? true
        wake = try c.decodeIfPresent(Int.self, forKey: .wake) ?? 420
        departure = try c.decodeIfPresent(Int.self, forKey: .departure)
    }
}

/// 段階（起床時刻からのずれ・分）
struct WakeStage: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var offset: Int

    init(id: String = UUID().uuidString, name: String, offset: Int) {
        self.id = id; self.name = name; self.offset = offset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let raw = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = ["そっと", "ふつう", "しっかり", "最終", "段階"].contains(raw) ? "" : raw   // 旧版の既定の名前は使わない
        offset = try c.decodeIfPresent(Int.self, forKey: .offset) ?? 0
    }
}

/// 朝のルーティンの1項目
struct WakeRoutineItem: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var minutes: Int

    init(id: String = UUID().uuidString, name: String, minutes: Int) {
        self.id = id; self.name = name; self.minutes = minutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 5
    }
}

/// 持ち物の1項目
struct WakeBelonging: Codable, Hashable, Identifiable {
    var id: String
    var name: String

    init(id: String = UUID().uuidString, name: String) { self.id = id; self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

/// 起床の設定
struct WakeSettings: Codable, Hashable {
    /// 日曜=0 … 土曜=6
    var days: [WakeDay]
    var stages: [WakeStage]
    /// 就寝時刻（0時からの分。12:00 より前は日付が変わった後とみなす）
    var bedtime: Int
    var routine: [WakeRoutineItem]
    var belongings: [WakeBelonging]
    var skipHolidays: Bool
    /// 「明日だけオフ」にした起床日（yyyy-MM-dd）
    var skipDay: String?
    /// すべてのアラームを止める
    var paused: Bool
    /// 二度寝の見張り（アラームの「止める」で始める）
    var watch: Bool
    /// 見張りのアラームを「止める」だけで止めたときに鳴らし直す上限
    var watchRearms: Int

    static let stageNames = ["", "", "", ""]   // 名前は任意（空なら「N回目」と表示）
    static let stageOffsets = [0, 10, 20, 30]

    init() {
        days = (0..<7).map { i in
            (1...5).contains(i) ? WakeDay(on: true, wake: 420, departure: 465) : WakeDay(on: false, wake: 480, departure: nil)
        }
        stages = (0..<4).map { WakeStage(name: Self.stageNames[$0], offset: Self.stageOffsets[$0]) }
        bedtime = 0
        routine = [
            WakeRoutineItem(name: "カーテンを開ける", minutes: 1),
            WakeRoutineItem(name: "洗顔", minutes: 5),
            WakeRoutineItem(name: "朝食", minutes: 15),
            WakeRoutineItem(name: "着替え", minutes: 10),
            WakeRoutineItem(name: "歯磨き", minutes: 5),
        ]
        belongings = ["鍵", "財布", "定期", "スマホ"].map { WakeBelonging(name: $0) }
        skipHolidays = true
        skipDay = nil
        paused = false
        watch = true
        watchRearms = WakeWatchLogic.defaultMaxRearms
    }

    init(from decoder: Decoder) throws {
        let d = WakeSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var ds = (try? c.decodeIfPresent([WakeDay].self, forKey: .days)) ?? d.days
        if ds.count != 7 { ds = d.days }
        days = ds
        var st = (try? c.decodeIfPresent([WakeStage].self, forKey: .stages)) ?? d.stages
        if st.isEmpty || st.count > 4 { st = d.stages }
        stages = st
        bedtime = (try? c.decodeIfPresent(Int.self, forKey: .bedtime)) ?? d.bedtime
        routine = (try? c.decodeIfPresent([WakeRoutineItem].self, forKey: .routine)) ?? d.routine
        belongings = (try? c.decodeIfPresent([WakeBelonging].self, forKey: .belongings)) ?? d.belongings
        skipHolidays = (try? c.decodeIfPresent(Bool.self, forKey: .skipHolidays)) ?? d.skipHolidays
        skipDay = (try? c.decodeIfPresent(String.self, forKey: .skipDay))
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? false
        watch = (try? c.decodeIfPresent(Bool.self, forKey: .watch)) ?? d.watch
        watchRearms = min(10, max(1, (try? c.decodeIfPresent(Int.self, forKey: .watchRearms)) ?? d.watchRearms))
    }
}

/// 予約したアラーム（取り消しに使う）
struct WakeScheduledAlarm: Codable, Hashable {
    var id: String
    var at: Date
    var day: String
    var stage: Int
}

/// その日の状態
struct WakeDayState: Codable {
    var day: String?
    var checkInAt: Date?
    var routineDone: [String]
    var belongingsDone: [String]
    var alarms: [WakeScheduledAlarm]
    /// アラームを予約した起床日（正午までにチェックインがなければ「未チェックイン」として記録する）
    var pendingDays: [String]
    /// 祝日（yyyy-MM-dd → 名前）。アプリがカレンダーから読み取って保存する
    var holidays: [String: String]

    init() {
        day = nil; checkInAt = nil; routineDone = []; belongingsDone = []; alarms = []; pendingDays = []; holidays = [:]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(String.self, forKey: .day))
        checkInAt = (try? c.decodeIfPresent(Date.self, forKey: .checkInAt))
        routineDone = (try? c.decodeIfPresent([String].self, forKey: .routineDone)) ?? []
        belongingsDone = (try? c.decodeIfPresent([String].self, forKey: .belongingsDone)) ?? []
        alarms = (try? c.decodeIfPresent([WakeScheduledAlarm].self, forKey: .alarms)) ?? []
        pendingDays = (try? c.decodeIfPresent([String].self, forKey: .pendingDays)) ?? []
        holidays = (try? c.decodeIfPresent([String: String].self, forKey: .holidays)) ?? [:]
    }
}

/// 起床記録（1日1件）
struct WakeSession: Codable, Hashable, Identifiable {
    var day: String
    var checkInAt: Date?
    var stage: Int          // 0 = 最初のアラームより前
    /// 昔の点数。もう表示も計算もしない（古い記録を読めるように残すだけ）
    var score: Int? = nil
    var missed: Bool? = nil
    // 二度寝の見張り（Shared/WakeWatch.swift）。見張りが無かった日は nil
    var oversleep: Int? = nil       // 二度寝の分（0 = 二度寝なし）
    var stopAt: Date? = nil         // 元のアラームを止めた時刻
    var watchedBy: String? = nil    // 見張りの終わり方（steps / walk / mission / checkin）

    var id: String { day }
    var isMissed: Bool { missed ?? false }
}

/// ある起床日の予定
struct WakePlan: Hashable {
    struct Stage: Hashable {
        var number: Int      // 1から
        var name: String
        var at: Date
    }
    var day: String
    var dayStart: Date
    var stages: [Stage]
    var departure: Date?
    /// オフの理由（明日だけオフ・祝日）。nil なら鳴る
    var skipReason: String?

    var first: Date { stages.first?.at ?? dayStart }
    var last: Date { stages.last?.at ?? dayStart }
    var isSkipped: Bool { skipReason != nil }
}

enum WakePhase: String {
    case before     // 次のアラームを待つ
    case window     // 起床中（チェックイン待ち）
    case morning    // チェックイン後、出発まで
    case day        // チェックイン後、出発の後
    case evening    // 18時以降
}

/// 画面確認用の時計（-demo のときだけずらす）
enum WakeClock {
    static var offset: TimeInterval = 0
    static var now: Date { Date().addingTimeInterval(offset) }
}

enum WakeStore {
    static let settingsFile = "wake-settings.json"
    static let stateFile = "wake-state.json"
    static let sessionsFile = "wake-sessions.json"

    static func settings() -> WakeSettings { SharedStore.load(WakeSettings.self, from: settingsFile) ?? WakeSettings() }
    static func save(_ s: WakeSettings) { SharedStore.save(s, to: settingsFile) }
    static func state() -> WakeDayState { SharedStore.load(WakeDayState.self, from: stateFile) ?? WakeDayState() }
    static func save(_ s: WakeDayState) { SharedStore.save(s, to: stateFile) }
    static func sessions() -> [WakeSession] {
        (SharedStore.load([WakeSession].self, from: sessionsFile) ?? []).sorted { $0.day > $1.day }
    }
    static func save(_ s: [WakeSession]) { SharedStore.save(s.sorted { $0.day > $1.day }, to: sessionsFile) }
}

enum WakeLogic {
    static var cal: Calendar { Calendar.current }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String {
        keyFormatter.timeZone = TimeZone.current
        return keyFormatter.string(from: d)
    }

    static func date(fromKey k: String) -> Date? {
        keyFormatter.timeZone = TimeZone.current
        return keyFormatter.date(from: k)
    }

    static func weekday(_ d: Date) -> Int { cal.component(.weekday, from: d) - 1 }

    static func minutes(_ m: Int, on dayStart: Date) -> Date {
        cal.date(byAdding: .minute, value: m, to: dayStart) ?? dayStart
    }

    /// その日の予定（曜日がオフなら nil）
    static func plan(for date: Date, settings s: WakeSettings, state: WakeDayState) -> WakePlan? {
        let start = cal.startOfDay(for: date)
        let d = s.days[weekday(start)]
        guard d.on, !s.stages.isEmpty else { return nil }
        let k = key(start)
        let stages = s.stages.enumerated().map { i, st in
            WakePlan.Stage(number: i + 1, name: st.name, at: minutes(d.wake + st.offset, on: start))
        }
        var reason: String? = nil
        if s.paused { reason = "アラームを停止中" }
        else if s.skipDay == k { reason = "明日だけオフ" }
        else if s.skipHolidays, let h = state.holidays[k] { reason = "祝日（\(h)）" }
        return WakePlan(day: k, dayStart: start, stages: stages,
                        departure: d.departure.map { minutes($0, on: start) }, skipReason: reason)
    }

    /// 今日から days 日分の予定（オフの曜日は除く）
    static func plans(from now: Date, days: Int, settings s: WakeSettings, state: WakeDayState) -> [WakePlan] {
        let start = cal.startOfDay(for: now)
        return (0..<days).compactMap { i in
            cal.date(byAdding: .day, value: i, to: start).flatMap { plan(for: $0, settings: s, state: state) }
        }
    }

    static func checkedIn(_ state: WakeDayState, now: Date) -> Date? {
        state.day == key(now) ? state.checkInAt : nil
    }

    /// 次に鳴る起床日（オフの日を除く。今日チェックイン済みなら今日を除く）
    static func nextPlan(now: Date, settings s: WakeSettings, state: WakeDayState, includeSkipped: Bool = false) -> WakePlan? {
        let checked = checkedIn(state, now: now) != nil
        let todayKey = key(now)
        return plans(from: now, days: 14, settings: s, state: state).first { p in
            if p.day == todayKey && checked { return false }
            if !includeSkipped && p.isSkipped { return false }
            return p.last > now
        }
    }

    /// 今日の出発時刻（曜日の設定から。チェックインの有無に関係なく）
    static func departure(now: Date, settings s: WakeSettings) -> Date? {
        let start = cal.startOfDay(for: now)
        return s.days[weekday(start)].departure.map { minutes($0, on: start) }
    }

    /// その時刻までに鳴った段階の数
    static func reached(_ plan: WakePlan, at: Date) -> Int {
        plan.stages.filter { $0.at <= at }.count
    }

    static func phase(now: Date, settings s: WakeSettings, state: WakeDayState) -> WakePhase {
        let hour = cal.component(.hour, from: now)
        if checkedIn(state, now: now) != nil {
            if let dep = departure(now: now, settings: s), now < dep { return .morning }
            return hour >= 18 ? .evening : .day
        }
        if canCheckIn(now: now, settings: s, state: state) {
            return .window
        }
        return hour >= 18 ? .evening : .before
    }

    /// その日のチェックインを受け付ける時間（最初のアラームの2時間前〜正午。遅い起床なら最後のアラームの1時間後まで）。
    /// 起きる日でない・オフの日は nil
    static func checkInWindow(for date: Date, settings s: WakeSettings, state: WakeDayState) -> (start: Date, end: Date)? {
        guard let p = plan(for: date, settings: s, state: state), !p.isSkipped else { return nil }
        let start: Date = p.first.addingTimeInterval(-2 * 3600)
        let noon: Date = cal.date(byAdding: .hour, value: 12, to: p.dayStart) ?? p.dayStart
        let end: Date = max(noon, p.last.addingTimeInterval(3600))
        return (start, end)
    }

    /// 今チェックインできるか（受付時間内で、まだチェックインしていない）
    static func canCheckIn(now: Date, settings s: WakeSettings, state: WakeDayState) -> Bool {
        guard checkedIn(state, now: now) == nil,
              let w = checkInWindow(for: now, settings: s, state: state) else { return false }
        return now >= w.start && now < w.end
    }

    /// 次にチェックインを押せるようになる時刻（今押せるなら今）
    static func nextCheckInStart(now: Date, settings s: WakeSettings, state: WakeDayState) -> Date? {
        let start = cal.startOfDay(for: now)
        let checked = checkedIn(state, now: now) != nil
        for i in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: i, to: start),
                  let w = checkInWindow(for: d, settings: s, state: state) else { continue }
            if i == 0 && checked { continue }
            if w.end > now { return max(w.start, now) }
        }
        return nil
    }

    /// 起床日の前夜の就寝時刻
    static func bedtime(before plan: WakePlan, settings s: WakeSettings) -> Date {
        if s.bedtime >= 12 * 60 {
            let prev = cal.date(byAdding: .day, value: -1, to: plan.dayStart) ?? plan.dayStart
            return minutes(s.bedtime, on: prev)
        }
        return minutes(s.bedtime, on: plan.dayStart)
    }

    /// 残りのルーティン（完了していないもの）
    static func remainingRoutine(settings s: WakeSettings, state: WakeDayState) -> [WakeRoutineItem] {
        s.routine.filter { !state.routineDone.contains($0.id) }
    }

    /// 連続記録（新しい順に、3回目までに起きて二度寝しなかった日が続いた数）
    static func streak(_ sessions: [WakeSession]) -> Int {
        var n = 0
        for s in sessions.sorted(by: { $0.day > $1.day }) {
            if s.isMissed || s.stage > 3 || (s.oversleep ?? 0) > 0 { break }
            n += 1
        }
        return n
    }

    /// 「1回目で起床」「アラームの前に起床」「未チェックイン」
    static func stageText(_ s: WakeSession) -> String {
        s.isMissed ? "未チェックイン" : stageText(stage: s.stage)
    }

    static func stageText(stage: Int) -> String {
        stage <= 0 ? "アラームの前に起床" : "\(stage)回目で起床"
    }

    /// 「二度寝なし」「二度寝 15分」（見張りが無かった日は nil）
    static func oversleepText(_ s: WakeSession) -> String? {
        guard let over = s.oversleep else { return nil }
        return over > 0 ? "二度寝 \(over)分" : "二度寝なし"
    }

    /// 「1回目で起床・二度寝なし」
    static func resultText(_ s: WakeSession) -> String {
        let st: String = stageText(s)
        guard let o = oversleepText(s) else { return st }
        return "\(st)・\(o)"
    }

    /// 起きた時刻（0時からの分）。未チェックインなら nil
    static func wakeMinutes(_ s: WakeSession) -> Int? {
        guard !s.isMissed, let at = s.checkInAt else { return nil }
        let c: DateComponents = cal.dateComponents([.hour, .minute], from: at)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func recent(_ sessions: [WakeSession], days: Int, now: Date) -> [WakeSession] {
        guard let from = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) else { return [] }
        let k: String = key(from)
        return sessions.filter { $0.day >= k }
    }

    /// 直近 days 日の平均の起床時刻（0時からの分）。チェックインした日だけで数える
    static func averageWakeMinutes(_ sessions: [WakeSession], days: Int, now: Date) -> Int? {
        let xs: [Int] = recent(sessions, days: days, now: now).compactMap { wakeMinutes($0) }
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / xs.count
    }

    /// 直近 days 日のうち、二度寝した日の数
    static func oversleepDays(_ sessions: [WakeSession], days: Int, now: Date) -> Int {
        recent(sessions, days: days, now: now).filter { ($0.oversleep ?? 0) > 0 }.count
    }

    /// 正午までにチェックインがなかった起床日を「未チェックイン」として記録する
    static func recordMissed(now: Date) {
        var state = WakeStore.state()
        let todayKey = key(now)
        let hour = cal.component(.hour, from: now)
        var sessions = WakeStore.sessions()
        var changed = false
        let s = WakeStore.settings()
        for d in state.pendingDays where d < todayKey || (d == todayKey && hour >= 12 && checkedIn(state, now: now) == nil) {
            if !sessions.contains(where: { $0.day == d }) {
                sessions.append(WakeSession(day: d, checkInAt: nil, stage: s.stages.count, missed: true))
            }
            state.pendingDays.removeAll { $0 == d }
            changed = true
        }
        if changed {
            WakeStore.save(sessions)
            WakeStore.save(state)
        }
    }

    /// 時間の長さを「1時間30分」のように
    static func duration(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)時間" : "\(m / 60)時間\(m % 60)分" }
        return "\(m)分"
    }

    /// 分（0時から）を「7:05」に
    static func clock(_ m: Int) -> String {
        let v = ((m % 1440) + 1440) % 1440
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    /// 「今日」「明日」「10月9日（金）」
    static func dayLabel(_ d: Date, now: Date) -> String {
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch diff {
        case 0: return "今日"
        case 1: return "明日"
        default: return JP.date(d)
        }
    }

    // MARK: 「今寝ると」の行（アプリの就寝カードとウィジェットで共通）

    /// 次に来る朝（正午より前なら今日、正午からは明日）の0時
    static func comingMorning(now: Date) -> Date {
        let today: Date = cal.startOfDay(for: now)
        let hour: Int = cal.component(.hour, from: now)
        if hour < 12 { return today }
        return cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// 次の朝がお休み（起床の曜日でない・明日だけオフ・祝日）か。
    /// next は鳴る予定の次の起床日（nextPlan。オフの日は入らない）。それが次の朝でなければ、次の朝にアラームはない
    static func isMorningOff(next: WakePlan, now: Date) -> Bool {
        let morning: Date = comingMorning(now: now)
        return next.day != key(morning)
    }

    /// 「月 7:00」（1週間より先なら「10月19日（月） 7:00」）
    static func nextWakeLabel(_ next: WakePlan, now: Date) -> String {
        let today: Date = cal.startOfDay(for: now)
        let days: Int = cal.dateComponents([.day], from: today, to: next.dayStart).day ?? 0
        let time: String = JP.time(next.first)
        if days >= 7 { return "\(JP.date(next.dayStart)) \(time)" }
        let symbols: [String] = ["日", "月", "火", "水", "木", "金", "土"]
        let w: Int = weekday(next.dayStart)
        return "\(symbols[w]) \(time)"
    }

    /// 次の朝がお休みのときの行（お休みでなければ nil。そのときは「今寝ると」の残り時間を出す）
    static func morningOffLine(next: WakePlan, now: Date) -> String? {
        guard isMorningOff(next: next, now: now) else { return nil }
        return "明日はお休み・次の起床は \(nextWakeLabel(next, now: now))"
    }
}

/// ウィジェットなどに出す要約
struct WakeSnapshot {
    var phase: WakePhase
    var next: WakePlan?
    var today: WakePlan?
    var reached: Int
    var nextStage: WakePlan.Stage?
    var checkInAt: Date?
    /// 今朝の記録（チェックイン後だけ）。「1回目で起床」などを出す
    var session: WakeSession?
    var departure: Date?
    var nextStep: WakeRoutineItem?
    var stepsLeft: Int
    var bedtime: Date?
    var canCheckIn: Bool = false
    var checkInFrom: Date? = nil

    static func make(now: Date) -> WakeSnapshot {
        let s = WakeStore.settings()
        let st = WakeStore.state()
        let phase = WakeLogic.phase(now: now, settings: s, state: st)
        let next = WakeLogic.nextPlan(now: now, settings: s, state: st)
        let today = WakeLogic.plan(for: now, settings: s, state: st)
        let reached = today.map { WakeLogic.reached($0, at: now) } ?? 0
        let checkIn = WakeLogic.checkedIn(st, now: now)
        let session = WakeStore.sessions().first { $0.day == WakeLogic.key(now) }
        let remaining = WakeLogic.remainingRoutine(settings: s, state: st)
        return WakeSnapshot(
            phase: phase, next: next, today: today, reached: reached,
            nextStage: today?.stages.first { $0.at > now },
            checkInAt: checkIn, session: checkIn != nil ? session : nil,
            departure: WakeLogic.departure(now: now, settings: s),
            nextStep: checkIn != nil ? remaining.first : nil, stepsLeft: remaining.count,
            bedtime: next.map { WakeLogic.bedtime(before: $0, settings: s) },
            canCheckIn: WakeLogic.canCheckIn(now: now, settings: s, state: st),
            checkInFrom: WakeLogic.nextCheckInStart(now: now, settings: s, state: st)
        )
    }
}
