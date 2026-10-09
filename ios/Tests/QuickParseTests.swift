import XCTest
@testable import TodoApp

/// すばやい追加（QuickParse）。いま＝2026-10-09（金）10:00
final class QuickParseTests: TokyoTestCase {
    private func p(_ s: String, now: Date = T.now) -> QuickParseResult {
        QuickParse.parse(s, now: now, calendar: T.cal)
    }

    private func check(_ s: String, title: String, due: Date?, allDay: Bool = false, rule: RepeatRule? = nil,
                       now: Date = T.now, file: StaticString = #filePath, line: UInt = #line) {
        let r = p(s, now: now)
        XCTAssertEqual(r.title, title, "題名: \(s)", file: file, line: line)
        XCTAssertEqual(r.due, due, "期限: \(s)", file: file, line: line)
        if due != nil { XCTAssertEqual(r.allDay, allDay, "終日: \(s)", file: file, line: line) }
        XCTAssertEqual(r.repeatRule, rule?.rawValue, "繰り返し: \(s)", file: file, line: line)
    }

    // MARK: 日付＋時刻

    func testTomorrowAt15() {
        check("明日15時 買い物", title: "買い物", due: T.d(2026, 10, 10, 15))
    }

    func testTitleFirstThenDate() {
        check("買い物 明日15時", title: "買い物", due: T.d(2026, 10, 10, 15))
    }

    func testTomorrowWithParticle() {
        check("明日の会議", title: "会議", due: T.d(2026, 10, 10), allDay: true)
        check("明日に 買い物", title: "買い物", due: T.d(2026, 10, 10), allDay: true)
    }

    func testHiraganaDays() {
        check("あした 洗濯", title: "洗濯", due: T.d(2026, 10, 10), allDay: true)
        check("あさって 映画", title: "映画", due: T.d(2026, 10, 11), allDay: true)
        check("明後日 映画", title: "映画", due: T.d(2026, 10, 11), allDay: true)
        check("今日 掃除", title: "掃除", due: T.d(2026, 10, 9), allDay: true)
        check("きょう 掃除", title: "掃除", due: T.d(2026, 10, 9), allDay: true)
    }

    func testMinutesAndHalf() {
        check("午後3時半 電話", title: "電話", due: T.d(2026, 10, 9, 15, 30))
        check("明日15時30分 打ち合わせ", title: "打ち合わせ", due: T.d(2026, 10, 10, 15, 30))
        check("明日 9:05 朝会", title: "朝会", due: T.d(2026, 10, 10, 9, 5))
    }

    func testTimeOnlyPastRollsToTomorrow() {
        // 今日の 9:00 は過ぎているので明日
        check("午前9時 散歩", title: "散歩", due: T.d(2026, 10, 10, 9))
        check("9:30 朝会", title: "朝会", due: T.d(2026, 10, 10, 9, 30))
        // まだ来ていない時刻は今日
        check("18時 夕飯", title: "夕飯", due: T.d(2026, 10, 9, 18))
        // ちょうど「いま」は過ぎた扱い
        check("10時 会議", title: "会議", due: T.d(2026, 10, 10, 10))
    }

    func testAmPmTwelve() {
        check("明日 午後12時 昼食", title: "昼食", due: T.d(2026, 10, 10, 12))
        check("明日 午前12時 就寝", title: "就寝", due: T.d(2026, 10, 10, 0))
        check("明日 午後7時 ジム", title: "ジム", due: T.d(2026, 10, 10, 19))
        check("明日 午後19時 ジム", title: "ジム", due: T.d(2026, 10, 10, 19))
    }

    func testPartsOfDay() {
        check("明日の朝 ジョギング", title: "ジョギング", due: T.d(2026, 10, 10, 8))
        check("明日の夜 電話", title: "電話", due: T.d(2026, 10, 10, 20))
        check("今日の昼 ランチ", title: "ランチ", due: T.d(2026, 10, 9, 12))
        check("明日夕方 買い物", title: "買い物", due: T.d(2026, 10, 10, 17))
    }

    func testWordsContainingPartOfDayAreNotTimes() {
        check("朝ごはんを作る", title: "朝ごはんを作る", due: nil)
        check("夜ご飯の材料", title: "夜ご飯の材料", due: nil)
    }

    func testHoursOfStudyIsNotATime() {
        // 「3時間」は時刻ではない
        check("3時間勉強", title: "3時間勉強", due: nil)
    }

    // MARK: 曜日

    func testNextWeekMonday() {
        check("来週月曜 会議", title: "会議", due: T.d(2026, 10, 12), allDay: true)
        check("来週の金曜日 飲み会", title: "飲み会", due: T.d(2026, 10, 16), allDay: true)
        check("来週日曜 掃除", title: "掃除", due: T.d(2026, 10, 18), allDay: true)
    }

    func testNextWeekFromSundayAndMonday() {
        // 日曜から見た「来週月曜」は翌日（週は月曜始まり）
        check("来週月曜 会議", title: "会議", due: T.d(2026, 10, 12), allDay: true, now: T.d(2026, 10, 11, 10))
        // 月曜から見た「来週月曜」は7日後
        check("来週月曜 会議", title: "会議", due: T.d(2026, 10, 19), allDay: true, now: T.d(2026, 10, 12, 10))
    }

    func testPlainWeekday() {
        check("火曜 ゴミ出し", title: "ゴミ出し", due: T.d(2026, 10, 13), allDay: true)
        check("土曜日 洗車", title: "洗車", due: T.d(2026, 10, 10), allDay: true)
        // 今日と同じ曜日は次の週
        check("金曜 飲み会", title: "飲み会", due: T.d(2026, 10, 16), allDay: true)
        check("水曜 19時 ジム", title: "ジム", due: T.d(2026, 10, 14, 19))
    }

    // MARK: 繰り返し

    func testWeeklyTuesday() {
        check("毎週火曜 ゴミ出し", title: "ゴミ出し", due: T.d(2026, 10, 13), allDay: true, rule: .weekly)
        check("毎週火曜日 19時 ジム", title: "ジム", due: T.d(2026, 10, 13, 19), rule: .weekly)
    }

    func testDailyWeekdaysMonthly() {
        check("毎日 ストレッチ", title: "ストレッチ", due: T.d(2026, 10, 9), allDay: true, rule: .daily)
        check("毎日7時 体重を量る", title: "体重を量る", due: T.d(2026, 10, 10, 7), rule: .daily)
        check("平日 日報", title: "日報", due: T.d(2026, 10, 9), allDay: true, rule: .weekdays)
        check("毎月 家賃", title: "家賃", due: T.d(2026, 10, 9), allDay: true, rule: .monthly)
        check("毎週 掃除", title: "掃除", due: T.d(2026, 10, 9), allDay: true, rule: .weekly)
    }

    func testWeekdaysOnSaturdayStartsMonday() {
        check("平日 日報", title: "日報", due: T.d(2026, 10, 12), allDay: true, rule: .weekdays, now: T.d(2026, 10, 10, 10))
    }

    func testRepeatWithDay() {
        check("毎週 明日15時 英会話", title: "英会話", due: T.d(2026, 10, 10, 15), rule: .weekly)
    }

    // MARK: 月日

    func testSlashDate() {
        check("10/12 歯医者", title: "歯医者", due: T.d(2026, 10, 12), allDay: true)
        check("10/12 15時 歯医者", title: "歯医者", due: T.d(2026, 10, 12, 15))
        check("10月12日 歯医者", title: "歯医者", due: T.d(2026, 10, 12), allDay: true)
    }

    func testPastMonthDayGoesToNextYear() {
        check("1/5 年賀状の返事", title: "年賀状の返事", due: T.d(2027, 1, 5), allDay: true)
        check("10/8 振り返り", title: "振り返り", due: T.d(2027, 10, 8), allDay: true)
        // 今日はそのまま今年
        check("10/9 提出", title: "提出", due: T.d(2026, 10, 9), allDay: true)
    }

    func testInvalidDates() {
        XCTAssertNil(p("13/1 なにか").due)
        XCTAssertNil(p("2/30 なにか").due)
        // ありえない時刻は時刻なし（日付だけ使う）
        check("明日25時 なにか", title: "なにか", due: T.d(2026, 10, 10), allDay: true)
        // 年つきの日付は読み取らない（題名に残る）
        XCTAssertNil(p("2026/10/12 提出").due)
    }

    // MARK: 全角

    func testFullWidthDigits() {
        check("明日１５時 買い物", title: "買い物", due: T.d(2026, 10, 10, 15))
        check("１０／１２ 歯医者", title: "歯医者", due: T.d(2026, 10, 12), allDay: true)
        check("明日　１５：３０　打ち合わせ", title: "打ち合わせ", due: T.d(2026, 10, 10, 15, 30))
        check("１０月１２日 歯医者", title: "歯医者", due: T.d(2026, 10, 12), allDay: true)
    }

    // MARK: 題名

    func testNoScheduleKeepsTitle() {
        let r = p("牛乳を買う")
        XCTAssertEqual(r.title, "牛乳を買う")
        XCTAssertNil(r.due)
        XCTAssertNil(r.repeatRule)
        XCTAssertFalse(r.hasSchedule)
    }

    func testOnlyDateFallsBackToInput() {
        // 題名が空になるときは入力をそのまま使う
        XCTAssertEqual(p("明日").title, "明日")
        XCTAssertEqual(p("  明日15時  ").title, "明日15時")
    }

    func testWhitespaceCollapsed() {
        XCTAssertEqual(p("明日   書類   を   出す").title, "書類 を 出す")
    }

    func testTitleStartingWithParticleCharacterIsKept() {
        // BUG-2（直した）：題名の先頭の「に・の」は、元から先頭にあれば残す
        XCTAssertEqual(p("にんじんを買う").title, "にんじんを買う")
        XCTAssertEqual(p("のりを買う 明日").title, "のりを買う")
        XCTAssertEqual(p("明日 にんじんを買う").title, "にんじんを買う")
        XCTAssertEqual(p("明日15時に買い物").title, "買い物")
    }

    // MARK: 確認の一行

    func testSummary() {
        XCTAssertEqual(QuickParse.summary(p("明日15時 買い物"), now: T.now, calendar: T.cal), "明日 15:00")
        XCTAssertEqual(QuickParse.summary(p("毎週 明日15時 英会話"), now: T.now, calendar: T.cal), "明日 15:00・毎週")
        XCTAssertEqual(QuickParse.summary(p("今日 掃除"), now: T.now, calendar: T.cal), "今日")
        XCTAssertEqual(QuickParse.summary(p("あさって 映画"), now: T.now, calendar: T.cal), "明後日")
        XCTAssertEqual(QuickParse.summary(p("10/14 歯医者"), now: T.now, calendar: T.cal), "10月14日（水）")
        XCTAssertEqual(QuickParse.summary(p("平日 日報"), now: T.now, calendar: T.cal), "今日・平日（月〜金）")
        XCTAssertNil(QuickParse.summary(p("牛乳を買う"), now: T.now, calendar: T.cal))
    }
}
