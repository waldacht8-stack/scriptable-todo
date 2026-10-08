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
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "段階"
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

    static let stageNames = ["そっと", "ふつう", "しっかり", "最終"]
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
    var score: Int
    var missed: Bool?

    var id: String { day }
    var isMissed: Bool { missed ?? false }
}

/// ある起床日の予定
struct WakePlan: Hashable {
    struct Stage: Hashable {
        var number: Int      // 1から
        var name: String
        var at: Date
        var score: Int
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

    /// 段階の点数（0 = 最初のアラームより前）
    static func score(stage: Int) -> Int {
        let table = [100, 100, 85, 70, 40]
        return table[max(0, min(stage, table.count - 1))]
    }

    /// その日の予定（曜日がオフなら nil）
    static func plan(for date: Date, settings s: WakeSettings, state: WakeDayState) -> WakePlan? {
        let start = cal.startOfDay(for: date)
        let d = s.days[weekday(start)]
        guard d.on, !s.stages.isEmpty else { return nil }
        let k = key(start)
        let stages = s.stages.enumerated().map { i, st in
            WakePlan.Stage(number: i + 1, name: st.name, at: minutes(d.wake + st.offset, on: start), score: score(stage: i + 1))
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
        if let p = plan(for: now, settings: s, state: state), !p.isSkipped,
           now >= p.first.addingTimeInterval(-2 * 3600), hour < 12 {
            return .window
        }
        return hour >= 18 ? .evening : .before
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

    /// 連続記録（新しい順に、段階3までに起きた日が続いた数）
    static func streak(_ sessions: [WakeSession]) -> Int {
        var n = 0
        for s in sessions.sorted(by: { $0.day > $1.day }) {
            if s.isMissed || s.score < 70 { break }
            n += 1
        }
        return n
    }

    /// 直近 days 日の平均スコア
    static func average(_ sessions: [WakeSession], days: Int, now: Date) -> Int? {
        guard let from = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) else { return nil }
        let k = key(from)
        let xs = sessions.filter { $0.day >= k }
        guard !xs.isEmpty else { return nil }
        return xs.map(\.score).reduce(0, +) / xs.count
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
                sessions.append(WakeSession(day: d, checkInAt: nil, stage: s.stages.count, score: 0, missed: true))
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
}

/// ウィジェットなどに出す要約
struct WakeSnapshot {
    var phase: WakePhase
    var next: WakePlan?
    var today: WakePlan?
    var reached: Int
    var nextStage: WakePlan.Stage?
    var checkInAt: Date?
    var score: Int?
    var departure: Date?
    var nextStep: WakeRoutineItem?
    var stepsLeft: Int
    var bedtime: Date?

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
            checkInAt: checkIn, score: checkIn != nil ? session?.score : nil,
            departure: WakeLogic.departure(now: now, settings: s),
            nextStep: checkIn != nil ? remaining.first : nil, stepsLeft: remaining.count,
            bedtime: next.map { WakeLogic.bedtime(before: $0, settings: s) }
        )
    }
}
