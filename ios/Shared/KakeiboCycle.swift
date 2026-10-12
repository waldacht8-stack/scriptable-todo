import Foundation

// 家計簿の「月」＝給料の周期（給料日から、次の給料日の前の日まで）。
// 給料日が土日・祝日・銀行の休み（12/31〜1/3）に当たると、銀行はその前の営業日に振り込むので、その日を給料日とする。
// 例：給料日 25 日なら 9/25〜10/24 が「10月分」。給料日を決めていなければ、ふつうの暦の月（1日〜月末）。

// MARK: - 祝日（内閣府の決まりを計算で出す。カレンダーの許可は要らない）

enum KakeiboHolidays {
    /// その日が祝日（振替休日・国民の休日を含む）か
    static func isHoliday(_ d: Date, calendar cal: Calendar = .current) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        guard let y = c.year, let m = c.month, let day = c.day else { return false }
        return days(y).contains(m * 100 + day)
    }

    /// 銀行が休みの日か（土日・祝日・12/31〜1/3）
    static func isBankHoliday(_ d: Date, calendar cal: Calendar = .current) -> Bool {
        let wd: Int = cal.component(.weekday, from: d)
        if wd == 1 || wd == 7 { return true }
        let m: Int = cal.component(.month, from: d)
        let day: Int = cal.component(.day, from: d)
        if (m == 12 && day == 31) || (m == 1 && day <= 3) { return true }
        return isHoliday(d, calendar: cal)
    }

    nonisolated(unsafe) private static var cache: [Int: Set<Int>] = [:]
    private static let lock = NSLock()

    /// その年の祝日（月 * 100 + 日）
    static func days(_ y: Int) -> Set<Int> {
        lock.lock()
        defer { lock.unlock() }
        if let c = cache[y] { return c }
        let s = compute(y)
        cache[y] = s
        return s
    }

    /// 曜日（1 日曜 〜 7 土曜）。暦の計算だけで出す（Zeller）
    private static func weekday(_ y: Int, _ m: Int, _ d: Int) -> Int {
        var yy = y, mm = m
        if mm < 3 { mm += 12; yy -= 1 }
        let k = yy % 100, j = yy / 100
        let h = (d + (13 * (mm + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7   // 0 土曜, 1 日曜, …
        return ((h + 6) % 7) + 1
    }

    private static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// 第 n 月曜日
    private static func nthMonday(_ y: Int, _ m: Int, _ n: Int) -> Int {
        let first = weekday(y, m, 1)
        let offset = (2 - first + 7) % 7
        return 1 + offset + (n - 1) * 7
    }

    private static func compute(_ y: Int) -> Set<Int> {
        var s: Set<Int> = [101, 211, 223, 429, 503, 504, 505, 811, 1103, 1123]
        s.insert(100 + nthMonday(y, 1, 2))     // 成人の日
        s.insert(700 + nthMonday(y, 7, 3))     // 海の日
        s.insert(900 + nthMonday(y, 9, 3))     // 敬老の日
        s.insert(1000 + nthMonday(y, 10, 2))   // スポーツの日
        // 春分・秋分（1980〜2099 年の近似式）
        let t = Double(y - 1980)
        let leap = Double((y - 1980) / 4)
        s.insert(300 + Int(20.8431 + 0.242194 * t - leap))
        s.insert(900 + Int(23.2488 + 0.242194 * t - leap))
        // 国民の休日：祝日にはさまれた平日
        for m in 1...12 {
            for d in 2..<daysIn(y, m) where !s.contains(m * 100 + d) {
                if s.contains(m * 100 + d - 1) && s.contains(m * 100 + d + 1) && weekday(y, m, d) != 1 {
                    s.insert(m * 100 + d)
                }
            }
        }
        // 振替休日：日曜の祝日のあと、最初の祝日でない日
        let sundays: [Int] = s.filter { weekday(y, $0 / 100, $0 % 100) == 1 }.sorted()
        for h in sundays {
            var m = h / 100, d = h % 100
            repeat {
                d += 1
                if d > daysIn(y, m) { d = 1; m += 1 }
            } while m <= 12 && s.contains(m * 100 + d)
            if m <= 12 { s.insert(m * 100 + d) }
        }
        return s
    }
}

// MARK: - 給料の周期

enum KakeiboCycle {
    /// 1つの周期。start〜end（end は含まない＝次の給料日）。label はその周期の呼び名の月の1日（「10月分」）
    struct Period: Hashable {
        var start: Date
        var end: Date
        var label: Date
        var usesPayday: Bool

        func contains(_ d: Date) -> Bool { d >= start && d < end }

        /// 最後の日（end の前の日）
        var lastDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end }

        /// 「10月分」（給料日なしは「10月」）
        var title: String {
            let m: Int = Calendar.current.component(.month, from: label)
            return usesPayday ? "\(m)月分" : "\(m)月"
        }

        /// 「2026年10月分」
        var longTitle: String {
            let y: Int = Calendar.current.component(.year, from: label)
            return "\(y)年" + title
        }

        /// 「9/25〜10/24」
        var rangeText: String {
            let cal = Calendar.current
            let a = start, b = lastDay
            return "\(cal.component(.month, from: a))/\(cal.component(.day, from: a))〜\(cal.component(.month, from: b))/\(cal.component(.day, from: b))"
        }

        /// 周期の日数
        var dayCount: Int { max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 30) }
    }

    /// 給料日の日（1〜31。31 は月末）。範囲の外は nil（給料日なし）
    static func validDay(_ payday: Int?) -> Int? {
        guard let p = payday, (1...31).contains(p) else { return nil }
        return p
    }

    private static func monthStart(_ y: Int, _ m: Int) -> Date {
        let cal = Calendar.current
        return cal.date(from: DateComponents(year: y, month: m, day: 1)) ?? .now
    }

    /// その月の、実際に振り込まれる日（休みなら前の営業日）
    static func payDate(year: Int, month: Int, payday: Int) -> Date {
        let cal = Calendar.current
        let first = monthStart(year, month)
        let days: Int = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var d: Date = cal.date(byAdding: .day, value: min(payday, days) - 1, to: first) ?? first
        var guardCount = 0
        while KakeiboHolidays.isBankHoliday(d, calendar: cal) && guardCount < 10 {
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
            guardCount += 1
        }
        return cal.startOfDay(for: d)
    }

    /// 月の番号（年 * 12 + 月 - 1）と年・月の行き来
    private static func index(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: d)
        return (c.year ?? 2000) * 12 + (c.month ?? 1) - 1
    }

    private static func ym(_ i: Int) -> (Int, Int) { (i / 12, i % 12 + 1) }

    private static func payDate(index i: Int, payday: Int) -> Date {
        let (y, m) = ym(i)
        return payDate(year: y, month: m, payday: payday)
    }

    /// 給料日が i 番めの月にある周期（その給料日から次の給料日の前日まで）
    private static func period(startingAt i: Int, payday: Int) -> Period {
        let start = payDate(index: i, payday: payday)
        let end = payDate(index: i + 1, payday: payday)
        // 呼び名：周期の最後の日の月（もとの給料日の前の日の月）。給料日 25 日なら 9/25〜10/24 が「10月分」、1日なら 10/1〜10/31 が「10月分」
        let labelIndex: Int = payday == 1 ? i : i + 1
        let (ly, lm) = ym(labelIndex)
        return Period(start: start, end: end, label: monthStart(ly, lm), usesPayday: true)
    }

    /// d を含む周期。offset で前後の周期へ（-1 は前の周期）
    static func period(containing d: Date, payday: Int?, offset: Int = 0) -> Period {
        let cal = Calendar.current
        guard let p = validDay(payday) else {
            let i = index(d) + offset
            let (y, m) = ym(i)
            let (ny, nm) = ym(i + 1)
            return Period(start: monthStart(y, m), end: monthStart(ny, nm), label: monthStart(y, m), usesPayday: false)
        }
        let day = cal.startOfDay(for: d)
        var i = index(day)
        // 給料日が前の営業日にずれるので、前後の月と比べて決める
        var tries = 0
        while tries < 4 {
            tries += 1
            if day < payDate(index: i, payday: p) { i -= 1; continue }
            if day >= payDate(index: i + 1, payday: p) { i += 1; continue }
            break
        }
        return period(startingAt: i + offset, payday: p)
    }

    /// 呼び名の月（「10月分」の 10 月）の周期
    static func period(label month: Date, payday: Int?) -> Period {
        guard let p = validDay(payday) else { return period(containing: month, payday: nil) }
        let i: Int = index(month) - (p == 1 ? 0 : 1)
        return period(startingAt: i, payday: p)
    }

    /// a の周期から b の周期まで、いくつ進むか（呼び名の月の差）
    static func distance(from a: Period, to b: Period) -> Int {
        index(b.label) - index(a.label)
    }

    /// 次の給料日まであと何日（今日が給料日なら 0）。給料日なしは nil
    static func daysToPayday(now: Date = .now, payday: Int?) -> Int? {
        guard validDay(payday) != nil else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let cur = period(containing: today, payday: payday)
        if cal.isDate(cur.start, inSameDayAs: today) { return 0 }
        return cal.dateComponents([.day], from: today, to: cur.end).day
    }

    /// 次の給料日（今日が給料日なら今日）
    static func nextPayday(now: Date = .now, payday: Int?) -> Date? {
        guard validDay(payday) != nil else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let cur = period(containing: today, payday: payday)
        return cal.isDate(cur.start, inSameDayAs: today) ? cur.start : cur.end
    }
}
