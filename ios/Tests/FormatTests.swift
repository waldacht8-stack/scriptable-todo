import XCTest
@testable import TodoApp

/// 期限の表示（DueText）と日本語の日付（JP）。いま＝2026-10-09（金）10:00
final class FormatTests: TokyoTestCase {
    private func label(_ due: Date?, allDay: Bool = false) -> String {
        DueText.label(TodoItem(title: "x", due: due, allDay: allDay), now: T.now)
    }

    func testDueTextNoDue() {
        XCTAssertEqual(label(nil), "期限なし")
    }

    func testDueTextTimed() {
        XCTAssertEqual(label(T.d(2026, 10, 9, 15)), "15:00")
        XCTAssertEqual(label(T.d(2026, 10, 9, 8, 5)), "08:05")
        XCTAssertEqual(label(T.d(2026, 10, 10, 9)), "明日 09:00")
        XCTAssertEqual(label(T.d(2026, 10, 8, 17)), "昨日 17:00")
        XCTAssertEqual(label(T.d(2026, 10, 14, 8, 5)), "10/14（水） 08:05")
        XCTAssertEqual(label(T.d(2026, 10, 5, 18)), "10/5（月） 18:00")
    }

    func testDueTextAllDay() {
        XCTAssertEqual(label(T.d(2026, 10, 9), allDay: true), "今日・終日")
        XCTAssertEqual(label(T.d(2026, 10, 10), allDay: true), "明日")
        XCTAssertEqual(label(T.d(2026, 10, 8), allDay: true), "昨日")
        XCTAssertEqual(label(T.d(2026, 10, 11), allDay: true), "10/11（日）")
    }

    func testDueTextAcrossYear() {
        XCTAssertEqual(DueText.label(TodoItem(title: "x", due: T.d(2027, 1, 1, 0)), now: T.d(2026, 12, 31, 23)), "明日 00:00")
    }

    func testJPFormatters() {
        XCTAssertEqual(JP.date(T.now), "10月9日（金）")
        XCTAssertEqual(JP.longDate(T.now), "2026年10月9日 金曜日")
        XCTAssertEqual(JP.time(T.d(2026, 10, 9, 7, 5)), "07:05")
        XCTAssertEqual(JP.time(T.d(2026, 10, 9, 23, 59)), "23:59")
        XCTAssertEqual(JP.shortDate(T.d(2026, 1, 4)), "1/4（日）")
    }

    func testJPClock() {
        XCTAssertEqual(JP.clock(TodoItem(title: "x")), "--:--")
        XCTAssertEqual(JP.clock(TodoItem(title: "x"), none: ""), "")
        XCTAssertEqual(JP.clock(TodoItem(title: "x", due: T.d(2026, 10, 9), allDay: true)), "終日")
        XCTAssertEqual(JP.clock(TodoItem(title: "x", due: T.d(2026, 10, 9, 14, 30))), "14:30")
    }

    func testThemeAndLayoutFallbacks() {
        XCTAssertEqual(AppTheme.from("night"), .night)
        XCTAssertEqual(AppTheme.from("unknown"), .focus)
        XCTAssertEqual(TodayLayout.from("timeline"), .timeline)
        XCTAssertEqual(TodayLayout.from(""), .focus)
        // 名前と説明がすべて埋まっている
        for t in AppTheme.allCases { XCTAssertFalse(t.name.isEmpty); XCTAssertFalse(t.summary.isEmpty) }
        for l in TodayLayout.allCases { XCTAssertFalse(l.name.isEmpty); XCTAssertFalse(l.summary.isEmpty) }
        for r in RepeatRule.allCases { XCTAssertFalse(r.name.isEmpty) }
    }
}
