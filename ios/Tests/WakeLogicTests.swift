import XCTest
@testable import TodoApp

/// 起床の判定（WakeLogic）。既定の設定：月〜金 7:00 起床・7:45 出発、段階は 0/10/20/30 分後、土日はオフ。
/// 2026-10-09 は金曜、10-10・10-11 は土日、10-12（月）はスポーツの日。
final class WakeLogicTests: TokyoTestCase {
    private let s = WakeSettings()
    private let empty = WakeDayState()

    private func checkedIn(at d: Date) -> WakeDayState {
        var st = WakeDayState()
        st.day = WakeLogic.key(d)
        st.checkInAt = d
        return st
    }

    // MARK: 予定

    func testPlanWeekday() throws {
        let p = try XCTUnwrap(WakeLogic.plan(for: T.d(2026, 10, 9, 15), settings: s, state: empty))
        XCTAssertEqual(p.day, "2026-10-09")
        XCTAssertEqual(p.dayStart, T.d(2026, 10, 9))
        XCTAssertEqual(p.stages.map(\.at), [T.d(2026, 10, 9, 7), T.d(2026, 10, 9, 7, 10), T.d(2026, 10, 9, 7, 20), T.d(2026, 10, 9, 7, 30)])
        XCTAssertEqual(p.stages.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(p.stages.map(\.score), [100, 85, 70, 40])
        XCTAssertEqual(p.departure, T.d(2026, 10, 9, 7, 45))
        XCTAssertEqual(p.first, T.d(2026, 10, 9, 7))
        XCTAssertEqual(p.last, T.d(2026, 10, 9, 7, 30))
        XCTAssertNil(p.skipReason)
        XCTAssertFalse(p.isSkipped)
    }

    func testPlanWeekendOff() {
        XCTAssertNil(WakeLogic.plan(for: T.d(2026, 10, 10, 9), settings: s, state: empty))
        XCTAssertNil(WakeLogic.plan(for: T.d(2026, 10, 11, 9), settings: s, state: empty))
    }

    func testPlans() {
        let ps = WakeLogic.plans(from: T.now, days: 7, settings: s, state: empty)
        XCTAssertEqual(ps.map(\.day), ["2026-10-09", "2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15"])
    }

    func testSkipReasons() {
        var st = WakeDayState()
        st.holidays = ["2026-10-12": "スポーツの日"]
        XCTAssertEqual(WakeLogic.plan(for: T.d(2026, 10, 12), settings: s, state: st)?.skipReason, "祝日（スポーツの日）")

        var noHoliday = s
        noHoliday.skipHolidays = false
        XCTAssertNil(WakeLogic.plan(for: T.d(2026, 10, 12), settings: noHoliday, state: st)?.skipReason)

        var skip = s
        skip.skipDay = "2026-10-13"
        XCTAssertEqual(WakeLogic.plan(for: T.d(2026, 10, 13), settings: skip, state: empty)?.skipReason, "明日だけオフ")
        XCTAssertNil(WakeLogic.plan(for: T.d(2026, 10, 14), settings: skip, state: empty)?.skipReason)

        var paused = s
        paused.paused = true
        XCTAssertEqual(WakeLogic.plan(for: T.d(2026, 10, 13), settings: paused, state: empty)?.skipReason, "アラームを停止中")
    }

    func testNextPlan() {
        // 7:15、まだチェックインしていない → 今日
        XCTAssertEqual(WakeLogic.nextPlan(now: T.d(2026, 10, 9, 7, 15), settings: s, state: empty)?.day, "2026-10-09")
        // 最後のアラームの後 → 月曜
        XCTAssertEqual(WakeLogic.nextPlan(now: T.d(2026, 10, 9, 8), settings: s, state: empty)?.day, "2026-10-12")
        // チェックイン済み → 月曜
        let st = checkedIn(at: T.d(2026, 10, 9, 7, 5))
        XCTAssertEqual(WakeLogic.nextPlan(now: T.d(2026, 10, 9, 7, 6), settings: s, state: st)?.day, "2026-10-12")
        // 月曜が祝日 → 火曜（オフの日は飛ばす）
        var hol = WakeDayState()
        hol.holidays = ["2026-10-12": "スポーツの日"]
        XCTAssertEqual(WakeLogic.nextPlan(now: T.d(2026, 10, 9, 8), settings: s, state: hol)?.day, "2026-10-13")
        XCTAssertEqual(WakeLogic.nextPlan(now: T.d(2026, 10, 9, 8), settings: s, state: hol, includeSkipped: true)?.day, "2026-10-12")
    }

    func testAllDaysOffHasNoNextPlan() {
        var off = s
        off.days = off.days.map { var d = $0; d.on = false; return d }
        XCTAssertNil(WakeLogic.nextPlan(now: T.now, settings: off, state: empty))
        XCTAssertNil(WakeLogic.nextCheckInStart(now: T.now, settings: off, state: empty))
    }

    // MARK: チェックインの受付（最初のアラームの2時間前〜正午）

    func testCheckInWindow() throws {
        let w = try XCTUnwrap(WakeLogic.checkInWindow(for: T.d(2026, 10, 9), settings: s, state: empty))
        XCTAssertEqual(w.start, T.d(2026, 10, 9, 5))
        XCTAssertEqual(w.end, T.d(2026, 10, 9, 12))
        XCTAssertNil(WakeLogic.checkInWindow(for: T.d(2026, 10, 10), settings: s, state: empty), "土曜はオフ")
    }

    func testCanCheckInBoundaries() {
        XCTAssertFalse(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 4, 59), settings: s, state: empty))
        XCTAssertTrue(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 5), settings: s, state: empty))
        XCTAssertTrue(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 11, 59), settings: s, state: empty))
        XCTAssertFalse(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 12), settings: s, state: empty))
        XCTAssertFalse(WakeLogic.canCheckIn(now: T.d(2026, 10, 10, 8), settings: s, state: empty), "土曜")
    }

    func testCannotCheckInTwice() {
        let st = checkedIn(at: T.d(2026, 10, 9, 7, 5))
        XCTAssertFalse(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 7, 10), settings: s, state: st))
        // 前の日のチェックインは関係ない
        let yesterday = checkedIn(at: T.d(2026, 10, 8, 7, 5))
        XCTAssertTrue(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 7, 10), settings: s, state: yesterday))
        XCTAssertNil(WakeLogic.checkedIn(yesterday, now: T.d(2026, 10, 9, 7, 10)))
    }

    func testCannotCheckInOnSkippedDay() {
        var skip = s
        skip.skipDay = "2026-10-09"
        XCTAssertFalse(WakeLogic.canCheckIn(now: T.d(2026, 10, 9, 7), settings: skip, state: empty))
    }

    func testLateWakeExtendsWindow() throws {
        var late = s
        late.days[5] = WakeDay(on: true, wake: 660, departure: nil)   // 金曜 11:00
        let w = try XCTUnwrap(WakeLogic.checkInWindow(for: T.d(2026, 10, 9), settings: late, state: empty))
        XCTAssertEqual(w.start, T.d(2026, 10, 9, 9))
        XCTAssertEqual(w.end, T.d(2026, 10, 9, 12, 30), "最後のアラーム（11:30）の1時間後")
    }

    func testNextCheckInStart() {
        XCTAssertEqual(WakeLogic.nextCheckInStart(now: T.d(2026, 10, 9, 6), settings: s, state: empty), T.d(2026, 10, 9, 6), "今押せるなら今")
        XCTAssertEqual(WakeLogic.nextCheckInStart(now: T.d(2026, 10, 9, 3), settings: s, state: empty), T.d(2026, 10, 9, 5))
        XCTAssertEqual(WakeLogic.nextCheckInStart(now: T.d(2026, 10, 9, 13), settings: s, state: empty), T.d(2026, 10, 12, 5))
        let st = checkedIn(at: T.d(2026, 10, 9, 7))
        XCTAssertEqual(WakeLogic.nextCheckInStart(now: T.d(2026, 10, 9, 8), settings: s, state: st), T.d(2026, 10, 12, 5))
    }

    // MARK: 段階・点数・連続

    func testScoreTable() {
        XCTAssertEqual((0...4).map { WakeLogic.score(stage: $0) }, [100, 100, 85, 70, 40])
        XCTAssertEqual(WakeLogic.score(stage: 9), 40)
        XCTAssertEqual(WakeLogic.score(stage: -1), 100)
    }

    func testReached() throws {
        let p = try XCTUnwrap(WakeLogic.plan(for: T.d(2026, 10, 9), settings: s, state: empty))
        XCTAssertEqual(WakeLogic.reached(p, at: T.d(2026, 10, 9, 6, 59)), 0)
        XCTAssertEqual(WakeLogic.reached(p, at: T.d(2026, 10, 9, 7)), 1)
        XCTAssertEqual(WakeLogic.reached(p, at: T.d(2026, 10, 9, 7, 15)), 2)
        XCTAssertEqual(WakeLogic.reached(p, at: T.d(2026, 10, 9, 9)), 4)
    }

    private func session(_ day: String, _ score: Int, missed: Bool? = nil) -> WakeSession {
        WakeSession(day: day, checkInAt: nil, stage: 1, score: score, missed: missed)
    }

    func testStreak() {
        let xs = [session("2026-10-06", 40), session("2026-10-09", 100), session("2026-10-07", 70),
                  session("2026-10-08", 85), session("2026-10-05", 100)]
        XCTAssertEqual(WakeLogic.streak(xs), 3, "新しい順に 70 点以上が続いた数（順不同の入力でも）")
        XCTAssertEqual(WakeLogic.streak([]), 0)
        XCTAssertEqual(WakeLogic.streak([session("2026-10-09", 100, missed: true), session("2026-10-08", 100)]), 0)
        XCTAssertEqual(WakeLogic.streak([session("2026-10-09", 69)]), 0)
    }

    func testAverage() {
        let xs = [session("2026-10-09", 100), session("2026-10-08", 70), session("2026-10-01", 0)]
        XCTAssertEqual(WakeLogic.average(xs, days: 7, now: T.now), 85)
        XCTAssertEqual(WakeLogic.average(xs, days: 30, now: T.now), 56)
        XCTAssertNil(WakeLogic.average([], days: 7, now: T.now))
    }

    // MARK: 画面の状態

    func testPhase() {
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 4), settings: s, state: empty), .before)
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 6), settings: s, state: empty), .window)
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 13), settings: s, state: empty), .before)
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 19), settings: s, state: empty), .evening)
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 10, 10), settings: s, state: empty), .before, "土曜")
        let st = checkedIn(at: T.d(2026, 10, 9, 7, 2))
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 7, 30), settings: s, state: st), .morning)
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 9), settings: s, state: st), .day)
        XCTAssertEqual(WakeLogic.phase(now: T.d(2026, 10, 9, 19), settings: s, state: st), .evening)
    }

    func testBedtime() throws {
        let p = try XCTUnwrap(WakeLogic.plan(for: T.d(2026, 10, 9), settings: s, state: empty))
        XCTAssertEqual(WakeLogic.bedtime(before: p, settings: s), T.d(2026, 10, 9, 0), "0:00 は当日の0時")
        var late = s
        late.bedtime = 23 * 60
        XCTAssertEqual(WakeLogic.bedtime(before: p, settings: late), T.d(2026, 10, 8, 23), "23:00 は前の日")
        late.bedtime = 90
        XCTAssertEqual(WakeLogic.bedtime(before: p, settings: late), T.d(2026, 10, 9, 1, 30))
    }

    func testRemainingRoutine() {
        var st = WakeDayState()
        st.routineDone = [s.routine[0].id, s.routine[2].id]
        XCTAssertEqual(WakeLogic.remainingRoutine(settings: s, state: st).map(\.name), ["洗顔", "着替え", "歯磨き"])
    }

    // MARK: 文字

    func testDurationAndClock() {
        XCTAssertEqual(WakeLogic.duration(5400), "1時間30分")
        XCTAssertEqual(WakeLogic.duration(3600), "1時間")
        XCTAssertEqual(WakeLogic.duration(59 * 60 + 59), "59分")
        XCTAssertEqual(WakeLogic.duration(-30), "0分")
        XCTAssertEqual(WakeLogic.clock(425), "7:05")
        XCTAssertEqual(WakeLogic.clock(-10), "23:50")
        XCTAssertEqual(WakeLogic.clock(1445), "0:05")
    }

    func testDayLabelAndKey() {
        XCTAssertEqual(WakeLogic.dayLabel(T.d(2026, 10, 9, 23), now: T.now), "今日")
        XCTAssertEqual(WakeLogic.dayLabel(T.d(2026, 10, 10, 7), now: T.now), "明日")
        XCTAssertEqual(WakeLogic.dayLabel(T.d(2026, 10, 12, 7), now: T.now), "10月12日（月）")
        XCTAssertEqual(WakeLogic.key(T.d(2026, 10, 9, 0, 30)), "2026-10-09", "日本時間の0時台は当日")
        XCTAssertEqual(WakeLogic.date(fromKey: "2026-10-09"), T.d(2026, 10, 9))
        XCTAssertNil(WakeLogic.date(fromKey: "10/9"))
    }

    // MARK: 古い設定ファイル

    func testDecodeOldSettings() throws {
        let json = #"{"days":[{"on":true}],"stages":[{"name":"そっと","offset":0},{"name":"起きて","offset":5}]}"#.data(using: .utf8)!
        let w = try JSONDecoder.iso.decode(WakeSettings.self, from: json)
        XCTAssertEqual(w.days.count, 7, "7日でなければ既定値")
        XCTAssertEqual(w.stages.map(\.name), ["", "起きて"], "旧版の既定の名前は空にする")
        XCTAssertTrue(w.skipHolidays)
        XCTAssertFalse(w.paused)
    }
}
