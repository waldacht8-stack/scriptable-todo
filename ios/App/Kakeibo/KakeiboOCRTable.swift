import Foundation
import CoreGraphics

// 文字認識（Vision）で読んだ明細の表を、見出しの位置から列に分ける。
// Safari で印刷した銀行・カードのウェブ明細を想定（1つの取引が見た目の1行、日付が「2026年」「10月5日」の2段など）。
// 決まった銀行の形には頼らず、見出しの言葉（日付・お支払い・お預かり・お取引内容・残高…）で列の幅を決める。

/// 文字認識の1かたまり。rect は Vision と同じ 0〜1 の座標（左下が原点）
struct KakeiboOCRBox: Hashable {
    var text: String
    var rect: CGRect
}

enum KakeiboOCRTable {
    enum Role: Hashable {
        /// skip：取り込まない列（支払回数・摘要の2つめなど）。列の境目を正しく決めるためだけに置く
        case date, withdrawal, deposit, amount, text, balance, skip

        var isMoney: Bool { self == .withdrawal || self == .deposit || self == .amount || self == .balance }
    }

    struct Column: Hashable {
        var role: Role
        var title: String
        var center: CGFloat
        var minX: CGFloat = 0
        var maxX: CGFloat = 1
    }

    /// 語ごとに分けたかたまり（1つの認識結果に列が2つ入ってしまったときのため）
    struct Token: Hashable {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var midX: CGFloat { (minX + maxX) / 2 }
    }

    // MARK: 行にまとめる

    /// 上から順に、高さが重なるかたまりを1行にまとめる（行の中は左から順）
    static func lines(_ boxes: [KakeiboOCRBox]) -> [[KakeiboOCRBox]] {
        let sorted = boxes.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.rect.maxY > $1.rect.maxY }
        var out: [[KakeiboOCRBox]] = []
        var anchors: [CGRect] = []
        for b in sorted {
            if let last = anchors.last {
                let top: CGFloat = min(last.maxY, b.rect.maxY)
                let bottom: CGFloat = max(last.minY, b.rect.minY)
                let overlap: CGFloat = top - bottom
                let need: CGFloat = 0.4 * min(last.height, b.rect.height)
                if overlap >= need && overlap > 0 {
                    out[out.count - 1].append(b)
                    continue
                }
            }
            out.append([b])
            anchors.append(b.rect)
        }
        return out.map { line in line.sorted { $0.rect.minX < $1.rect.minX } }
    }

    /// かたまりを空白で語に分け、文字の幅（全角は2）の割合で横の位置を割り振る
    static func tokens(_ line: [KakeiboOCRBox]) -> [Token] {
        var out: [Token] = []
        for b in line {
            let s = b.text.trimmingCharacters(in: .whitespaces)
            let parts = s.split(whereSeparator: { $0 == " " || $0 == "　" }).map(String.init)
            if parts.count <= 1 {
                out.append(Token(text: s, minX: b.rect.minX, maxX: b.rect.maxX))
                continue
            }
            let total: CGFloat = CGFloat(weight(s))
            guard total > 0 else { continue }
            var pos = 0
            var rest = Substring(s)
            for part in parts {
                guard let r = rest.range(of: part) else { continue }
                let before: Int = weight(String(rest[..<r.lowerBound]))
                let start: Int = pos + before
                let end: Int = start + weight(part)
                let x0: CGFloat = b.rect.minX + b.rect.width * CGFloat(start) / total
                let x1: CGFloat = b.rect.minX + b.rect.width * CGFloat(end) / total
                out.append(Token(text: part, minX: x0, maxX: x1))
                pos = end
                rest = rest[r.upperBound...]
            }
        }
        return out
    }

    private static func weight(_ s: String) -> Int {
        s.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
    }

    // MARK: 見出し

    /// 見出しの言葉から列の役割を決める
    static func role(of raw: String) -> Role? {
        let s = raw.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty, s.count <= 20 else { return nil }
        if s.contains("残高") { return .balance }
        let dateWords = ["日付", "年月日", "取引日", "利用日", "お取引日", "ご利用日"]
        if dateWords.contains(where: { s.contains($0) }) && !s.contains("金額") { return .date }
        if s.contains("金額") {
            if s.contains("利用") { return .amount }
            if s.contains("支払") || s.contains("出金") || s.contains("引出") { return .withdrawal }
            if s.contains("預") || s.contains("入金") { return .deposit }
            return .amount
        }
        let avoid = ["区分", "回数", "方法", "日", "予定"]
        if avoid.contains(where: { s.contains($0) }) { return nil }
        // 2段の見出し「支払／回数」の上の段だけ（カードの支払回数。お支払いの金額ではない）
        if s == "支払" { return nil }
        // 表の題（「ご利用明細」「入出金明細」）は列ではない
        if s.hasSuffix("明細") && s != "明細" { return nil }
        if s.contains("支払") || s.contains("出金") || s.contains("引出") { return .withdrawal }
        if s.contains("預") || s.contains("入金") { return .deposit }
        let textWords = ["取引内容", "内容", "摘要", "利用先", "店名", "利用店", "取引先", "明細", "お取引"]
        if textWords.contains(where: { s.contains($0) }) { return .text }
        return nil
    }

    /// 1文字ずつ空けた見出し（「ご　利　用　店　名」）を1語にまとめる
    static func joinSpaced(_ ts: [Token]) -> [Token] {
        var out: [Token] = []
        var run: [Token] = []
        func flush() {
            if run.count >= 2, let a = run.first, let b = run.last {
                out.append(Token(text: run.map(\.text).joined(), minX: a.minX, maxX: b.maxX))
            } else {
                out.append(contentsOf: run)
            }
            run = []
        }
        for t in ts {
            let single: Bool = t.text.count == 1 && !t.text.unicodeScalars.allSatisfy(\.isASCII)
            guard single else { flush(); out.append(t); continue }
            // 離れた1文字（「何」と「摘」）はつながない。字間はおおむね字の幅の数倍まで
            if let last = run.last {
                let width: CGFloat = max(last.maxX - last.minX, t.maxX - t.minX)
                if t.minX - last.maxX > 5 * width { flush() }
            }
            run.append(t)
        }
        flush()
        return out
    }

    /// 見出しの行なら列を返す（日付ともう2つ以上の役割が並んでいること）
    static func headerColumns(_ line: [KakeiboOCRBox]) -> [Column]? {
        headerColumns(tokens: joinSpaced(tokens(line)))
    }

    /// 2〜3段に分かれた見出し：段ごとに語にしてから、まとめて列を決める
    static func headerColumns(lines: [[KakeiboOCRBox]]) -> [Column]? {
        var ts: [Token] = []
        for l in lines { ts.append(contentsOf: joinSpaced(tokens(l))) }
        return headerColumns(tokens: ts.sorted { $0.midX < $1.midX })
    }

    private static func headerColumns(tokens ts: [Token]) -> [Column]? {
        var cols: [Column] = []
        var used = Set<Role>()
        var others: [Token] = []
        for t in ts {
            if let r = role(of: t.text), !used.contains(r) {
                used.insert(r)
                cols.append(Column(role: r, title: t.text, center: t.midX))
            } else {
                others.append(t)
            }
        }
        guard used.contains(.date), cols.count >= 3,
              used.contains(.withdrawal) || used.contains(.deposit) || used.contains(.amount) else { return nil }
        // 「ご利用金額」と「お支払い金額」が両方あるカードは、ご利用金額を使う（もう一方は取り込まない列）
        if used.contains(.amount), let i = cols.firstIndex(where: { $0.role == .withdrawal }),
           cols[i].title.contains("金額") {
            cols[i].role = .skip
        }
        // ほかの見出しの言葉（支払回数・摘要・現地通貨額…）も、取り込まない列として境目に使う。
        // すでにある列と同じ位置のもの（2段めの「海外ご利用店名」など）は足さない
        for t in others {
            let s: String = t.text.precomposedStringWithCompatibilityMapping
            guard s.count <= 12, s.rangeOfCharacter(from: .decimalDigits) == nil, !s.contains("明細") else { continue }
            let near: Bool = cols.contains { abs($0.center - t.midX) < 0.05 }
            if !near { cols.append(Column(role: .skip, title: t.text, center: t.midX)) }
        }
        cols.sort { $0.center < $1.center }
        for i in cols.indices {
            let left: CGFloat = i == 0 ? 0 : (cols[i - 1].center + cols[i].center) / 2
            let right: CGFloat = i == cols.count - 1 ? 1 : (cols[i].center + cols[i + 1].center) / 2
            cols[i].minX = left
            cols[i].maxX = right
        }
        return cols
    }

    // MARK: 表にする

    /// 口座の情報など、残さない行（見出しより前の文は年の手がかりと銀行の見分けにだけ使う）
    private static let privateWords = ["お名前", "名前", "名義", "口座番号", "店番", "店名", "科目", "様", "お客様番号", "会員番号", "カード番号"]

    /// 印刷の上下の余白（URL・印刷日時・ページ番号）
    static func isFooter(_ s: String) -> Bool {
        let n = s.precomposedStringWithCompatibilityMapping
        if n.contains("http") || n.contains("www.") || n.contains("ページ") || n.contains(".jp/") || n.contains(".com/") { return true }
        if KakeiboRegex.matches(#"^\s*\d+\s*/\s*\d+\s*$"#, n) { return true }
        if KakeiboRegex.matches(#"\d{1,2}:\d{2}"#, n) { return true }
        return false
    }

    private static func isYearOnly(_ s: String) -> Bool {
        KakeiboRegex.matches(#"^((19|20)\d{2}|令和\d{1,2}|R\d{1,2})年?$"#, s)
    }

    private static func hasYear(_ s: String) -> Bool {
        KakeiboRegex.matches(#"((19|20)\d{2}|令和\d{1,2})[年./\-]"#, s)
    }

    private static func hasMonthDay(_ s: String) -> Bool {
        KakeiboRegex.matches(#"\d{1,2}\s*[月/\-.]\s*\d{1,2}"#, s)
    }

    /// 文字認識で崩れやすい金額を直す（「12.345円」「12, 345 円」「¥ 1,000」）
    static func cleanMoney(_ raw: String) -> String {
        var s = raw.precomposedStringWithCompatibilityMapping
        s = s.replacingOccurrences(of: " ", with: "")
        if let re = try? NSRegularExpression(pattern: #"(\d)\.(\d{3})(?!\d)"#) {
            for _ in 0..<4 {
                let ns = s as NSString
                let next = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "$1,$2")
                if next == s { break }
                s = next
            }
        }
        return s
    }

    /// ページごとの認識結果から表を作る。見出しが見つからなければ「列1」「列2」…の表（列の対応を選んでもらう）
    static func build(pages: [[KakeiboOCRBox]]) -> (table: KakeiboTable, mapping: KakeiboColumnMapping)? {
        var columns: [Column]? = nil
        var preamble: [String] = []
        var rows: [[String]] = []
        var pending: [String]? = nil
        var pendingNeedsDay = false
        var plainLines: [[String]] = []     // 見出しが無いとき用

        func commit() {
            if let p = pending, p.contains(where: { !$0.isEmpty }) { rows.append(p) }
            pending = nil
            pendingNeedsDay = false
        }

        for page in pages {
            let ls = lines(page)
            var skipUntil = -1
            for (li, line) in ls.enumerated() {
                if li <= skipUntil { continue }
                let joined: String = line.map(\.text).joined(separator: " ")
                if let h = headerBlock(ls, at: li) {
                    commit()
                    columns = h.columns
                    skipUntil = li + h.lineCount - 1
                    continue
                }
                if isFooter(joined) { commit(); continue }
                guard let cols = columns else {
                    let n = joined.precomposedStringWithCompatibilityMapping
                    if !privateWords.contains(where: { n.contains($0) }) { preamble.append(joined) }
                    plainLines.append(tokens(line).map(\.text))
                    continue
                }
                // 列に振り分ける
                var cells = Array(repeating: "", count: cols.count)
                for t in tokens(line) {
                    let x = t.midX
                    let hit: Int? = cols.firstIndex(where: { x >= $0.minX && x < $0.maxX })
                    let i: Int = hit ?? (cols.count - 1)
                    cells[i] = cells[i].isEmpty ? t.text : cells[i] + " " + t.text
                }
                guard let di = cols.firstIndex(where: { $0.role == .date }) else { continue }
                // 日付の列に入り込んだ店名（見出しが列の真ん中にあり、境目が右に寄るとき）は内容の列へ戻す
                let parts: [String] = cells[di].split(separator: " ").map(String.init)
                let isDatePart: (String) -> Bool = { KakeiboRegex.matches(#"^[0-9０-９/／.\-年月日令和R]+$"#, $0) }
                let datePart: [String] = Array(parts.prefix(while: isDatePart))
                let spill: [String] = Array(parts.dropFirst(datePart.count))
                if !spill.isEmpty, let ti = cols.firstIndex(where: { $0.role == .text }) {
                    let moved: String = spill.joined(separator: " ")
                    cells[ti] = cells[ti].isEmpty ? moved : moved + " " + cells[ti]
                    cells[di] = datePart.joined(separator: " ")
                }
                let dateCell = cells[di].precomposedStringWithCompatibilityMapping.replacingOccurrences(of: " ", with: "")
                cells[di] = dateCell

                if isYearOnly(dateCell) {
                    // 2段の日付の上の段：新しい取引
                    commit()
                    pending = cells
                    pendingNeedsDay = true
                } else if hasMonthDay(dateCell) {
                    if var p = pending, pendingNeedsDay, !hasYear(dateCell) {
                        // 下の段の「10月5日」を上の「2026年」につなぐ
                        p[di] = p[di] + dateCell
                        merge(&p, cells, skip: di, cols: cols)
                        pending = p
                        pendingNeedsDay = false
                    } else {
                        commit()
                        pending = cells
                    }
                } else if var p = pending {
                    // 日付の無い行：内容が折り返した・金額だけ段がずれた
                    merge(&p, cells, skip: di, cols: cols)
                    pending = p
                }
            }
            commit()
        }

        guard let cols = columns else {
            let width = plainLines.map(\.count).max() ?? 0
            guard width > 0 else { return nil }
            let headers = (0..<width).map { "列\($0 + 1)" }
            let t = KakeiboTable(headers: headers, rows: plainLines, preamble: "", headerFound: false)
            return (t, KakeiboColumnMapping())
        }

        // 金額の列を直す
        let moneyCols: [Int] = cols.indices.filter { cols[$0].role.isMoney }
        for r in rows.indices {
            for c in moneyCols { rows[r][c] = cleanMoney(rows[r][c]) }
        }
        // 見出しの名前（同じ名前が2つあれば番号を付ける）
        var headers: [String] = []
        for c in cols {
            var name = c.title
            var k = 2
            while headers.contains(name) { name = "\(c.title)\(k)"; k += 1 }
            headers.append(name)
        }
        var m = KakeiboColumnMapping()
        for (i, c) in cols.enumerated() {
            switch c.role {
            case .date: m.date = headers[i]
            case .withdrawal: m.withdrawal = headers[i]
            case .deposit: m.deposit = headers[i]
            case .amount: m.amount = headers[i]
            case .text: m.text = headers[i]
            case .balance: m.balance = headers[i]
            case .skip: break
            }
        }
        let t = KakeiboTable(headers: headers, rows: rows, preamble: preamble.joined(separator: "\n"), headerFound: true)
        return (t, m)
    }

    /// i 行目から始まる見出し（1段、またはすぐ下に続く数字の無い段と合わせて2〜3段）
    static func headerBlock(_ ls: [[KakeiboOCRBox]], at i: Int) -> (columns: [Column], lineCount: Int)? {
        var best: (columns: [Column], lineCount: Int)? = nil
        if let h = headerColumns(ls[i]) { best = (columns: h, lineCount: 1) }
        var block: [[KakeiboOCRBox]] = [ls[i]]
        // 下の段（「海外ご利用店名」「現地通貨額」など）も、見出しであるうちは合わせる。宛名の行（〜様）は入れない
        for k in 1...2 {
            guard i + k < ls.count else { break }
            let prev: [KakeiboOCRBox] = block[block.count - 1]
            let next: [KakeiboOCRBox] = ls[i + k]
            let text: String = next.map(\.text).joined()
            guard text.rangeOfCharacter(from: .decimalDigits) == nil, !text.contains("様") else { break }
            let prevBottom: CGFloat = prev.map(\.rect.minY).min() ?? 0
            let nextTop: CGFloat = next.map(\.rect.maxY).max() ?? 0
            let height: CGFloat = prev.map(\.rect.height).max() ?? 0
            // 見出しの段どうしはほぼ接している（上の「ご利用明細」のような表の題は、少し離れているので入れない）
            guard prevBottom - nextTop < 0.6 * height else { break }
            block.append(next)
            if let h = headerColumns(lines: block) {
                best = (columns: h, lineCount: block.count)
            } else if best != nil {
                break
            }
        }
        return best
    }

    /// 行にまとめた文字（見出しで読めなかったときに、文字の明細と同じ読み方を試す）
    static func text(pages: [[KakeiboOCRBox]]) -> String {
        var out: [String] = []
        for page in pages {
            for line in lines(page) {
                let s: String = line.map(\.text).joined(separator: " ")
                if isFooter(s) { continue }
                let n = s.precomposedStringWithCompatibilityMapping
                if privateWords.contains(where: { n.contains($0) }) && headerColumns(line) == nil { continue }
                out.append(s)
            }
        }
        return out.joined(separator: "\n")
    }

    /// 段がずれた行を足す。内容はつなぎ、金額は空いているところにだけ入れる
    private static func merge(_ p: inout [String], _ cells: [String], skip: Int, cols: [Column]) {
        for i in cells.indices where i != skip && !cells[i].isEmpty {
            if p[i].isEmpty {
                p[i] = cells[i]
            } else if !cols[i].role.isMoney {
                p[i] = p[i] + " " + cells[i]
            }
        }
    }
}
