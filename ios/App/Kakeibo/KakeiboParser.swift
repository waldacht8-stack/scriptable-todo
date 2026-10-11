import Foundation
import PDFKit
import Vision
import UIKit

// 明細ファイル（CSV・PDF）の読み取り。銀行やカード会社ごとの決まった形に頼らず、
// 見出しの名前で列を探す・日付と金額の形で行を見つける。

/// 読み取った1行（確認画面で直してから取り込む）
struct KakeiboDraft: Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Int
    var kind: KakeiboKind
    var text: String
    var balance: Int? = nil
    var suspect: Bool = false           // 残高の検算が合わない・文字認識で読んだ
    var category: String = "その他"
    var include: Bool = true
    var flag: Flag? = nil

    enum Flag: String, Hashable {
        case duplicate      // すでにある
        case transfer       // カード引落・振替
        case cardOverlap    // カードの明細と重なる（JCB の引落）

        var label: String {
            switch self {
            case .duplicate: "重複"
            case .transfer: "入れない"
            case .cardOverlap: "カードと重複"
            }
        }
    }

    var signed: Int { kind == .expense ? -amount : amount }
}

// MARK: - 文字の小道具

enum KakeiboRegex {
    static func groups(_ pattern: String, in s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var out: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }

    static func matches(_ pattern: String, _ s: String) -> Bool { groups(pattern, in: s) != nil }
}

/// 日付：2026/09/28・2026-09-28・2026年9月28日・20260928・R8.9.28・令和8年9月28日・26/09/28・9/28
enum KakeiboDateParser {
    static func parse(_ raw: String, defaultYear: Int? = nil, now: Date = .now) -> Date? {
        let s = raw.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let cal = Calendar.current
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d), (1990...2100).contains(y) else { return nil }
            var c = DateComponents()
            c.year = y; c.month = m; c.day = d; c.hour = 12
            guard let date = cal.date(from: c), cal.component(.day, from: date) == d else { return nil }
            return date
        }
        // 元号（令和・平成）
        if let g = KakeiboRegex.groups(#"^(令和|平成|R|H|r|h)\s*(\d{1,2})[./\-年](\d{1,2})[./\-月](\d{1,2})"#, in: s) {
            let base = (g[1] == "平成" || g[1].uppercased() == "H") ? 1988 : 2018
            return make(base + (Int(g[2]) ?? 0), Int(g[3]) ?? 0, Int(g[4]) ?? 0)
        }
        if let g = KakeiboRegex.groups(#"^(\d{4})[./\-年]\s*(\d{1,2})[./\-月]\s*(\d{1,2})"#, in: s) {
            return make(Int(g[1]) ?? 0, Int(g[2]) ?? 0, Int(g[3]) ?? 0)
        }
        if let g = KakeiboRegex.groups(#"^(\d{4})(\d{2})(\d{2})(?!\d)"#, in: s) {
            return make(Int(g[1]) ?? 0, Int(g[2]) ?? 0, Int(g[3]) ?? 0)
        }
        // 2けたの年：西暦の下2けたとして近ければそれ、遠ければ令和
        if let g = KakeiboRegex.groups(#"^(\d{2})[./\-](\d{1,2})[./\-](\d{1,2})(?!\d)"#, in: s) {
            let yy = Int(g[1]) ?? 0
            let thisYear = cal.component(.year, from: now)
            let western = 2000 + yy
            let year = abs(western - thisYear) <= 3 ? western : 2018 + yy
            return make(year, Int(g[2]) ?? 0, Int(g[3]) ?? 0)
        }
        // 月日だけ：年は文書から（なければ今年。先の日付になるなら前の年）
        if let g = KakeiboRegex.groups(#"^(\d{1,2})[/\-月](\d{1,2})日?(?![\d/])"#, in: s) {
            let m = Int(g[1]) ?? 0, d = Int(g[2]) ?? 0
            if let y = defaultYear { return make(y, m, d) }
            let y = cal.component(.year, from: now)
            guard let date = make(y, m, d) else { return nil }
            if date > now.addingTimeInterval(2 * 86_400) { return make(y - 1, m, d) }
            return date
        }
        return nil
    }

    /// 文書の中の「2026年」「2026/」から年を拾う（月日だけの明細のため）
    static func yearHint(in text: String) -> Int? {
        let s = text.precomposedStringWithCompatibilityMapping
        if let g = KakeiboRegex.groups(#"(20\d{2})\s*[年/\-.]"#, in: s) { return Int(g[1]) }
        if let g = KakeiboRegex.groups(#"令和\s*(\d{1,2})\s*年"#, in: s), let n = Int(g[1]) { return 2018 + n }
        return nil
    }
}

/// 金額：「1,234」「¥1,234」「1,234円」「-500」「▲500」「(500)」。空や「—」は nil
enum KakeiboAmountParser {
    static func parse(_ raw: String) -> Int? {
        var s = raw.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        var negative = false
        if let f = s.first, "-−▲△".contains(f) { negative = true; s.removeFirst() }
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let dot = s.firstIndex(of: ".") {
            let frac = s[s.index(after: dot)...]
            guard frac.allSatisfy({ $0 == "0" }) || frac.isEmpty else { return nil }
            s = String(s[..<dot])
        }
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(s) else { return nil }
        return negative ? -v : v
    }

    /// 金額らしい語か（PDF の行の後ろから拾う）
    static func isAmountToken(_ t: String) -> Bool {
        let s = t.precomposedStringWithCompatibilityMapping
        return KakeiboRegex.matches(#"^[-−▲△]?[¥\\]?(\d{1,3}(,\d{3})+|\d+)(\.00)?円?$"#, s)
    }
}

// MARK: - CSV

/// CSV の表（見出しの行と、そのあとの行）
struct KakeiboTable: Hashable {
    var headers: [String]
    var rows: [[String]]
    var preamble: String            // 見出しより前の行（口座名など。銀行・カードの見分けに使う）
    var headerFound: Bool

    func column(_ name: String?) -> Int? {
        guard let name else { return nil }
        return headers.firstIndex(of: name)
    }

    /// 列の見本（対応を選ぶ画面で、見出しの横に出す）
    func sample(_ col: Int) -> String {
        rows.lazy.map { col < $0.count ? $0[col] : "" }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
    }
}

enum KakeiboCSV {
    /// 文字コード：UTF-8（BOM あり・なし）→ Shift_JIS（CP932）の順に試す
    static func decode(_ data: Data) -> String? {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        if let s = String(data: d, encoding: .utf8) { return s }
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        if let s = String(data: d, encoding: cp932) { return s }
        return String(data: d, encoding: .shiftJIS)
    }

    /// CSV を行と列に分ける（"…" の中のカンマ・改行もそのまま）
    static func rows(_ text: String) -> [[String]] {
        var out: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if chars.last != "\n" { chars.append("\n") }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": quoted = true
                case ",", "\t": row.append(field); field = ""
                case "\n":
                    row.append(field); field = ""
                    if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { out.append(row) }
                    row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        return out.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// 見出しの名前から列の役割を決める
    static func autoMapping(_ headers: [String]) -> KakeiboColumnMapping {
        var used = Set<Int>()
        func pick(_ words: [String], avoid: [String] = []) -> String? {
            for w in words {
                for (i, h) in headers.enumerated() where !used.contains(i) {
                    let n = h.precomposedStringWithCompatibilityMapping
                    if n.contains(w) && !avoid.contains(where: { n.contains($0) }) {
                        used.insert(i)
                        return h
                    }
                }
            }
            return nil
        }
        var m = KakeiboColumnMapping()
        m.balance = pick(["残高"])
        m.date = pick(["利用日", "取引日", "日付", "年月日", "お取引日", "ご利用年月日"], avoid: ["支払日", "引落日"])
        m.withdrawal = pick(["お引出", "お引き出し", "引出", "出金", "支払い金額", "お支払い金額"], avoid: ["入出金", "区分"])
        m.deposit = pick(["お預入", "お預け入れ", "預入", "預かり金額", "お預かり", "入金"], avoid: ["入出金", "区分"])
        m.amount = pick(["利用金額", "ご利用金額", "お支払金額", "支払金額", "金額"], avoid: ["手数料", "区分", "回数"])
        m.text = pick(["ご利用先", "利用先", "ご利用店名", "利用店名", "店名", "摘要", "お取引内容", "取引内容", "内容", "取引先", "メモ", "備考"])
        return m
    }

    /// 見出しの行を探して表にする（見つからなければ「列1」「列2」…の見出しにして、対応を選んでもらう）
    static func table(_ text: String) -> KakeiboTable? {
        let all = rows(text)
        guard !all.isEmpty else { return nil }
        for (i, r) in all.prefix(40).enumerated() where autoMapping(r).isUsable {
            let pre = all[..<i].map { $0.joined(separator: " ") }.joined(separator: "\n")
            return KakeiboTable(headers: r, rows: Array(all[(i + 1)...]), preamble: pre, headerFound: true)
        }
        let width = all.map(\.count).max() ?? 0
        let headers = (0..<width).map { "列\($0 + 1)" }
        return KakeiboTable(headers: headers, rows: all, preamble: "", headerFound: false)
    }

    /// 表と列の対応から行を作る
    static func drafts(_ t: KakeiboTable, mapping m: KakeiboColumnMapping, isCard: Bool, now: Date = .now) -> [KakeiboDraft] {
        let dc = t.column(m.date), ac = t.column(m.amount), wc = t.column(m.withdrawal)
        let pc = t.column(m.deposit), tc = t.column(m.text), bc = t.column(m.balance)
        guard let dc else { return [] }
        let hint = KakeiboDateParser.yearHint(in: t.preamble)
        // 「利用金額」「支払金額」はカードと同じく、プラスが支出
        let amountIsSpend = isCard || (m.amount.map { $0.contains("利用") || $0.contains("支払") } ?? false)
        func cell(_ r: [String], _ c: Int?) -> String { (c != nil && c! < r.count) ? r[c!] : "" }
        var out: [KakeiboDraft] = []
        for r in t.rows {
            guard let date = KakeiboDateParser.parse(cell(r, dc), defaultYear: hint, now: now) else { continue }
            var amount = 0
            var kind = KakeiboKind.expense
            let w = KakeiboAmountParser.parse(cell(r, wc)) ?? 0
            let p = KakeiboAmountParser.parse(cell(r, pc)) ?? 0
            if w != 0 {
                amount = abs(w); kind = .expense
            } else if p != 0 {
                amount = abs(p); kind = .income
            } else if let v = KakeiboAmountParser.parse(cell(r, ac)), v != 0 {
                amount = abs(v)
                kind = amountIsSpend ? (v > 0 ? .expense : .income) : (v < 0 ? .expense : .income)
            } else {
                continue
            }
            let text = cell(r, tc)
            out.append(KakeiboDraft(date: date, amount: amount, kind: kind, text: text,
                                    balance: KakeiboAmountParser.parse(cell(r, bc))))
        }
        KakeiboBalanceCheck.mark(&out)
        return out
    }
}

// MARK: - 残高の検算

enum KakeiboBalanceCheck {
    /// 前の行の残高 ± 金額 ＝ この行の残高 になっているか。古い順・新しい順の合う方で確かめ、合わない行に印を付ける
    static func mark(_ rows: inout [KakeiboDraft]) {
        let idx = rows.indices.filter { rows[$0].balance != nil }
        guard idx.count >= 2 else { return }
        var asc = 0, desc = 0
        for k in 1..<idx.count {
            let a = rows[idx[k - 1]], b = rows[idx[k]]
            if a.balance! + b.signed == b.balance! { asc += 1 }
            if b.balance! + a.signed == a.balance! { desc += 1 }
        }
        for k in 1..<idx.count {
            let i = idx[k - 1], j = idx[k]
            let a = rows[i], b = rows[j]
            if asc >= desc {
                if a.balance! + b.signed != b.balance! { rows[j].suspect = true }
            } else {
                if b.balance! + a.signed != a.balance! { rows[i].suspect = true }
            }
        }
    }
}

// MARK: - PDF

enum KakeiboPDF {
    /// PDFKit で文字を取り出す（画像だけの PDF は空）
    static func text(from data: Data) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { pages.append(s) }
        }
        let s = pages.joined(separator: "\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }

    /// 文字が化けていないか。Safari で印刷した PDF は、日本語の字形に文字の対応（ToUnicode）が無く、
    /// 取り出すと「೥ ݄೔ ԁ」のようなよその文字になる（数字まで化ける）。そのときは文字認識で読む
    static func isGarbled(_ text: String) -> Bool {
        var total = 0, japanese = 0, foreign = 0, nonASCII = 0
        var hasKey = false
        for u in text.unicodeScalars {
            if u.properties.isWhitespace { continue }
            total += 1
            let v = u.value
            if v < 0x80 { continue }
            nonASCII += 1
            if "年月日円".unicodeScalars.contains(u) { hasKey = true }
            let kana: Bool = (0x3040...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v)
            let kanji: Bool = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v)
            if kana || kanji { japanese += 1; continue }
            let ok: Bool = (0x00A0...0x00FF).contains(v) || (0x2000...0x2BFF).contains(v)
                || (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v)
            if !ok { foreign += 1 }
        }
        guard total > 0 else { return false }
        // よその文字が多い
        if foreign >= 3 && Double(foreign) / Double(total) > 0.1 { return true }
        // ASCII 以外の文字がそれなりにあるのに、日本語（年・月・日・円）がほとんど無い
        if nonASCII >= 10 && !hasKey && japanese * 5 < nonASCII { return true }
        // 漢字に化けることもある：日本語の明細なら「年・月・日・円」のどれかは必ずある
        if nonASCII >= 30 && !hasKey { return true }
        return false
    }

    /// 文字が無い・化けた PDF：ページを2倍で描いて文字認識（Vision）。ページごとの認識結果を返す
    static func recognizeBoxes(_ data: Data) async -> [[KakeiboOCRBox]] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var pages: [[KakeiboOCRBox]] = []
        for i in 0..<min(doc.pageCount, 20) {
            guard let page = doc.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cg = image.cgImage else { continue }
            pages.append(await recognizeBoxes(cg))
        }
        return pages
    }

    private static func recognizeBoxes(_ image: CGImage) async -> [KakeiboOCRBox] {
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["ja-JP"]
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        do { try handler.perform([req]) } catch { return [] }
        let obs: [VNRecognizedTextObservation] = req.results ?? []
        var out: [KakeiboOCRBox] = []
        for o in obs {
            guard let s = o.topCandidates(1).first?.string else { continue }
            out.append(KakeiboOCRBox(text: s, rect: o.boundingBox))
        }
        return out
    }

    private static let dateHead = #"^\s*((令和|平成|R|H)\s*\d{1,2}[./\-年]\d{1,2}[./\-月]\d{1,2}日?|\d{4}[./\-年]\s*\d{1,2}[./\-月]\s*\d{1,2}日?|\d{2}[./\-]\d{1,2}[./\-]\d{1,2}|\d{1,2}[/月]\d{1,2}日?)(?=\s|$)"#

    /// 取り出した文字から行を作る。見出しに「残高」があれば、最後の数字を残高として検算に使う
    static func drafts(text: String, isCard: Bool, now: Date = .now) -> (rows: [KakeiboDraft], hasBalance: Bool) {
        let normalized = text.precomposedStringWithCompatibilityMapping
        let lines = normalized.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let hint = KakeiboDateParser.yearHint(in: normalized)
        // 見出しの行
        let header = lines.first { l in
            (l.contains("日付") || l.contains("年月日") || l.contains("取引日") || l.contains("利用日"))
                && (l.contains("残高") || l.contains("出金") || l.contains("引出") || l.contains("金額") || l.contains("摘要"))
        }
        var headerHasBalance = header?.contains("残高") ?? false
        let withdrawalFirst: Bool = {
            guard let h = header else { return true }
            let w = h.range(of: "出金") ?? h.range(of: "引出") ?? h.range(of: "支払")
            let d = h.range(of: "入金") ?? h.range(of: "預入")
            guard let w, let d else { return true }
            return w.lowerBound < d.lowerBound
        }()

        // 日付で始まる行ごとにまとめる（金額が次の行に落ちたときは続けて読む）
        var records: [String] = []
        for l in lines {
            if KakeiboRegex.matches(dateHead, l) {
                records.append(l)
            } else if let last = records.last, trailingAmounts(last).isEmpty, records.count > 0 {
                records[records.count - 1] = last + " " + l
            }
        }

        struct Raw { var date: Date; var text: String; var nums: [Int] }
        var raws: [Raw] = []
        for r in records {
            guard let g = KakeiboRegex.groups(dateHead, in: r),
                  let date = KakeiboDateParser.parse(g[1], defaultYear: hint, now: now) else { continue }
            let rest = String(r.dropFirst(g[0].count)).trimmingCharacters(in: .whitespaces)
            var tokens = rest.split(separator: " ").map(String.init)
            var nums: [Int] = []
            if isCard {
                // カード：店名のあとの最初の金額が利用金額
                if let i = tokens.firstIndex(where: { KakeiboAmountParser.isAmountToken($0) }), i > 0,
                   let v = KakeiboAmountParser.parse(tokens[i]) {
                    nums = [v]
                    tokens = Array(tokens[..<i])
                }
            } else {
                let tail = trailingAmounts(rest)
                nums = tail.compactMap(KakeiboAmountParser.parse)
                tokens = Array(tokens.dropLast(tail.count))
            }
            guard !nums.isEmpty else { continue }
            raws.append(Raw(date: date, text: tokens.joined(separator: " "), nums: nums))
        }
        if header == nil {
            // 見出しが読めないとき：数字が2つの行が多ければ「金額・残高」とみなす
            headerHasBalance = !isCard && raws.filter { $0.nums.count == 2 }.count * 2 >= max(1, raws.count)
        }

        var rows: [KakeiboDraft] = []
        for raw in raws {
            var amount = 0
            var balance: Int? = nil
            var kind: KakeiboKind? = nil
            let n = raw.nums
            if isCard {
                amount = abs(n[0]); kind = n[0] < 0 ? .income : .expense
            } else if n.count >= 3 {
                // 出金・入金・残高（片方は 0）
                let a = withdrawalFirst ? n[n.count - 3] : n[n.count - 2]
                let b = withdrawalFirst ? n[n.count - 2] : n[n.count - 3]
                balance = n[n.count - 1]
                if a != 0 { amount = abs(a); kind = .expense } else { amount = abs(b); kind = .income }
            } else if n.count == 2 && headerHasBalance {
                amount = abs(n[0]); balance = n[1]
                if n[0] < 0 { kind = .expense }
            } else if n.count == 1 && headerHasBalance {
                continue    // 残高だけの行（繰越など）
            } else {
                amount = abs(n[0])
                if n[0] < 0 { kind = .expense }
            }
            guard amount > 0 else { continue }
            rows.append(KakeiboDraft(date: raw.date, amount: amount, kind: kind ?? guessKind(raw.text), text: raw.text, balance: balance))
        }
        if !isCard { inferKinds(&rows) }
        KakeiboBalanceCheck.mark(&rows)
        return (rows, headerHasBalance)
    }

    /// 行の後ろに続く金額らしい語（最大3つ：出金・入金・残高）
    private static func trailingAmounts(_ line: String) -> [String] {
        let tokens = line.split(separator: " ").map(String.init)
        var out: [String] = []
        for t in tokens.reversed() {
            guard KakeiboAmountParser.isAmountToken(t), out.count < 3 else { break }
            out.insert(t, at: 0)
        }
        // 全部が数字なら、少なくとも1語は内容として残す
        if out.count == tokens.count && !out.isEmpty { out.removeFirst() }
        return out
    }

    /// 金額だけでは出金か入金か分からない行は、残高の増え減りで決める
    private static func inferKinds(_ rows: inout [KakeiboDraft]) {
        let idx = rows.indices.filter { rows[$0].balance != nil }
        guard idx.count >= 2 else { return }
        var asc = 0, desc = 0
        for k in 1..<idx.count {
            let a = rows[idx[k - 1]], b = rows[idx[k]]
            if abs(b.balance! - a.balance!) == b.amount { asc += 1 }
            if abs(a.balance! - b.balance!) == a.amount { desc += 1 }
        }
        for k in 1..<idx.count {
            let i = idx[k - 1], j = idx[k]
            if asc >= desc {
                let delta = rows[j].balance! - rows[i].balance!
                if abs(delta) == rows[j].amount { rows[j].kind = delta < 0 ? .expense : .income }
            } else {
                let delta = rows[i].balance! - rows[j].balance!
                if abs(delta) == rows[i].amount { rows[i].kind = delta < 0 ? .expense : .income }
            }
        }
    }

    /// 言葉から入金らしいか（残高で決められない行）
    static func guessKind(_ text: String) -> KakeiboKind {
        let n = KakeiboText.normalize(text)
        let words = ["給与", "給料", "賞与", "利息", "入金", "振込入金", "預入", "キュウヨ", "リソク", "返金"]
        return words.contains { n.contains(KakeiboText.normalize($0)) } ? .income : .expense
    }
}

// MARK: - 銀行・カードの見分け

enum KakeiboDetect {
    /// ファイルの中身から、どこの明細かを推測する（共有で受け取ったとき）
    static func institution(_ text: String) -> KakeiboInstitution? {
        let n = KakeiboText.normalize(text.prefix(4000).description)
        if n.contains("十六") || n.contains(KakeiboText.normalize("じゅうろく")) { return .juroku }
        if n.contains("JCB") || n.contains(KakeiboText.normalize("ジェーシービー")) { return .jcb }
        if n.contains("三菱UFJ") || n.contains("MUFG") { return .mufg }
        return nil
    }
}
