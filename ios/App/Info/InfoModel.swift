import Foundation
import NaturalLanguage
import SwiftUI

/// 話題の一覧で選んでいるもの
enum InfoFilter: Hashable {
    case all
    case recommend
    case topic(String)
    case saved
}

/// 「情報」タブの状態。保存は InfoData（info-*.json）
@MainActor
final class InfoModel: ObservableObject {
    @Published var topics: [InfoTopic] = []
    @Published var cache: [String: InfoFeedCache] = [:]
    @Published var readIDs: Set<String> = []
    @Published var saved: [InfoArticle] = []
    @Published var prefs = InfoPrefs()
    @Published var translations: [String: String] = [:]
    @Published var showOriginal: Set<String> = []
    @Published var loading = false
    @Published var offline = false            // 前回の更新でどこにもつながらなかった
    @Published var translationUnavailable = false
    @Published var translateRequest = 0        // 増えると翻訳を始める（画面側の translationTask が見る）

    let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    init() {
        if isDemo {
            topics = InfoDemo.topics
            let all = InfoDemo.articles()
            var c: [String: InfoFeedCache] = [:]
            for (key, items) in Dictionary(grouping: all, by: \.feedKey) {
                c[key + "|demo"] = InfoFeedCache(fetchedAt: InfoDemo.fixedNow, items: items)
            }
            cache = c
            translations = InfoDemo.translations
            prefs = InfoDemo.prefs
            saved = [all[2]]
        } else {
            topics = InfoData.load([InfoTopic].self, InfoData.topicsFile) ?? []
            cache = InfoData.load([String: InfoFeedCache].self, InfoData.cacheFile) ?? [:]
            readIDs = Set(InfoData.load([String].self, InfoData.readFile) ?? [])
            saved = InfoData.load([InfoArticle].self, InfoData.savedFile) ?? []
            prefs = InfoData.load(InfoPrefs.self, InfoData.prefsFile) ?? InfoPrefs()
            translations = InfoData.load([String: String].self, InfoData.translationsFile) ?? [:]
        }
    }

    // MARK: 記事の集まり

    var lastUpdated: Date? { cache.values.map(\.fetchedAt).max() }

    private func items(forKey key: String) -> [InfoArticle] {
        cache.filter { $0.key.hasPrefix(key + "|") }.flatMap(\.value.items)
    }

    private func dedup(_ list: [InfoArticle]) -> [InfoArticle] {
        var seen = Set<String>()
        var titles = Set<String>()
        return list.filter { a in
            let t = a.title.lowercased()
            guard !seen.contains(a.id), !titles.contains(t) else { return false }
            seen.insert(a.id); titles.insert(t)
            return true
        }
    }

    private func newestFirst(_ list: [InfoArticle]) -> [InfoArticle] {
        list.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
    }

    func articles(topic: InfoTopic) -> [InfoArticle] { newestFirst(dedup(items(forKey: topic.id))) }

    var topicArticles: [InfoArticle] { newestFirst(dedup(topics.flatMap { items(forKey: $0.id) })) }

    func unreadCount(_ topic: InfoTopic) -> Int { articles(topic: topic).filter { !readIDs.contains($0.id) }.count }

    /// 一覧に出すもの（既読も含む）
    func list(_ filter: InfoFilter) -> [InfoArticle] {
        switch filter {
        case .all: return topicArticles
        case .recommend: return recommended.map(\.article)
        case .topic(let id): return topics.first { $0.id == id }.map(articles(topic:)) ?? []
        case .saved: return saved
        }
    }

    /// カードの山に出すもの（未読だけ）
    func deck(_ filter: InfoFilter) -> [InfoArticle] {
        if filter == .saved { return saved }
        return list(filter).filter { !readIDs.contains($0.id) }
    }

    func topic(for a: InfoArticle) -> InfoTopic? { topics.first { $0.id == a.feedKey } }

    func isSaved(_ a: InfoArticle) -> Bool { saved.contains { $0.id == a.id } }

    // MARK: 操作

    func markRead(_ a: InfoArticle) {
        readIDs.insert(a.id)
        learn(a, weight: -0.3)
        persistRead()
    }

    func markUnread(_ a: InfoArticle) {
        readIDs.remove(a.id)
        persistRead()
    }

    func save(_ a: InfoArticle) {
        if !isSaved(a) { saved.insert(a, at: 0) }
        readIDs.insert(a.id)
        learn(a, weight: 1.0)
        persistRead()
        persistSaved()
    }

    func unsave(_ a: InfoArticle) {
        saved.removeAll { $0.id == a.id }
        persistSaved()
    }

    func opened(_ a: InfoArticle) {
        readIDs.insert(a.id)
        learn(a, weight: 1.5)
        persistRead()
    }

    /// 開いていた時間（長く読んだものほど好みに近い）
    func dwell(_ a: InfoArticle, seconds: TimeInterval) {
        if seconds >= 30 { learn(a, weight: min(2, seconds / 60)) }
    }

    func toggleOriginal(_ a: InfoArticle) {
        if showOriginal.contains(a.id) { showOriginal.remove(a.id) } else { showOriginal.insert(a.id) }
    }

    /// 表示する見出し（翻訳があれば日本語）
    func title(_ a: InfoArticle) -> String {
        if !showOriginal.contains(a.id), let t = translations[a.id] { return t }
        return a.title
    }

    func isTranslated(_ a: InfoArticle) -> Bool { translations[a.id] != nil && !showOriginal.contains(a.id) }

    // MARK: 話題の追加・編集

    func upsert(_ t: InfoTopic) {
        let isNew = !topics.contains { $0.id == t.id }
        if let i = topics.firstIndex(where: { $0.id == t.id }) {
            if topics[i].keyword != t.keyword || topics[i].sourceIDs != t.sourceIDs {
                cache = cache.filter { !$0.key.hasPrefix(t.id + "|") }
            }
            topics[i] = t
        } else {
            topics.append(t)
        }
        persistTopics()
        if isNew || cache.keys.allSatisfy({ !$0.hasPrefix(t.id + "|") }) { Task { await refresh(only: t) } }
    }

    func delete(_ t: InfoTopic) {
        topics.removeAll { $0.id == t.id }
        cache = cache.filter { !$0.key.hasPrefix(t.id + "|") }
        persistTopics()
        persistCache()
    }

    func move(from: IndexSet, to: Int) {
        topics.move(fromOffsets: from, toOffset: to)
        persistTopics()
    }

    // MARK: 更新

    /// 30分以上たっていたら取り直す
    func refreshIfStale() async {
        guard !isDemo else { return }
        if let last = lastUpdated, Date().timeIntervalSince(last) < 30 * 60 { return }
        await refresh()
    }

    func refresh(only: InfoTopic? = nil) async {
        guard !isDemo, !loading else { return }
        loading = true
        defer { loading = false }
        var jobs: [InfoJob] = []
        for t in (only.map { [$0] } ?? topics) {
            for s in t.sources { jobs.append(InfoJob(key: t.id, source: s, keyword: t.keyword)) }
        }
        if only == nil { jobs += [InfoJob(key: "_hot", source: nil, keyword: ""), InfoJob(key: "_top", source: nil, keyword: "")] }
        let results: [(String, [InfoArticle]?)] = await withTaskGroup(of: (String, [InfoArticle]?).self) { group in
            for job in jobs {
                group.addTask {
                    let key = job.key + "|" + (job.source?.rawValue ?? "general")
                    do {
                        let items: [InfoArticle]
                        if let s = job.source {
                            items = try await InfoFetcher.search(s, keyword: job.keyword, feedKey: job.key)
                        } else {
                            items = try await InfoFetcher.general(job.key)
                        }
                        return (key, Array(items.prefix(40)))
                    } catch {
                        return (key, nil)
                    }
                }
            }
            var out: [(String, [InfoArticle]?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var ok = 0
        for (key, items) in results {
            if let items {
                cache[key] = InfoFeedCache(fetchedAt: .now, items: items)
                ok += 1
            } else if var old = cache[key] {
                old.failed = true
                cache[key] = old
            }
        }
        offline = !results.isEmpty && ok == 0
        pruneRead()
        persistCache()
        requestTranslation()
    }

    // MARK: 翻訳（端末の翻訳機能。iOS 18 以降）

    /// 翻訳がまだの外国語の見出し
    var pendingTranslations: [InfoArticle] {
        let all = topicArticles + items(forKey: "_hot") + items(forKey: "_top") + saved
        return Array(dedup(all).filter { $0.isForeign && translations[$0.id] == nil }.prefix(60))
    }

    func requestTranslation() {
        guard !isDemo, !pendingTranslations.isEmpty else { return }
        translateRequest += 1
    }

    func applyTranslations(_ result: [String: String]) {
        for (k, v) in result where !v.isEmpty { translations[k] = v }
        // 古いものから消して、多くなりすぎないようにする
        if translations.count > 600 {
            let keep = Set((topicArticles + saved).map(\.id))
            translations = translations.filter { keep.contains($0.key) }
        }
        InfoData.write(translations, InfoData.translationsFile)
    }

    // MARK: おすすめ（端末の中だけで学ぶ）

    struct Pick: Identifiable {
        let article: InfoArticle
        let score: Double
        let reason: String
        var id: String { article.id }
    }

    private var tokenMemo: [String: [String]] = [:]

    private func words(_ a: InfoArticle) -> [String] {
        if let w = tokenMemo[a.id] { return w }
        let w = Self.tokens(translations[a.id] ?? a.title)
        tokenMemo[a.id] = w
        return w
    }

    static func tokens(_ s: String) -> [String] {
        let tk = NLTokenizer(unit: .word)
        tk.string = s
        var out: [String] = []
        tk.enumerateTokens(in: s.startIndex..<s.endIndex) { range, _ in
            let w = s[range].lowercased()
            if w.count >= 2, w.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) { out.append(w) }
            return out.count < 30
        }
        return out
    }

    private func learn(_ a: InfoArticle, weight: Double) {
        guard !isDemo else { return }
        var words = Set(self.words(a))
        if let t = topic(for: a) { words.insert(t.keyword.lowercased()) }
        for w in words { prefs.tokens[w, default: 0] += weight * 0.5 }
        prefs.sources[a.source, default: 0] += weight * 0.2
        // 弱い言葉は減らし、数を抑える
        if prefs.tokens.count > 400 {
            let sorted = prefs.tokens.sorted { abs($0.value) > abs($1.value) }
            prefs.tokens = Dictionary(uniqueKeysWithValues: sorted.prefix(300).map { ($0.key, $0.value) })
        }
        prefs.updatedAt = .now
        InfoData.write(prefs, InfoData.prefsFile)
    }

    var recommended: [Pick] {
        let pool = dedup(topicArticles + items(forKey: "_hot") + items(forKey: "_top"))
        let now = Date()
        let picks: [Pick] = pool.map { a in
            var best: (String, Double)? = nil
            var score = 0.0
            for w in Set(words(a)) {
                let v = prefs.tokens[w] ?? 0
                score += v
                if v > (best?.1 ?? 0.4) { best = (w, v) }
            }
            if let t = topic(for: a) {
                let v = prefs.tokens[t.keyword.lowercased()] ?? 0
                score += 0.5 + v
                if v > (best?.1 ?? 0.4) { best = (t.keyword, v) }
            }
            let sv = prefs.sources[a.source] ?? 0
            score += sv
            let hours = now.timeIntervalSince(a.published ?? now) / 3600
            score += max(0, 1.5 - hours / 24)  // 新しいものを少し上に
            let reason: String
            if let b = best {
                reason = "「\(b.0)」の記事をよく読むので"
            } else if sv > 0.5 {
                reason = "\(a.sourceName)をよく開くので"
            } else if a.feedKey == "_hot" {
                reason = "いま話題の記事"
            } else if a.feedKey == "_top" {
                reason = "今日の主要ニュース"
            } else {
                reason = "登録した話題の新着"
            }
            return Pick(article: a, score: score, reason: reason)
        }
        return picks.sorted { $0.score > $1.score }
    }

    func resetPrefs() {
        prefs = InfoPrefs()
        if !isDemo { InfoData.write(prefs, InfoData.prefsFile) }
    }

    // MARK: 保存

    /// 既読の記録は、今ある記事とあとで読むの分だけ残す
    private func pruneRead() {
        guard readIDs.count > 1500 else { return }
        let keep = Set(cache.values.flatMap(\.items).map(\.id) + saved.map(\.id))
        readIDs = readIDs.intersection(keep)
        persistRead()
    }

    private func persistTopics() { if !isDemo { InfoData.write(topics, InfoData.topicsFile) } }
    private func persistCache() { if !isDemo { InfoData.write(cache, InfoData.cacheFile) } }
    private func persistRead() { if !isDemo { InfoData.write(Array(readIDs), InfoData.readFile) } }
    private func persistSaved() { if !isDemo { InfoData.write(saved, InfoData.savedFile) } }
}

/// 1つの取得の仕事（話題 × 元。おすすめ用は source が nil）
struct InfoJob: Sendable {
    let key: String
    let source: InfoSource?
    let keyword: String
}
