import Foundation

/// すばやい追加：「明日15時 買い物」のような日本語から、題名・期限・繰り返しを取り出す
struct QuickParseResult: Equatable {
    var title: String
    var due: Date?
    var allDay: Bool
    var repeatRule: String?

    var hasSchedule: Bool { due != nil || repeatRule != nil }
}

enum QuickParse {
    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> QuickParseResult {
        let cal = calendar
        var text = normalize(input)
        let today = cal.startOfDay(for: now)
        var rule: String?
        var day: Date?
        var hour: Int?
        var minute = 0

        // 繰り返し
        if let g = take(&text, "毎週(月|火|水|木|金|土|日)曜日?") {
            rule = RepeatRule.weekly.rawValue
            day = weekday(g[1], from: today, cal: cal, nextWeek: false)
        } else if take(&text, "毎日") != nil {
            rule = RepeatRule.daily.rawValue
        } else if take(&text, "平日") != nil {
            rule = RepeatRule.weekdays.rawValue
        } else if take(&text, "毎週") != nil {
            rule = RepeatRule.weekly.rawValue
        } else if take(&text, "毎月") != nil {
            rule = RepeatRule.monthly.rawValue
        }

        // 時刻
        if let g = take(&text, "(午前|午後)?(\\d{1,2})時(?!間)(半|(\\d{1,2})分)?") {
            hour = hour24(Int(g[2]) ?? -1, g[1])
            minute = g[3] == "半" ? 30 : (Int(g[4]) ?? 0)
        } else if let g = take(&text, "(午前|午後)?(\\d{1,2}):(\\d{2})") {
            hour = hour24(Int(g[2]) ?? -1, g[1])
            minute = Int(g[3]) ?? 0
        } else if let g = take(&text, "(?:^|(?<=[\\s日曜]))の?(朝|昼|夕方|夜)に?(?=\\s|$)") {
            switch g[1] {
            case "朝": hour = 8
            case "昼": hour = 12
            case "夕方": hour = 17
            default: hour = 20
            }
        }
        if minute < 0 || minute > 59 { minute = 0 }

        // 日付
        if day == nil {
            if let g = take(&text, "(\\d{1,2})月(\\d{1,2})日") {
                day = monthDay(Int(g[1]) ?? 0, Int(g[2]) ?? 0, today: today, cal: cal)
            } else if let g = take(&text, "(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?![\\d/])") {
                day = monthDay(Int(g[1]) ?? 0, Int(g[2]) ?? 0, today: today, cal: cal)
            } else if take(&text, "明後日|あさって") != nil {
                day = cal.date(byAdding: .day, value: 2, to: today)
            } else if take(&text, "明日|あした") != nil {
                day = cal.date(byAdding: .day, value: 1, to: today)
            } else if take(&text, "今日|きょう") != nil {
                day = today
            } else if let g = take(&text, "(来週の?)?(月|火|水|木|金|土|日)曜日?") {
                day = weekday(g[2], from: today, cal: cal, nextWeek: !g[1].isEmpty)
            }
        }

        // 期限を組み立てる
        var due: Date?
        var allDay = false
        if let h = hour {
            var d = cal.date(bySettingHour: h, minute: minute, second: 0, of: day ?? today)
            if day == nil, let x = d, x <= now { d = cal.date(byAdding: .day, value: 1, to: x) }
            due = d
        } else if let d = day {
            due = d
            allDay = true
        } else if let r = rule {
            var d = today
            if r == RepeatRule.weekdays.rawValue {
                var n = 0
                while cal.isDateInWeekend(d) && n < 7 { d = cal.date(byAdding: .day, value: 1, to: d) ?? d; n += 1 }
            }
            due = d
            allDay = true
        }

        // 題名（取り出した語を除く）
        var title = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while title.count > 1, let f = title.first, "にの、,".contains(f) {
            title = String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty { title = input.trimmingCharacters(in: .whitespacesAndNewlines) }
        return QuickParseResult(title: title, due: due, allDay: allDay, repeatRule: rule)
    }

    /// 画面に出す確認の一行（例「明日 15:00・毎週」）。何も読み取れなければ nil
    static func summary(_ r: QuickParseResult, now: Date = .now, calendar: Calendar = .current) -> String? {
        let cal = calendar
        var parts: [String] = []
        if let d = r.due {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
            var s: String
            switch days {
            case 0: s = "今日"
            case 1: s = "明日"
            case 2: s = "明後日"
            default: s = JP.date(d)
            }
            if !r.allDay { s += " " + JP.time(d) }
            parts.append(s)
        }
        if let raw = r.repeatRule, let rule = RepeatRule(rawValue: raw) { parts.append(rule.name) }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

    // MARK: - 部品

    private static func hour24(_ h: Int, _ ampm: String) -> Int? {
        var h = h
        if ampm == "午後" && h < 12 { h += 12 }
        if ampm == "午前" && h == 12 { h = 0 }
        return (0...23).contains(h) ? h : nil
    }

    /// 曜日（"月" など）の次の日。来週なら次の月曜から始まる週の中で選ぶ
    private static func weekday(_ symbol: String, from today: Date, cal: Calendar, nextWeek: Bool) -> Date? {
        guard let ch = symbol.first, let idx = Array("日月火水木金土").firstIndex(of: ch) else { return nil }
        let target = idx + 1 // Calendar の weekday（日曜 = 1）
        let current = cal.component(.weekday, from: today)
        if nextWeek {
            func mon(_ w: Int) -> Int { (w + 5) % 7 } // 月曜 = 0 … 日曜 = 6
            let nextMonday = 7 - mon(current)
            return cal.date(byAdding: .day, value: nextMonday + mon(target), to: today)
        }
        var ahead = (target - current + 7) % 7
        if ahead == 0 { ahead = 7 }
        return cal.date(byAdding: .day, value: ahead, to: today)
    }

    private static func monthDay(_ m: Int, _ d: Int, today: Date, cal: Calendar) -> Date? {
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        let year = cal.component(.year, from: today)
        for y in [year, year + 1] {
            guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)),
                  cal.component(.month, from: date) == m else { return nil }
            if date >= today { return date }
        }
        return nil
    }

    /// 全角の数字・記号を半角に
    private static func normalize(_ s: String) -> String {
        let chars = s.unicodeScalars.map { u -> Character in
            switch u.value {
            case 0xFF10...0xFF1A, 0xFF0F: return Character(UnicodeScalar(u.value - 0xFEE0) ?? u)
            case 0x3000: return " "
            default: return Character(u)
            }
        }
        return String(chars)
    }

    /// 最初に合う部分を取り出して空白に置き換える。返り値は [全体, グループ1, …]（合わないグループは ""）
    private static func take(_ text: inout String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        text = ns.replacingCharacters(in: m.range, with: " ")
        return groups
    }
}
