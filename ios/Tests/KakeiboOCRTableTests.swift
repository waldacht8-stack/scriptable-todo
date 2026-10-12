import XCTest
import CoreGraphics
@testable import TodoApp

/// 文字が化けた PDF の見分けと、文字認識の結果を表にする処理。中身はすべて作り物の見本
final class KakeiboOCRTableTests: TokyoTestCase {
    private func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    /// Vision と同じ座標（左下が原点、0〜1）。top は上端
    private func box(_ text: String, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat = 0.012) -> KakeiboOCRBox {
        KakeiboOCRBox(text: text, rect: CGRect(x: x, y: top - h, width: w, height: h))
    }

    // MARK: 化けた文字

    func testGarbledTextIsDetected() {
        XCTAssertTrue(KakeiboPDF.isGarbled("\u{0CE5}\u{0744}\u{0CD4} \u{0501}"))
        // URL だけは正しく出て、ほかは化けている
        let mixed = "https://www.example.jp/ib/meisai\n\u{0CE5} \u{0744}\u{0CD4} \u{0501}\n\u{0CE5}\u{0CD4}\u{0744} \u{0501}\u{05D0}\n1 / 3"
        XCTAssertTrue(KakeiboPDF.isGarbled(mixed))
        // 漢字に化けても「年・月・日・円」が一つも無い
        let kanjiNoise = String(repeating: "\u{4E3F}\u{4E8D}\u{5C6E} ", count: 12)
        XCTAssertTrue(KakeiboPDF.isGarbled(kanjiNoise))
    }

    func testNormalTextIsNotGarbled() {
        XCTAssertFalse(KakeiboPDF.isGarbled("日付 お支払い お預かり お取引内容 差引残高\n2026年 10月5日 1,234円 口座振替 ＪＣＢ 98,766円"))
        XCTAssertFalse(KakeiboPDF.isGarbled("Date Description Amount\n2026/10/05 Coffee 450"))
        XCTAssertFalse(KakeiboPDF.isGarbled(""))
    }

    // MARK: 行にまとめる

    func testLinesGroupByVerticalOverlap() {
        let ls = KakeiboOCRTable.lines([
            box("98,500円", 0.80, 0.794, 0.09),
            box("2026年", 0.06, 0.800, 0.07),
            box("1,500円", 0.22, 0.794, 0.08),
            box("9月25日", 0.06, 0.786, 0.07),
        ])
        XCTAssertEqual(ls.map { $0.map(\.text) }, [["2026年", "1,500円", "98,500円"], ["9月25日"]])
    }

    func testHeaderColumnsAndRoles() throws {
        let cols = try XCTUnwrap(KakeiboOCRTable.headerColumns([
            box("日付", 0.06, 0.85, 0.06),
            box("お支払い お預かり", 0.20, 0.85, 0.26),
            box("お取引内容", 0.52, 0.85, 0.14),
            box("差引残高", 0.80, 0.85, 0.10),
        ]))
        XCTAssertEqual(cols.map(\.role), [.date, .withdrawal, .deposit, .text, .balance])
        XCTAssertEqual(KakeiboOCRTable.role(of: "ご利用金額"), .amount)
        XCTAssertNil(KakeiboOCRTable.role(of: "支払区分"))
        XCTAssertNil(KakeiboOCRTable.headerColumns([box("口座振替 ＪＣＢ", 0.5, 0.7, 0.2)]))
    }

    func testCleanMoney() {
        XCTAssertEqual(KakeiboOCRTable.cleanMoney("12.345 円"), "12,345円")
        XCTAssertEqual(KakeiboAmountParser.parse(KakeiboOCRTable.cleanMoney("1.234.567円")), 1_234_567)
    }

    // MARK: Safari で印刷したウェブの入出金明細（見本）

    private var samplePages: [[KakeiboOCRBox]] {
        let page1: [KakeiboOCRBox] = [
            box("入出金明細照会", 0.05, 0.95, 0.30),
            box("お名前 ミホン タロウ 様", 0.05, 0.92, 0.40),
            box("口座番号 0000000", 0.05, 0.905, 0.30),
            box("照会期間 2026年9月1日～2026年10月9日", 0.05, 0.89, 0.60),
            // 見出し
            box("日付", 0.06, 0.85, 0.06),
            box("お支払い", 0.20, 0.85, 0.10),
            box("お預かり", 0.36, 0.85, 0.10),
            box("お取引内容", 0.52, 0.85, 0.14),
            box("差引残高", 0.80, 0.85, 0.10),
            // 1行目：年の段に金額が並ぶ
            box("2026年", 0.06, 0.800, 0.07),
            box("1,500円", 0.22, 0.794, 0.08),
            box("口座振替 ＪＣＢ", 0.52, 0.794, 0.15),
            box("98,500円", 0.80, 0.794, 0.09),
            box("9月25日", 0.06, 0.786, 0.07),
            // 2行目：月日の段に金額が並ぶ
            box("2026年", 0.06, 0.760, 0.07),
            box("10月1日", 0.06, 0.746, 0.07),
            box("200,000円", 0.37, 0.746, 0.09),
            box("振込 カ）ミホンショウジ", 0.52, 0.746, 0.20),
            box("298,500円", 0.80, 0.746, 0.09),
            // 3行目：年が無い（照会期間の年を使う）
            box("10月7日", 0.06, 0.720, 0.07),
            box("440円", 0.24, 0.720, 0.05),
            box("手数料", 0.52, 0.720, 0.06),
            box("298.060円", 0.80, 0.720, 0.09),     // 文字認識の「,」→「.」
            // 印刷の下の余白
            box("https://example.jp/ib/meisai", 0.05, 0.05, 0.40),
            box("1 / 2 ページ", 0.80, 0.05, 0.12),
        ]
        let page2: [KakeiboOCRBox] = [
            box("2026/10/09 10:00", 0.05, 0.97, 0.20),
            box("入出金明細照会", 0.40, 0.97, 0.20),
            // 4行目：見出しの無いページ。内容が2段に折り返す
            box("2026年", 0.06, 0.900, 0.07),
            box("10月8日", 0.06, 0.886, 0.07),
            box("1,060円", 0.22, 0.886, 0.08),
            box("カード ミホン", 0.52, 0.886, 0.12),
            box("297,000円", 0.80, 0.886, 0.09),
            box("（見本）", 0.52, 0.872, 0.06),
            box("https://example.jp/ib/meisai", 0.05, 0.05, 0.40),
            box("2 / 2 ページ", 0.80, 0.05, 0.12),
        ]
        return [page1, page2]
    }

    func testSafariPrintedStatementRows() throws {
        let ocr = try XCTUnwrap(KakeiboOCRTable.build(pages: samplePages))
        let t = ocr.table
        let m = ocr.mapping
        XCTAssertTrue(t.headerFound)
        XCTAssertEqual(t.headers, ["日付", "お支払い", "お預かり", "お取引内容", "差引残高"])
        XCTAssertEqual(m.date, "日付")
        XCTAssertEqual(m.withdrawal, "お支払い")
        XCTAssertEqual(m.deposit, "お預かり")
        XCTAssertEqual(m.text, "お取引内容")
        XCTAssertEqual(m.balance, "差引残高")
        XCTAssertTrue(m.isUsable)

        // 口座の情報は残さない。年の手がかり（照会期間）は残す
        XCTAssertFalse(t.preamble.contains("ミホン タロウ"))
        XCTAssertFalse(t.preamble.contains("0000000"))
        XCTAssertTrue(t.preamble.contains("照会期間"))
        // 余白（URL・ページ番号・印刷日時）は行にならない
        let all: String = t.rows.flatMap { $0 }.joined(separator: " ")
        XCTAssertFalse(all.contains("example.jp"))
        XCTAssertFalse(all.contains("ページ"))

        let rows = KakeiboCSV.drafts(t, mapping: m, isCard: false, now: T.now)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map { ymd($0.date) }, ["2026-9-25", "2026-10-1", "2026-10-7", "2026-10-8"])
        XCTAssertEqual(rows.map(\.amount), [1_500, 200_000, 440, 1_060])
        XCTAssertEqual(rows.map(\.kind), [.expense, .income, .expense, .expense])
        XCTAssertEqual(rows.map(\.balance), [98_500, 298_500, 298_060, 297_000])
        XCTAssertFalse(rows.contains { $0.suspect }, "残高の検算はすべて合う")
        XCTAssertEqual(rows[0].text, "口座振替 ＪＣＢ")
        XCTAssertEqual(rows[1].text, "振込 カ）ミホンショウジ")
        XCTAssertEqual(rows[2].text, "手数料")
        XCTAssertEqual(rows[3].text, "カード ミホン （見本）")
    }

    func testBalanceMismatchIsMarked() throws {
        var pages = samplePages
        // 3行目の金額を読み違えた
        if let i = pages[0].firstIndex(where: { $0.text == "440円" }) { pages[0][i].text = "740円" }
        let ocr = try XCTUnwrap(KakeiboOCRTable.build(pages: pages))
        let rows = KakeiboCSV.drafts(ocr.table, mapping: ocr.mapping, isCard: false, now: T.now)
        XCTAssertEqual(rows.map(\.suspect), [false, false, true, false])
    }

    func testCardStatementWithoutBalance() throws {
        let page: [KakeiboOCRBox] = [
            box("ご利用日", 0.05, 0.85, 0.10),
            box("ご利用先", 0.25, 0.85, 0.10),
            box("ご利用金額", 0.70, 0.85, 0.12),
            box("2026/09/20", 0.05, 0.80, 0.12),
            box("ミホンストア", 0.25, 0.80, 0.15),
            box("2,980円", 0.72, 0.80, 0.08),
        ]
        let ocr = try XCTUnwrap(KakeiboOCRTable.build(pages: [page]))
        XCTAssertEqual(ocr.mapping.amount, "ご利用金額")
        let rows = KakeiboCSV.drafts(ocr.table, mapping: ocr.mapping, isCard: true, now: T.now)
        XCTAssertEqual(rows.map(\.amount), [2_980])
        XCTAssertEqual(rows.map(\.kind), [.expense])
        XCTAssertEqual(rows.first?.text, "ミホンストア")
    }

    /// 三菱UFJ（MUFG カード）の形：3段の見出し、1文字ずつ空けた「ご 利 用 店 名」、支払回数・摘要の列、宛名の行
    func testCardStatementWithStackedHeader() throws {
        let page: [KakeiboOCRBox] = [
            box("ご利用明細", 0.07, 0.935, 0.10, 0.011),
            // 見出し（3段）
            box("ご 利 用 店 名", 0.20, 0.912, 0.15, 0.007),
            box("支払", 0.455, 0.912, 0.025, 0.007),
            box("何", 0.49, 0.912, 0.012, 0.007),
            box("摘 要", 0.75, 0.912, 0.06, 0.007),
            box("ご利用日", 0.04, 0.905, 0.05, 0.007),
            box("回", 0.49, 0.905, 0.012, 0.007),
            box("ご利用金額(円)", 0.51, 0.905, 0.08, 0.007),
            box("海外ご利用店名／海外都市名", 0.20, 0.898, 0.15, 0.007),
            box("回数", 0.455, 0.898, 0.025, 0.007),
            box("目", 0.49, 0.898, 0.012, 0.007),
            box("現地通貨額", 0.63, 0.898, 0.06, 0.007),
            box("通貨名称", 0.76, 0.898, 0.05, 0.007),
            box("換算レート", 0.87, 0.898, 0.06, 0.007),
            // 宛名の行（取り込まない）
            box("【ミホン 様】", 0.10, 0.881, 0.08, 0.007),
            // 明細：店名が日付の列まで左に広がっている
            box("8/ 7/ 1", 0.04, 0.869, 0.055, 0.007),
            box("ETC ミホン出口", 0.10, 0.869, 0.15, 0.007),
            box("1", 0.468, 0.869, 0.006, 0.007),
            box("700", 0.565, 0.869, 0.025, 0.007),
            box("車種：普通車", 0.595, 0.869, 0.07, 0.007),
            box("8/ 8/12", 0.04, 0.857, 0.055, 0.007),
            box("WL *SAMPLE PURCHASE", 0.10, 0.857, 0.20, 0.007),
            box("1", 0.468, 0.857, 0.006, 0.007),
            box("3,400", 0.555, 0.857, 0.035, 0.007),
            box("3400.00 エン", 0.63, 0.857, 0.10, 0.007),
            box("1.000", 0.87, 0.857, 0.04, 0.007),
        ]
        let ocr = try XCTUnwrap(KakeiboOCRTable.build(pages: [page]))
        XCTAssertTrue(ocr.table.headerFound)
        XCTAssertEqual(ocr.mapping.date, "ご利用日")
        XCTAssertEqual(ocr.mapping.text, "ご利用店名")
        XCTAssertEqual(ocr.mapping.amount, "ご利用金額(円)")
        XCTAssertNil(ocr.mapping.withdrawal, "支払回数はお支払いの金額ではない")
        XCTAssertTrue(ocr.mapping.isUsable)
        let all: String = ocr.table.rows.flatMap { $0 }.joined(separator: " ")
        XCTAssertFalse(all.contains("ミホン 様"), "宛名は行にならない")

        let rows = KakeiboCSV.drafts(ocr.table, mapping: ocr.mapping, isCard: false, now: T.now)
        XCTAssertEqual(rows.map { ymd($0.date) }, ["2026-7-1", "2026-8-12"])
        XCTAssertEqual(rows.map(\.amount), [700, 3_400])
        XCTAssertEqual(rows.map(\.kind), [.expense, .expense])
        XCTAssertEqual(rows.map(\.text), ["ETC ミホン出口", "WL *SAMPLE PURCHASE"])
    }

    func testNoHeaderFallsBackToNumberedColumns() throws {
        let page: [KakeiboOCRBox] = [
            box("2026/09/20", 0.05, 0.80, 0.12),
            box("ミホンストア", 0.25, 0.80, 0.15),
            box("2,980", 0.72, 0.80, 0.08),
        ]
        let ocr = try XCTUnwrap(KakeiboOCRTable.build(pages: [page]))
        XCTAssertFalse(ocr.table.headerFound)
        XCTAssertEqual(ocr.table.headers, ["列1", "列2", "列3"])
        XCTAssertFalse(ocr.mapping.isUsable)
    }
}
