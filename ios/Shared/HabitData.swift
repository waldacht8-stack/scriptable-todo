import Foundation
import SwiftUI

// 習慣のデータ（アプリとウィジェットで共有）。保存先は habit-list.json と habit-log.json。

/// 習慣の色。どの色合い（palette）でも読める、中くらいの明るさの色だけを用意する。
/// 「テーマの色」は palette の強調色をそのまま使う。
enum HabitColor: String, CaseIterable, Identifiable, Codable {
    case accent, coral, orange, amber, green, teal, sky, indigo, purple, pink

    var id: String { rawValue }

    static func from(_ raw: String?) -> HabitColor { HabitColor(rawValue: raw ?? "") ?? .accent }

    func color(_ p: Palette) -> Color {
        switch self {
        case .accent: p.accent
        case .coral: Color(red: 0.93, green: 0.42, blue: 0.38)
        case .orange: Color(red: 0.95, green: 0.55, blue: 0.20)
        case .amber: Color(red: 0.86, green: 0.65, blue: 0.10)
        case .green: Color(red: 0.30, green: 0.68, blue: 0.38)
        case .teal: Color(red: 0.12, green: 0.64, blue: 0.64)
        case .sky: Color(red: 0.24, green: 0.56, blue: 0.92)
        case .indigo: Color(red: 0.38, green: 0.40, blue: 0.86)
        case .purple: Color(red: 0.62, green: 0.40, blue: 0.85)
        case .pink: Color(red: 0.90, green: 0.40, blue: 0.62)
        }
    }

    var name: String {
        switch self {
        case .accent: "テーマの色"
        case .coral: "コーラル"
        case .orange: "オレンジ"
        case .amber: "からし"
        case .green: "みどり"
        case .teal: "ターコイズ"
        case .sky: "空"
        case .indigo: "あい"
        case .purple: "むらさき"
        case .pink: "ピンク"
        }
    }
}

/// 1つの習慣
struct Habit: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var icon: String
    var color: String          // HabitColor の rawValue
    var target: Int            // 1日の目標回数（1なら「できた／まだ」）
    var unit: String           // 回数の単位（例：杯）
    var weekdays: [Int]        // する曜日（Calendar の曜日：1=日曜〜7=土曜）。空なら毎日
    var remindHour: Int?       // リマインダーの時刻（なければ通知しない）
    var remindMinute: Int?
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, icon: String = "star.fill", color: HabitColor = .accent,
         target: Int = 1, unit: String = "", weekdays: [Int] = Array(1...7),
         remindHour: Int? = nil, remindMinute: Int? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color.rawValue
        self.target = target
        self.unit = unit
        self.weekdays = weekdays
        self.remindHour = remindHour
        self.remindMinute = remindMinute
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, target, unit, weekdays, remindHour, remindMinute, createdAt
    }

    // 項目が増えたり型が違っても読めるように、読めない項目は既定値にする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "習慣"
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? "star.fill"
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? HabitColor.accent.rawValue
        target = max(1, (try? c.decodeIfPresent(Int.self, forKey: .target)) ?? 1)
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
        weekdays = (try? c.decodeIfPresent([Int].self, forKey: .weekdays)) ?? Array(1...7)
        remindHour = (try? c.decodeIfPresent(Int.self, forKey: .remindHour)) ?? nil
        remindMinute = (try? c.decodeIfPresent(Int.self, forKey: .remindMinute)) ?? nil
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .now
    }

    var isCount: Bool { target > 1 }
    var tint: HabitColor { HabitColor.from(color) }

    func isActive(on date: Date, calendar cal: Calendar = .current) -> Bool {
        weekdays.isEmpty || weekdays.count >= 7 || weekdays.contains(cal.component(.weekday, from: date))
    }

    /// 曜日の説明（毎日・平日・月水金 など）
    var weekdayText: String {
        let set = Set(weekdays)
        if set.isEmpty || set.count == 7 { return "毎日" }
        if set == [2, 3, 4, 5, 6] { return "平日" }
        if set == [1, 7] { return "週末" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { set.contains($0) }.map { HabitData.weekdaySymbol($0) }.joined()
    }

    var reminderText: String? {
        guard let h = remindHour else { return nil }
        return String(format: "%d:%02d", h, remindMinute ?? 0)
    }

    /// 「3/8杯」「できた」などの表示
    func progressText(_ count: Int) -> String {
        isCount ? "\(count)/\(target)\(unit)" : (count >= 1 ? "できた" : "まだ")
    }
}

/// 日ごとの記録：「2026-10-08」→ 習慣のID → 回数
typealias HabitLog = [String: [String: Int]]

enum HabitData {
    static let habitsFile = "habit-list.json"
    static let logFile = "habit-log.json"

    static func habits() -> [Habit] { SharedStore.load([Habit].self, from: habitsFile) ?? [] }
    static func saveHabits(_ h: [Habit]) { SharedStore.save(h, to: habitsFile) }

    static func log() -> HabitLog { SharedStore.load(HabitLog.self, from: logFile) ?? [:] }
    static func saveLog(_ l: HabitLog) { SharedStore.save(l, to: logFile) }

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ d: Date) -> String { keyFormatter.string(from: d) }

    static func weekdaySymbol(_ weekday: Int) -> String {
        ["日", "月", "火", "水", "木", "金", "土"][max(0, min(6, weekday - 1))]
    }

    // MARK: 記録の読み書き

    static func count(_ log: HabitLog, _ h: Habit, _ d: Date) -> Int { log[key(d)]?[h.id] ?? 0 }

    static func isDone(_ log: HabitLog, _ h: Habit, _ d: Date) -> Bool { count(log, h, d) >= h.target }

    /// 1回分チェックする（「できた／まだ」は切り替え、回数は1つ増やす）。新しい回数を返す
    @discardableResult
    static func tap(id: String, on date: Date = .now) -> Int {
        guard let h = habits().first(where: { $0.id == id }) else { return 0 }
        var l = log()
        let cur = count(l, h, date)
        let next = h.isCount ? min(cur + 1, 999) : (cur >= 1 ? 0 : 1)
        set(&l, h, date, next)
        saveLog(l)
        return next
    }

    static func set(_ log: inout HabitLog, _ h: Habit, _ d: Date, _ value: Int) {
        let k = key(d)
        var day = log[k] ?? [:]
        if value <= 0 { day[h.id] = nil } else { day[h.id] = value }
        log[k] = day.isEmpty ? nil : day
    }

    // MARK: 集計

    /// 今の連続日数。今日がまだ終わっていなければ、今日は数えずに昨日からさかのぼる。お休みの曜日は飛ばす
    static func currentStreak(_ h: Habit, _ log: HabitLog, today: Date = .now) -> Int {
        let cal = Calendar.current
        var d = cal.startOfDay(for: today)
        if h.isActive(on: d) && !isDone(log, h, d) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var streak = 0
        for _ in 0..<1000 {
            if h.isActive(on: d) {
                if isDone(log, h, d) { streak += 1 } else { break }
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return streak
    }

    /// これまでの最高の連続日数（最大で約2年分を見る）
    static func bestStreak(_ h: Habit, _ log: HabitLog, today: Date = .now) -> Int {
        let cal = Calendar.current
        let end = cal.startOfDay(for: today)
        let earliest = log.keys.sorted().first.flatMap { keyFormatter.date(from: $0) } ?? end
        let start = max(cal.startOfDay(for: min(earliest, h.createdAt)), cal.date(byAdding: .day, value: -730, to: end) ?? end)
        var best = 0, run = 0
        var d = start
        while d <= end {
            if h.isActive(on: d) {
                if isDone(log, h, d) {
                    run += 1
                    best = max(best, run)
                } else if d < end {
                    run = 0   // 今日がまだのときは途切れにしない
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return max(best, currentStreak(h, log, today: today))
    }

    /// この7日間の達成率（0〜1）。今日がまだなら今日は数えない。対象の日がなければ nil
    static func weekRate(_ h: Habit, _ log: HabitLog, today: Date = .now) -> Double? {
        let cal = Calendar.current
        var active = 0, done = 0
        for offset in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: today)), h.isActive(on: d) else { continue }
            let ok = isDone(log, h, d)
            if offset == 0 && !ok { continue }
            active += 1
            if ok { done += 1 }
        }
        return active == 0 ? nil : Double(done) / Double(active)
    }

    /// 今日の対象の習慣全体の進み具合（0〜1。回数の習慣は途中まででも数える）
    static func dayProgress(_ habits: [Habit], _ log: HabitLog, on d: Date = .now) -> Double {
        let active = habits.filter { $0.isActive(on: d) }
        guard !active.isEmpty else { return 0 }
        let sum = active.reduce(0.0) { $0 + min(1, Double(count(log, $1, d)) / Double($1.target)) }
        return sum / Double(active.count)
    }

    // MARK: 見本データ（起動引数 -demo。一般的な内容だけ）

    static func demo(now: Date = .now) -> ([Habit], HabitLog) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let created = cal.date(byAdding: .day, value: -120, to: today) ?? today
        let habits = [
            Habit(name: "水を飲む", icon: "drop.fill", color: .sky, target: 8, unit: "杯", createdAt: created),
            Habit(name: "朝のストレッチ", icon: "figure.flexibility", color: .green, remindHour: 7, remindMinute: 30, createdAt: created),
            Habit(name: "読書 15分", icon: "book.fill", color: .amber, remindHour: 21, remindMinute: 0, createdAt: created),
            Habit(name: "英単語", icon: "character.book.closed.fill", color: .purple, target: 3, unit: "セット", createdAt: created),
            Habit(name: "ジョギング", icon: "figure.run", color: .coral, weekdays: [2, 4, 6], createdAt: created),
        ]
        // 習慣ごとの「できる確率」と、最近続いている日数
        let rates = [88, 80, 70, 62, 75]
        let recent = [12, 9, 4, 2, 3]
        var log: HabitLog = [:]
        for back in 1...110 {
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            for (i, h) in habits.enumerated() where h.isActive(on: d) {
                let roll = (back * 37 + i * 53 + (back * back) % 17) % 100
                let ok = back <= recent[i] || roll < rates[i]
                let value = ok ? h.target : (h.isCount ? roll % h.target : 0)
                set(&log, h, d, value)
            }
        }
        // 今日：途中まで
        let todayValues = [5, 1, 0, 1, 0]
        for (i, h) in habits.enumerated() where h.isActive(on: today) {
            set(&log, h, today, todayValues[i])
        }
        return (habits, log)
    }
}

// MARK: - 共通の部品（アプリとウィジェット）

/// 進み具合の輪
struct HabitRing: View {
    let fraction: Double
    let color: Color
    var track: Color? = nil
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke((track ?? color.opacity(0.18)), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
