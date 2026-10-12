import XCTest
@testable import TodoApp

// 第五人格：予定（メンテナンス・アップデート）・コラボ/ガチャ・ランクマッチのシーズンを読む部分。
// 題名や本文は、公式の書き方に似せた架空のもの

final class IdvScheduleTests: TokyoTestCase {
    // MARK: 日時

    func testOfficialTitleWithAmTime() {
        let w = IdvSchedule.when(in: "2026-10-14 ゲームアップデートのお知らせ（10/14 AM 9：00実施）", reference: T.d(2026, 10, 13))
        XCTAssertEqual(w?.start, T.d(2026, 10, 14, 9, 0))
        XCTAssertEqual(w?.hasTime, true)
        XCTAssertNil(w?.end)
    }

    func testUtcPlus8AndDuration() {
        let text = "見本の告知\n『見本』は2026年10月15日8:00（UTC+8）にサーバーメンテナンスを行います。所要時間は240分を予定しております。"
        let w = IdvSchedule.when(in: text, reference: T.now)
        XCTAssertEqual(w?.start, T.d(2026, 10, 15, 9, 0), "UTC+8 の 8:00 は日本時間の 9:00")
        XCTAssertEqual(w?.end, T.d(2026, 10, 15, 13, 0))
    }

    func testTimeRangeWithWeekdayAndFullWidth() {
        let w = IdvSchedule.when(in: "臨時メンテナンスのお知らせ　日時：１０月２０日（火）１１：００～１５：３０", reference: T.now)
        XCTAssertEqual(w?.start, T.d(2026, 10, 20, 11, 0))
        XCTAssertEqual(w?.end, T.d(2026, 10, 20, 15, 30))
    }

    func testJapaneseHourAndPm() {
        XCTAssertEqual(IdvSchedule.when(in: "メンテナンス 10月21日 14時30分から", reference: T.now)?.start, T.d(2026, 10, 21, 14, 30))
        XCTAssertEqual(IdvSchedule.when(in: "アップデート 10/22 PM 3:00", reference: T.now)?.start, T.d(2026, 10, 22, 15, 0))
    }

    func testDateOnlyIsAllDay() {
        let w = IdvSchedule.when(in: "バージョン更新は10月28日を予定", reference: T.now)
        XCTAssertEqual(w?.start, T.d(2026, 10, 28))
        XCTAssertEqual(w?.hasTime, false)
        XCTAssertNil(IdvSchedule.when(in: "新衣装の紹介", reference: T.now))
    }

    // MARK: 予定の一覧

    func testItemsFromNewsAndArticles() {
        let official = IdvNews(title: "2026-10-14 ゲームアップデートのお知らせ（10/14 AM 9：00実施）", link: "https://example.com/u/1",
                               date: T.d(2026, 10, 13), kind: .official)
        let past = IdvNews(title: "2026-10-07 ゲームアップデートのお知らせ（10/07 AM 9：00実施）", link: "https://example.com/u/0",
                           date: T.d(2026, 10, 6), kind: .official)
        let press = IdvNews(title: "『見本』メンテナンスのお知らせ", link: "https://example.com/p/1", date: T.d(2026, 10, 8), kind: .press,
                            summary: "見本の説明。日時：10月16日（金）10:00～12:00")
        let other = IdvNews(title: "見本の新衣装", link: "https://example.com/p/2", date: T.d(2026, 10, 8), kind: .press)
        let articles = ["https://example.com/u/1": "サーバーメンテナンスを行います。所要時間は240分"]
        let items = IdvSchedule.items(news: [past, official, press, other], articles: articles, now: T.now)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].start, T.d(2026, 10, 14, 9, 0), "これからのものが近い順に先")
        XCTAssertEqual(items[0].kind, .maintenance, "本文にメンテナンスとあれば公式のお知らせもメンテナンス")
        XCTAssertEqual(items[0].end, T.d(2026, 10, 14, 13, 0))
        XCTAssertEqual(items[0].title, "ゲームアップデートのお知らせ（10/14 AM 9：00実施）", "頭の日付は外す")
        XCTAssertEqual(items[1].start, T.d(2026, 10, 16, 10, 0))
        XCTAssertEqual(items[1].kind, .maintenance)
        XCTAssertEqual(items[2].start, T.d(2026, 10, 7, 9, 0), "終わったものは後ろ")
        XCTAssertEqual(items[2].kind, .update, "本文を読んでいなければアップデート")
        XCTAssertTrue(items[2].isPast(now: T.now))
        XCTAssertFalse(items[0].isPast(now: T.now))
    }

    func testScheduleLabel() {
        let s = IdvScheduleItem(id: "a", kind: .maintenance, title: "x", start: T.d(2026, 10, 14, 9, 0), end: T.d(2026, 10, 14, 13, 0),
                                hasTime: true, link: nil)
        XCTAssertEqual(IdvSchedule.label(s), "10月14日（水） 09:00〜13:00")
    }

    // MARK: 通知

    func testPlanMaintenanceAndSeason() {
        let m = IdvScheduleItem(id: "a", kind: .maintenance, title: "定期メンテナンス", start: T.d(2026, 10, 14, 9, 0), end: nil,
                                hasTime: true, link: nil)
        let u = IdvScheduleItem(id: "b", kind: .update, title: "更新", start: T.d(2026, 10, 15, 9, 0), end: nil, hasTime: true, link: nil)
        let allDay = IdvScheduleItem(id: "c", kind: .maintenance, title: "x", start: T.d(2026, 10, 16), end: nil, hasTime: false, link: nil)
        let season = IdvSeason(number: 44, name: "シーズン44", start: T.d(2026, 9, 10), end: T.d(2026, 11, 12), source: "見本", link: nil)
        let p = IdvReminder.plan(events: [], schedule: [m, u, allDay], season: season, now: T.now)
        XCTAssertEqual(p.map(\.at), [T.d(2026, 10, 13, 19, 0), T.d(2026, 10, 15, 19, 0), T.d(2026, 11, 9, 19, 0)],
                       "メンテナンスは前の日の夜、シーズンは終了の3日前")
        XCTAssertTrue(p.allSatisfy { $0.id.hasPrefix("idv-") })
        XCTAssertEqual(p[0].title, "明日はメンテナンス")
        XCTAssertEqual(p[2].title, "ランクマ シーズン44 終了まであと3日")
    }

    // MARK: コラボ・ガチャ

    func testCollabTags() {
        XCTAssertEqual(IdvCollab.tag("『見本』×『架空の物語』コラボ開催！"), "コラボ")
        XCTAssertEqual(IdvCollab.tag("復刻ガチャのお知らせ"), "ガチャ")
        XCTAssertEqual(IdvCollab.tag("S44・真髄2 ミニストーリー"), "ガチャ")
        XCTAssertEqual(IdvCollab.tag("推理の径 新しい報酬"), "ガチャ")
        XCTAssertNil(IdvCollab.tag("新衣装の紹介"))
    }

    func testCollabLabels() {
        XCTAssertEqual(IdvCollab.label(start: T.d(2026, 10, 15), end: T.d(2026, 10, 31), now: T.now), "開始まであと6日")
        XCTAssertEqual(IdvCollab.label(start: T.d(2026, 10, 1), end: T.d(2026, 10, 19), now: T.now), "終了まであと10日")
        XCTAssertEqual(IdvCollab.label(start: nil, end: T.d(2026, 10, 9, 23, 0), now: T.now), "今日で終了")
    }

    func testCandidatesFromSummaryAndArticle() {
        let fromTitle = IdvNews(title: "『見本』コラボが10/15～10/31に開催", link: "https://example.com/a", date: T.now, kind: .press)
        let fromSummary = IdvNews(title: "復刻ガチャのお知らせ", link: "https://example.com/b", date: T.now, kind: .press,
                                  summary: "2026年10月1日発表。開催期間：10月10日メンテナンス後～10月24日23:59")
        let fromArticle = IdvNews(title: "『見本』×『架空の物語』コラボ開催！", link: "https://example.com/c", date: T.now, kind: .press)
        let articles = ["https://example.com/c": "2026年10月9日 10時00分\nコラボイベント（開催期間：2026年10月22日メンテナンス後～2026年11月19日23:59）"]
        let c = IdvDates.candidates([fromTitle, fromSummary, fromArticle], articles: articles, now: T.now)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].tag, "コラボ")
        XCTAssertEqual(c[0].start, T.d(2026, 10, 15))
        XCTAssertEqual(IdvCollab.label(start: c[0].start, end: c[0].end, now: T.now), "開始まであと6日")
        XCTAssertEqual(c[1].tag, "ガチャ")
        XCTAssertEqual(c[1].start, T.d(2026, 10, 10), "説明文の「期間」より後ろから探す（発表日は使わない）")
        XCTAssertEqual(c[1].end, T.d(2026, 10, 24))
        XCTAssertEqual(c[2].start, T.d(2026, 10, 22))
        XCTAssertEqual(c[2].end, T.d(2026, 11, 19))
    }

    func testKaraRangeAndNotDuration() {
        XCTAssertEqual(IdvDates.range(in: "9月19日（土）から30日（水）まで", reference: T.d(2026, 9, 10))?.end, T.d(2026, 9, 30))
        XCTAssertNil(IdvDates.range(in: "10月8日から2日間の開催", reference: T.now)?.start, "「2日間」は終わりの日ではない")
    }

    // MARK: シーズン

    func testSeasonNumberFromTitles() {
        XCTAssertEqual(IdvSeasonParser.number(in: "S44・真髄2衣装 ゲーム内展示【見本】"), 44)
        XCTAssertEqual(IdvSeasonParser.number(in: "ランクマッチ シーズン４５ 開幕"), 45)
        XCTAssertEqual(IdvSeasonParser.number(in: "第46シーズンのお知らせ"), 46)
        XCTAssertNil(IdvSeasonParser.number(in: "S0シーズン暗喩専用のパッシブ"), "1桁の S0 は数えない")
        XCTAssertNil(IdvSeasonParser.number(in: "SSR衣装の紹介"))
    }

    func testSeasonFromOfficialUpdates() {
        let startNote = IdvNews(title: "2026-09-10 ゲームアップデートのお知らせ（09/10 AM 9：00実施）", link: "https://example.com/u/start",
                                date: T.d(2026, 9, 9), kind: .official)
        let otherNote = IdvNews(title: "2026-10-08 ゲームアップデートのお知らせ（10/08 AM 9：00実施）", link: "https://example.com/u/mid",
                                date: T.d(2026, 10, 7), kind: .official)
        let articles = [
            "https://example.com/u/start": "新シーズン\n今週のメンテナンス後に、S43が終了し、S44が始まります。また、シーズンラストスパートイベントも終了します。\n【シーズン真髄】：今週よりS44・真髄1\n販売期間：2026年9月10日メンテナンス後～2026年11月19日メンテナンス前",
            "https://example.com/u/mid": "イベント期間：2026年10月8日メンテナンス後～2026年10月21日23時59分",
        ]
        let s = IdvSeasonParser.resolve(updates: [otherNote, startNote], articles: articles, news: [], now: T.now)
        XCTAssertEqual(s?.number, 44)
        XCTAssertEqual(s?.title, "シーズン44")
        XCTAssertEqual(s?.start, T.d(2026, 9, 10, 9, 0))
        XCTAssertNil(s?.end, "ラストスパートの期間がまだ出ていなければ終わりは分からない（推定しない）")
        XCTAssertNil(s?.progress(now: T.now))

        // 終わる前の週：「シーズンラストスパートイベント」の期間の終わりがシーズンの終わり
        let lastNote = IdvNews(title: "2026-11-05 ゲームアップデートのお知らせ（11/05 AM 9：00実施）", link: "https://example.com/u/last",
                               date: T.d(2026, 11, 4), kind: .official)
        var more = articles
        more["https://example.com/u/last"] = "シーズンラストスパートイベント\n2026年11月5日メンテナンス後から2026年11月12日メンテナンス前まで、週間の推理点数の上限が上昇します。"
        let s2 = IdvSeasonParser.resolve(updates: [lastNote, otherNote, startNote], articles: more, news: [], now: T.d(2026, 11, 6))
        XCTAssertEqual(s2?.number, 44)
        XCTAssertEqual(s2?.end, T.d(2026, 11, 12))
        XCTAssertNotNil(s2?.progress(now: T.d(2026, 11, 6)))
    }

    func testSeasonFromTitlesOnlyOrNothing() {
        let v = IdvNews(title: "S44・真髄2 ミニストーリー動画【見本】", link: "https://example.com/v", date: T.d(2026, 10, 1), kind: .video)
        let s = IdvSeasonParser.resolve(updates: [], articles: [:], news: [v], now: T.now)
        XCTAssertEqual(s?.number, 44)
        XCTAssertNil(s?.start)
        XCTAssertNil(s?.end)

        let r = IdvNews(title: "ランクマッチ シーズン45 10月15日～12月17日", link: "https://example.com/r", date: T.now, kind: .press)
        let s2 = IdvSeasonParser.resolve(updates: [], articles: [:], news: [r], now: T.now)
        XCTAssertEqual(s2?.number, 45)
        XCTAssertEqual(s2?.start, T.d(2026, 10, 15))
        XCTAssertEqual(s2?.end, T.d(2026, 12, 17))

        let none = IdvNews(title: "新衣装の紹介", link: "https://example.com/n", date: T.now, kind: .video)
        XCTAssertNil(IdvSeasonParser.resolve(updates: [], articles: [:], news: [none], now: T.now), "見つからなければ nil（カードは「見つかりませんでした」）")
    }

    func testOverride() {
        var o = IdvSeasonOverride()
        XCTAssertNil(o.season)
        o.enabled = true
        o.name = "シーズン44"
        o.start = T.d(2026, 9, 10)
        o.end = T.d(2026, 11, 12)
        XCTAssertEqual(o.season?.number, 44)
        XCTAssertEqual(o.season?.end, T.d(2026, 11, 12))
    }

    // MARK: 公式サイトの一覧・本文

    func testParseOfficialList() {
        let html = """
        <ul><li><a href="https://idv.163.com/jp/news/update/20261013/1_1.html" class="newsItem" target="_blank" title="2026-10-14 ゲームアップデートのお知らせ（10/14 AM 9：00実施）"><span>x</span></a></li>
        <li><a href="https://idv.163.com/jp/news/update/20261013/1_1.html" title="2026-10-14 ゲームアップデートのお知らせ（10/14 AM 9：00実施）"></a></li>
        <li><a href="https://evil.example.com/jp/news/update/20261013/2.html" title="ほか"></a></li></ul>
        """
        let list = IdvOfficial.parseList(html)
        XCTAssertEqual(list.count, 1, "同じリンクは1つ、ほかのサイトは読まない")
        XCTAssertEqual(list.first?.kind, .official)
        XCTAssertEqual(list.first?.date, T.d(2026, 10, 13))
    }

    func testArticleTextKeepsDatedLines() {
        let html = """
        <html><head><style>.a{color:red}</style><script>var x = "10月1日";</script></head>
        <body><p>こんにちは</p><p>&nbsp;『見本』は2026年10月15日8:00（UTC+8）にサーバーメンテナンスを行います。</p>
        <div>新シーズン</div><div>関係のない行</div></body></html>
        """
        let t = IdvOfficial.text(fromHTML: html)
        XCTAssertTrue(t.contains("2026年10月15日8:00（UTC+8）"))
        XCTAssertTrue(t.contains("新シーズン"))
        XCTAssertFalse(t.contains("こんにちは"))
        XCTAssertFalse(t.contains("var x"))
    }

    func testArticlesToFetchLimit() {
        var news: [IdvNews] = (0..<8).map { i in
            IdvNews(title: "2026-10-0\(i) ゲームアップデートのお知らせ", link: "https://example.com/u/\(i)",
                    date: T.d(2026, 10, 1).addingTimeInterval(Double(i) * 3600), kind: .official)
        }
        news.append(IdvNews(title: "『見本』コラボ開催！", link: "https://example.com/p/1", date: T.now, kind: .press))
        news.append(IdvNews(title: "『見本』コラボ 10/15～10/31", link: "https://example.com/p/2", date: T.now, kind: .press))
        news.append(IdvNews(title: "見本の動画", link: "https://example.com/v/1", date: T.now, kind: .video))
        let pick = IdvOfficial.articlesToFetch(news: news, cached: ["https://example.com/u/7"])
        XCTAssertEqual(pick.count, 5)
        XCTAssertTrue(pick.contains { $0.link == "https://example.com/p/1" }, "期間の分からないコラボは本文を読む")
        XCTAssertFalse(pick.contains { $0.link == "https://example.com/p/2" }, "題名に期間があれば読まない")
        XCTAssertFalse(pick.contains { $0.link == "https://example.com/u/7" }, "読んだものは読まない")
        XCTAssertFalse(pick.contains { $0.kind == .video })
    }
}
