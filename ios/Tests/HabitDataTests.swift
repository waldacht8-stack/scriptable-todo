import XCTest
@testable import TodoApp

/// 習慣の集計（HabitData）。いま＝2026-10-09（金）10:00
final class HabitDataTests: TokyoTestCase {
    private let created = T.d(2026, 9, 1)
    private lazy var water = Habit(id: "water", name: "水", target: 8, unit: "杯", createdAt: created)
    private lazy var stretch = Habit(id: "stretch", name: "ストレッチ", createdAt: created)
    private lazy var jog = Habit(id: "jog", name: "ジョギング", weekdays: [2, 4, 6], createdAt: created)   // 月水金

    private func log(_ entries: [(Habit, Date, Int)]) -> HabitLog {
        var l: HabitLog = [:]
        for (h, d, v) in entries { HabitData.set(&l, h, d, v) }
        return l
    }

    // MARK: 日ごとの進み具合

    func testDayProgress() {
        let l = log([(water, T.now, 5), (stretch, T.now, 1), (jog, T.now, 0)])
        // 金曜は3つとも対象。達成は「ストレッチ」だけ（水は 5/8 で途中）
        XCTAssertEqual(HabitData.dayProgress([water, stretch, jog], l, on: T.now), 1.0 / 3.0, accuracy: 1e-9)
    }

    func testDayProgressSkipsInactiveWeekday() {
        let sat = T.d(2026, 10, 10, 10)
        let l = log([(stretch, sat, 1)])
        // 土曜はジョギングの対象外 → 2つのうち1つ
        XCTAssertEqual(HabitData.dayProgress([water, stretch, jog], l, on: sat), 0.5, accuracy: 1e-9)
    }

    func testDayProgressEmptyAndComplete() {
        XCTAssertEqual(HabitData.dayProgress([], [:], on: T.now), 0)
        XCTAssertEqual(HabitData.dayProgress([jog], [:], on: T.d(2026, 10, 10)), 0, "対象がない日は 0")
        let l = log([(water, T.now, 8), (stretch, T.now, 1), (jog, T.now, 1)])
        XCTAssertEqual(HabitData.dayProgress([water, stretch, jog], l, on: T.now), 1)
        // 目標を超えても 1 を超えない
        let over = log([(water, T.now, 12)])
        XCTAssertEqual(HabitData.dayProgress([water], over, on: T.now), 1)
    }

    // MARK: 記録

    func testSetAndCount() {
        var l: HabitLog = [:]
        HabitData.set(&l, water, T.now, 3)
        XCTAssertEqual(HabitData.count(l, water, T.now), 3)
        XCTAssertFalse(HabitData.isDone(l, water, T.now))
        HabitData.set(&l, water, T.now, 0)
        XCTAssertTrue(l.isEmpty, "0 にしたら記録を消す")
        XCTAssertEqual(HabitData.key(T.d(2026, 10, 9, 0, 30)), "2026-10-09")
        XCTAssertEqual(HabitData.key(T.d(2026, 10, 9, 23, 59)), "2026-10-09")
    }

    // MARK: 連続・達成率

    func testCurrentStreak() {
        var entries: [(Habit, Date, Int)] = []
        for day in 5...8 { entries.append((stretch, T.d(2026, 10, day), 1)) }
        let l = log(entries)
        XCTAssertEqual(HabitData.currentStreak(stretch, l, today: T.now), 4, "今日がまだなら昨日から数える")
        var l2 = l
        HabitData.set(&l2, stretch, T.now, 1)
        XCTAssertEqual(HabitData.currentStreak(stretch, l2, today: T.now), 5)
        XCTAssertEqual(HabitData.currentStreak(stretch, [:], today: T.now), 0)
    }

    func testCurrentStreakSkipsOffDays() {
        // 月水金：10/5（月）10/7（水）できた、今日（金）はまだ → 2
        let l = log([(jog, T.d(2026, 10, 5), 1), (jog, T.d(2026, 10, 7), 1)])
        XCTAssertEqual(HabitData.currentStreak(jog, l, today: T.now), 2)
    }

    func testBestStreak() {
        var entries: [(Habit, Date, Int)] = []
        for day in 10...16 { entries.append((stretch, T.d(2026, 9, day), 1)) }   // 7日
        for day in 7...8 { entries.append((stretch, T.d(2026, 10, day), 1)) }    // 2日
        XCTAssertEqual(HabitData.bestStreak(stretch, log(entries), today: T.now), 7)
    }

    func testWeekRate() throws {
        // 10/3〜10/8 のうち 3日できた、今日はまだ → 3/6
        let l = log([(stretch, T.d(2026, 10, 3), 1), (stretch, T.d(2026, 10, 5), 1), (stretch, T.d(2026, 10, 8), 1)])
        XCTAssertEqual(try XCTUnwrap(HabitData.weekRate(stretch, l, today: T.now)), 0.5, accuracy: 1e-9)
        // 今日できたら 4/7
        var l2 = l
        HabitData.set(&l2, stretch, T.now, 1)
        XCTAssertEqual(try XCTUnwrap(HabitData.weekRate(stretch, l2, today: T.now)), 4.0 / 7.0, accuracy: 1e-9)
    }

    // MARK: 表示の文字

    func testTexts() {
        XCTAssertEqual(water.progressText(3), "3/8杯")
        XCTAssertEqual(stretch.progressText(0), "まだ")
        XCTAssertEqual(stretch.progressText(1), "できた")
        XCTAssertEqual(stretch.weekdayText, "毎日")
        XCTAssertEqual(jog.weekdayText, "月水金")
        XCTAssertEqual(Habit(name: "x", weekdays: [2, 3, 4, 5, 6]).weekdayText, "平日")
        XCTAssertEqual(Habit(name: "x", weekdays: [7, 1]).weekdayText, "週末")
        XCTAssertEqual(Habit(name: "x", weekdays: [1, 7, 2]).weekdayText, "月土日")
        XCTAssertEqual(Habit(name: "x", weekdays: []).weekdayText, "毎日")
        XCTAssertEqual(Habit(name: "x", remindHour: 7, remindMinute: 5).reminderText, "7:05")
        XCTAssertNil(stretch.reminderText)
    }

    func testIsActive() {
        XCTAssertTrue(jog.isActive(on: T.now))                  // 金
        XCTAssertFalse(jog.isActive(on: T.d(2026, 10, 10)))     // 土
        XCTAssertTrue(Habit(name: "x", weekdays: []).isActive(on: T.d(2026, 10, 10)))
    }

    func testDecodeBrokenHabit() throws {
        let json = #"[{"id":"a","target":0,"weekdays":"bad"}]"#.data(using: .utf8)!
        let hs = try JSONDecoder.iso.decode([Habit].self, from: json)
        XCTAssertEqual(hs.first?.target, 1, "目標は1以上")
        XCTAssertEqual(hs.first?.weekdays, Array(1...7))
        XCTAssertEqual(hs.first?.name, "習慣")
    }
}
