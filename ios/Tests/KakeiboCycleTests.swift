import XCTest
@testable import TodoApp

/// 家計簿の給料の周期・給料の見分け・自動の分類・目標貯金・取り込みの重複とカードの引き落とし。
/// お店・会社・金額はすべて作り物の見本。基準の「いま」は 2026-10-09（金）
final class KakeiboCycleTests: TokyoTestCase {
    private func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func entry(_ d: Date, _ a: Int, _ kind: KakeiboKind = .expense, cat: String = "食費", memo: String = "見本",
                       source: KakeiboSource = .manual, inst: KakeiboInstitution? = nil) -> KakeiboEntry {
        KakeiboEntry(date: d, amount: a, kind: kind, category: cat, memo: memo, source: source, institution: inst?.rawValue, dedupeKey: "")
    }

    // MARK: 祝日

    func testHolidays2026() {
        let yes: [Date] = [T.d(2026, 1, 1), T.d(2026, 1, 12), T.d(2026, 3, 20), T.d(2026, 5, 6), T.d(2026, 7, 20),
                           T.d(2026, 9, 21), T.d(2026, 9, 22), T.d(2026, 9, 23), T.d(2026, 10, 12), T.d(2026, 11, 23),
                           T.d(2027, 3, 22)]
        for d in yes { XCTAssertTrue(KakeiboHolidays.isHoliday(d), "\(ymd(d)) は祝日") }
        let no: [Date] = [T.d(2026, 5, 7), T.d(2026, 9, 24), T.d(2026, 10, 9), T.d(2026, 10, 13)]
        for d in no { XCTAssertFalse(KakeiboHolidays.isHoliday(d), "\(ymd(d)) は祝日でない") }
        XCTAssertTrue(KakeiboHolidays.isBankHoliday(T.d(2026, 12, 31)), "大みそかは銀行の休み")
        XCTAssertTrue(KakeiboHolidays.isBankHoliday(T.d(2027, 1, 3)))
        XCTAssertTrue(KakeiboHolidays.isBankHoliday(T.d(2026, 10, 10)), "土曜")
        XCTAssertFalse(KakeiboHolidays.isBankHoliday(T.d(2026, 10, 9)))
    }

    // MARK: 給料日・周期

    func testPayDateMovesToEarlierBusinessDay() {
        XCTAssertEqual(ymd(KakeiboCycle.payDate(year: 2026, month: 9, payday: 25)), "2026-09-25", "平日はそのまま")
        XCTAssertEqual(ymd(KakeiboCycle.payDate(year: 2026, month: 10, payday: 25)), "2026-10-23", "日曜は前の金曜")
        XCTAssertEqual(ymd(KakeiboCycle.payDate(year: 2026, month: 9, payday: 22)), "2026-09-18", "連休（国民の休日・敬老の日・土日）の前の営業日")
        XCTAssertEqual(ymd(KakeiboCycle.payDate(year: 2026, month: 10, payday: 31)), "2026-10-30", "月末が土曜")
        XCTAssertEqual(ymd(KakeiboCycle.payDate(year: 2027, month: 2, payday: 30)), "2027-02-26", "2月は月末（28日の日曜）から前へ")
        XCTAssertEqual(ymd(KakeiboCycle.payDate(year: 2027, month: 1, payday: 1)), "2026-12-30", "元日・大みそかは銀行の休み")
    }

    func testCycleFromPayday() {
        let c = KakeiboCycle.period(containing: T.now, payday: 25)
        XCTAssertEqual(ymd(c.start), "2026-09-25")
        XCTAssertEqual(ymd(c.end), "2026-10-23", "10/25 は日曜なので 10/23 が次の給料日")
        XCTAssertEqual(ymd(c.lastDay), "2026-10-22")
        XCTAssertEqual(c.title, "10月分")
        XCTAssertEqual(c.rangeText, "9/25〜10/22")
        XCTAssertTrue(c.contains(T.d(2026, 10, 22, 23, 59)))
        XCTAssertFalse(c.contains(T.d(2026, 10, 23)))
        // 振り込みが早まった日からは次の周期
        XCTAssertEqual(KakeiboCycle.period(containing: T.d(2026, 10, 23, 9), payday: 25).title, "11月分")
        XCTAssertEqual(KakeiboCycle.period(containing: T.d(2026, 9, 24), payday: 25).title, "9月分")
        // 前後の周期
        let prev = KakeiboCycle.period(containing: T.now, payday: 25, offset: -1)
        XCTAssertEqual(ymd(prev.start), "2026-08-25")
        XCTAssertEqual(ymd(prev.end), "2026-09-25")
        XCTAssertEqual(KakeiboCycle.distance(from: prev, to: c), 1)
        // 呼び名の月から
        XCTAssertEqual(ymd(KakeiboCycle.period(label: T.d(2026, 10, 1), payday: 25).start), "2026-09-25")
        XCTAssertEqual(KakeiboCycle.daysToPayday(now: T.now, payday: 25), 14)
        XCTAssertEqual(KakeiboCycle.daysToPayday(now: T.d(2026, 10, 23, 8), payday: 25), 0, "今日が給料日")
    }

    func testCycleWithPaydayOnFirstAndNone() {
        // 給料日 1 日：11/1 は日曜なので 10/30 から「11月分」
        let oct = KakeiboCycle.period(containing: T.now, payday: 1)
        XCTAssertEqual(ymd(oct.start), "2026-10-01")
        XCTAssertEqual(ymd(oct.end), "2026-10-30")
        XCTAssertEqual(oct.title, "10月分")
        XCTAssertEqual(KakeiboCycle.period(containing: T.d(2026, 10, 31), payday: 1).title, "11月分")
        // 給料日なし：暦の月
        let cal = KakeiboCycle.period(containing: T.now, payday: nil)
        XCTAssertEqual(ymd(cal.start), "2026-10-01")
        XCTAssertEqual(ymd(cal.end), "2026-11-01")
        XCTAssertEqual(cal.title, "10月")
        XCTAssertNil(KakeiboCycle.daysToPayday(now: T.now, payday: nil))
        XCTAssertNil(KakeiboCycle.validDay(0))
        XCTAssertNil(KakeiboCycle.validDay(32))
    }

    // MARK: 給料（振り込み元の会社名）

    func testSalaryByEmployer() {
        var s = KakeiboSettings()
        s.employer = "株式会社ミホン商事、ミホンショウジ"
        let pay = KakeiboRules.classify("振込 ｶ)ﾐﾎﾝｼﾖｳｼﾞ", kind: .income, settings: s)
        XCTAssertEqual(pay.category, "給料")
        XCTAssertTrue(pay.salary)
        XCTAssertTrue(KakeiboMerchants.isFromEmployer("ミホン商事 ９月分", employer: s.employer), "全角の数字・漢字の会社名でも")
        let other = KakeiboRules.classify("振込 ﾐﾎﾝﾀﾛｳ", kind: .income, settings: s)
        XCTAssertEqual(other.category, "収入")
        XCTAssertFalse(other.salary)
        XCTAssertFalse(KakeiboRules.classify("ミホンショウジ 売店", kind: .expense, settings: s).salary, "支出は給料にしない")
        // 会社名なしでも「給与」「キュウヨ」は給料
        let none = KakeiboSettings()
        XCTAssertEqual(KakeiboRules.classify("振込 キュウヨ", kind: .income, settings: none).category, "給料")
        XCTAssertEqual(KakeiboMerchants.employerKeys("(株)見本"), ["見本"])
        XCTAssertEqual(KakeiboMerchants.employerKeys("株式会社"), [], "短すぎる名前は使わない")
    }

    // MARK: 自動の分類

    func testAutoClassification() {
        let s = KakeiboSettings()
        let cases: [(String, String)] = [
            ("ETC 見本インター", "交通"), ("NEXCO中日本 見本", "交通"), ("ｾﾌﾞﾝｲﾚﾌﾞﾝ 見本店", "食費"), ("ローソン 見本駅前", "食費"),
            ("APPLE COM BILL", "サブスク"), ("AMAZON PRIME 会費", "サブスク"), ("AMAZON.CO.JP", "買い物"), ("楽天市場 見本ショップ", "買い物"),
            ("楽天モバイル 通信料", "通信"), ("ＥＮＥＯＳ　見本ＳＳ", "車・ガソリン"), ("ｺｽﾓｾｷﾕ 見本", "車・ガソリン"), ("出光 見本給油所", "車・ガソリン"),
            ("東邦ガス 見本", "光熱"), ("ガスト 見本店", "食費"), ("見本市 水道局", "光熱"), ("でんき料金", "光熱"), ("ドコモ ご利用料金", "通信"),
            ("STEAM PURCHASE", "ゲーム"), ("Nintendo eShop", "ゲーム"), ("PlayStation Store", "ゲーム"), ("家賃 見本ハイツ", "住まい"),
            ("見本の何か", "その他"), ("", "その他"),
        ]
        for (text, cat) in cases {
            XCTAssertEqual(KakeiboRules.suggest(text, kind: .expense, settings: s), cat, text)
        }
    }

    func testLearnedRuleBeatsDictionary() {
        var s = KakeiboSettings()
        KakeiboRules.learn("ミホンジム 月会費", category: "娯楽", into: &s)
        XCTAssertEqual(s.rules.first?.keyword, "ミホンジム")
        XCTAssertTrue(s.rules.first?.learned ?? false)
        XCTAssertEqual(KakeiboRules.suggest("ﾐﾎﾝｼﾞﾑ", kind: .expense, settings: s), "娯楽", "半角カナでも")
        KakeiboRules.learn("ローソン 見本", category: "日用品", into: &s)
        XCTAssertEqual(KakeiboRules.suggest("ローソン 見本駅前", kind: .expense, settings: s), "日用品", "直した分類は辞書より先")
        KakeiboRules.learn("ミホンジム", category: "医療", into: &s)
        XCTAssertEqual(s.rules.filter { $0.keyword == "ミホンジム" }.count, 1, "同じ言葉は上書き")
        XCTAssertEqual(KakeiboRules.suggest("ミホンジム", kind: .expense, settings: s), "医療")
        XCTAssertEqual(KakeiboRules.suggest("ミホンジム", kind: .income, settings: s), "収入", "支出の分類は収入に使わない")
    }

    func testOldSettingsDecode() throws {
        let json = """
        {"categories":["食費","その他","ペット"],"budget":50000,
         "rules":[{"id":"a","keyword":"スーパー","category":"食費","learned":false},
                  {"id":"b","keyword":"ミホンジム","category":"娯楽","learned":true}],
         "mappings":{},"excludeTransfers":false,"applePayTested":true,
         "savingsGoal":{"amount":1000,"deadline":"2027-03-01T00:00:00Z","start":"2026-09-01T00:00:00Z"}}
        """
        let s = try JSONDecoder.iso.decode(KakeiboSettings.self, from: Data(json.utf8))
        XCTAssertNil(s.payday)
        XCTAssertEqual(s.employer, "")
        XCTAssertEqual(s.rules.map(\.keyword), ["ミホンジム"], "前の版の組みこみの決まりは捨て、覚えたものは残す")
        XCTAssertFalse(s.excludeTransfers)
        XCTAssertEqual(s.savingsGoal?.amount, 1000)
        let out = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.iso.encode(s)) as? [String: Any])
        XCTAssertNil(out["budget"], "予算は書かない")
        // 前の版の記録（Apple Pay・新しい項目なし）も読める
        let old = """
        [{"id":"x","date":"2026-10-01T03:00:00Z","amount":680,"kind":"expense","category":"食費","memo":"見本",
          "source":"applePay","card":"見本のカード","dedupeKey":"k","createdAt":"2026-10-01T03:00:00Z"}]
        """
        let list = try JSONDecoder.iso.decode([KakeiboEntry].self, from: Data(old.utf8))
        XCTAssertEqual(list.first?.source, .applePay)
        XCTAssertFalse(list.first?.isSalary ?? true)
        XCTAssertTrue(list.first?.counts ?? false)
    }

    // MARK: 周期のまとめ・ウィジェットのファイル

    func testSummaryUsesPayCycle() throws {
        var test = entry(T.d(2026, 10, 4), 100)
        test.isTest = true
        var ex = entry(T.d(2026, 10, 3), 5000)
        ex.excluded = true
        let list = [entry(T.d(2026, 9, 25, 9), 200_000, .income, cat: "給料"), entry(T.d(2026, 10, 1), 1000),
                    entry(T.d(2026, 10, 8), 2000, cat: "交通"), ex, test,
                    entry(T.d(2026, 9, 24), 7000), entry(T.d(2026, 10, 23), 9999)]
        let cycle = KakeiboCycle.period(containing: T.now, payday: 25)
        let s = KakeiboSummary.make(entries: list, cycle: cycle, payday: 25, now: T.now)
        XCTAssertEqual(s.spent, 3000)
        XCTAssertEqual(s.income, 200_000)
        XCTAssertEqual(s.left, 197_000)
        XCTAssertEqual(s.daysToPayday, 14)
        XCTAssertEqual(s.categories.map(\.name), ["交通", "食費"])
        // 前の周期を見ているときは「あと何日」を出さない
        let prev = KakeiboSummary.make(entries: list, cycle: KakeiboCycle.period(containing: T.now, payday: 25, offset: -1), payday: 25, now: T.now)
        XCTAssertNil(prev.daysToPayday)
        XCTAssertEqual(prev.spent, 7000)

        // ファイルの形
        let data = try JSONEncoder().encode(s)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["month", "spent", "income", "cycleStart", "cycleEnd", "payday", "topCategories"])
        XCTAssertEqual(obj["month"] as? String, "2026-10")
        XCTAssertEqual(obj["cycleStart"] as? String, "2026-09-25")
        XCTAssertEqual(obj["cycleEnd"] as? String, "2026-10-22")
        XCTAssertEqual(obj["payday"] as? Int, 25)
        let back = try JSONDecoder().decode(KakeiboSummary.self, from: data)
        XCTAssertEqual(back.spent, 3000)
        XCTAssertEqual(ymd(back.cycle.end), "2026-10-23")

        // ウィジェットの読み方
        let feed = try JSONDecoder().decode(KakeiboFeed.self, from: data)
        XCTAssertTrue(feed.isCurrent(T.now))
        XCTAssertFalse(feed.isCurrent(T.d(2026, 10, 23)), "次の周期になったら 0 として扱う")
        XCTAssertEqual(feed.spentNow(T.now), 3000)
        XCTAssertEqual(feed.leftNow(T.now), 197_000)
        XCTAssertEqual(feed.daysToPayday(T.now), 14)
        XCTAssertEqual(feed.title(T.now), "10月分の支出")
        XCTAssertEqual(feed.paydayText(T.now), "給料日まであと14日")
        // 前の版のファイル（予算あり・周期なし）も読める
        let old = try JSONDecoder().decode(KakeiboFeed.self, from: Data(#"{"month":"2026-10","spent":1200,"budget":50000,"remaining":48800}"#.utf8))
        XCTAssertEqual(old.spentNow(T.now), 1200)
        XCTAssertEqual(old.title(T.now), "10月の支出")
    }

    // MARK: 目標貯金（周期で数える）

    func testGoalPerMonthAgainstCycle() {
        // 2026年9月分（8/25〜）から数えて、2027年3月分までに 100,000 円。給料日 25 日
        let goal = KakeiboSavingsGoal(amount: 100_000, deadline: T.d(2027, 3, 1), start: T.d(2026, 8, 25))
        let list = [entry(T.d(2026, 8, 20), 50_000, .income),          // 数えはじめより前
                    entry(T.d(2026, 8, 25, 9), 200_000, .income), entry(T.d(2026, 9, 10), 170_000),   // 9月分：+30,000
                    entry(T.d(2026, 9, 25, 9), 200_000, .income), entry(T.d(2026, 10, 5), 150_000),   // 10月分（今）：+50,000
                    entry(T.d(2027, 3, 26), 9_000, .income)]           // 期限の周期より後
        let g = KakeiboSavings.progress(goal, entries: list, payday: 25, now: T.now)
        XCTAssertEqual(g.saved, 80_000)
        XCTAssertEqual(g.savedThisCycle, 50_000)
        XCTAssertEqual(g.remaining, 20_000)
        XCTAssertEqual(g.monthsLeft, 6, "10月分〜3月分（今の周期を含む）")
        XCTAssertEqual(g.needThisCycle, 11_667, "前の周期までの残り 70,000 円を 6 で割って切り上げ")
        XCTAssertEqual(g.perMonth, 11_667)
        XCTAssertTrue(g.onTrack)
        XCTAssertEqual(g.ratio, 0.8, accuracy: 0.0001)

        // 今の周期に使いすぎ：必要額は動かず、目標どおりでない
        let over = list + [entry(T.d(2026, 10, 8), 45_000)]
        let o = KakeiboSavings.progress(goal, entries: over, payday: 25, now: T.now)
        XCTAssertEqual(o.savedThisCycle, 5_000)
        XCTAssertEqual(o.needThisCycle, 11_667)
        XCTAssertFalse(o.onTrack)

        // 給料日の前の日（10/22）までは 10月分、給料日（10/23）からは 11月分
        let lastDay = KakeiboSavings.progress(goal, entries: list, payday: 25, now: T.d(2026, 10, 22, 20))
        XCTAssertEqual(lastDay.monthsLeft, 6)
        let payday = KakeiboSavings.progress(goal, entries: list, payday: 25, now: T.d(2026, 10, 23, 9))
        XCTAssertEqual(payday.monthsLeft, 5)
        XCTAssertEqual(payday.savedThisCycle, 0)
        XCTAssertEqual(payday.needThisCycle, 4_000, "残り 20,000 円を 5 で割る")

        // 期限を過ぎた
        let late = KakeiboSavings.progress(goal, entries: list, payday: 25, now: T.d(2027, 4, 2))
        XCTAssertEqual(late.monthsLeft, 0)
        XCTAssertEqual(late.perMonth, late.remaining)

        // 給料日なし：暦の月で数える（10月〜3月の 6 か月）
        let cal = KakeiboSavings.progress(goal, entries: list, payday: nil, now: T.now)
        XCTAssertEqual(cal.monthsLeft, 6)
    }

    // MARK: 取り込み：重複・カードの引き落とし・口座間の振替

    func testCardSettlementAndTransferWords() {
        for t in ["ｼﾞﾕｳﾛｸｶｰﾄﾞ", "十六カード 引落", "ﾐﾂｲｽﾐﾄﾓｶｰﾄﾞ", "ﾗｸﾃﾝｶｰﾄﾞｻｰﾋﾞｽ", "ｾｿﾞﾝ", "ＰａｙＰａｙカード", "ﾋﾞｭｰｶｰﾄﾞ",
                  "AMEX 見本", "ﾆｺｽ", "ｶｰﾄﾞ ｼﾞｪｰｼｰﾋﾞｰ", "DCカード", "イオンカード", "エポスカード"] {
            XCTAssertTrue(KakeiboMerchants.isCardSettlement(t), t)
        }
        for t in ["まちのスーパー", "電気料金", "ドコモ ご利用料金", "イオン 見本店"] {
            XCTAssertFalse(KakeiboMerchants.isCardSettlement(t), t)
        }
        XCTAssertTrue(KakeiboMerchants.isOwnTransfer("振替 積立"))
        XCTAssertTrue(KakeiboMerchants.isOwnTransfer("ﾌﾘｶｴ ﾌﾂｳﾖｷﾝ"))
        XCTAssertTrue(KakeiboMerchants.isOwnTransfer("口座振替 積立"))
        XCTAssertFalse(KakeiboMerchants.isOwnTransfer("口座振替 電気料金"), "口座振替は引落（支出）")
        XCTAssertFalse(KakeiboMerchants.isOwnTransfer("振込 ｶ)ﾐﾎﾝｼﾖｳｼﾞ"))
        XCTAssertNil(KakeiboRules.excludeReason("ｼﾞﾕｳﾛｸｶｰﾄﾞ 年会費", kind: .expense, isCard: true), "カードの明細の行は見ない")
    }

    func testPrepareBankStatement() {
        var s = KakeiboSettings()
        s.employer = "ミホンショウジ"
        let existing = [entry(T.d(2026, 9, 5, 20), 680, memo: "MIHON BAKERY", source: .cardCSV, inst: .jcb)]
        let rows = [
            KakeiboDraft(date: T.d(2026, 9, 6), amount: 680, kind: .expense, text: "MIHON BAKERY"),       // カードの明細と同じ取引（翌日付け）
            KakeiboDraft(date: T.d(2026, 9, 10), amount: 24_600, kind: .expense, text: "ｼﾞﾕｳﾛｸｶｰﾄﾞ"),     // カードの引き落とし
            KakeiboDraft(date: T.d(2026, 9, 15), amount: 210_000, kind: .income, text: "振込 ｶ)ﾐﾎﾝｼﾖｳｼﾞ"),  // 給料
            KakeiboDraft(date: T.d(2026, 9, 20), amount: 20_000, kind: .expense, text: "振替 積立"),      // 自分の口座へ
            KakeiboDraft(date: T.d(2026, 9, 21), amount: 3_280, kind: .expense, text: "ﾏﾁﾉｽｰﾊﾟｰ"),
        ]
        let out = KakeiboImportRules.prepare(rows, existing: existing, settings: s, institution: .juroku, isCard: false, excludeTransfers: true)
        XCTAssertEqual(out.map(\.flag), [.duplicate, .cardSettlement, nil, .ownTransfer, nil])
        XCTAssertEqual(out.map(\.include), [false, false, true, false, true])
        XCTAssertEqual(out[2].category, "給料")
        XCTAssertTrue(out[2].salary)
        XCTAssertEqual(out[4].category, "食費")
        XCTAssertEqual(out[1].flag?.label, "カードの引き落とし（明細で計上）")
        XCTAssertFalse(KakeiboImportRules.missingCardStatement(out, existing: existing), "前のカードの明細がある")
        XCTAssertTrue(KakeiboImportRules.missingCardStatement(out, existing: []), "カードの明細がまだ")

        // 記録にする：重複は入れず、引き落とし・振替は「合計に入れない記録」として残す
        let made = KakeiboImportRules.entries(out, institution: .juroku, source: .bankCSV, batch: "b")
        XCTAssertEqual(made.map(\.memo), ["ｼﾞﾕｳﾛｸｶｰﾄﾞ", "振込 ｶ)ﾐﾎﾝｼﾖｳｼﾞ", "振替 積立", "ﾏﾁﾉｽｰﾊﾟｰ"])
        XCTAssertEqual(made.map(\.isExcluded), [true, false, true, false])
        XCTAssertEqual(made[0].excludeReason, .cardSettlement)
        XCTAssertEqual(made[0].excludeLabel, "カードの引き落とし（明細で計上）")
        XCTAssertEqual(made[2].excludeReason, .ownTransfer)
        XCTAssertTrue(made[1].isSalary)
        let cycle = KakeiboCycle.period(containing: T.d(2026, 9, 15), payday: nil)
        let sum = KakeiboSummary.make(entries: made + existing, cycle: cycle, payday: nil, now: T.now)
        XCTAssertEqual(sum.spent, 3_280 + 680, "引き落とし・振替は数えない")
        XCTAssertEqual(sum.income, 210_000)

        // 外した行をタップで入れ直すと、ふつうの記録になる
        var again = out
        again[1].include = true
        let made2 = KakeiboImportRules.entries(again, institution: .juroku, source: .bankCSV, batch: "b")
        XCTAssertFalse(made2[0].isExcluded)

        // 「合計に入れない」を切ると、引き落とし・振替も入れる
        let off = KakeiboImportRules.prepare(rows, existing: existing, settings: s, institution: .juroku, isCard: false, excludeTransfers: false)
        XCTAssertEqual(off.map(\.include), [false, true, true, true, true])
    }

    func testDuplicatesAcrossSources() {
        let s = KakeiboSettings()
        let jcb = [entry(T.d(2026, 9, 5, 20), 680, memo: "MIHON BAKERY", source: .cardCSV, inst: .jcb)]
        // 同じカードの明細を2回：同じ日は重複、翌日の同じ買い物は別の1件
        let rows = [KakeiboDraft(date: T.d(2026, 9, 5), amount: 680, kind: .expense, text: "MIHON BAKERY"),
                    KakeiboDraft(date: T.d(2026, 9, 6), amount: 680, kind: .expense, text: "MIHON BAKERY")]
        let again = KakeiboImportRules.prepare(rows, existing: jcb, settings: s, institution: .jcb, isCard: true, excludeTransfers: true)
        XCTAssertEqual(again.map(\.flag), [.duplicate, nil])
        // 前の版の Apple Pay の記録と、翌日付けのカードの明細は同じ取引
        let ap = [entry(T.d(2026, 9, 5, 21), 680, memo: "MIHON BAKERY", source: .applePay)]
        XCTAssertTrue(KakeiboDedupe.isDuplicate(date: T.d(2026, 9, 6), amount: 680, kind: .expense, text: "MIHON BAKERY 見本店",
                                                institution: KakeiboInstitution.jcb.rawValue, in: ap))
        XCTAssertFalse(KakeiboDedupe.isDuplicate(date: T.d(2026, 9, 5), amount: 680, kind: .expense, text: "まったく別のお店", in: ap),
                       "同じ日・同じ金額でも、文字が違えば別の支払い")
        XCTAssertFalse(KakeiboDedupe.isDuplicate(date: T.d(2026, 9, 6), amount: 681, kind: .expense, text: "MIHON BAKERY", in: ap))
        XCTAssertFalse(KakeiboDedupe.isDuplicate(date: T.d(2026, 9, 8), amount: 680, kind: .expense, text: "MIHON BAKERY", in: ap), "2日以上ずれたら別")
        // 期間の重なった銀行の明細：手入力の記録とも重ならない
        let manual = [entry(T.d(2026, 9, 10, 12), 1_540, memo: "ドラッグひまわり")]
        XCTAssertTrue(KakeiboDedupe.isDuplicate(date: T.d(2026, 9, 11), amount: 1_540, kind: .expense, text: "ﾄﾞﾗｯｸﾞﾋﾏﾜﾘ",
                                                institution: KakeiboInstitution.juroku.rawValue, in: manual))
        XCTAssertTrue(KakeiboText.similar("ﾏﾁﾉｽｰﾊﾟｰ", "マチノスーパー 本店"))
    }

    func testDemoDataUsesPayCycle() {
        let list = KakeiboDemo.entries(now: T.now)
        XCTAssertFalse(list.contains { $0.date > T.now })
        XCTAssertTrue(list.contains { $0.isSalary }, "見本の給料がある")
        XCTAssertTrue(list.contains { $0.excludeReason == .cardSettlement })
        let cycle = KakeiboCycle.period(containing: T.now, payday: KakeiboDemo.payday)
        let s = KakeiboSummary.make(entries: list, cycle: cycle, payday: KakeiboDemo.payday, now: T.now)
        XCTAssertEqual(s.income, 215_000)
        XCTAssertGreaterThan(s.spent, 0)
        XCTAssertFalse(s.categories.contains { $0.name == "その他" }, "見本は辞書で分類できる")
    }
}
