import Foundation

// MARK: - 第五人格：メンテナンス・アップデートの予定、コラボ・ガチャ、ランクマッチのシーズン
// 読むもの：
// - 公式サイトのアップデート情報の一覧（identityvgame.com/jp/news/update/）。毎週の「ゲームアップデートのお知らせ」が並ぶ
//   題名に「（09/30 AM 9：00実施）」のように日時があり、本文には所要時間・新シーズンの開始・シーズンラストスパートの期間がある
// - PR TIMES の説明文（RDF の description。120字ほどで切れている）
// - 本文が要るものだけ記事の HTML を読む（1回の更新で最大5件。読んだものは idv-articles.json に残し、二度読まない）
// シーズンは公式の文だけから決める（推定はしない）。見つからなければ「見つかりませんでした」と出し、手動の日付で上書きできる

// MARK: 予定

struct IdvScheduleItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case maintenance, update
        var label: String { self == .maintenance ? "メンテナンス" : "アップデート" }
    }

    var id: String
    var kind: Kind
    var title: String
    var start: Date
    var end: Date?
    var hasTime: Bool
    var link: String?

    /// 終わったか（時刻がなければその日の終わりまでは「これから」）
    func isPast(now: Date = .now) -> Bool {
        if let end { return end < now }
        if hasTime { return start.addingTimeInterval(3600) < now }
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: start)) ?? start
        return dayEnd <= now
    }
}

enum IdvSchedule {
    static let keywords = ["メンテナンス", "メンテ", "アップデート", "更新", "バージョン"]

    static func isSchedule(_ text: String) -> Bool { keywords.contains { text.contains($0) } }

    static func kind(_ text: String) -> IdvScheduleItem.Kind { text.contains("メンテ") ? .maintenance : .update }

    struct When: Equatable {
        var start: Date
        var end: Date?
        var hasTime: Bool
    }

    private static func regex(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }
    private static let dateRE = regex("(?:(\\d{4})[年/\\-])?(?<!\\d)(\\d{1,2})(?:月|/|-)(\\d{1,2})(?!\\d)日?")
    private static let timeRE = regex("^\\s*(?:[（(][^）)\\d]{1,4}[）)])?\\s*(?:(AM|PM|am|pm|午前|午後)\\s*)?(\\d{1,2})(?::(\\d{2})|時(?:(\\d{1,2})分)?)")
    private static let zoneRE = regex("^\\s*[（(]UTC\\s*\\+\\s*(\\d{1,2})[）)]")
    private static let endRE = regex("^[^。\\n～〜~－–—]{0,6}?[～〜~－–—]\\s*(?:(?:(\\d{4})年)?(\\d{1,2})月(\\d{1,2})日(?:[（(][^）)]{1,4}[）)])?\\s*)?(\\d{1,2})(?::(\\d{2})|時(?:(\\d{1,2})分)?)")
    private static let durationRE = regex("所要時間は?(?:約)?(\\d{1,4})(分|時間)")

    /// 文から日時を探す。時刻のある日付を優先し、無ければ最初の日付（終日）
    /// 例：「（09/30 AM 9：00実施）」「2026年9月10日8:00（UTC+8）…所要時間は240分」「10月15日（木）11:00～15:00」
    static func when(in raw: String, reference: Date) -> When? {
        let t = IdvDates.normalize(raw)
        let ns = t as NSString
        guard let dateRE else { return nil }
        let matches = dateRE.matches(in: t, range: NSRange(location: 0, length: ns.length))
        var firstDay: Date?
        for m in matches {
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            guard let day = IdvDates.day(Int(g(1)), Int(g(2)) ?? 0, Int(g(3)) ?? 0, reference: reference) else { continue }
            if firstDay == nil { firstDay = day }
            let after = m.range.location + m.range.length
            let rest = ns.substring(from: after)
            guard let tm = firstMatch(timeRE, rest) else { continue }
            let rns = rest as NSString
            func tg(_ i: Int) -> String { tm.range(at: i).location == NSNotFound ? "" : rns.substring(with: tm.range(at: i)) }
            var hour = Int(tg(2)) ?? 0
            let minute = Int(tg(3)) ?? Int(tg(4)) ?? 0
            let ampm = tg(1).lowercased()
            if (ampm == "pm" || ampm == "午後") && hour < 12 { hour += 12 }
            guard (0...24).contains(hour), (0...59).contains(minute) else { continue }
            var tail = rns.substring(from: tm.range.location + tm.range.length)
            var offset: Int? = nil
            if let z = firstMatch(zoneRE, tail) {
                let tns = tail as NSString
                offset = Int(tns.substring(with: z.range(at: 1)))
                tail = tns.substring(from: z.range.location + z.range.length)
            }
            guard let start = at(day, hour, minute, utcOffset: offset) else { continue }
            var end: Date? = nil
            if let e = firstMatch(endRE, tail) {
                let tns = tail as NSString
                func eg(_ i: Int) -> String { e.range(at: i).location == NSNotFound ? "" : tns.substring(with: e.range(at: i)) }
                var endDay = day
                if !eg(2).isEmpty, let d = IdvDates.day(Int(eg(1)), Int(eg(2)) ?? 0, Int(eg(3)) ?? 0, reference: reference) { endDay = d }
                let eh = Int(eg(4)) ?? 0, em = Int(eg(5)) ?? Int(eg(6)) ?? 0
                if (0...24).contains(eh), (0...59).contains(em), let e = at(endDay, eh, em, utcOffset: offset), e > start { end = e }
            }
            if end == nil, let d = firstMatch(durationRE, t) {
                let n = Double(ns.substring(with: d.range(at: 1))) ?? 0
                let unit = ns.substring(with: d.range(at: 2))
                if n > 0 { end = start.addingTimeInterval(n * (unit == "分" ? 60 : 3600)) }
            }
            return When(start: start, end: end, hasTime: true)
        }
        return firstDay.map { When(start: $0, end: nil, hasTime: false) }
    }

    private static func firstMatch(_ re: NSRegularExpression?, _ s: String) -> NSTextCheckingResult? {
        guard let re else { return nil }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    /// その日（端末の時間帯で決めた年月日）の時刻。utcOffset があれば、その時間帯の時刻として読む
    static func at(_ day: Date, _ hour: Int, _ minute: Int, utcOffset: Int?) -> Date? {
        let cal = Calendar.current
        let ymd = cal.dateComponents([.year, .month, .day], from: day)
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utcOffset.flatMap { TimeZone(secondsFromGMT: $0 * 3600) } ?? cal.timeZone
        return c.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: hour, minute: minute))
    }

    /// 公式の題名の頭の「2026-09-30 」は表示では外す
    static func displayTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "^\\d{4}-\\d{2}-\\d{2}\\s*", with: "", options: .regularExpression)
    }

    /// お知らせ（と読んだ本文）から予定を作る。30日より前のものは出さない
    static func items(news: [IdvNews], articles: [String: String], now: Date = .now) -> [IdvScheduleItem] {
        var out: [IdvScheduleItem] = []
        var seen = Set<String>()
        for n in news {
            let base = n.title + "\n" + (n.summary ?? "")
            guard isSchedule(base) else { continue }
            let article = articles[n.link]
            let text = base + "\n" + (article ?? "")
            guard let w = when(in: text, reference: n.date ?? now) else { continue }
            guard w.start > now.addingTimeInterval(-30 * 86400) else { continue }
            let k: IdvScheduleItem.Kind
            if n.kind == .official {
                k = (article ?? "").contains("メンテナンス") || n.title.contains("メンテ") ? .maintenance : .update
            } else {
                k = kind(base)
            }
            let id = "\(Int(w.start.timeIntervalSince1970))-\(n.link)"
            guard seen.insert(id).inserted else { continue }
            out.append(IdvScheduleItem(id: id, kind: k, title: displayTitle(n.title), start: w.start, end: w.end,
                                       hasTime: w.hasTime, link: n.link))
        }
        return sorted(out, now: now)
    }

    /// これからのものを近い順に、そのあと終わったものを新しい順に
    static func sorted(_ items: [IdvScheduleItem], now: Date = .now) -> [IdvScheduleItem] {
        let upcoming = items.filter { !$0.isPast(now: now) }.sorted { $0.start < $1.start }
        let past = items.filter { $0.isPast(now: now) }.sorted { $0.start > $1.start }
        return upcoming + past
    }

    /// 「9月30日（水） 09:00〜13:00」
    static func label(_ s: IdvScheduleItem) -> String {
        var out = JP.date(s.start)
        guard s.hasTime else { return out }
        out += " " + JP.time(s.start)
        if let e = s.end {
            let sameDay = Calendar.current.isDate(e, inSameDayAs: s.start)
            out += "〜" + (sameDay ? JP.time(e) : "\(JP.shortDate(e)) \(JP.time(e))")
        }
        return out
    }
}

// MARK: - コラボ・ガチャ

enum IdvCollab {
    static let gachaWords = ["ガチャ", "限定", "復刻", "推理の径", "真髄"]

    /// 題名から「コラボ」「ガチャ」のどちらか
    static func tag(_ title: String) -> String? {
        if title.contains("コラボ") { return "コラボ" }
        if gachaWords.contains(where: { title.contains($0) }) { return "ガチャ" }
        return nil
    }

    /// 本文から期間を探すときは「期間」より後ろを見る（本文の頭の日付は発表日のことが多い）
    static func periodRange(in text: String, reference: Date) -> IdvDates.Range? {
        if let r = text.range(of: "期間"), let found = IdvDates.range(in: String(text[r.lowerBound...]), reference: reference) {
            return found
        }
        return IdvDates.range(in: text, reference: reference)
    }

    /// 「開始まであと◯日」「終了まであと◯日」
    static func label(start: Date?, end: Date, now: Date = .now) -> String {
        if let s = start {
            let n = IdvDates.daysLeft(s, now: now)
            if n > 0 { return "開始まであと\(n)日" }
        }
        let n = IdvDates.daysLeft(end, now: now)
        if n < 0 { return "終了" }
        if n == 0 { return "今日で終了" }
        return "終了まであと\(n)日"
    }
}

// MARK: - ランクマッチのシーズン

struct IdvSeason: Codable, Equatable {
    var number: Int?
    var name: String
    var start: Date?
    var end: Date?
    var source: String
    var link: String?

    var title: String { number.map { "シーズン\($0)" } ?? name }

    /// 始まりから終わりまでのどこにいるか（0〜1。どちらかが無ければ nil）
    func progress(now: Date = .now) -> Double? {
        guard let s = start, let e = end, e > s else { return nil }
        return min(1, max(0, now.timeIntervalSince(s) / e.timeIntervalSince(s)))
    }
}

/// 手動の上書き（「日付がずれているとき」）
struct IdvSeasonOverride: Codable, Equatable {
    var enabled = false
    var name = ""
    var start = Date.now
    var end = Date.now.addingTimeInterval(86400 * 60)

    var season: IdvSeason? {
        guard enabled, end > start else { return nil }
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return IdvSeason(number: IdvSeasonParser.number(in: t), name: t.isEmpty ? "今シーズン" : t,
                         start: start, end: end, source: "手動で入れた日付", link: nil)
    }
}

enum IdvSeasonParser {
    private static func ints(_ pattern: String, _ text: String) -> [Int] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            Int(ns.substring(with: m.range(at: 1)))
        }
    }

    /// 「S44・真髄2」「シーズン44」「第44シーズン」の番号（S0 のような1桁は暗喩などなので数えない）
    static func number(in title: String) -> Int? {
        let t = IdvDates.normalize(title)
        let found = ints("(?<![A-Za-z0-9])S(\\d{2,3})(?!\\d)", t) + ints("シーズン\\s*(\\d{1,3})(?!\\d)", t) + ints("第(\\d{1,3})シーズン", t)
        return found.max()
    }

    /// 公式のアップデートのお知らせ：「今週のメンテナンス後に、S43が終了し、S44が始まります」
    static func started(in text: String) -> Int? {
        let t = IdvDates.normalize(text)
        if let n = ints("S\\d{2,3}が終了し、?\\s*S(\\d{2,3})が(?:始まり|開始|開幕|スタート)", t).max() { return n }
        return ints("S(\\d{2,3})が(?:始まります|開幕します|開始します|スタートします)", t).max()
    }

    /// 「シーズンラストスパートイベント：2026年9月3日メンテナンス後から2026年9月10日メンテナンス前まで」の終わりの日
    static func lastSpurtEnd(in text: String, reference: Date) -> Date? {
        let t = IdvDates.normalize(text)
        guard let r = t.range(of: "ラストスパート") else { return nil }
        var window = String(t[r.upperBound...].prefix(160))
        if let cut = window.range(of: "【") { window = String(window[..<cut.lowerBound]) }
        guard let range = IdvDates.range(in: window, reference: reference), range.start != nil else { return nil }
        return range.end
    }

    /// 公式の文だけから今のシーズンを決める（推定はしない）
    /// - updates：公式サイトのアップデートのお知らせ（articles に本文があるもの）
    /// - news：YouTube・PR TIMES の題名（番号と、ランク戦の題名にある期間）
    static func resolve(updates: [IdvNews], articles: [String: String], news: [IdvNews], now: Date = .now) -> IdvSeason? {
        var startFound: (n: Int, date: Date, link: String)? = nil
        var endFound: (date: Date, link: String)? = nil
        for u in updates {
            guard let text = articles[u.link] else { continue }
            let ref = u.date ?? now
            let day = IdvSchedule.when(in: u.title, reference: ref)?.start ?? ref
            if let n = started(in: text) {
                let prevN: Int = startFound?.n ?? -1
                let prevDay: Date = startFound?.date ?? .distantPast
                let better: Bool = n > prevN || (n == prevN && day > prevDay)
                if better { startFound = (n, day, u.link) }
            }
            if let e = lastSpurtEnd(in: text, reference: ref), e > (endFound?.date ?? .distantPast) {
                endFound = (e, u.link)
            }
        }
        let recent = (updates + news).filter { ($0.date ?? now) > now.addingTimeInterval(-120 * 86400) }
        let titleMax = recent.compactMap { number(in: $0.title) }.max()
        let n = [startFound?.n, titleMax].compactMap { $0 }.max()
        var start: Date? = nil
        if let s = startFound, s.n == n { start = s.date }
        var end: Date? = nil
        if let e = endFound, e.date > (start ?? .distantPast) { end = e.date }
        var source = start != nil || end != nil ? "公式サイトのアップデート情報" : "公式の動画・お知らせの題名"
        var link = start != nil ? startFound?.link : (end != nil ? endFound?.link : nil)
        // 題名に「ランクマッチ」「ランク戦」「シーズン」と期間があるもの（PR TIMES・YouTube）
        if start == nil || end == nil {
            for item in news {
                let t = item.title
                guard t.contains("ランクマッチ") || t.contains("ランク戦") || t.contains("シーズン") else { continue }
                guard let r = IdvDates.range(in: t, reference: item.date ?? now), r.start != nil else { continue }
                if let tn = number(in: t), let n, tn != n { continue }
                if start == nil { start = r.start }
                if end == nil { end = r.end }
                source = "公式のお知らせの題名"
                link = item.link
                break
            }
        }
        guard n != nil || start != nil || end != nil else { return nil }
        return IdvSeason(number: n, name: n.map { "シーズン\($0)" } ?? "今シーズン", start: start, end: end, source: source, link: link)
    }
}

// MARK: - 公式サイトのアップデート情報・記事の本文

enum IdvOfficial {
    /// 公式サイトのアップデート情報の一覧（1ページ目に新しい13件ほど）
    static let updateListURL = URL(string: "https://www.identityvgame.com/jp/news/update/index.html")

    /// 一覧の HTML から、お知らせ（kind .official）を作る
    static func parseList(_ html: String) -> [IdvNews] {
        let pattern = "<a\\s+href=\"(https://idv\\.163\\.com/jp/news/[a-z]+/(\\d{8})/[^\"]+\\.html)\"[^>]*?title=\"([^\"]+)\""
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        var out: [IdvNews] = []
        var seen = Set<String>()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = "yyyyMMdd"
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let link = ns.substring(with: m.range(at: 1))
            guard seen.insert(link).inserted else { continue }
            let title = InfoFeedParser.unescape(ns.substring(with: m.range(at: 3)))
            let date = f.date(from: ns.substring(with: m.range(at: 2)))
            out.append(IdvNews(title: title, link: link, date: date, kind: .official, image: nil))
        }
        return out
    }

    private static let keepLine = try? NSRegularExpression(pattern: "\\d{1,2}月\\d{1,2}日|\\d{1,2}/\\d{1,2}|UTC|所要時間|シーズン|S\\d{2}|ラストスパート|メンテナンス|期間|日時")

    /// 記事の HTML から、日付や期間のある行だけを残した文（キャッシュ用。最大6000字）
    static func text(fromHTML html: String) -> String {
        var s = html
        for p in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<!--[\\s\\S]*?-->"] {
            s = s.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<(br|/p|/div|/li|/h\\d|/tr|/dd|/dt)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        s = InfoFeedParser.unescape(s.replacingOccurrences(of: "&amp;nbsp;", with: " "))
        let lines = s.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[\\s\\x{00A0}\\x{3000}]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty, line.count < 400, let re = keepLine else { return false }
                let n = IdvDates.normalize(line)
                return re.firstMatch(in: n, range: NSRange(location: 0, length: (n as NSString).length)) != nil
            }
        var out: [String] = []
        var total = 0
        for l in lines where out.last != l {
            total += l.count + 1
            if total > 6000 { break }
            out.append(l)
        }
        return out.joined(separator: "\n")
    }

    /// 本文を読みに行くもの（まだ読んでいないもの、新しい順）。公式を3件・PR TIMES を2件まで、余りはもう一方で埋める（合わせて最大 limit 件）
    static func articlesToFetch(news: [IdvNews], cached: Set<String>, limit: Int = 5) -> [IdvNews] {
        let fresh = news.filter { !cached.contains($0.link) && $0.url != nil }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let official = Array(fresh.filter { $0.kind == .official }.prefix(12))
        let press = fresh.filter { n in
            guard n.kind == .press else { return false }
            let base = n.title + "\n" + (n.summary ?? "")
            let ref = n.date ?? .now
            if IdvSchedule.isSchedule(base), IdvSchedule.when(in: base, reference: ref)?.hasTime != true { return true }
            if IdvCollab.tag(n.title) != nil, IdvDates.range(in: base, reference: ref) == nil { return true }
            return false
        }
        var pick = Array(official.prefix(3)) + Array(press.prefix(2))
        let rest = Array(official.dropFirst(3)) + Array(press.dropFirst(2))
        pick += rest.prefix(max(0, limit - pick.count))
        return Array(pick.prefix(limit))
    }
}
