import Foundation

/// 記事・投稿を取りに行く（キー不要・無料の公開 API と RSS だけ）
enum InfoFetcher {
    enum FetchError: Error { case badStatus(Int), badURL }

    static let userAgent = "ios:com.todoapp.TodoApp:v0.3 (Hiyori personal feed reader)"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw FetchError.badStatus(h.statusCode) }
        return data
    }

    /// 話題のキーワードで1つの元を検索する
    static func search(_ source: InfoSource, keyword: String, feedKey: String) async throws -> [InfoArticle] {
        let q = InfoText.encode(keyword)
        var items: [InfoArticle]
        switch source {
        case .googleNews:
            items = try await rss("https://news.google.com/rss/search?q=\(q)&hl=ja&gl=JP&ceid=JP:ja", source: source.rawValue)
        case .googleNewsEN:
            items = try await rss("https://news.google.com/rss/search?q=\(q)&hl=en-US&gl=US&ceid=US:en", source: source.rawValue)
        case .hatena:
            items = try await rss("https://b.hatena.ne.jp/q/\(q)?mode=rss&sort=recent", source: source.rawValue)
        case .hackerNews:
            items = try await hackerNews(q)
        case .bluesky:
            items = try await bluesky(q, japanese: !InfoText.isForeign(keyword))
        case .reddit:
            items = try await reddit(q)
        }
        for i in items.indices { items[i].feedKey = feedKey }
        return items
    }

    /// おすすめの候補：はてブの人気エントリーと Google ニュースの主要ニュース
    static func general(_ key: String) async throws -> [InfoArticle] {
        var items: [InfoArticle]
        if key == "_hot" {
            items = try await rss("https://b.hatena.ne.jp/hotentry/all.rss", source: "hot")
        } else {
            items = try await rss("https://news.google.com/rss?hl=ja&gl=JP&ceid=JP:ja", source: "top")
        }
        for i in items.indices { items[i].feedKey = key }
        return items
    }

    static func rss(_ urlString: String, source: String) async throws -> [InfoArticle] {
        guard let url = URL(string: urlString) else { throw FetchError.badURL }
        let data = try await get(url)
        return InfoFeedParser.parse(data, source: source)
    }

    // MARK: Hacker News（Algolia の検索 API）

    private struct HNResponse: Decodable {
        struct Hit: Decodable {
            let title: String?
            let url: String?
            let objectID: String
            let created_at_i: Double?
            let points: Int?
            let num_comments: Int?
        }
        let hits: [Hit]
    }

    static func hackerNews(_ q: String) async throws -> [InfoArticle] {
        guard let url = URL(string: "https://hn.algolia.com/api/v1/search_by_date?query=\(q)&tags=story&hitsPerPage=30") else { throw FetchError.badURL }
        let r = try JSONDecoder().decode(HNResponse.self, from: try await get(url))
        return r.hits.compactMap { h in
            guard let title = h.title, !title.isEmpty else { return nil }
            let link = h.url ?? "https://news.ycombinator.com/item?id=\(h.objectID)"
            let date = h.created_at_i.map { Date(timeIntervalSince1970: $0) }
            let host = URL(string: link)?.host
            return InfoArticle(title: title, link: link, source: InfoSource.hackerNews.rawValue, site: host,
                               published: date, likes: h.points)
        }
    }

    // MARK: Bluesky（公開の検索 API。public.api.bsky.app が断るときは api.bsky.app）

    private struct BskyResponse: Decodable {
        struct Post: Decodable {
            struct Author: Decodable { let handle: String; let displayName: String? }
            struct Record: Decodable { let text: String?; let createdAt: String? }
            struct Embed: Decodable {
                struct Image: Decodable { let thumb: String? }
                struct External: Decodable { let thumb: String? }
                let images: [Image]?
                let external: External?
            }
            let uri: String
            let author: Author
            let record: Record
            let embed: Embed?
            let likeCount: Int?
            let repostCount: Int?
            let indexedAt: String?
        }
        let posts: [Post]
    }

    static func bluesky(_ q: String, japanese: Bool) async throws -> [InfoArticle] {
        let query = "q=\(q)&limit=25&sort=latest" + (japanese ? "&lang=ja" : "")
        var data: Data?
        var lastError: Error = FetchError.badURL
        for host in ["public.api.bsky.app", "api.bsky.app"] {
            guard let url = URL(string: "https://\(host)/xrpc/app.bsky.feed.searchPosts?\(query)") else { continue }
            do { data = try await get(url); break } catch { lastError = error }
        }
        guard let data else { throw lastError }
        let r = try JSONDecoder().decode(BskyResponse.self, from: data)
        return r.posts.compactMap { p in
            let text = (p.record.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let rkey = p.uri.split(separator: "/").last.map(String.init) ?? ""
            let link = "https://bsky.app/profile/\(p.author.handle)/post/\(rkey)"
            let name = (p.author.displayName ?? "").isEmpty ? p.author.handle : (p.author.displayName ?? "")
            let date = InfoFeedParser.date(p.record.createdAt ?? p.indexedAt ?? "")
            let thumb = p.embed?.images?.first?.thumb ?? p.embed?.external?.thumb
            return InfoArticle(title: String(text.prefix(280)), link: link, source: InfoSource.bluesky.rawValue, site: name,
                               published: date, image: thumb, author: name, handle: p.author.handle,
                               likes: p.likeCount, reposts: p.repostCount)
        }
    }

    // MARK: Reddit（つながるときだけ。断られることが多い）

    private struct RedditResponse: Decodable {
        struct Listing: Decodable { let children: [Child] }
        struct Child: Decodable { let data: Post }
        struct Post: Decodable {
            let title: String
            let permalink: String
            let created_utc: Double?
            let subreddit_name_prefixed: String?
            let thumbnail: String?
            let over_18: Bool?
            let score: Int?
        }
        let data: Listing
    }

    static func reddit(_ q: String) async throws -> [InfoArticle] {
        guard let url = URL(string: "https://www.reddit.com/search.json?q=\(q)&sort=new&limit=25") else { throw FetchError.badURL }
        let r = try JSONDecoder().decode(RedditResponse.self, from: try await get(url))
        return r.data.children.compactMap { c in
            let p = c.data
            if p.over_18 == true { return nil }
            let thumb = (p.thumbnail ?? "").hasPrefix("http") ? p.thumbnail : nil
            return InfoArticle(title: p.title, link: "https://www.reddit.com\(p.permalink)", source: InfoSource.reddit.rawValue,
                               site: p.subreddit_name_prefixed, published: p.created_utc.map { Date(timeIntervalSince1970: $0) },
                               image: thumb, likes: p.score)
        }
    }
}

// MARK: - RSS 2.0・RSS 1.0（RDF）・Atom を読む

final class InfoFeedParser: NSObject, XMLParserDelegate {
    private let source: String
    private var items: [InfoArticle] = []
    private var inItem = false
    private var text = ""
    private var title = ""
    private var link = ""
    private var dateText = ""
    private var summary = ""
    private var image: String?
    private var site: String?
    private var feedTitle: String?

    private init(source: String) { self.source = source }

    static func parse(_ data: Data, source: String) -> [InfoArticle] {
        let delegate = InfoFeedParser(source: source)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes a: [String: String] = [:]) {
        text = ""
        switch name {
        case "item", "entry":
            inItem = true
            title = ""; link = ""; dateText = ""; summary = ""; image = nil; site = nil
        case "link" where inItem:
            // Atom は href 属性。rel が無いか alternate のものを使う
            if let href = a["href"], link.isEmpty, (a["rel"] == nil || a["rel"] == "alternate") { link = href }
        case "media:thumbnail" where inItem:
            if image == nil, let u = a["url"] { image = u }
        case "media:content" where inItem:
            if image == nil, let u = a["url"], (a["medium"] == "image" || (a["type"] ?? "").hasPrefix("image")) { image = u }
        case "enclosure" where inItem:
            if image == nil, let u = a["url"], (a["type"] ?? "").hasPrefix("image") { image = u }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        guard inItem else {
            if name == "title", feedTitle == nil { feedTitle = value }
            return
        }
        switch name {
        case "title": title = value
        case "link": if link.isEmpty && !value.isEmpty { link = value }
        case "pubDate", "dc:date", "published": dateText = value
        case "updated": if dateText.isEmpty { dateText = value }
        case "description", "summary", "content:encoded", "content":
            if summary.isEmpty || name == "description" { summary = value }
        case "source", "dc:creator": if site == nil, !value.isEmpty { site = value }
        case "hatena:imageurl": if image == nil, !value.isEmpty { image = value }
        case "item", "entry":
            inItem = false
            finishItem()
        default: break
        }
    }

    private func finishItem() {
        guard !title.isEmpty, link.hasPrefix("http") else { return }
        var t = Self.unescape(title)
        let host = URL(string: link)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let publisher = site ?? host ?? feedTitle
        // Google ニュースの見出しは末尾に「 - 媒体名」が付く
        if let s = site, t.hasSuffix(" - \(s)") { t = String(t.dropLast(s.count + 3)) }
        if image == nil { image = Self.firstImage(summary) }
        var body = Self.plain(summary)
        if body.isEmpty || body.contains(t) || t.contains(body) { body = "" }
        let article = InfoArticle(title: t, link: link, source: source, site: publisher, published: Self.date(dateText),
                                  image: image.flatMap { $0.hasPrefix("http") ? $0 : nil },
                                  summary: body.isEmpty ? nil : String(body.prefix(200)))
        items.append(article)
    }

    // MARK: 文字の整形

    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = unescape(s)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unescape(_ s: String) -> String {
        var r = s
        for (k, v) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            r = r.replacingOccurrences(of: k, with: v)
        }
        return r
    }

    static func firstImage(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "<img[^>]+src=[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: 日付（RFC 822 と ISO 8601 の両方）

    private static let rfc822: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm zzz", "dd MMM yyyy HH:mm:ss Z",
    ].map { pattern in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let d = iso.date(from: t) ?? isoFraction.date(from: t) { return d }
        for f in rfc822 { if let d = f.date(from: t) { return d } }
        return nil
    }
}
