import XCTest
@testable import TodoApp

/// 「今寝ると」の行（WakeLogic.morningOffLine）。次の朝がお休みなら残り時間ではなく次の起床を出す。
/// 既定の設定：月〜金 7:00 起床、土日はオフ。2026-10-09 は金曜、10-10・10-11 は土日、10-12（月）はスポーツの日。
final class WakeSleepLineTests: TokyoTestCase {
    private let s = WakeSettings()
    private let empty = WakeDayState()

    private func next(_ now: Date, settings: WakeSettings? = nil, state: WakeDayState? = nil) throws -> WakePlan {
        let st: WakeSettings = settings ?? s
        let ds: WakeDayState = state ?? empty
        return try XCTUnwrap(WakeLogic.nextPlan(now: now, settings: st, state: ds))
    }

    func testComingMorning() {
        XCTAssertEqual(WakeLogic.comingMorning(now: T.d(2026, 10, 9, 1)), T.d(2026, 10, 9), "日付が変わった後は今日の朝")
        XCTAssertEqual(WakeLogic.comingMorning(now: T.d(2026, 10, 9, 11, 59)), T.d(2026, 10, 9))
        XCTAssertEqual(WakeLogic.comingMorning(now: T.d(2026, 10, 9, 12)), T.d(2026, 10, 10), "正午からは明日の朝")
        XCTAssertEqual(WakeLogic.comingMorning(now: T.d(2026, 10, 9, 23)), T.d(2026, 10, 10))
    }

    func testWeekdayNightKeepsCountdown() throws {
        let now: Date = T.d(2026, 10, 8, 22)   // 木曜の夜 → 金曜の朝に鳴る
        let n: WakePlan = try next(now)
        XCTAssertEqual(n.day, "2026-10-09")
        XCTAssertFalse(WakeLogic.isMorningOff(next: n, now: now))
        XCTAssertNil(WakeLogic.morningOffLine(next: n, now: now))
    }

    func testAfterMidnightKeepsCountdown() throws {
        let now: Date = T.d(2026, 10, 9, 1)    // 金曜の 1:00（木曜の夜ふかし）→ 同じ日の朝に鳴る
        let n: WakePlan = try next(now)
        XCTAssertNil(WakeLogic.morningOffLine(next: n, now: now))
    }

    func testFridayNightIsDayOff() throws {
        let now: Date = T.d(2026, 10, 9, 22)   // 金曜の夜 → 土曜はお休み、次は月曜
        let n: WakePlan = try next(now)
        XCTAssertEqual(n.day, "2026-10-12")
        XCTAssertTrue(WakeLogic.isMorningOff(next: n, now: now))
        let line: String = try XCTUnwrap(WakeLogic.morningOffLine(next: n, now: now))
        XCTAssertEqual(line, "明日はお休み・次の起床は 月 \(JP.time(n.first))")
        XCTAssertFalse(line.contains("眠れます"))
    }

    func testSaturdayAfterMidnightIsDayOff() throws {
        let now: Date = T.d(2026, 10, 10, 1)   // 土曜の 1:00 → 土曜の朝はお休み
        let n: WakePlan = try next(now)
        XCTAssertNotNil(WakeLogic.morningOffLine(next: n, now: now))
    }

    func testHolidayIsDayOff() throws {
        var st = WakeDayState()
        st.holidays = ["2026-10-12": "スポーツの日"]
        let now: Date = T.d(2026, 10, 11, 22)  // 日曜の夜。月曜は祝日で鳴らない → 次は火曜
        let n: WakePlan = try next(now, state: st)
        XCTAssertEqual(n.day, "2026-10-13")
        XCTAssertEqual(WakeLogic.morningOffLine(next: n, now: now), "明日はお休み・次の起床は 火 \(JP.time(n.first))")
    }

    func testSkipDayIsDayOff() throws {
        var settings = WakeSettings()
        settings.skipDay = "2026-10-09"        // 金曜だけオフ
        let now: Date = T.d(2026, 10, 8, 22)
        let n: WakePlan = try next(now, settings: settings)
        XCTAssertEqual(n.day, "2026-10-12")
        XCTAssertNotNil(WakeLogic.morningOffLine(next: n, now: now))
    }

    func testFarNextWakeShowsDate() throws {
        var settings = WakeSettings()
        for i in 0..<7 { settings.days[i].on = (i == 1) }   // 月曜だけ
        let now: Date = T.d(2026, 10, 12, 22)  // 月曜の夜 → 次は1週間後の月曜
        let n: WakePlan = try next(now, settings: settings)
        XCTAssertEqual(n.day, "2026-10-19")
        let line: String = try XCTUnwrap(WakeLogic.morningOffLine(next: n, now: now))
        XCTAssertEqual(line, "明日はお休み・次の起床は \(JP.date(n.dayStart)) \(JP.time(n.first))")
    }
}
