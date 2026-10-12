import XCTest
@testable import TodoApp

// 第五人格：ランクマッチ・対戦情報・アプリの版・第五録の新着を読む部分。
// 見本の HTML・JSON はどれも、このテストのために書いた架空のもの（公式や第五録の文の写しではない）

final class IdvPlayTests: TokyoTestCase {
    // MARK: 公式の本文の期間

    private let sampleLines: [String] = [
        "2026-10-07 見本のお知らせ",
        "娯楽モード",
        "見本の期間限定モード 2V8",
        "見本の説明の文です。8人で遊べます。",
        "開放時間は2026年10月7日メンテナンス後から10月21日23:59:59まで。",
        "大会",
        "2026見本リーグ秋季大会決勝戦",
        "試合の日程は以下の通りです：",
        "10月17日（土）",
        "チームA vs チームB",
        "10月18日（日）",
        "Identity V×見本の物語コラボ",
        "見本の衣装がショップに登場",
        "見本の衣装の説明。",
        "販売期間：2026年10月7日メンテナンス後～2026年11月4日23時59分",
        "シーズン真髄",
        "見本の真髄3が開放",
        "イベント期間：2026年10月7日メンテナンス後～2026年11月18日メンテナンス前",
        "ゲームの改善",
        "見本の改善",
        "イベント期間：2026年10月1日～2026年10月30日",
    ]

    func testPeriodsFromArticleLines() {
        let p = IdvArticle.periods(lines: sampleLines, link: "https://example.com/u/1", reference: T.d(2026, 10, 6))
        XCTAssertEqual(p.count, 4, "ゲームの改善の区切りは読まない")
        let mode = p.first { $0.kind == .mode }
        XCTAssertEqual(mode?.title, "見本の期間限定モード 2V8")
        XCTAssertEqual(mode?.start, T.d(2026, 10, 7))
        XCTAssertEqual(mode?.end, T.d(2026, 10, 21))
        let cup = p.first { $0.kind == .tournament }
        XCTAssertEqual(cup?.title, "2026見本リーグ秋季大会決勝戦", "vs の行は見出しにしない")
        XCTAssertEqual(cup?.start, T.d(2026, 10, 17))
        XCTAssertEqual(cup?.end, T.d(2026, 10, 18))
        let collab = p.first { $0.kind == .collab }
        XCTAssertEqual(collab?.title, "見本の衣装がショップに登場", "コラボの見出しの下はコラボ")
        XCTAssertEqual(collab?.end, T.d(2026, 11, 4))
        XCTAssertEqual(p.first { $0.kind == .gacha }?.end, T.d(2026, 11, 18))
        XCTAssertTrue(p.allSatisfy { $0.link == "https://example.com/u/1" })
    }

    func testCurrentPeriodsSkipEndedAndDuplicates() {
        let a = IdvPeriod(kind: .mode, section: "", title: "A", start: nil, end: T.d(2026, 10, 20), link: "https://example.com/1")
        let a2 = IdvPeriod(kind: .mode, section: "", title: "A", start: nil, end: T.d(2026, 10, 25), link: "https://example.com/2")
        let old = IdvPeriod(kind: .mode, section: "", title: "B", start: nil, end: T.d(2026, 10, 1), link: "https://example.com/1")
        let soon = IdvPeriod(kind: .gacha, section: "", title: "C", start: nil, end: T.d(2026, 10, 10), link: "https://example.com/1")
        XCTAssertEqual(IdvArticle.current([a2, old, a, soon], now: T.now).map(\.title), ["C", "A"])
        XCTAssertEqual(soon.asEvent.tag, "ガチャ")
    }

    // MARK: ランクマッチ

    func testRankWindowsAndOpenNow() {
        let w = IdvRank.windows(in: "見本\nランク戦の開放時間：毎日12:00～14:00、19:00～24:00\n関係のない 10:00～11:00")
        XCTAssertEqual(w.map(\.text), ["12:00〜14:00", "19:00〜24:00"])
        let info = IdvRankInfo(windows: w)
        XCTAssertNil(info.openWindow(now: T.now), "10:00 は閉じている")
        XCTAssertEqual(info.nextOpen(now: T.now), T.d(2026, 10, 9, 12, 0))
        XCTAssertEqual(info.openWindow(now: T.d(2026, 10, 9, 20, 0))?.end, 24 * 60)
        XCTAssertEqual(info.nextOpen(now: T.d(2026, 10, 9, 15, 0)), T.d(2026, 10, 9, 19, 0))
        XCTAssertEqual(IdvRankInfo(windows: [w[0]]).nextOpen(now: T.d(2026, 10, 9, 15, 0)), T.d(2026, 10, 10, 12, 0), "今日の分が終われば明日")
    }

    func testRankWindowsUtcPlus8AndFivePlayer() {
        let w = IdvRank.windows(in: "５人ランク戦の開放時間（UTC+8）：１８：００～２３：００")
        XCTAssertEqual(w.first?.label, "5人ランク")
        XCTAssertEqual(w.first?.text, "19:00〜24:00", "UTC+8 は日本時間に1時間足す")
    }

    func testRankInfoFromOfficialArticles() {
        let new = IdvNews(title: "2026-10-07 見本", link: "https://example.com/u/2", date: T.d(2026, 10, 6), kind: .official)
        let start = IdvNews(title: "2026-09-10 見本", link: "https://example.com/u/1", date: T.d(2026, 9, 9), kind: .official)
        let articles: [String: String] = [
            "https://example.com/u/2": "見本のメンテナンス（注意：ランク戦モードはサーバー維持メンテナンスの間封鎖されます。）",
            "https://example.com/u/1": "今週のメンテナンス後に、S43が終了し、S44が始まります。\n【段位継承】：S44が開始すると、前シーズンの段位をもとに継承が行われます。二文目。\n【推理の径】：S44が開始すると、推理の径のレベルが0にリセットされます。",
        ]
        let r = IdvRank.info(updates: [start, new], articles: articles)
        XCTAssertTrue(r.closedDuringMaintenance)
        XCTAssertTrue(r.windows.isEmpty, "開放時間が書かれていなければ空（推測しない）")
        XCTAssertEqual(r.notes.count, 2)
        XCTAssertEqual(r.notes.first, "【段位継承】：S44が開始すると、前シーズンの段位をもとに継承が行われます。")
        XCTAssertEqual(r.link, "https://example.com/u/1")
    }

    // MARK: 次回のメンテナンス

    func testNextMaintenanceFromArticle() {
        let n = IdvNews(title: "2026-09-30 ゲームアップデートのお知らせ（09/30 AM 9：00実施）", link: "https://example.com/u/1",
                        date: T.d(2026, 9, 29), kind: .official)
        let articles = ["https://example.com/u/1": "見本のメンテナンス\n次回のメンテナンスは2026年10月15日午前8:00（UTC+8）になります。"]
        let items = IdvSchedule.items(news: [n], articles: articles, now: T.now)
        let next = IdvSchedule.nextMaintenanceItem(items, now: T.now)
        XCTAssertEqual(next?.start, T.d(2026, 10, 15, 9, 0))
        XCTAssertEqual(next?.hasTime, true)
        XCTAssertEqual(items.filter { $0.id.hasPrefix("next-") }.count, 1)
    }

    // MARK: App Store

    func testAppStoreLookup() {
        let json = """
        {"resultCount":1,"results":[{"version":"9.8.7","currentVersionReleaseDate":"2026-10-01T06:30:00Z",
        "releaseNotes":"——見本の不具合を修正しました。\\n——見本の表示を直しました。\\n\\n——三つ目\\n——四つ目","trackViewUrl":"https://apps.apple.com/jp/app/x/id1"}]}
        """
        let v = IdvAppStore.parse(Data(json.utf8))
        XCTAssertEqual(v?.version, "9.8.7")
        XCTAssertEqual(v?.released, T.d(2026, 10, 1, 15, 30))
        XCTAssertEqual(v?.notes, "見本の不具合を修正しました。\n見本の表示を直しました。\n三つ目", "頭の3行だけ")
        XCTAssertEqual(v?.url, "https://apps.apple.com/jp/app/x/id1")
        XCTAssertNil(IdvAppStore.parse(Data("{\"resultCount\":0,\"results\":[]}".utf8)))
        XCTAssertNil(IdvAppStore.parse(Data("not json".utf8)))
    }

    // MARK: 第五録（見出しと日付だけ）

    func testDaigorokuListingHeadlinesOnly() throws {
        let html = """
        <html><body><section>
        <div id="list">
          <article class="update-item">
            <h3>2026.10.7現在</h3>
            <img src="../images/x.jpeg" alt="見本の画像" />
            <h2>見本の見出し<span>その1</span></h2>
            <p>この本文は取り込まれてはいけない文です。</p>
            <a href="../detail/one.html">詳しくはこちら</a>
            <h2>見本の見出し &amp; その2</h2>
            <p>本文その2</p>
            <a href="https://other.example.com/x.html">外のサイト</a>
          </article>
          <article class="update-item">
            <h3>2026.9.30現在</h3>
            <h2>見本の見出しその3</h2>
          </article>
        </div></section></body></html>
        """
        let base = try XCTUnwrap(URL(string: "https://daigoroku.com/honntai/saisinn/saisinn.html"))
        let h = IdvDaigoroku.parseListing(html, base: base)
        XCTAssertEqual(h.map(\.title), ["見本の見出しその1", "見本の見出し & その2", "見本の見出しその3"])
        XCTAssertEqual(h[0].date, T.d(2026, 10, 7))
        XCTAssertEqual(h[2].date, T.d(2026, 9, 30))
        XCTAssertEqual(h[0].link, "https://daigoroku.com/honntai/detail/one.html", "相対リンクはサイトの中で解決")
        XCTAssertEqual(h[1].link, base.absoluteString, "外のサイトのリンクは使わず一覧を開く")
        let all = h.map { "\($0.title) \($0.link)" }.joined()
        XCTAssertFalse(all.contains("本文"), "本文は残さない")
        XCTAssertFalse(all.contains("jpeg"), "画像は残さない")
        XCTAssertEqual(IdvDaigoroku.parseListing(html, base: base, limit: 2).count, 2)
    }

    func testDaigorokuInterval() {
        XCTAssertTrue(IdvDaigoroku.due(lastFetch: nil, now: T.now))
        XCTAssertFalse(IdvDaigoroku.due(lastFetch: T.now.addingTimeInterval(-3 * 3600), now: T.now), "数時間に1回まで")
        XCTAssertTrue(IdvDaigoroku.due(lastFetch: T.now.addingTimeInterval(-7 * 3600), now: T.now))
    }

    // MARK: 取得の時刻・残り時間

    func testFreshLabel() {
        XCTAssertEqual(IdvFresh.label("公式", T.now.addingTimeInterval(-3 * 3600 - 60), now: T.now), "公式・3時間前")
        XCTAssertEqual(IdvFresh.label("第五録", T.now.addingTimeInterval(-26 * 3600), now: T.now), "第五録・1日前")
        XCTAssertEqual(IdvFresh.label("App Store", nil, failed: true, now: T.now), "App Store・未取得・更新できませんでした")
        XCTAssertEqual(IdvFresh.ago(T.now.addingTimeInterval(-90), now: T.now), "1分前")
    }

    func testCountdown() {
        XCTAssertEqual(IdvCountdown.text(end: T.d(2026, 10, 9), now: T.now), "残り14時間")
        XCTAssertEqual(IdvCountdown.text(end: T.d(2026, 10, 10), now: T.now), "残り1日")
        XCTAssertEqual(IdvCountdown.text(end: T.d(2026, 10, 12), now: T.now), "あと3日")
        XCTAssertEqual(IdvCountdown.text(end: T.d(2026, 10, 8), now: T.now), "終了")
        XCTAssertTrue(IdvCountdown.isLastDay(end: T.d(2026, 10, 10), now: T.now))
        XCTAssertFalse(IdvCountdown.isLastDay(end: T.d(2026, 10, 11), now: T.now))
    }

    // MARK: 大会の配信

    func testBroadcastsFromOfficialVideos() {
        let v1 = IdvNews(title: "【見本】IJL 秋季大会 Day1 生配信", link: "https://www.youtube.com/watch?v=a", date: T.now, kind: .video)
        let v2 = IdvNews(title: "見本の新衣装", link: "https://www.youtube.com/watch?v=b", date: T.now, kind: .video)
        let p = IdvNews(title: "見本 大会のお知らせ", link: "https://example.com/p", date: T.now, kind: .press)
        XCTAssertEqual(IdvMatches.broadcasts([v1, v2, p]).map(\.link), ["https://www.youtube.com/watch?v=a"])
    }

    // MARK: 通知

    func testPlanIncludesOfficialGachaLastDay() {
        let gacha = IdvPeriod(kind: .gacha, section: "シーズン真髄", title: "見本の真髄", start: nil, end: T.d(2026, 10, 20), link: "https://example.com/1")
        let mode = IdvPeriod(kind: .mode, section: "娯楽モード", title: "見本のモード", start: nil, end: T.d(2026, 10, 20), link: "https://example.com/1")
        let p = IdvReminder.plan(events: [], periods: [gacha, mode], schedule: [], season: nil, now: T.now)
        XCTAssertEqual(p.count, 1, "モードは通知しない")
        XCTAssertEqual(p.first?.at, T.d(2026, 10, 19, 19, 0))
        XCTAssertEqual(p.first?.title, "残り1日：見本の真髄")
        XCTAssertTrue(p.allSatisfy { $0.id.hasPrefix("idv-") })
    }
}
