import XCTest
@testable import TodoApp

/// 設定の「アプリのアイコン」の選択肢（AppIconOption）
final class AppIconOptionTests: XCTestCase {
    func testOrderAndLabels() {
        let ids: [String] = AppIconOption.allCases.map(\.id)
        XCTAssertEqual(ids, ["W2", "W6", "W1", "W3", "W4", "W5", "W7", "W8"])
        let labels: [String] = AppIconOption.allCases.map(\.label)
        XCTAssertEqual(labels, ["珊瑚", "生成り", "朱", "山吹", "若草", "抹茶", "白", "桜"])
    }

    func testAlternateNames() {
        // W2 はふだんのアイコン（AppIcon）なので nil。ほかは project.yml の ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES と同じ
        XCTAssertEqual(AppIconOption.primary, .w2)
        XCTAssertNil(AppIconOption.w2.alternateName)
        let names: [String] = AppIconOption.allCases.compactMap(\.alternateName)
        XCTAssertEqual(names, ["AppIcon-W6", "AppIcon-W1", "AppIcon-W3", "AppIcon-W4", "AppIcon-W5", "AppIcon-W7", "AppIcon-W8"])
    }

    func testFromAlternateName() {
        XCTAssertEqual(AppIconOption.from(alternateName: nil), .w2)
        XCTAssertEqual(AppIconOption.from(alternateName: "AppIcon-W5"), .w5)
        XCTAssertEqual(AppIconOption.from(alternateName: "AppIcon-dark"), .w2)
        for option in AppIconOption.allCases {
            XCTAssertEqual(AppIconOption.from(alternateName: option.alternateName), option)
        }
    }

    func testColors() {
        XCTAssertEqual(AppIconOption.w2.ground, 0xF08A6A)
        XCTAssertEqual(AppIconOption.w5.bird, 0xF3EBCF)
        XCTAssertEqual(AppIconOption.w1.bird, 0x24345E)
    }
}
