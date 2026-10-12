import XCTest
@testable import TodoApp
import UserNotifications

/// 明細の取り込み忘れを防ぐ期限とお知らせ。基準の「いま」は 2026-10-09（金）
final class KakeiboReminderTests: TokyoTestCase {
    private func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private let r = KakeiboReminderSettings()

    func testBankDueIsDayAfterPayday() {
        // 給料日 25 日。10/25 は日曜なので 10/23 に振り込まれ、その次の日
        let a = KakeiboReminders.due(.juroku, last: T.d(2026, 10, 1, 21), payday: 25, reminder: r)
        XCTAssertEqual(ymd(a.due), "2026-10-24")
        XCTAssertEqual(a.reason, .payday)
        XCTAssertEqual(ymd(a.fallback), "2026-11-05", "35 日め")
        // 給料日の当日に取り込んでも、次の日にもう一度
        XCTAssertEqual(ymd(KakeiboReminders.due(.juroku, last: T.d(2026, 10, 23, 8), payday: 25, reminder: r).due), "2026-10-24")
        // 給料日の次の日に取り込んだら、次の給料日（11/25 水）の次の日
        XCTAssertEqual(ymd(KakeiboReminders.due(.juroku, last: T.d(2026, 10, 24, 10), payday: 25, reminder: r).due), "2026-11-26")
        // 連休（9/19〜9/22）に当たる給料日 22 日は 9/18（金）に早まる
        XCTAssertEqual(ymd(KakeiboReminders.due(.juroku, last: T.d(2026, 9, 10), payday: 22, reminder: r).due), "2026-09-19")
        // 給料日なし：月の初め（1日）の次の日
        XCTAssertEqual(ymd(KakeiboReminders.due(.juroku, last: T.now, payday: nil, reminder: r).due), "2026-11-02")
    }

    func testCardDueIsStatementDay() {
        let jcb = KakeiboReminders.due(.jcb, last: T.now, payday: 25, reminder: r)
        XCTAssertEqual(ymd(jcb.due), "2026-10-15", "JCB は 15 日ごろ")
        XCTAssertEqual(jcb.reason, .statement)
        XCTAssertEqual(ymd(KakeiboReminders.due(.jcb, last: T.d(2026, 10, 15, 21), payday: 25, reminder: r).due), "2026-11-15",
                       "確定日に取り込んだら次の月")
        XCTAssertEqual(ymd(KakeiboReminders.due(.mufg, last: T.now, payday: 25, reminder: r).due), "2026-11-01", "MUFG は月初")
        var custom = KakeiboReminderSettings()
        custom.cardDays = ["jcb": 31]
        XCTAssertEqual(custom.cardDay(.jcb), 28, "29 日より後は 28 日に")
        XCTAssertEqual(ymd(KakeiboReminders.due(.jcb, last: T.now, payday: 25, reminder: custom).due), "2026-10-28")
        XCTAssertEqual(ymd(KakeiboReminders.nextDay(of: 28, after: T.d(2027, 1, 30))), "2027-02-28")
    }

    func testOverdueAndDaysSince() {
        let old = KakeiboReminders.due(.jcb, last: T.d(2026, 8, 30, 12), payday: 25, reminder: r)
        XCTAssertEqual(ymd(old.due), "2026-09-15")
        XCTAssertTrue(old.isOverdue(T.now))
        XCTAssertEqual(old.daysSince(T.now), 40)
        let fresh = KakeiboReminders.due(.juroku, last: T.d(2026, 10, 7), payday: 25, reminder: r)
        XCTAssertFalse(fresh.isOverdue(T.now))
        XCTAssertFalse(fresh.isOverdue(T.d(2026, 10, 23, 23)), "期限の前の日")
        XCTAssertTrue(fresh.isOverdue(T.d(2026, 10, 24, 0, 1)), "期限の日から")
        XCTAssertEqual(fresh.daysSince(T.now), 2)
    }

    func testLastImportsAndDues() {
        var s = KakeiboSettings()
        s.payday = 25
        var e = KakeiboEntry(date: T.d(2026, 9, 5), amount: 680, category: "食費", memo: "見本", source: .cardCSV,
                             institution: KakeiboInstitution.jcb.rawValue, dedupeKey: "")
        e.createdAt = T.d(2026, 9, 20)
        var manual = KakeiboEntry(date: T.d(2026, 10, 5), amount: 500, category: "食費", memo: "見本", source: .manual, dedupeKey: "")
        manual.createdAt = T.d(2026, 10, 8)
        s.lastImports = [KakeiboInstitution.juroku.rawValue: T.d(2026, 10, 7)]
        let last = KakeiboReminders.lastImports(settings: s, entries: [e, manual])
        XCTAssertEqual(last.count, 2, "手入力は数えない")
        XCTAssertEqual(ymd(last[.jcb]!), "2026-09-20", "覚えた日がなければ記録を入れた日")
        s.lastImports[KakeiboInstitution.jcb.rawValue] = T.d(2026, 10, 1)
        XCTAssertEqual(ymd(KakeiboReminders.lastImports(settings: s, entries: [e])[.jcb]!), "2026-10-01")
        let dues = KakeiboReminders.dues(settings: s, entries: [e])
        XCTAssertEqual(dues.map(\.institution), [.juroku, .jcb])
        XCTAssertEqual(dues.map { ymd($0.due) }, ["2026-10-24", "2026-10-15"])
    }

    func testNotificationRequests() {
        var s = KakeiboSettings()
        s.payday = 25
        s.lastImports = [KakeiboInstitution.jcb.rawValue: T.d(2026, 10, 1)]
        let dues = KakeiboReminders.dues(settings: s, entries: [])
        let list = KakeiboReminderScheduler.requests(dues, settings: s.reminder, now: T.now)
        XCTAssertEqual(list.map(\.identifier), ["kakeibo-import-jcb", "kakeibo-import-jcb-late"])
        XCTAssertEqual(list.first?.content.body, "JCB の明細が確定するころです。取り込みましょう")
        XCTAssertEqual(list.first?.content.userInfo["kakeiboURL"] as? String, "hiyori://kakeibo?import=jcb")
        let trigger = list.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.day, 15)
        XCTAssertEqual(trigger?.dateComponents.hour, 20)
        // 期限を過ぎていたら、35 日めのお知らせだけ
        let late = KakeiboReminderScheduler.requests(dues, settings: s.reminder, now: T.d(2026, 10, 16))
        XCTAssertEqual(late.map(\.identifier), ["kakeibo-import-jcb-late"])
        XCTAssertEqual(late.first?.content.body, "JCB の明細を 35 日取り込んでいません")
        // 銀行の文
        s.lastImports = [KakeiboInstitution.juroku.rawValue: T.d(2026, 10, 1)]
        let bank = KakeiboReminderScheduler.requests(KakeiboReminders.dues(settings: s, entries: []), settings: s.reminder, now: T.now)
        XCTAssertEqual(bank.first?.content.body, "給料日のあとです。口座の明細を取り込みましょう")
    }

    func testLinkAndWidgetNote() throws {
        XCTAssertEqual(KakeiboReminders.institution(from: KakeiboReminders.link(.mufg)), .mufg)
        XCTAssertNil(KakeiboReminders.institution(from: URL(string: "hiyori://kakeibo")!))
        XCTAssertNil(KakeiboReminders.institution(from: URL(string: "hiyori://todo?import=jcb")!))

        var sum = KakeiboSummary.make(entries: [], cycle: KakeiboCycle.period(containing: T.now, payday: 25), payday: 25, now: T.now)
        sum.importDue = T.d(2026, 10, 15)
        let data = try JSONEncoder().encode(sum)
        let feed = try JSONDecoder().decode(KakeiboFeed.self, from: data)
        XCTAssertEqual(feed.importDue, "2026-10-15")
        XCTAssertFalse(feed.importOverdue(T.now))
        XCTAssertTrue(feed.importOverdue(T.d(2026, 10, 15, 9)))
        let back = try JSONDecoder().decode(KakeiboSummary.self, from: data)
        XCTAssertEqual(back.importDue.map(ymd), "2026-10-15")
        // 古い設定（お知らせの項目なし）は、お知らせありで読む
        let s = try JSONDecoder.iso.decode(KakeiboSettings.self, from: Data(#"{"excludeTransfers":true}"#.utf8))
        XCTAssertTrue(s.reminder.enabled)
        XCTAssertEqual(s.reminder.hour, 20)
        XCTAssertTrue(s.lastImports.isEmpty)
    }
}
