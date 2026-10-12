import Foundation

/// 画面確認用の見本（起動引数 -demo のときだけ）。お店・金額・口座はすべて架空
enum KakeiboDemo {
    static func install(now: Date = .now) {
        KakeiboData.saveEntries(entries(now: now))
        var s = KakeiboSettings()
        s.budget = 50_000
        // 目標貯金の見本（先月から数えて、半年後の月までに 30 万円）
        s.savingsGoal = KakeiboSavingsGoal(amount: 300_000, deadline: KakeiboMonth.start(now, offset: 5), start: KakeiboMonth.start(now, offset: -1))
        // 見本の CSV は列の対応を覚えた状態にする（-kakeiboimport mapping のときは覚えていない状態）
        if !ProcessInfo.processInfo.arguments.contains("mapping") {
            s.mappings[KakeiboInstitution.juroku.rawValue] = KakeiboCSV.autoMapping(sampleHeaders)
        }
        KakeiboData.saveSettings(s)
    }

    static func entries(now: Date = .now) -> [KakeiboEntry] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ days: Int, _ h: Int = 12, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: h * 60 + m, to: cal.date(byAdding: .day, value: -days, to: today)!)!
        }
        let lastMonth = KakeiboMonth.start(now, offset: -1)
        func prev(_ day: Int) -> Date { cal.date(byAdding: .hour, value: (day - 1) * 24 + 12, to: lastMonth)! }

        func e(_ date: Date, _ amount: Int, _ cat: String, _ memo: String, _ src: KakeiboSource,
               _ inst: KakeiboInstitution? = nil, kind: KakeiboKind = .expense, card: String? = nil, pending: Bool = false) -> KakeiboEntry {
            var x = KakeiboEntry(date: date, amount: amount, kind: kind, category: cat, memo: memo, source: src,
                                 institution: inst?.rawValue, card: card,
                                 dedupeKey: KakeiboDedupe.key(date: date, amount: amount, kind: kind, text: memo))
            if pending { x.needsAmount = true }
            return x
        }
        return [
            e(at(0, 12, 10), 680, "食費", "駅前ベーカリー", .applePay, card: "見本のカード"),
            e(at(0, 8, 40), 0, "食費", "コーヒースタンド", .applePay, card: "見本のカード", pending: true),
            e(at(1, 13), 850, "食費", "お昼ごはん", .manual),
            e(at(1, 19), 3_420, "食費", "まちのスーパー", .cardCSV, .jcb),
            e(at(2), 1_980, "日用品", "ドラッグひまわり", .bankCSV, .juroku),
            e(at(3, 8, 15), 230, "交通", "市営バス", .applePay, card: "見本のカード"),
            e(at(4), 990, "サブスク", "動画サブスク", .cardCSV, .jcb),
            e(at(5, 18), 1_800, "娯楽", "映画館", .manual),
            e(at(6), 2_200, "ゲーム", "ゲームストア", .cardCSV, .jcb),
            e(at(7), 6_120, "光熱", "電気料金", .bankCSV, .juroku),
            e(at(8, 20), 2_500, "交際", "ランチ会", .manual),
            e(at(9), 3_300, "通信", "携帯電話料金", .bankCSV, .mufg),
            // 先月
            e(prev(10), 1_540, "日用品", "ドラッグひまわり", .bankCSV, .juroku),
            e(prev(12), 4_210, "食費", "まちのスーパー", .cardCSV, .jcb),
            e(prev(15), 210_000, "収入", "給与", .bankCSV, .juroku, kind: .income),
            e(prev(20), 8_800, "服", "洋服のお店", .cardCSV, .jcb),
            e(prev(22), 5_400, "食費", "まちのスーパー", .cardCSV, .jcb),
        ]
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
            (5, "ｶｰﾄﾞ ｼﾞｪｰｼｰﾋﾞｰ", 12_000, nil),
            (8, "電気料金", 6_540, nil),
            (10, "ドラッグひまわり", 1_540, nil),
            (15, "振込 キュウヨ", nil, 210_000),
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
