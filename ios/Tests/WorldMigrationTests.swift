import XCTest
@testable import TodoApp

/// 世界観の設定の読みこみ。なくなった世界観（日なた・ネオブルータル・ベント・クレイ・スイス）は「なし」に戻る
final class WorldMigrationTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testRemovedWorldsFallBackToNone() throws {
        for raw in ["hinata", "brutal", "bento", "clay", "swiss"] {
            let s: AppSettings = try decode("{\"world\":\"\(raw)\"}")
            XCTAssertEqual(s.world, "none", raw)
            XCTAssertEqual(World.from(raw), World.none, raw)
        }
    }

    func testRemainingWorldsAreKept() throws {
        for raw in ["strata", "galaxy", "sky", "mist", "deepsea", "aurora", "none"] {
            let s: AppSettings = try decode("{\"world\":\"\(raw)\"}")
            XCTAssertEqual(s.world, raw)
            XCTAssertEqual(World.from(raw).rawValue, raw)
        }
    }

    func testMissingWorldIsNone() throws {
        let s: AppSettings = try decode("{}")
        XCTAssertEqual(s.world, "none")
    }

    func testSixWorldsRemain() {
        let names: [String] = World.allCases.filter { $0.isOn }.map { $0.rawValue }
        XCTAssertEqual(Set(names), Set(["strata", "galaxy", "sky", "mist", "deepsea", "aurora"]))
    }
}
