import XCTest
@testable import TodoApp

/// TODO の見返し（ReviewLogic）。いま＝2026-10-09（金）10:00。既定の時刻：朝 8:30（アラームの無い日）・昼 12:00・夜 21:00
final class ReviewLogicTests: TokyoTestCase {
    private let s = ReviewSettings()

    private func todo(_ title: String, due: Date? = nil, allDay: Bool? = nil, done: Bool = false, doneAt: Date? = nil) -> TodoItem {
        TodoItem(id: title, title: title, done: done, due: due, allDay: allDay, doneAt: doneAt)
    }

    private func allDone(_ log: inout ReviewLog, _ y: Int, _ m: Int, _ d: Int) {
        var day = ReviewDay()
        for slot in ReviewSlot.allCases { day.done[slot.rawValue] = T.d(y, m, d, 22) }
        log.days[WakeLogic.key(T.d(y, m, d))] = day
    }

    // MARK: 日と枠

    func testReviewDayStartsAt4am() {
        XCTAssertEqual(ReviewLogic.reviewDay(T.d(2026, 10, 10, 2)), T.d(2026, 10, 9), "0時〜4時は前の日")
        XCTAssertEqual(ReviewLogic.reviewDay(T.d(2026, 10, 10, 4)), T.d(2026, 10, 10))
        XCTAssertEqual(ReviewLogic.key(T.d(2026, 10, 10, 1)), "2026-10-09")
    }

    func testSlotAtTime() {
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 9, 6), settings: s), .morning)
        XCTAssertEqual(ReviewLogic.slot(at: T.now, settings: s), .morning)
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 9, 12), settings: s), .noon)
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 9, 20, 59), settings: s), .noon)
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 9, 21), settings: s), .night)
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 10, 1), settings: s), .night, "夜中は前の日の夜")
    }

    func testEditedTimes() {
        var e = ReviewSettings()
        e.noonMinute = 13 * 60
        e.nightMinute = 22 * 60 + 30
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 9, 12, 30), settings: e), .morning)
        XCTAssertEqual(ReviewLogic.slot(at: T.d(2026, 10, 9, 22), settings: e), .noon)
        XCTAssertEqual(ReviewLogic.start(.night, on: T.d(2026, 10, 9), settings: e, log: nil), T.d(2026, 10, 9, 22, 30))
    }

    func testMorningStartsAtAlarmStop() {
        var d = ReviewDay()
        XCTAssertEqual(ReviewLogic.start(.morning, on: T.d(2026, 10, 9), settings: s, log: d), T.d(2026, 10, 9, 8, 30))
        d.morningAt = T.d(2026, 10, 9, 7, 1)
        XCTAssertEqual(ReviewLogic.start(.morning, on: T.d(2026, 10, 9), settings: s, log: d), T.d(2026, 10, 9, 7, 1))
    }

    func testDue() {
        var log = ReviewLog()
        XCTAssertNil(ReviewLogic.due(now: T.d(2026, 10, 9, 7), settings: s, log: log), "止める前・8:30 より前はまだ")
        XCTAssertEqual(ReviewLogic.due(now: T.now, settings: s, log: log), .morning)
        var d = ReviewDay()
        d.morningAt = T.d(2026, 10, 9, 6, 50)
        log.days["2026-10-09"] = d
        XCTAssertEqual(ReviewLogic.due(now: T.d(2026, 10, 9, 7), settings: s, log: log), .morning, "止めた直後から朝の見返し")
        d.done["morning"] = T.d(2026, 10, 9, 7, 5)
        log.days["2026-10-09"] = d
        XCTAssertNil(ReviewLogic.due(now: T.now, settings: s, log: log))
        XCTAssertEqual(ReviewLogic.due(now: T.d(2026, 10, 9, 12, 1), settings: s, log: log), .noon)
    }

    func testPreviousMissed() {
        var log = ReviewLog()
        XCTAssertNil(ReviewLogic.previousMissed(before: .noon, now: T.d(2026, 10, 9, 12), log: log), "まだ使っていない人には出さない")
        var y = ReviewDay()
        y.done["morning"] = T.d(2026, 10, 8, 7)
        y.done["noon"] = T.d(2026, 10, 8, 12)
        log.days["2026-10-08"] = y
        XCTAssertEqual(ReviewLogic.previousMissed(before: .morning, now: T.now, log: log), .night, "昨日の夜がまだ")
        XCTAssertEqual(ReviewLogic.previousMissed(before: .noon, now: T.d(2026, 10, 9, 12), log: log), .morning)
        var t = ReviewDay()
        t.done["morning"] = T.d(2026, 10, 9, 7)
        log.days["2026-10-09"] = t
        XCTAssertNil(ReviewLogic.previousMissed(before: .noon, now: T.d(2026, 10, 9, 12), log: log))
        XCTAssertEqual(ReviewLogic.previousMissed(before: .night, now: T.d(2026, 10, 9, 21), log: log), .noon)
    }

    // MARK: 連続日数

    func testStreak() {
        var log = ReviewLog()
        XCTAssertEqual(ReviewLogic.streak(log, now: T.now), 0)
        allDone(&log, 2026, 10, 6)
        allDone(&log, 2026, 10, 7)
        allDone(&log, 2026, 10, 8)
        XCTAssertEqual(ReviewLogic.streak(log, now: T.now), 3, "今日が途中なら昨日から数える")
        allDone(&log, 2026, 10, 9)
        XCTAssertEqual(ReviewLogic.streak(log, now: T.d(2026, 10, 9, 22)), 4)
        XCTAssertEqual(ReviewLogic.streak(log, now: T.d(2026, 10, 10, 1)), 4, "夜中はまだ前の日")
        // 1回でも抜けた日で切れる
        var partial = ReviewDay()
        partial.done["morning"] = T.d(2026, 10, 5, 7)
        partial.done["night"] = T.d(2026, 10, 5, 21)
        log.days["2026-10-05"] = partial
        allDone(&log, 2026, 10, 4)
        XCTAssertEqual(ReviewLogic.streak(log, now: T.d(2026, 10, 9, 22)), 4)
        log.days["2026-10-07"] = nil
        XCTAssertEqual(ReviewLogic.streak(log, now: T.d(2026, 10, 9, 22)), 2)
    }

    // MARK: 通知の予定

    func testNotices() {
        let n = ReviewLogic.notices(now: T.now, settings: s, log: ReviewLog())
        XCTAssertTrue(n.allSatisfy { $0.id.hasPrefix("review-") })
        // 今日：朝はもう過ぎた（8:30 と 9:00）。昼・夜と、それぞれ30分後の再通知。明日：3回 × 2
        XCTAssertEqual(n.filter { $0.day == "2026-10-09" }.map(\.at),
                       [T.d(2026, 10, 9, 12), T.d(2026, 10, 9, 12, 30), T.d(2026, 10, 9, 21), T.d(2026, 10, 9, 21, 30)])
        XCTAssertEqual(n.filter { $0.day == "2026-10-10" }.count, 6)
        XCTAssertEqual(n.first?.id, "review-noon-2026-10-09")
        XCTAssertEqual(n.filter(\.again).count, 5)
        XCTAssertEqual(Set(n.map(\.id)).count, n.count, "識別子は重ならない")
    }

    func testNoticesSkipDoneAndOpened() {
        var log = ReviewLog()
        var d = ReviewDay()
        d.done["noon"] = T.d(2026, 10, 9, 12, 2)
        d.opened["night"] = T.d(2026, 10, 9, 9)
        log.days["2026-10-09"] = d
        let today = ReviewLogic.notices(now: T.now, settings: s, log: log).filter { $0.day == "2026-10-09" }
        XCTAssertEqual(today.map(\.id), ["review-night-2026-10-09"], "済んだ昼は出さない・開いた夜は再通知しない")
    }

    func testMorningTriggeredRenotify() {
        var log = ReviewLog()
        var d = ReviewDay()
        d.morningAt = T.d(2026, 10, 9, 7, 1)
        log.days["2026-10-09"] = d
        let n = ReviewLogic.notices(now: T.d(2026, 10, 9, 7, 2), settings: s, log: log).filter { $0.day == "2026-10-09" && $0.slot == .morning }
        XCTAssertEqual(n.map(\.id), ["review-morning-2026-10-09-again"])
        XCTAssertEqual(n.first?.at, T.d(2026, 10, 9, 7, 31), "止めてから30分たっても開かなければもう一度")
    }

    func testNoticesOffAndNoRenotify() {
        var off = ReviewSettings()
        off.on = false
        XCTAssertTrue(ReviewLogic.notices(now: T.now, settings: off, log: ReviewLog()).isEmpty)
        var once = ReviewSettings()
        once.renotify = false
        XCTAssertTrue(ReviewLogic.notices(now: T.now, settings: once, log: ReviewLog()).allSatisfy { !$0.again })
    }

    // MARK: 期限内の完了

    func testWeekStart() {
        XCTAssertEqual(ReviewLogic.weekStart(T.now), T.d(2026, 10, 5))
        XCTAssertEqual(ReviewLogic.weekStart(T.d(2026, 10, 11, 21)), T.d(2026, 10, 5), "日曜は週の終わり")
        XCTAssertEqual(ReviewLogic.weekStart(T.d(2026, 10, 12, 8)), T.d(2026, 10, 12))
    }

    func testOnTime() {
        let items = [
            todo("月・期限内", due: T.d(2026, 10, 5, 18), done: true, doneAt: T.d(2026, 10, 5, 17)),
            todo("水・遅れ", due: T.d(2026, 10, 7, 9), done: true, doneAt: T.d(2026, 10, 7, 20)),
            todo("木・終日・当日中", due: T.d(2026, 10, 8), allDay: true, done: true, doneAt: T.d(2026, 10, 8, 23)),
            todo("木・未完了", due: T.d(2026, 10, 8, 12)),
            todo("土・まだ先", due: T.d(2026, 10, 10, 12)),
            todo("先週", due: T.d(2026, 10, 2, 12)),
            todo("期限なし"),
        ]
        let r = ReviewLogic.onTime(items, now: T.now)
        XCTAssertEqual(r.onTime, 2)
        XCTAssertEqual(r.total, 4)
        XCTAssertEqual(ReviewLogic.onTimePercent(items, now: T.now), 50)
        XCTAssertNil(ReviewLogic.onTimePercent([todo("期限なし")], now: T.now))
    }

    // MARK: 初めて見た日・忘れそうな1件

    func testUpdatedSeen() {
        let old = ["a": T.d(2026, 10, 1), "gone": T.d(2026, 10, 1)]
        let s2 = ReviewLogic.updatedSeen(old, items: [todo("a"), todo("b")], now: T.now)
        XCTAssertEqual(s2["a"], T.d(2026, 10, 1), "前に見た日は変えない")
        XCTAssertEqual(s2["b"], T.now)
        XCTAssertNil(s2["gone"], "消えたTODOは忘れる")
    }

    func testForgottenRotatesDaily() {
        let items = [todo("a"), todo("b"), todo("c"), todo("new"), todo("done", done: true)]
        let seen: [String: Date] = ["a": T.d(2026, 10, 1), "b": T.d(2026, 10, 2), "c": T.d(2026, 10, 6, 9),
                                    "new": T.d(2026, 10, 8), "done": T.d(2026, 9, 1)]
        var picked: [String] = []
        for day in 9...14 {
            let f = ReviewLogic.forgotten(items, seen: seen, now: T.d(2026, 10, day, 10))
            XCTAssertNotNil(f)
            XCTAssertNotEqual(f?.id, "done", "完了したものは出さない")
            if day == 9 { XCTAssertNotEqual(f?.id, "new", "3日たっていないものは出さない") }
            picked.append(f?.id ?? "")
        }
        XCTAssertEqual(ReviewLogic.forgotten(items, seen: seen, now: T.now)?.id,
                       ReviewLogic.forgotten(items, seen: seen, now: T.d(2026, 10, 9, 20))?.id, "同じ日は同じ1件")
        XCTAssertNotEqual(picked[0], picked[1], "次の日は別の1件")
        XCTAssertNil(ReviewLogic.forgotten([todo("x")], seen: ["x": T.d(2026, 10, 8)], now: T.now))
    }

    // MARK: カード

    func testMorningPlan() {
        let items = [
            todo("期限切れ", due: T.d(2026, 10, 8, 17)),
            todo("今日", due: T.d(2026, 10, 9, 14)),
            todo("明日", due: T.d(2026, 10, 10, 9)),
            todo("古い・期限なし"),
            todo("済み", due: T.d(2026, 10, 9, 8), done: true, doneAt: T.d(2026, 10, 9, 8)),
        ]
        let seen: [String: Date] = ["古い・期限なし": T.d(2026, 10, 4)]
        let p = ReviewLogic.plan(.morning, items: items, seen: seen, now: T.now, weekly: false)
        XCTAssertEqual(p.cards.map(\.id), ["期限切れ", "今日", "古い・期限なし"])
        XCTAssertEqual(p.cards.map(\.kind), [.overdue, .today, .forgotten])
        XCTAssertTrue(p.preview.isEmpty)
    }

    func testNoonMarksAfternoon() {
        let items = [todo("朝", due: T.d(2026, 10, 9, 13)), todo("終日", due: T.d(2026, 10, 9), allDay: true)]
        let p = ReviewLogic.plan(.noon, items: items, seen: [:], now: T.d(2026, 10, 9, 12), weekly: false)
        XCTAssertEqual(p.cards.first { $0.id == "朝" }?.kind, .afternoon)
        XCTAssertEqual(p.cards.first { $0.id == "終日" }?.kind, .today)
    }

    func testNightPlanWithWeeklyAndPreview() {
        let items = [
            todo("今日の残り", due: T.d(2026, 10, 11, 18)),
            todo("期限なし"),
            todo("7日以上前から", due: T.d(2026, 10, 20)),
            todo("最近", due: T.d(2026, 10, 25)),
            todo("明日1", due: T.d(2026, 10, 12, 9)),
            todo("明日2", due: T.d(2026, 10, 12, 10)),
            todo("明日3", due: T.d(2026, 10, 12, 11)),
            todo("明日4", due: T.d(2026, 10, 12, 12)),
        ]
        let seen: [String: Date] = ["7日以上前から": T.d(2026, 10, 1), "最近": T.d(2026, 10, 10)]
        let sunday = T.d(2026, 10, 11, 21)
        XCTAssertTrue(ReviewLogic.isWeekly(now: sunday, settings: s))
        XCTAssertFalse(ReviewLogic.isWeekly(now: T.d(2026, 10, 10, 21), settings: s))
        let p = ReviewLogic.plan(.night, items: items, seen: seen, now: sunday, weekly: true)
        XCTAssertTrue(p.weekly)
        XCTAssertEqual(p.cards.map(\.id), ["今日の残り", "7日以上前から", "期限なし"])
        XCTAssertEqual(p.cards.map(\.kind), [.unfinished, .stale, .noDue])
        XCTAssertEqual(p.preview.map(\.id), ["明日1", "明日2", "明日3"], "明日の最初の3件")
        let plain = ReviewLogic.plan(.night, items: items, seen: seen, now: T.d(2026, 10, 10, 21), weekly: false)
        XCTAssertFalse(plain.cards.contains { $0.kind == .noDue || $0.kind == .stale }, "棚卸しは週1回だけ")
    }

    func testCardsAreCapped() {
        let items = (0..<12).map { todo("t\($0)", due: T.d(2026, 10, 9, 13, $0)) }
        let p = ReviewLogic.plan(.morning, items: items, seen: [:], now: T.now, weekly: false)
        XCTAssertEqual(p.cards.count, 6, "30秒で終わるように")
        XCTAssertEqual(p.more, 6)
    }

    func testThisWeekDay() {
        XCTAssertEqual(ReviewLogic.thisWeekDay(from: T.d(2026, 10, 9, 21)), T.d(2026, 10, 10), "金 → 土")
        XCTAssertEqual(ReviewLogic.thisWeekDay(from: T.d(2026, 10, 10, 21)), T.d(2026, 10, 11), "土 → 日")
        XCTAssertEqual(ReviewLogic.thisWeekDay(from: T.d(2026, 10, 11, 21)), T.d(2026, 10, 17), "日 → 次の土")
        XCTAssertEqual(ReviewLogic.thisWeekDay(from: T.d(2026, 10, 6, 21)), T.d(2026, 10, 10), "火 → 土")
    }

    // MARK: ウィジェット向け

    func testReviewState() {
        var log = ReviewLog()
        allDone(&log, 2026, 10, 8)
        var d = ReviewDay()
        d.done["morning"] = T.d(2026, 10, 9, 7)
        log.days["2026-10-09"] = d
        let items = [todo("今日", due: T.d(2026, 10, 9, 14))]
        let st = ReviewState.make(log: log, settings: s, items: items, now: T.d(2026, 10, 9, 12, 10))
        XCTAssertTrue(st.morningDone)
        XCTAssertFalse(st.noonDone)
        XCTAssertEqual(st.dueSlot, .noon)
        XCTAssertEqual(st.unreviewedCount, 1)
        XCTAssertEqual(st.nextSlot, .night)
        XCTAssertEqual(st.nextAt, T.d(2026, 10, 9, 21))
        XCTAssertEqual(st.streak, 1)
    }

    func testSettingsDecodeOld() throws {
        let old = try JSONDecoder().decode(ReviewSettings.self, from: Data(#"{"noonMinute": 780}"#.utf8))
        XCTAssertEqual(old.noonMinute, 780)
        XCTAssertEqual(old.nightMinute, 1260)
        XCTAssertTrue(old.on)
    }
}
