import XCTest
@testable import TodoApp

/// 家計簿の明細の読み取り（CSV・PDF の文字）。中身はすべて作り物の見本
final class KakeiboParserTests: TokyoTestCase {
    private func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    // MARK: 文字コード

    func testDecodeUTF8WithBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("日付,摘要\n".utf8)
        XCTAssertEqual(KakeiboCSV.decode(data), "日付,摘要\n")
    }

    func testDecodeShiftJIS() throws {
        let text = "日付,摘要,お引出し,お預入れ,残高\r\n2026/09/02,ﾏﾁﾉｽｰﾊﾟｰ,\"1,234\",,\"98,766\"\r\n"
        let data = try XCTUnwrap(text.data(using: .shiftJIS))
        XCTAssertNil(String(data: data, encoding: .utf8), "Shift_JIS は UTF-8 としては読めない")
        let decoded = try XCTUnwrap(KakeiboCSV.decode(data))
        XCTAssertTrue(decoded.hasPrefix("日付,摘要"))
        let t = try XCTUnwrap(KakeiboCSV.table(decoded))
        XCTAssertEqual(t.headers, ["日付", "摘要", "お引出し", "お預入れ", "残高"])
        let rows = KakeiboCSV.drafts(t, mapping: KakeiboCSV.autoMapping(t.headers), isCard: false, now: T.now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].amount, 1234)
        XCTAssertEqual(rows[0].kind, .expense)
        XCTAssertEqual(rows[0].text, "ﾏﾁﾉｽｰﾊﾟｰ")
    }

    // MARK: CSV の行と列

    func testQuotedFieldsAndCRLF() {
        let rows = KakeiboCSV.rows("a,\"b,c\",\"say \"\"hi\"\"\"\r\n\r\n1,2,3")
        XCTAssertEqual(rows, [["a", "b,c", "say \"hi\""], ["1", "2", "3"]])
    }

    func testHeaderAfterPreambleAndBankColumns() throws {
        let csv = """
        見本銀行 入出金明細
        口座,普通 見本
        日付,摘要,お引出し,お預入れ,残高
        2026/09/01,振込 キュウヨ,,"200,000","300,000"
        2026/09/03,ﾏﾁﾉｽｰﾊﾟｰ,"3,280",,"296,720"
        2026/09/05,ｶｰﾄﾞ ｼﾞｪｰｼｰﾋﾞｰ,"12,000",,"284,720"
        """
        let t = try XCTUnwrap(KakeiboCSV.table(csv))
        XCTAssertTrue(t.headerFound)
        XCTAssertTrue(t.preamble.contains("見本銀行"))
        let m = KakeiboCSV.autoMapping(t.headers)
        XCTAssertEqual(m.date, "日付")
        XCTAssertEqual(m.text, "摘要")
        XCTAssertEqual(m.withdrawal, "お引出し")
        XCTAssertEqual(m.deposit, "お預入れ")
        XCTAssertEqual(m.balance, "残高")
        let rows = KakeiboCSV.drafts(t, mapping: m, isCard: false, now: T.now)
        XCTAssertEqual(rows.map(\.amount), [200_000, 3_280, 12_000])
        XCTAssertEqual(rows.map(\.kind), [.income, .expense, .expense])
        XCTAssertFalse(rows.contains { $0.suspect }, "残高の検算はすべて合う")
        XCTAssertTrue(KakeiboText.isTransferLike(rows[2].text))
        XCTAssertTrue(KakeiboText.isJCBWithdrawal(rows[2].text))
        XCTAssertFalse(KakeiboText.isTransferLike(rows[1].text))
    }

    func testBalanceMismatchIsMarked() throws {
        let csv = """
        日付,摘要,出金,入金,残高
        2026-09-01,A,1000,,9000
        2026-09-02,B,500,,8000
        2026-09-03,C,2000,,6000
        """
        let t = try XCTUnwrap(KakeiboCSV.table(csv))
        let rows = KakeiboCSV.drafts(t, mapping: KakeiboCSV.autoMapping(t.headers), isCard: false, now: T.now)
        XCTAssertEqual(rows.map(\.suspect), [false, true, false], "9000−500 は 8000 にならない")
    }

    func testNewestFirstBalanceOrder() throws {
        let csv = """
        日付,摘要,出金,入金,残高
        2026/09/03,C,2000,,6000
        2026/09/02,B,1000,,8000
        2026/09/01,A,1000,,9000
        """
        let t = try XCTUnwrap(KakeiboCSV.table(csv))
        let rows = KakeiboCSV.drafts(t, mapping: KakeiboCSV.autoMapping(t.headers), isCard: false, now: T.now)
        XCTAssertFalse(rows.contains { $0.suspect }, "新しい順の明細でも検算が合う")
    }

    func testCardCSVHeaderVariant() throws {
        // カードの明細に似せた見出し（利用日・ご利用先・ご利用金額）。プラスが支出、マイナスは返金
        let csv = """
        見本カード ご利用明細
        ご利用者,ご利用日,ご利用先,ご利用金額,支払区分,今回回数
        本人,26/09/10,ﾐﾎﾝﾍﾞｰｶﾘｰ,"1,200",1回,1
        本人,2026/9/12,見本書店,-800,1回,1
        """
        let t = try XCTUnwrap(KakeiboCSV.table(csv))
        let m = KakeiboCSV.autoMapping(t.headers)
        XCTAssertEqual(m.date, "ご利用日")
        XCTAssertEqual(m.text, "ご利用先")
        XCTAssertEqual(m.amount, "ご利用金額")
        let rows = KakeiboCSV.drafts(t, mapping: m, isCard: true, now: T.now)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(ymd(rows[0].date), "2026-9-10")
        XCTAssertEqual(rows[0].kind, .expense)
        XCTAssertEqual(rows[1].kind, .income)
        XCTAssertEqual(rows[1].amount, 800)
    }

    func testSignedAmountColumn() throws {
        let csv = "日付,内容,金額\n2026-09-01,見本スーパー,-1500\n2026-09-02,見本の入金,3000\n"
        let t = try XCTUnwrap(KakeiboCSV.table(csv))
        let rows = KakeiboCSV.drafts(t, mapping: KakeiboCSV.autoMapping(t.headers), isCard: false, now: T.now)
        XCTAssertEqual(rows.map(\.kind), [.expense, .income])
        XCTAssertEqual(rows.map(\.amount), [1500, 3000])
    }

    func testHeaderlessCSVNeedsMapping() throws {
        let t = try XCTUnwrap(KakeiboCSV.table("2026/09/01,見本,500\n2026/09/02,見本2,600\n"))
        XCTAssertFalse(t.headerFound)
        XCTAssertEqual(t.headers, ["列1", "列2", "列3"])
        var m = KakeiboColumnMapping()
        XCTAssertFalse(m.isUsable)
        m.date = "列1"; m.text = "列2"; m.withdrawal = "列3"
        XCTAssertTrue(m.fits(t.headers))
        XCTAssertEqual(KakeiboCSV.drafts(t, mapping: m, isCard: false, now: T.now).count, 2)
    }

    // MARK: 日付・金額

    func testDateFormats() {
        let cases: [(String, String)] = [
            ("2026/09/28", "2026-9-28"), ("2026-9-8", "2026-9-8"), ("2026年9月28日", "2026-9-28"),
            ("20260928", "2026-9-28"), ("R8.9.28", "2026-9-28"), ("令和8年9月28日", "2026-9-28"),
            ("26/09/28", "2026-9-28"), ("08.09.28", "2026-9-28"),
        ]
        for (raw, want) in cases {
            guard let d = KakeiboDateParser.parse(raw, now: T.now) else { XCTFail("読めない: \(raw)"); continue }
            XCTAssertEqual(ymd(d), want, raw)
        }
        XCTAssertNil(KakeiboDateParser.parse("2026/13/01", now: T.now))
        XCTAssertNil(KakeiboDateParser.parse("摘要", now: T.now))
    }

    func testMonthDayUsesHintOrPreviousYear() {
        XCTAssertEqual(ymd(KakeiboDateParser.parse("9/28", defaultYear: 2025, now: T.now)!), "2025-9-28")
        XCTAssertEqual(ymd(KakeiboDateParser.parse("9/28", now: T.now)!), "2026-9-28")
        XCTAssertEqual(ymd(KakeiboDateParser.parse("12/24", now: T.now)!), "2025-12-24", "先の日付なら前の年")
    }

    func testAmounts() {
        XCTAssertEqual(KakeiboAmountParser.parse("1,234"), 1234)
        XCTAssertEqual(KakeiboAmountParser.parse("¥1,234"), 1234)
        XCTAssertEqual(KakeiboAmountParser.parse("１，２３４円"), 1234)
        XCTAssertEqual(KakeiboAmountParser.parse("-500"), -500)
        XCTAssertEqual(KakeiboAmountParser.parse("▲500"), -500)
        XCTAssertEqual(KakeiboAmountParser.parse("(500)"), -500)
        XCTAssertEqual(KakeiboAmountParser.parse("1200.00"), 1200)
        XCTAssertNil(KakeiboAmountParser.parse(""))
        XCTAssertNil(KakeiboAmountParser.parse("—"))
        XCTAssertNil(KakeiboAmountParser.parse("1回"))
    }

    // MARK: PDF の文字

    func testPDFTextWithBalance() {
        let text = """
        見本銀行 入出金明細 2026年9月
        お取引日 摘要 お引出し お預入れ 残高
        9/01 繰越 100,000
        9/03 ミホンスーパー 1,234 98,766
        9/10 振込 キュウヨ 50,000 148,766
        9/15 カード ジェーシービー 8,000 140,766
        9/20 ミホン薬局 2,000 138,000
        ページ 1/1
        """
        let r = KakeiboPDF.drafts(text: text, isCard: false, now: T.now)
        XCTAssertTrue(r.hasBalance)
        let rows = r.rows
        XCTAssertEqual(rows.map(\.amount), [1_234, 50_000, 8_000, 2_000], "繰越（数字が1つで残高だけ）の行は金額として読まない")
        XCTAssertEqual(rows.map(\.kind), [.expense, .income, .expense, .expense])
        XCTAssertEqual(rows[0].text, "ミホンスーパー")
        XCTAssertEqual(ymd(rows[0].date), "2026-9-3")
        XCTAssertEqual(rows.map(\.suspect), [false, false, false, true], "140,766−2,000 は 138,000 にならない")
    }

    func testPDFAmountOnNextLine() {
        let text = """
        日付 摘要 金額 残高
        2026/09/03 ミホン商店
        500 9,500
        2026/09/04 ミホン食堂 700 8,800
        """
        let rows = KakeiboPDF.drafts(text: text, isCard: false, now: T.now).rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].amount, 500)
        XCTAssertEqual(rows[0].balance, 9_500)
        XCTAssertEqual(rows[1].kind, .expense)
    }

    func testPDFCardStatement() {
        let text = """
        ご利用日 ご利用先 ご利用金額 支払区分
        26/09/05 ミホンベーカリー 680 1回 680
        26/09/07 ミホン映画館 1,800 1回 1,800
        """
        let rows = KakeiboPDF.drafts(text: text, isCard: true, now: T.now).rows
        XCTAssertEqual(rows.map(\.amount), [680, 1_800])
        XCTAssertEqual(rows.map(\.text), ["ミホンベーカリー", "ミホン映画館"])
    }

    /// 三菱UFJ（MUFG カード）の形：「8/ 7/ 1」の日付（令和の年）、店名と金額の間に支払回数、金額のあとに摘要
    func testPDFCardStatementWithEraDateAndPayCount() {
        XCTAssertEqual(ymd(KakeiboDateParser.parse("8/ 7/ 1", now: T.now)!), "2026-7-1")
        XCTAssertEqual(ymd(KakeiboDateParser.parse("8/ 8/12", now: T.now)!), "2026-8-12")
        let text = """
        ご利用日 ご 利 用 店 名 支払 何 ご利用金額(円) 摘 要
        8/ 7/ 1 ETC ミホン出口 1 700 車種:普通車
        8/ 8/12 WL *SAMPLE PURCHASE 1 3,400 3400.00 エン 1.000
        """
        // 口座（カードでない）を選んでいても、見出しからカードの明細と分かる
        let rows = KakeiboPDF.drafts(text: text, isCard: false, now: T.now).rows
        XCTAssertEqual(rows.map { ymd($0.date) }, ["2026-7-1", "2026-8-12"])
        XCTAssertEqual(rows.map(\.amount), [700, 3_400])
        XCTAssertEqual(rows.map(\.kind), [.expense, .expense])
        XCTAssertEqual(rows.map(\.text), ["ETC ミホン出口", "WL *SAMPLE PURCHASE"])
    }

    func testDemoSampleCSVParses() throws {
        let t = try XCTUnwrap(KakeiboCSV.table(KakeiboDemo.sampleCSV(now: T.now)))
        XCTAssertEqual(t.headers, KakeiboDemo.sampleHeaders)
        let rows = KakeiboCSV.drafts(t, mapping: KakeiboCSV.autoMapping(t.headers), isCard: false, now: T.now)
        XCTAssertEqual(rows.count, 9)
        XCTAssertFalse(rows.contains { $0.suspect })
        XCTAssertEqual(KakeiboDetect.institution(t.preamble), .juroku)
    }
}
