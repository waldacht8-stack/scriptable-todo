import XCTest
@testable import TodoApp

/// 繰り返し・完了・期限切れ・並び順。いま＝2026-10-09（金）10:00
final class TodoLogicTests: TokyoTestCase {
    private func item(_ due: Date?, _ rule: RepeatRule?, allDay: Bool? = nil, eventID: String? = nil) -> TodoItem {
        TodoItem(title: "テスト", due: due, allDay: allDay, repeatRule: rule?.rawValue, eventID: eventID)
    }

    // MARK: nextOccurrence

    func testNoRepeatHasNoNext() {
        XCTAssertNil(item(T.d(2026, 10, 9, 9), nil).nextOccurrence(now: T.now))
        XCTAssertNil(item(nil, .daily).nextOccurrence(now: T.now), "期限なしの繰り返しは次がない")
        var x = item(T.d(2026, 10, 9, 9), nil)
        x.repeatRule = "yearly"   // 知らない値
        XCTAssertNil(x.nextOccurrence(now: T.now))
    }

    func testDaily() {
        XCTAssertEqual(item(T.d(2026, 10, 9, 9), .daily).nextOccurrence(now: T.now), T.d(2026, 10, 10, 9))
        // 遅れていたら今日まで進める（時刻は保つ）
        XCTAssertEqual(item(T.d(2026, 10, 5, 9), .daily).nextOccurrence(now: T.now), T.d(2026, 10, 9, 9))
        XCTAssertEqual(item(T.d(2026, 10, 1), .daily, allDay: true).nextOccurrence(now: T.now), T.d(2026, 10, 9))
    }

    func testWeekdays() {
        // 金曜 → 月曜
        XCTAssertEqual(item(T.d(2026, 10, 9, 8), .weekdays).nextOccurrence(now: T.now), T.d(2026, 10, 12, 8))
        // 月曜 → 火曜
        XCTAssertEqual(item(T.d(2026, 10, 12, 8), .weekdays).nextOccurrence(now: T.now), T.d(2026, 10, 13, 8))
        // 土曜（ずれたもの）→ 月曜
        XCTAssertEqual(item(T.d(2026, 10, 10, 8), .weekdays).nextOccurrence(now: T.now), T.d(2026, 10, 12, 8))
    }

    func testWeekly() {
        XCTAssertEqual(item(T.d(2026, 10, 9, 19), .weekly).nextOccurrence(now: T.now), T.d(2026, 10, 16, 19))
        // 3週前から今日以降へ
        XCTAssertEqual(item(T.d(2026, 9, 15, 19), .weekly).nextOccurrence(now: T.now), T.d(2026, 10, 13, 19))
        // 先の日付を早めに完了 → さらに1週後
        XCTAssertEqual(item(T.d(2026, 10, 16, 19), .weekly).nextOccurrence(now: T.now), T.d(2026, 10, 23, 19))
    }

    func testMonthly() {
        XCTAssertEqual(item(T.d(2026, 10, 9, 9), .monthly).nextOccurrence(now: T.now), T.d(2026, 11, 9, 9))
        XCTAssertEqual(item(T.d(2026, 12, 25), .monthly, allDay: true).nextOccurrence(now: T.now), T.d(2027, 1, 25))
    }

    func testMonthlyMonthEndClampsOnce() {
        // 1/31 の次は 2/28（その月の最後の日）
        XCTAssertEqual(item(T.d(2026, 1, 31, 9), .monthly).nextOccurrence(now: T.d(2026, 1, 31, 10)), T.d(2026, 2, 28, 9))
    }

    func testMonthlyMonthEndDoesNotDrift() {
        // BUG-1（直した）：月末の「毎月」を何か月か飛ばして完了しても、元の日付で数える
        // 1/31 の毎月を 4/15 に完了 → 次は 4/30 のはず
        XCTAssertEqual(item(T.d(2026, 1, 31, 9), .monthly).nextOccurrence(now: T.d(2026, 4, 15, 10)), T.d(2026, 4, 30, 9))
    }

    // MARK: complete

    func testCompleteRepeatingCreatesNext() {
        var items = [item(T.d(2026, 10, 9, 9), .daily)]
        let origID = items[0].id
        TodoActions.complete(&items, at: 0, now: T.now)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].done)
        XCTAssertEqual(items[0].doneAt, T.now)
        XCTAssertEqual(items[0].id, origID)
        let next = items[1]
        XCTAssertNotEqual(next.id, origID)
        XCTAssertFalse(next.done)
        XCTAssertNil(next.doneAt)
        XCTAssertEqual(next.due, T.d(2026, 10, 10, 9))
        XCTAssertEqual(next.repeatRule, RepeatRule.daily.rawValue)
        XCTAssertEqual(next.title, "テスト")
    }

    func testCompleteKeepsAllDayAndImportant() {
        var t = item(T.d(2026, 10, 9), .weekly, allDay: true)
        t.important = true
        t.note = "メモ"
        var items = [t]
        TodoActions.complete(&items, at: 0, now: T.now)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[1].due, T.d(2026, 10, 16))
        XCTAssertTrue(items[1].isAllDay)
        XCTAssertTrue(items[1].isImportant)
        XCTAssertEqual(items[1].note, "メモ")
    }

    func testCompleteOneOff() {
        var items = [item(T.d(2026, 10, 9, 9), nil), item(nil, nil)]
        TodoActions.complete(&items, at: 1, now: T.now)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[1].done)
        XCTAssertFalse(items[0].done)
    }

    func testCompleteCalendarItemDoesNotRepeat() {
        // カレンダーから取り込んだものは、繰り返しをカレンダー側に任せる
        var items = [item(T.d(2026, 10, 9, 9), .weekly, eventID: "event-1")]
        TodoActions.complete(&items, at: 0, now: T.now)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].done)
    }

    // MARK: isOverdue

    func testOverdueTimed() {
        XCTAssertTrue(item(T.d(2026, 10, 9, 9), nil).isOverdue(T.now))
        XCTAssertFalse(item(T.d(2026, 10, 9, 11), nil).isOverdue(T.now))
        XCTAssertFalse(item(T.d(2026, 10, 9, 10), nil).isOverdue(T.now), "ちょうどの時刻はまだ")
        XCTAssertTrue(item(T.d(2026, 10, 8, 23, 59), nil).isOverdue(T.now))
    }

    func testOverdueAllDay() {
        // 終日は、その日のうちは期限切れにしない
        XCTAssertFalse(item(T.d(2026, 10, 9), nil, allDay: true).isOverdue(T.now))
        XCTAssertFalse(item(T.d(2026, 10, 9), nil, allDay: true).isOverdue(T.d(2026, 10, 9, 23, 59)))
        XCTAssertTrue(item(T.d(2026, 10, 8), nil, allDay: true).isOverdue(T.now))
        XCTAssertFalse(item(T.d(2026, 10, 10), nil, allDay: true).isOverdue(T.now))
    }

    func testOverdueDoneOrNoDue() {
        var t = item(T.d(2026, 10, 1, 9), nil)
        t.done = true
        XCTAssertFalse(t.isOverdue(T.now))
        XCTAssertFalse(item(nil, nil).isOverdue(T.now))
    }

    // MARK: sorted

    func testSortedOrder() {
        let overdue = TodoItem(title: "期限切れ", due: T.d(2026, 10, 8, 17))
        let soon = TodoItem(title: "近い", due: T.d(2026, 10, 9, 14))
        let later = TodoItem(title: "あと", due: T.d(2026, 10, 12, 9))
        let noneB = TodoItem(title: "B", due: nil)
        let noneA = TodoItem(title: "A", due: nil)
        let importantLate = TodoItem(title: "重要", due: T.d(2026, 10, 20), important: true)
        let importantNone = TodoItem(title: "重要なし", due: nil, important: true)
        let sorted = TodoData.sorted([noneB, later, importantNone, soon, noneA, overdue, importantLate])
        XCTAssertEqual(sorted.map(\.title), ["重要", "重要なし", "期限切れ", "近い", "あと", "A", "B"])
    }

    func testSortedIsStable() {
        XCTAssertEqual(TodoData.sorted([]).count, 0)
        let one = [TodoItem(title: "ひとつ")]
        XCTAssertEqual(TodoData.sorted(one).map(\.title), ["ひとつ"])
    }

    // MARK: 設定の読み込み（古いファイル）

    func testSettingsDecodeOldFile() throws {
        let json = #"{"theme":"night"}"#.data(using: .utf8)!
        let s = try JSONDecoder.iso.decode(AppSettings.self, from: json)
        XCTAssertEqual(s.theme, "night")
        XCTAssertEqual(s.layout, "focus")
        XCTAssertEqual(s.remindMinutes, 30)
        XCTAssertTrue(s.calendarImport)
    }

    func testSettingsRoundTripKeepsOff() throws {
        var s = AppSettings()
        s.remindMinutes = nil
        let data = try JSONEncoder.iso.encode(s)
        let back = try JSONDecoder.iso.decode(AppSettings.self, from: data)
        XCTAssertNil(back.remindMinutes, "オフ（nil）が既定値に戻らない")
        XCTAssertEqual(back.morningHour, 7)
    }

    func testTodoItemRoundTrip() throws {
        let t = TodoItem(title: "往復", due: T.d(2026, 10, 9, 9), allDay: false, important: true, repeatRule: "weekly")
        let back = try JSONDecoder.iso.decode([TodoItem].self, from: JSONEncoder.iso.encode([t]))
        XCTAssertEqual(back, [t])
    }
}
