import XCTest
@testable import TodoApp

/// Steam のキーなしの読み込み：コミュニティの XML・ストアの特集・入力の見分け。見本はすべて架空のもの
final class SteamKeylessTests: TokyoTestCase {
    private let profileXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?><profile>
        <steamID64>76561190000000001</steamID64>
        <steamID><![CDATA[テスト用の名前]]></steamID>
        <onlineState>in-game</onlineState>
        <stateMessage><![CDATA[In-Game<br/>Sample Game]]></stateMessage>
        <privacyState>public</privacyState>
        <visibilityState>3</visibilityState>
        <avatarFull><![CDATA[https://avatars.example.com/sample_full.jpg]]></avatarFull>
        <inGameInfo>
            <gameName><![CDATA[Sample Game]]></gameName>
            <gameLink><![CDATA[https://steamcommunity.com/app/10]]></gameLink>
        </inGameInfo>
        <groups><group><groupID64>10358279000000000</groupID64></group></groups>
    </profile>
    """

    private let privateXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?><profile>
        <steamID64>76561190000000002</steamID64>
        <steamID><![CDATA[himitsu]]></steamID>
        <onlineState>offline</onlineState>
        <stateMessage><![CDATA[Offline]]></stateMessage>
        <privacyState>private</privacyState>
        <visibilityState>1</visibilityState>
    </profile>
    """

    func testParseProfileXML() throws {
        let x = try SteamProfileXML.parse(Data(profileXML.utf8))
        XCTAssertEqual(x.steamID64, "76561190000000001")
        XCTAssertEqual(x.name, "テスト用の名前")
        XCTAssertEqual(x.avatar, "https://avatars.example.com/sample_full.jpg")
        XCTAssertEqual(x.gameName, "Sample Game")
        let p = x.profile
        XCTAssertEqual(p.playing, "Sample Game")
        XCTAssertEqual(p.stateText, "Sample Game をプレイ中")
        XCTAssertEqual(p.isPublic, true)
        XCTAssertTrue(p.isOnline)
    }

    func testParsePrivateProfileXML() throws {
        let p = try SteamProfileXML.parse(Data(privateXML.utf8)).profile
        XCTAssertEqual(p.steamID, "76561190000000002")
        XCTAssertEqual(p.state, 0)
        XCTAssertNil(p.playing)
        XCTAssertNil(p.avatar)
        XCTAssertEqual(p.isPublic, false)
        var s = SteamSnapshot()
        s.profile = p
        XCTAssertTrue(s.looksPrivate)
    }

    func testProfileXMLAwayState() throws {
        let xml = privateXML.replacingOccurrences(of: "<onlineState>offline", with: "<onlineState>online")
            .replacingOccurrences(of: "[Offline]", with: "[Away]")
        let p = try SteamProfileXML.parse(Data(xml.utf8)).profile
        XCTAssertEqual(p.state, 3)
        XCTAssertEqual(p.stateText, "離席中")
    }

    func testProfileXMLErrorIsNotFound() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?><response><error><![CDATA[The specified profile could not be found.]]></error></response>
        """
        XCTAssertThrowsError(try SteamProfileXML.parse(Data(xml.utf8))) { e in
            XCTAssertEqual(e as? SteamAPIError, .notFound)
        }
        XCTAssertThrowsError(try SteamProfileXML.parse(Data("not xml <<".utf8)))
    }

    private let featured = """
    {"0":{"id":"cat_spotlight","name":"Spotlights","items":[{"name":"見本のセール","url":"https://store.steampowered.com/sale/x"}]},
     "specials":{"id":"cat_specials","name":"スペシャル","items":[
       {"id":100,"type":0,"name":"見本ゲームA","discounted":true,"discount_percent":50,"original_price":198000,"final_price":99000,"currency":"JPY","discount_expiration":1790000000},
       {"id":101,"type":0,"name":"見本ゲームB","discounted":false,"discount_percent":0,"original_price":150000,"final_price":150000,"currency":"JPY"},
       {"id":102,"type":1,"name":"見本パック","discounted":true,"discount_percent":30,"final_price":70000}
     ]},
     "top_sellers":{"id":"cat_topsellers","name":"売上上位","items":[
       {"id":100,"type":0,"name":"見本ゲームA","discounted":true,"discount_percent":50,"final_price":99000},
       {"id":103,"type":0,"name":"見本ゲームC","discounted":true,"discount_percent":15,"original_price":190000,"final_price":161500}
     ]},
     "new_releases":{"id":"cat_newreleases","name":"新作","items":[
       {"id":104,"name":"見本ゲームD","discount_percent":10,"final_price":121500}
     ]},
     "genres":{"id":"cat_genres","name":"ジャンル"}}
    """

    func testParseFeatured() throws {
        let list = try SteamAPI.parseFeatured(Data(featured.utf8))
        XCTAssertEqual(list.map(\.appID), [100, 103, 104])   // 割引なし・パック・重複は除く
        let a = list[0]
        XCTAssertEqual(a.name, "見本ゲームA")
        XCTAssertEqual(a.discount, 50)
        XCTAssertEqual(a.finalYen, 990)
        XCTAssertEqual(a.originalYen, 1980)
        XCTAssertEqual(a.finalText, "¥ 990")
        XCTAssertEqual(a.originalText, "¥ 1,980")
        XCTAssertEqual(a.endsAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(list[1].finalText, "¥ 1,615")
        XCTAssertNil(list[1].endsAt)
        XCTAssertNil(list[2].originalYen)
    }

    func testParseFeaturedLimitAndEmpty() throws {
        XCTAssertEqual(try SteamAPI.parseFeatured(Data(featured.utf8), limit: 1).count, 1)
        XCTAssertEqual(try SteamAPI.parseFeatured(Data("{}".utf8)), [])
    }

    func testUntilFormat() {
        // 2026-10-20 12:00（日本時間）
        let d = Date(timeIntervalSince1970: 1_792_465_200)
        XCTAssertEqual(SteamFormat.until(d), "10/20 まで")
    }

    func testClassifyInput() {
        XCTAssertEqual(SteamAPI.classify("76561190000000003"), .id("76561190000000003"))
        XCTAssertEqual(SteamAPI.classify("https://steamcommunity.com/profiles/76561190000000003/"), .id("76561190000000003"))
        XCTAssertEqual(SteamAPI.classify("https://steamcommunity.com/id/sample_name/"), .vanity("sample_name"))
        XCTAssertEqual(SteamAPI.classify(" sample_name "), .vanity("sample_name"))
        XCTAssertNil(SteamAPI.classify(""))
        XCTAssertNil(SteamAPI.classify("two words"))
    }

    func testNewsTargetsWithoutKey() {
        let deals: [SteamDeal] = [SteamDeal(appID: 1, name: "A", discount: 10), SteamDeal(appID: 2, name: "B", discount: 0)]
        let specials: [SteamSpecial] = [SteamSpecial(appID: 2, name: "B", discount: 20), SteamSpecial(appID: 3, name: "C", discount: 30),
                                        SteamSpecial(appID: 4, name: "D", discount: 40)]
        let t = SteamAPI.newsTargets(recent: [], deals: deals, specials: specials)
        XCTAssertEqual(t.map(\.appID), [1, 2, 3])
    }

    func testOldSnapshotStillDecodes() throws {
        // 前の版で保存したデータ（あとから足した項目が無い）も読める
        let json = """
        {"recent":[],"deals":[],"news":[],"fetchedAt":0,"profile":{"steamID":"76561190000000004","name":"n","state":1}}
        """
        let s = try JSONDecoder().decode(SteamSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(s.specials)
        XCTAssertNil(s.profile?.isPublic)
        XCTAssertFalse(s.looksPrivate)
    }

    func testWidgetFallsBackToStoreSale() {
        var s = SteamSnapshot()
        s.specials = [SteamSpecial(appID: 3, name: "C", discount: 30), SteamSpecial(appID: 4, name: "D", discount: 40)]
        XCTAssertEqual(InfoWidgetSync.steam(s)?.title, "D")
        s.deals = [SteamDeal(appID: 1, name: "A", discount: 10)]
        XCTAssertEqual(InfoWidgetSync.steam(s)?.title, "A")
    }
}
