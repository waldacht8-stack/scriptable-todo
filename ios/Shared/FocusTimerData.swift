import Foundation
import UserNotifications

// 集中タイマー（ポモドーロ）のデータと動き。保存先は focus-settings.json / focus-state.json / focus-sessions.json。
// 残り時間は「終わる時刻」で持つので、アプリを閉じても正しく進む。

enum FocusPhase: String, Codable, CaseIterable {
    case focus, shortBreak, longBreak

    var name: String {
        switch self {
        case .focus: "集中"
        case .shortBreak: "短い休憩"
        case .longBreak: "長い休憩"
        }
    }

    var icon: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
        }
    }

    var isBreak: Bool { self != .focus }
}

struct FocusTimerSettings: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var longBreakEvery = 4
    var autoStartBreak = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = (try? c.decodeIfPresent(Int.self, forKey: .focusMinutes)) ?? 25
        shortBreakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes)) ?? 5
        longBreakMinutes = (try? c.decodeIfPresent(Int.self, forKey: .longBreakMinutes)) ?? 15
        longBreakEvery = (try? c.decodeIfPresent(Int.self, forKey: .longBreakEvery)) ?? 4
        autoStartBreak = (try? c.decodeIfPresent(Bool.self, forKey: .autoStartBreak)) ?? true
    }

    func minutes(_ phase: FocusPhase) -> Int {
        switch phase {
        case .focus: max(1, focusMinutes)
        case .shortBreak: max(1, shortBreakMinutes)
        case .longBreak: max(1, longBreakMinutes)
        }
    }

    func seconds(_ phase: FocusPhase) -> Double { Double(minutes(phase) * 60) }
}

/// 今のタイマーの状態
struct FocusTimerState: Codable, Equatable {
    var phase: FocusPhase = .focus
    var title: String = ""
    var todoID: String? = nil
    var isRunning = false          // 計測中（一時停止中も含む）
    var isPaused = false
    var endAt: Date? = nil         // 動いているときの終わる時刻
    var remaining: Double = 0      // 一時停止中の残り秒
    var total: Double = 0          // このセッションの長さ（秒）
    var startedAt: Date? = nil
    var cycleCount = 0             // 今のサイクルで終えた集中の回数
    var day: String? = nil         // cycleCount を数えている日

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = (try? c.decodeIfPresent(FocusPhase.self, forKey: .phase)) ?? .focus
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        todoID = (try? c.decodeIfPresent(String.self, forKey: .todoID)) ?? nil
        isRunning = (try? c.decodeIfPresent(Bool.self, forKey: .isRunning)) ?? false
        isPaused = (try? c.decodeIfPresent(Bool.self, forKey: .isPaused)) ?? false
        endAt = (try? c.decodeIfPresent(Date.self, forKey: .endAt)) ?? nil
        remaining = (try? c.decodeIfPresent(Double.self, forKey: .remaining)) ?? 0
        total = (try? c.decodeIfPresent(Double.self, forKey: .total)) ?? 0
        startedAt = (try? c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? nil
        cycleCount = (try? c.decodeIfPresent(Int.self, forKey: .cycleCount)) ?? 0
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? nil
    }

    /// 残り秒（止まっているときは nil）
    func left(at now: Date) -> Double? {
        guard isRunning else { return nil }
        if isPaused { return remaining }
        return max(0, (endAt ?? now).timeIntervalSince(now))
    }
}

/// 終えた（または途中でやめた）集中の記録
struct FocusSessionRecord: Codable, Identifiable {
    var id: String = UUID().uuidString
    var title: String
    var start: Date
    var end: Date
    var minutes: Double
    var completed: Bool

    init(title: String, start: Date, end: Date, minutes: Double, completed: Bool) {
        self.title = title
        self.start = start
        self.end = end
        self.minutes = minutes
        self.completed = completed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        end = (try? c.decodeIfPresent(Date.self, forKey: .end)) ?? .now
        start = (try? c.decodeIfPresent(Date.self, forKey: .start)) ?? end
        minutes = (try? c.decodeIfPresent(Double.self, forKey: .minutes)) ?? 0
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? true
    }

    /// その日に入る集中の分数。日付をまたいだ集中（23:50〜0:15 など）は、それぞれの日に分けて数える
    func minutes(on day: Date, calendar cal: Calendar = .current) -> Double {
        let dayStart: Date = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let wall: Double = end.timeIntervalSince(start)
        guard wall > 0 else { return (end >= dayStart && end < dayEnd) ? minutes : 0 }
        let lo: Date = max(start, dayStart)
        let hi: Date = min(end, dayEnd)
        let overlap: Double = hi.timeIntervalSince(lo)
        guard overlap > 0 else { return 0 }
        return minutes * overlap / wall
    }
}

enum FocusTimerData {
    static let settingsFile = "focus-settings.json"
    static let stateFile = "focus-state.json"
    static let sessionsFile = "focus-sessions.json"

    static func settings() -> FocusTimerSettings { SharedStore.load(FocusTimerSettings.self, from: settingsFile) ?? FocusTimerSettings() }
    static func saveSettings(_ s: FocusTimerSettings) { SharedStore.save(s, to: settingsFile) }

    static func state() -> FocusTimerState { SharedStore.load(FocusTimerState.self, from: stateFile) ?? FocusTimerState() }
    static func saveState(_ s: FocusTimerState) { SharedStore.save(s, to: stateFile) }

    static func sessions() -> [FocusSessionRecord] { SharedStore.load([FocusSessionRecord].self, from: sessionsFile) ?? [] }
    static func saveSessions(_ s: [FocusSessionRecord]) { SharedStore.save(Array(s.suffix(3000)), to: sessionsFile) }

    static func add(_ r: FocusSessionRecord) {
        var all = sessions()
        all.append(r)
        saveSessions(all)
    }

    /// 見本データ（起動引数 -demo）：この7日間の記録と、集中の途中の状態
    static func installDemo(now: Date = .now) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let titles = ["企画書の下書き", "メールの返信", "資料の読み込み", "勉強", "部屋の片づけ"]
        let perDay = [3, 5, 2, 4, 6, 1, 3]   // 6日前 → 昨日、最後は今日
        var records: [FocusSessionRecord] = []
        for (i, n) in perDay.enumerated() {
            let back = perDay.count - 1 - i
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            for k in 0..<n {
                let start = day.addingTimeInterval(Double(9 * 3600 + k * 1800))
                if start > now { continue }
                records.append(FocusSessionRecord(title: titles[(i + k) % titles.count], start: start,
                                                  end: start.addingTimeInterval(1500), minutes: 25, completed: true))
            }
        }
        // 日付をまたいだ集中（昨日 23:45〜今日 0:10）。昨日に15分、今日に10分として数える
        let lateStart: Date = today.addingTimeInterval(-15 * 60)
        let lateEnd: Date = today.addingTimeInterval(10 * 60)
        if lateEnd <= now {
            records.append(FocusSessionRecord(title: "資料の読み込み", start: lateStart, end: lateEnd, minutes: 25, completed: true))
        }
        saveSessions(records)
        var s = FocusTimerState()
        s.phase = .focus
        s.title = "企画書の下書き"
        s.isRunning = true
        s.total = 1500
        s.endAt = now.addingTimeInterval(17 * 60 + 32)
        s.startedAt = now.addingTimeInterval(-(1500 - (17 * 60 + 32)))
        s.cycleCount = 2
        s.day = HabitData.key(now)
        saveState(s)
        saveSettings(FocusTimerSettings())
    }
}

/// タイマーの操作。どれも状態を保存し、終了の通知（focus-end）を予約し直す
enum FocusTimerEngine {
    static let notificationID = "focus-end"

    @discardableResult
    static func start(title: String, todoID: String?, now: Date = .now) -> FocusTimerState {
        var s = FocusTimerData.state()
        let settings = FocusTimerData.settings()
        let today = HabitData.key(now)
        if s.day != today { s.cycleCount = 0; s.day = today }
        s.title = title
        s.todoID = todoID
        begin(&s, settings, now)
        commit(s)
        return s
    }

    @discardableResult
    static func togglePause(now: Date = .now) -> FocusTimerState {
        var s = FocusTimerData.state()
        guard s.isRunning else { return s }
        if s.isPaused {
            s.endAt = now.addingTimeInterval(s.remaining)
            s.isPaused = false
        } else {
            s.remaining = max(0, (s.endAt ?? now).timeIntervalSince(now))
            s.endAt = nil
            s.isPaused = true
        }
        commit(s)
        return s
    }

    /// やめる（集中を1分以上していれば、その分を記録する）
    @discardableResult
    static func stop(now: Date = .now) -> FocusTimerState {
        var s = FocusTimerData.state()
        recordPartial(s, now)
        let settings = FocusTimerData.settings()
        if s.phase.isBreak && s.phase == .longBreak { s.cycleCount = 0 }
        s.phase = .focus
        idle(&s, settings)
        commit(s)
        return s
    }

    /// 次へ進む（集中は途中までを記録して休憩へ、休憩は集中へ）
    @discardableResult
    static func skip(now: Date = .now) -> FocusTimerState {
        var s = FocusTimerData.state()
        let settings = FocusTimerData.settings()
        if s.phase == .focus {
            recordPartial(s, now)
            s.phase = .shortBreak
        } else {
            if s.phase == .longBreak { s.cycleCount = 0 }
            s.phase = .focus
        }
        idle(&s, settings)
        commit(s)
        return s
    }

    /// 終わる時刻を過ぎていたら、記録して次の段階へ。終わったセッションの状態を返す
    static func settle(now: Date = .now, autoStart: Bool) -> (state: FocusTimerState, finished: FocusTimerState?) {
        var s = FocusTimerData.state()
        guard s.isRunning, !s.isPaused, let end = s.endAt, end <= now else { return (s, nil) }
        let finished = s
        let settings = FocusTimerData.settings()
        if s.phase == .focus {
            FocusTimerData.add(FocusSessionRecord(title: s.title, start: end.addingTimeInterval(-s.total), end: end,
                                                  minutes: s.total / 60, completed: true))
            s.cycleCount += 1
            s.phase = s.cycleCount % max(2, settings.longBreakEvery) == 0 ? .longBreak : .shortBreak
        } else {
            if s.phase == .longBreak { s.cycleCount = 0 }
            s.phase = .focus
        }
        if autoStart && finished.phase == .focus && settings.autoStartBreak {
            begin(&s, settings, now)
        } else {
            idle(&s, settings)
        }
        commit(s)
        return (s, finished)
    }

    // MARK: 内部

    private static func begin(_ s: inout FocusTimerState, _ settings: FocusTimerSettings, _ now: Date) {
        s.total = settings.seconds(s.phase)
        s.remaining = s.total
        s.endAt = now.addingTimeInterval(s.total)
        s.startedAt = now
        s.isRunning = true
        s.isPaused = false
    }

    private static func idle(_ s: inout FocusTimerState, _ settings: FocusTimerSettings) {
        s.isRunning = false
        s.isPaused = false
        s.endAt = nil
        s.startedAt = nil
        s.total = settings.seconds(s.phase)
        s.remaining = s.total
    }

    private static func recordPartial(_ s: FocusTimerState, _ now: Date) {
        guard s.isRunning, s.phase == .focus, let left = s.left(at: now) else { return }
        let done = s.total - left
        guard done >= 60 else { return }
        FocusTimerData.add(FocusSessionRecord(title: s.title, start: now.addingTimeInterval(-done), end: now,
                                              minutes: done / 60, completed: false))
    }

    private static func commit(_ s: FocusTimerState) {
        FocusTimerData.saveState(s)
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard s.isRunning, !s.isPaused, let end = s.endAt, end.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        if s.phase == .focus {
            content.title = "集中おつかれさま"
            content.body = s.title.isEmpty ? "\(Int(s.total / 60))分集中しました。休憩しましょう。"
                : "「\(s.title)」に\(Int(s.total / 60))分集中しました。休憩しましょう。"
        } else {
            content.title = "休憩が終わりました"
            content.body = "次の集中を始めましょう。"
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
        c.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}
