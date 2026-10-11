import XCTest
@testable import TodoApp

/// リリース4 の情報タブ：Discord のサーバーウィジェット・第五人格のお知らせ・1日1枚。見本はすべて架空のもの
final class DiscordWidgetTests: TokyoTestCase {
    private let sample = """
    {"id":"100000000000000001","name":"テストサーバー","instant_invite":"https://discord.com/invite/abcdef",
     "channels":[{"id":"200","name":"雑談","position":0},{"id":"201","name":"ナワバリ部屋","position":1},{"id":"202","name":"空き部屋","position":2}],
     "members":[
       {"id":"0","username":"いちご","discriminator":"0000","avatar":null,"status":"online","avatar_url":"https://cdn.discordapp.com/widget-avatars/x/y","channel_id":"201","self_mute":true,"game":{"name":"スプラトゥーン3"}},
       {"id":"1","username":"みかん","discriminator":"0000","avatar":null,"status":"idle","avatar_url":"https://cdn.discordapp.com/widget-avatars/x/z","channel_id":"201"},
       {"id":"2","username":"ぶどう","discriminator":"0000","avatar":null,"status":"dnd","avatar_url":"https://cdn.discordapp.com/widget-avatars/x/w","channel_id":"200"},
       {"id":"3","username":"もも","discriminator":"0000","avatar":null,"status":"online","avatar_url":"https://cdn.discordapp.com/widget-avatars/x/v"}
     ],
     "presence_count":4}
    """

    func testDecodeWidget() throws {
        let w = try DiscordWidget.decode(Data(sample.utf8))
        XCTAssertEqual(w.name, "テストサーバー")
        XCTAssertEqual(w.presenceCount, 4)
        XCTAssertEqual(w.members.count, 4)
        XCTAssertEqual(w.inviteURL?.absoluteString, "https://discord.com/invite/abcdef")
        XCTAssertEqual(w.members[0].game?.name, "スプラトゥーン3")
        XCTAssertEqual(w.members[0].selfMute, true)
    }

    func testVoiceGroupsSortedByCount() throws {
        let w = try DiscordWidget.decode(Data(sample.utf8))
        let g = w.voiceGroups
        XCTAssertEqual(g.map(\.channel.name), ["ナワバリ部屋", "雑談"])   // 空き部屋は出さない
        XCTAssertEqual(g.first?.members.count, 2)
    }

    func testDecodeWithoutInviteAndMissingFields() throws {
        let json = #"{"id":"100000000000000002","name":"小さな部屋","instant_invite":null,"channels":[],"members":[]}"#
        let w = try DiscordWidget.decode(Data(json.utf8))
        XCTAssertNil(w.inviteURL)
        XCTAssertEqual(w.presenceCount, 0)
        XCTAssertTrue(w.voiceGroups.isEmpty)
    }

    func testInviteMustBeHTTPS() throws {
        let json = #"{"id":"1","name":"a","instant_invite":"javascript:alert(1)","channels":[],"members":[],"presence_count":1}"#
        XCTAssertNil(try DiscordWidget.decode(Data(json.utf8)).inviteURL)
    }

    func testDecodeMessagesAndLink() throws {
        let json = """
        [{"id":"300","channel_id":"201","content":"21時からスプラ募集 あと2人","timestamp":"2026-10-09T12:00:00.123000+00:00",
          "author":{"username":"ichigo","global_name":"いちご"}},
         {"id":"301","channel_id":"201","content":"","timestamp":"2026-10-09T11:00:00+00:00","author":{"username":"mikan"}}]
        """
        let m = try DiscordAPI.decodeMessages(Data(json.utf8), channelName: "募集", guildID: "100000000000000001")
        XCTAssertEqual(m.count, 1, "本文が空のメッセージは出さない")
        XCTAssertEqual(m[0].author, "いちご")
        XCTAssertEqual(m[0].link?.absoluteString, "https://discord.com/channels/100000000000000001/201/300")
        XCTAssertEqual(m[0].date, T.d(2026, 10, 9, 21, 0))
        XCTAssertTrue(m[0].matches("スプラ"))
        XCTAssertTrue(m[0].matches("募集"))
        XCTAssertFalse(m[0].matches("サーモン"))
    }

    func testSnowflake() {
        XCTAssertTrue(DiscordAPI.isSnowflake("100000000000000001"))
        XCTAssertFalse(DiscordAPI.isSnowflake("12345"))
        XCTAssertFalse(DiscordAPI.isSnowflake("10000000000000000a"))
    }
}

final class IdvFeedTests: TokyoTestCase {
    private let youtube = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
     <title>サンプルチャンネル</title>
     <entry>
      <id>yt:video:AAAAAAAAAAA</id>
      <yt:videoId>AAAAAAAAAAA</yt:videoId>
      <title>【見本】秋のイベント 開催期間：10月10日（土）～10月24日（土）</title>
      <link rel="alternate" href="https://www.youtube.com/watch?v=AAAAAAAAAAA"/>
      <published>2026-10-08T10:00:00+00:00</published>
      <media:group>
       <media:title>【見本】秋のイベント</media:title>
       <media:thumbnail url="https://i1.ytimg.com/vi/AAAAAAAAAAA/hqdefault.jpg" width="480" height="360"/>
      </media:group>
     </entry>
     <entry>
      <title>【見本】新しい衣装の紹介</title>
      <link rel="alternate" href="https://www.youtube.com/watch?v=BBBBBBBBBBB"/>
      <published>2026-10-07T10:00:00+00:00</published>
     </entry>
    </feed>
    """

    private let press = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <rdf:RDF xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
     <channel rdf:about="https://example.com/"><title>見本の会社のプレスリリース</title><link>https://example.com</link></channel>
     <item rdf:about="https://example.com/p/1.html">
      <title>『IdentityＶ 第五人格』見本のコラボが10/15～10/31に開催！</title>
      <link>https://example.com/p/1.html</link>
      <description>見本の説明</description>
      <dc:date>2026-10-09T11:00:00+09:00</dc:date>
     </item>
     <item rdf:about="https://example.com/p/2.html">
      <title>別のゲームの見本のお知らせ</title>
      <link>https://example.com/p/2.html</link>
      <dc:date>2026-10-09T10:00:00+09:00</dc:date>
     </item>
    </rdf:RDF>
    """

    func testParseYouTubeAtom() {
        let n = IdvFeed.parse(Data(youtube.utf8), kind: .video)
        XCTAssertEqual(n.count, 2)
        XCTAssertEqual(n[0].link, "https://www.youtube.com/watch?v=AAAAAAAAAAA")
        XCTAssertEqual(n[0].image, "https://i1.ytimg.com/vi/AAAAAAAAAAA/hqdefault.jpg")
        XCTAssertEqual(n[0].date, T.d(2026, 10, 8, 19, 0))
        XCTAssertEqual(n[1].image, "https://i.ytimg.com/vi/BBBBBBBBBBB/hqdefault.jpg", "サムネイルが無ければ動画IDから作る")
    }

    func testParsePressKeepsOnlyIdentityV() {
        let n = IdvFeed.parse(Data(press.utf8), kind: .press)
        XCTAssertEqual(n.count, 1)
        XCTAssertTrue(n[0].title.contains("第五人格"))
        XCTAssertEqual(n[0].kind, .press)
    }

    func testRangeJapanese() {
        let r = IdvDates.range(in: "開催期間：10月10日（土）～10月24日（土）", reference: T.now)
        XCTAssertEqual(r?.start, T.d(2026, 10, 10))
        XCTAssertEqual(r?.end, T.d(2026, 10, 24))
    }

    func testRangeSlashAndFullWidth() {
        let r = IdvDates.range(in: "見本のコラボが１０/１５～１０/３１に開催", reference: T.now)
        XCTAssertEqual(r?.end, T.d(2026, 10, 31))
        let short = IdvDates.range(in: "10月28日～11月3日 まで", reference: T.now)
        XCTAssertEqual(short?.end, T.d(2026, 11, 3))
    }

    func testRangeEndWithoutMonthAndAcrossYear() {
        XCTAssertEqual(IdvDates.range(in: "12月20日(日)～25日(金)", reference: T.now)?.end, T.d(2026, 12, 25))
        XCTAssertEqual(IdvDates.range(in: "12月26日～1月5日", reference: T.now)?.end, T.d(2027, 1, 5))
    }

    func testUntilOnly() {
        XCTAssertEqual(IdvDates.range(in: "限定ショップは10月20日まで", reference: T.now)?.end, T.d(2026, 10, 20))
        XCTAssertNil(IdvDates.range(in: "10月15日より開催決定", reference: T.now), "始まりの日だけなら期限にしない")
        XCTAssertNil(IdvDates.range(in: "新衣装の紹介", reference: T.now))
    }

    func testDaysLeftAndLabel() {
        XCTAssertEqual(IdvDates.daysLeft(T.d(2026, 10, 12), now: T.now), 3)
        XCTAssertEqual(IdvDates.label(T.d(2026, 10, 9, 23, 0), now: T.now), "今日まで")
        XCTAssertEqual(IdvDates.label(T.d(2026, 10, 8), now: T.now), "終了")
        XCTAssertEqual(IdvDates.label(T.d(2026, 10, 12), now: T.now), "あと3日")
    }

    func testCandidatesSkipEnded() {
        let n = [IdvNews(title: "10月1日～10月5日", link: "https://example.com/a", date: T.now, kind: .press),
                 IdvNews(title: "10月8日～10月20日", link: "https://example.com/b", date: T.now, kind: .press)]
        let c = IdvDates.candidates(n, now: T.now)
        XCTAssertEqual(c.map(\.link), ["https://example.com/b"])
    }

    func testReminderDayBefore() {
        XCTAssertEqual(IdvReminder.fireDate(T.d(2026, 10, 12), now: T.now), T.d(2026, 10, 11, 19, 0))
        XCTAssertNil(IdvReminder.fireDate(T.d(2026, 10, 9), now: T.now), "前日の夜が過ぎていれば出さない")
    }
}

final class DayCardTests: TokyoTestCase {
    func testFileNames() {
        XCTAssertEqual(DayCardData.fileName("2026-10-09"), "daycard-2026-10-09.json")
        XCTAssertEqual(DayCardData.day(fromFileName: "daycard-2026-10-09.json"), "2026-10-09")
        XCTAssertNil(DayCardData.day(fromFileName: "daycard-settings.json"))
        XCTAssertNil(DayCardData.day(fromFileName: DayCardData.reviewFile))
    }

    func testFireDatesSkipTodayWhenWritten() {
        let evening = T.d(2026, 10, 9, 20, 0)
        let notWritten = DayCardReminder.fireDates(now: evening, minutes: 21 * 60, writtenToday: false, days: 3)
        XCTAssertEqual(notWritten, [T.d(2026, 10, 9, 21, 0), T.d(2026, 10, 10, 21, 0), T.d(2026, 10, 11, 21, 0)])
        let written = DayCardReminder.fireDates(now: evening, minutes: 21 * 60, writtenToday: true, days: 3)
        XCTAssertEqual(written.first, T.d(2026, 10, 10, 21, 0))
        let late = DayCardReminder.fireDates(now: T.d(2026, 10, 9, 22, 0), minutes: 21 * 60, writtenToday: false, days: 2)
        XCTAssertEqual(late, [T.d(2026, 10, 10, 21, 0)])
    }

    func testWeekRangeStartsMonday() {
        let r = DayCardData.weekRange(T.now)   // 金曜
        XCTAssertEqual(r.start, T.d(2026, 10, 5))
        XCTAssertEqual(r.end, T.d(2026, 10, 12))
    }

    func testPromptHasNoTodoTitles() {
        let c = DayCard(day: "2026-10-09", note: "よく眠れた", doneCount: 3, doneTitles: ["ひみつの用事"], wakeStage: 1,
                        wakeTime: T.d(2026, 10, 9, 7, 8), mood: .good, photo: "x.jpg", savedAt: T.now)
        let s = DayCardData.promptLines([c])
        XCTAssertTrue(s.contains("TODO完了 3件"))
        XCTAssertTrue(s.contains("起床 7:08・1回目"))
        XCTAssertFalse(s.contains("点"), "起床の点数は送らない")
        XCTAssertTrue(s.contains("よく眠れた"))
        XCTAssertFalse(s.contains("ひみつの用事"))
        XCTAssertFalse(s.contains("x.jpg"))
    }

    func testOldDayCardWithScoreDecodes() throws {
        let json = #"{"day":"2026-10-08","note":"","doneCount":1,"doneTitles":[],"wakeScore":85,"savedAt":"2026-10-08T12:00:00Z"}"#
        let c = try JSONDecoder.iso.decode(DayCard.self, from: Data(json.utf8))
        XCTAssertNil(c.wakeStage)
        XCTAssertNil(c.wakeText, "時刻のない昔の記録は起床を出さない")
    }
}

final class ConsultWidgetFeedTests: TokyoTestCase {
    func testStreakCountsFromTodayOrYesterday() {
        let days: Set<String> = ["2026-10-09", "2026-10-08", "2026-10-07", "2026-10-05"]
        XCTAssertEqual(ConsultWidgetSync.streak(days: days, now: T.now), 3)
        XCTAssertEqual(ConsultWidgetSync.streak(days: ["2026-10-08", "2026-10-07"], now: T.now), 2, "今日まだなら昨日から")
        XCTAssertEqual(ConsultWidgetSync.streak(days: ["2026-10-06"], now: T.now), 0)
    }

    func testMoodLevelMapping() {
        XCTAssertEqual(ConsultMood.from(score: 5), .great)
        XCTAssertEqual(ConsultMood.from(score: 1), .bad)
        XCTAssertEqual(ConsultMood.from(score: 9), .great, "範囲外は丸める")
    }

    func testFeedFieldNames() throws {
        let data = try JSONEncoder().encode(ConsultWidgetFeed(todayMood: 4, dayCardWritten: true, streakDays: 2))
        let s = String(decoding: data, as: UTF8.self)
        for k in ["todayMood", "dayCardWritten", "streakDays"] { XCTAssertTrue(s.contains("\"\(k)\""), k) }
        let info = InfoWidgetFeed(headlines: [.init(title: "a", source: "b", topic: "c", colorIndex: 1)],
                                  splat: .init(endsAt: "2026-10-09T11:00:00Z", regular: "r", bankara: "b", x: "x"),
                                  steamSale: .init(title: "t", discount: 50))
        let t = String(decoding: try JSONEncoder().encode(info), as: UTF8.self)
        for k in ["headlines", "title", "source", "topic", "colorIndex", "splat", "endsAt", "regular", "bankara", "\"x\"", "steamSale", "discount"] {
            XCTAssertTrue(t.contains(k.hasPrefix("\"") ? k : "\"\(k)\""), k)
        }
    }
}
