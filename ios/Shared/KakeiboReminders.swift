import Foundation

// 明細の取り込み忘れを防ぐ：銀行・カードごとに最後に取り込んだ日と、次に取り込むとよい日（期限）。
// - 銀行：給料日の次の日（給料が入り、その周期の口座の明細がそろう）
// - カード：明細の確定日（カードごとに決められる。JCB は 15 日ごろ、MUFG は月初）
// - どちらも、35 日取り込んでいなければ期限
// 期限を過ぎた銀行・カードは、ホームで注意の色と「取り込む」ボタン、ウィジェットに「明細の取り込みがまだです」。
// 通知（アプリだけ）は KakeiboReminderScheduler（App/Kakeibo）が、この期限で予約する。

/// 取り込みのお知らせの設定
struct KakeiboReminderSettings: Codable, Hashable {
    var enabled: Bool = true
    var hour: Int = 20
    var minute: Int = 0
    var cardDays: [String: Int] = [:]       // カードの明細の確定日（KakeiboInstitution.rawValue → 日。なければ既定）

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KakeiboReminderSettings()
        enabled = ((try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil) ?? d.enabled
        hour = ((try? c.decodeIfPresent(Int.self, forKey: .hour)) ?? nil) ?? d.hour
        minute = ((try? c.decodeIfPresent(Int.self, forKey: .minute)) ?? nil) ?? d.minute
        cardDays = ((try? c.decodeIfPresent([String: Int].self, forKey: .cardDays)) ?? nil) ?? d.cardDays
    }

    enum CodingKeys: String, CodingKey {
        case enabled, hour, minute, cardDays
    }

    /// カードの明細の確定日（1〜28）
    func cardDay(_ i: KakeiboInstitution) -> Int {
        let v: Int = cardDays[i.rawValue] ?? KakeiboReminders.defaultCardDay(i)
        return min(28, max(1, v))
    }
}

enum KakeiboReminders {
    static let fallbackDays = 35

    /// 銀行かカードか（MUFG はカードの明細を取り込む）
    static func isCard(_ i: KakeiboInstitution) -> Bool { i == .jcb || i == .mufg }

    /// カードの明細の確定日の既定（JCB 15 日ごろ・MUFG 月初）
    static func defaultCardDay(_ i: KakeiboInstitution) -> Int {
        switch i {
        case .jcb: 15
        case .mufg: 1
        default: 10
        }
    }

    enum Reason: String, Hashable {
        case payday     // 給料日の次の日
        case statement  // カードの明細の確定日
        case fallback   // 35 日取り込んでいない
    }

    struct Due: Hashable, Identifiable {
        var id: String { institution.rawValue }
        var institution: KakeiboInstitution
        var last: Date          // 最後に取り込んだ日
        var due: Date           // 次に取り込むとよい日（日の始まり）
        var reason: Reason
        var fallback: Date      // 35 日めの日

        /// 期限を過ぎたか（期限の日を含む）
        func isOverdue(_ now: Date = .now) -> Bool { Calendar.current.startOfDay(for: now) >= due }

        /// 最後に取り込んでから何日（今日は 0）
        func daysSince(_ now: Date = .now) -> Int {
            let cal = Calendar.current
            return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now)).day ?? 0)
        }
    }

    /// 次に取り込むとよい日
    static func due(_ i: KakeiboInstitution, last: Date, payday: Int?, reminder: KakeiboReminderSettings) -> Due {
        let cal = Calendar.current
        let day: Date = cal.startOfDay(for: last)
        let fallback: Date = cal.date(byAdding: .day, value: fallbackDays, to: day) ?? day
        let primary: Date
        let reason: Reason
        if isCard(i) {
            primary = nextDay(of: reminder.cardDay(i), after: day)
            reason = .statement
        } else {
            // 最後に取り込んだ日か、それより後の最初の給料日の、次の日
            let cycle = KakeiboCycle.period(containing: day, payday: payday)
            let pay: Date = cycle.start >= day ? cycle.start : cycle.end
            primary = cal.date(byAdding: .day, value: 1, to: pay) ?? pay
            reason = .payday
        }
        if fallback < primary {
            return Due(institution: i, last: last, due: fallback, reason: .fallback, fallback: fallback)
        }
        return Due(institution: i, last: last, due: primary, reason: reason, fallback: fallback)
    }

    /// day より後で、日が d の最初の日（その月に d 日がなければ月末）
    static func nextDay(of d: Int, after day: Date) -> Date {
        let cal = Calendar.current
        let start: Date = KakeiboMonth.start(day)
        for offset in 0...2 {
            let m: Date = cal.date(byAdding: .month, value: offset, to: start) ?? start
            let days: Int = cal.range(of: .day, in: .month, for: m)?.count ?? 28
            let c: Date = cal.date(byAdding: .day, value: min(d, days) - 1, to: m) ?? m
            if c > day { return c }
        }
        return cal.date(byAdding: .month, value: 1, to: day) ?? day
    }

    /// 銀行・カードごとの最後の取り込み（覚えた日を使う。覚えていなければ、その明細の記録を入れた日）
    static func lastImports(settings: KakeiboSettings, entries: [KakeiboEntry]) -> [KakeiboInstitution: Date] {
        var out: [KakeiboInstitution: Date] = [:]
        for e in entries where e.source.isFile {
            guard let i = e.institutionValue else { continue }
            if let d = out[i], d >= e.createdAt { continue }
            out[i] = e.createdAt
        }
        for (k, v) in settings.lastImports {
            guard let i = KakeiboInstitution(rawValue: k) else { continue }
            out[i] = v      // 覚えた日を先に使う（前の版の記録だけのときは、記録の入れた日）
        }
        return out
    }

    /// 取り込んだことのある銀行・カードの期限（並びは KakeiboInstitution の順）
    static func dues(settings: KakeiboSettings, entries: [KakeiboEntry]) -> [Due] {
        let last = lastImports(settings: settings, entries: entries)
        return KakeiboInstitution.allCases.compactMap { i in
            last[i].map { due(i, last: $0, payday: settings.payday, reminder: settings.reminder) }
        }
    }

    /// 通知の文
    static func message(_ d: Due) -> (title: String, body: String) {
        let name: String = d.institution.name
        switch d.reason {
        case .payday: return ("\(name)の明細", "給料日のあとです。口座の明細を取り込みましょう")
        case .statement: return ("\(name)の明細", "\(name) の明細が確定するころです。取り込みましょう")
        case .fallback: return ("\(name)の明細", "\(name) の明細を \(fallbackDays) 日取り込んでいません")
        }
    }

    /// 通知を押したときに開く先（hiyori://kakeibo?import=jcb）
    static func link(_ i: KakeiboInstitution) -> URL {
        URL(string: "hiyori://kakeibo?import=\(i.rawValue)") ?? URL(string: "hiyori://kakeibo")!
    }

    /// hiyori://kakeibo?import=jcb から銀行・カードを読む
    static func institution(from url: URL) -> KakeiboInstitution? {
        guard url.scheme?.lowercased() == "hiyori", url.host?.lowercased() == "kakeibo" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first { $0.name == "import" }?.value.flatMap(KakeiboInstitution.init(rawValue:))
    }
}
