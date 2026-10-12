import Foundation

/// 画面確認用の見本（起動引数 -demo のときだけ）。お店・金額・口座・会社はすべて架空
enum KakeiboDemo {
    static let payday = 25
    static let employer = "ミホンショウジ"

    static func install(now: Date = .now) {
        KakeiboData.saveEntries(entries(now: now))
        var s = KakeiboSettings()
        s.payday = payday
        s.employer = employer
        let cycle = KakeiboCycle.period(containing: now, payday: payday)
        let prev = KakeiboCycle.period(containing: now, payday: payday, offset: -1)
        // 目標貯金の見本（前の周期から数えて、5か月後の月分までに 30 万円）
        s.savingsGoal = KakeiboSavingsGoal(amount: 300_000, deadline: KakeiboMonth.start(cycle.label, offset: 5), start: prev.start)
        // 最後の取り込みの見本：十六銀行は2日前、JCB は 40 日前（35 日を過ぎて「取り込む」が出る）
        let day: TimeInterval = 86_400
        s.lastImports = [KakeiboInstitution.juroku.rawValue: now.addingTimeInterval(-2 * day),
                         KakeiboInstitution.jcb.rawValue: now.addingTimeInterval(-40 * day)]
        // 覚えた分類の見本
        s.rules = [KakeiboRule(keyword: "ミホンジム", category: "娯楽", learned: true)]
        // 見本の CSV は列の対応を覚えた状態にする（-kakeiboimport mapping のときは覚えていない状態）
        if !ProcessInfo.processInfo.arguments.contains("mapping") {
            s.mappings[KakeiboInstitution.juroku.rawValue] = KakeiboCSV.autoMapping(sampleHeaders)
        }
        KakeiboData.saveSettings(s)
    }

    static func entries(now: Date = .now) -> [KakeiboEntry] {
        let cal = Calendar.current
        let cycle = KakeiboCycle.period(containing: now, payday: payday)
        let prev = KakeiboCycle.period(containing: now, payday: payday, offset: -1)
        let today = cal.startOfDay(for: now)
        /// 今日から days 日前（今の周期の初日より前にはしない）
        func at(_ days: Int, _ h: Int = 12, _ m: Int = 0) -> Date {
            let d: Date = max(cycle.start, cal.date(byAdding: .day, value: -days, to: today) ?? today)
            return cal.date(byAdding: .minute, value: h * 60 + m, to: d) ?? d
        }
        /// 前の周期の初日から day 日後
        func prevDay(_ day: Int) -> Date { cal.date(byAdding: .hour, value: day * 24 + 12, to: prev.start) ?? prev.start }

        let settings: KakeiboSettings = {
            var s = KakeiboSettings()
            s.employer = employer
            return s
        }()
        func e(_ date: Date, _ amount: Int, _ memo: String, _ src: KakeiboSource, _ inst: KakeiboInstitution? = nil,
               kind: KakeiboKind = .expense, excluded: KakeiboExcludeReason? = nil) -> KakeiboEntry {
            let c = KakeiboRules.classify(memo, kind: kind, settings: settings)
            var x = KakeiboEntry(date: date, amount: amount, kind: kind, category: c.category, memo: memo, source: src,
                                 institution: inst?.rawValue,
                                 dedupeKey: KakeiboDedupe.key(date: date, amount: amount, kind: kind, text: memo))
            if c.salary { x.salary = true }
            if let excluded {
                x.excluded = true
                x.excludeReason = excluded
            }
            return x
        }
        let list: [KakeiboEntry] = [
            // 今の周期
            e(cycle.start.addingTimeInterval(9 * 3600), 215_000, "振込 カ)ミホンショウジ", .bankCSV, .juroku, kind: .income),
            e(at(0, 12, 10), 680, "駅前ベーカリー", .cardCSV, .jcb),
            e(at(1, 13), 850, "見本食堂", .manual),
            e(at(1, 19), 3_420, "まちのスーパー", .cardCSV, .jcb),
            e(at(2), 1_980, "ドラッグひまわり", .cardCSV, .jcb),
            e(at(3, 8, 15), 1_320, "ETC 見本インター", .cardCSV, .jcb),
            e(at(3, 18), 4_800, "エネオス 見本SS", .cardCSV, .jcb),
            e(at(4), 1_200, "APPLE COM BILL", .cardCSV, .jcb),
            e(at(5, 18), 2_980, "AMAZON 見本", .cardCSV, .jcb),
            e(at(6), 2_200, "STEAM 見本", .cardCSV, .jcb),
            e(at(7), 6_120, "電気料金", .bankCSV, .juroku),
            e(at(7), 58_000, "家賃 見本ハイツ", .bankCSV, .juroku),
            e(at(8, 20), 2_500, "居酒屋 見本", .manual),
            e(at(9), 3_300, "携帯電話料金", .bankCSV, .juroku),
            e(at(9), 24_600, "ジユウロクカード", .bankCSV, .juroku, excluded: .cardSettlement),
            e(at(9), 20_000, "振替 積立", .bankCSV, .juroku, excluded: .ownTransfer),
            // 前の周期
            e(prev.start.addingTimeInterval(9 * 3600), 210_000, "振込 カ)ミホンショウジ", .bankCSV, .juroku, kind: .income),
            e(prevDay(2), 58_000, "家賃 見本ハイツ", .bankCSV, .juroku),
            e(prevDay(5), 1_540, "ドラッグひまわり", .cardCSV, .jcb),
            e(prevDay(8), 4_210, "まちのスーパー", .cardCSV, .jcb),
            e(prevDay(12), 8_800, "ユニクロ 見本店", .cardCSV, .jcb),
            e(prevDay(15), 5_400, "まちのスーパー", .cardCSV, .jcb),
            e(prevDay(18), 3_300, "携帯電話料金", .bankCSV, .juroku),
            e(prevDay(20), 6_480, "電気料金", .bankCSV, .juroku),
        ]
        return list.filter { $0.date <= now }
    }

    // MARK: 見本の CSV（十六銀行の入出金明細に似せた、架空の明細。取り込みの確認画面の見本）

    static let sampleHeaders = ["日付", "摘要", "お引出し", "お預入れ", "残高"]

    static func sampleCSV(now: Date = .now) -> String {
        let cal = Calendar.current
        let m = KakeiboMonth.start(now, offset: -1)
        let y = cal.component(.year, from: m), mo = cal.component(.month, from: m)
        func d(_ day: Int) -> String { String(format: "%04d/%02d/%02d", y, mo, day) }
        let rows: [(Int, String, Int?, Int?)] = [
            (2, "ﾏﾁﾉｽｰﾊﾟｰ", 3_280, nil),
            (5, "ｼﾞﾕｳﾛｸｶｰﾄﾞ", 12_000, nil),
            (8, "電気料金", 6_540, nil),
            (10, "ドラッグひまわり", 1_540, nil),
            (15, "振込 ｶ)ﾐﾎﾝｼﾖｳｼﾞ", nil, 210_000),
            (18, "携帯電話料金", 3_300, nil),
            (20, "ATM 引出", 10_000, nil),
            (25, "振替 積立", 30_000, nil),
            (28, "市営バス 回数券", 2_000, nil),
        ]
        var balance = 200_000
        var lines = ["十六銀行 入出金明細（見本・架空のデータ）", "口座,普通預金 見本", sampleHeaders.joined(separator: ",")]
        for (day, text, out, inn) in rows {
            balance += (inn ?? 0) - (out ?? 0)
            let o = out.map { "\"\(KakeiboFormat.yen($0))\"" } ?? ""
            let i = inn.map { "\"\(KakeiboFormat.yen($0))\"" } ?? ""
            lines.append("\(d(day)),\(text),\(o),\(i),\"\(KakeiboFormat.yen(balance))\"")
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
