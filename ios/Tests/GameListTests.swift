import XCTest
@testable import TodoApp

/// 情報 › ゲームの並びと表示（GameListLogic）と、なくした機能の記録の片づけ（RetiredDataCleanup）
final class GameListTests: XCTestCase {
    func testDefaultOrder() {
        XCTAssertEqual(GameListLogic.order([]), [.splatoon, .steam, .identityV])
    }

    func testSavedOrderAndMissingAppended() {
        XCTAssertEqual(GameListLogic.order(["identityV", "steam"]), [.identityV, .steam, .splatoon])
    }

    func testUnknownAndDuplicatesDropped() {
        // Discord は一覧から外したので、古い並びに残っていても出さない
        let order: [GameItem] = GameListLogic.order(["discord", "steam", "steam", "xyz", "splatoon"])
        XCTAssertEqual(order, [.steam, .splatoon, .identityV])
        XCTAssertFalse(GameItem.allCases.map(\.rawValue).contains("discord"))
    }

    func testHidden() {
        let shown: [GameItem] = GameListLogic.visible(order: ["steam", "splatoon"], hidden: ["splatoon", "discord"])
        XCTAssertEqual(shown, [.steam, .identityV])
        XCTAssertEqual(GameListLogic.visible(order: [], hidden: ["splatoon", "steam", "identityV"]), [])
    }

    func testSettingsRoundTrip() throws {
        var s = AppSettings()
        s.gameOrder = ["identityV", "splatoon", "steam"]
        s.hiddenGames = ["steam"]
        let data: Data = try JSONEncoder().encode(s)
        let back: AppSettings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.visibleGames, [.identityV, .splatoon])
        XCTAssertFalse(back.isGameShown(.steam))
    }

    func testOldSettingsFileHasDefaults() throws {
        let old: Data = Data("{\"theme\":\"night\"}".utf8)
        let s: AppSettings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(s.visibleGames, [.splatoon, .steam, .identityV])
    }

    func testWidgetFeedFollowsGames() {
        var s = AppSettings()
        let feed: InfoFeed = InfoFeed.demo()
        XCTAssertNotNil(feed.applyingGames(s).splat)
        XCTAssertFalse(feed.applyingGames(s).steamFirst)
        s.gameOrder = ["steam", "splatoon"]
        s.hiddenGames = ["splatoon"]
        let applied: InfoFeed = feed.applyingGames(s)
        XCTAssertNil(applied.splat)
        XCTAssertNotNil(applied.steamSale)
        XCTAssertTrue(applied.steamFirst)
    }

    func testRetiredDataCleanupRunsOnce() throws {
        let suite: String = "test.cleanup.\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fm: FileManager = FileManager.default
        for name in RetiredDataCleanup.files {
            try Data("[]".utf8).write(to: SharedStore.url(name))
        }
        RetiredDataCleanup.runOnce(defaults: defaults)
        for name in RetiredDataCleanup.files {
            XCTAssertFalse(fm.fileExists(atPath: SharedStore.url(name).path), name)
        }
        XCTAssertTrue(defaults.bool(forKey: RetiredDataCleanup.doneKey))
        // 2回目は何もしない（あとから同じ名前のファイルができても消さない）
        let again: URL = SharedStore.url("habit-list.json")
        try Data("[]".utf8).write(to: again)
        RetiredDataCleanup.runOnce(defaults: defaults)
        XCTAssertTrue(fm.fileExists(atPath: again.path))
        try? fm.removeItem(at: again)
    }
}
