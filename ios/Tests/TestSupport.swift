import XCTest
@testable import TodoApp

// テストの共通部品。時刻はすべて日本時間（Asia/Tokyo）で固定する。
// 基準の「いま」は 2026-10-09（金）10:00。

enum T {
    static let tz = TimeZone(identifier: "Asia/Tokyo")!

    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.locale = Locale(identifier: "ja_JP")
        return c
    }()

    /// 日本時間の日時
    static func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(timeZone: tz, year: y, month: m, day: day, hour: h, minute: mi))!
    }

    /// 基準の「いま」：2026-10-09（金）10:00
    static let now = d(2026, 10, 9, 10, 0)
}

/// Calendar.current・TimeZone.current を使う処理のために、既定の時間帯を日本時間にしてから走らせる
class TokyoTestCase: XCTestCase {
    private var savedTZ: TimeZone!

    override func setUp() {
        super.setUp()
        savedTZ = NSTimeZone.default
        NSTimeZone.default = T.tz
    }

    override func tearDown() {
        NSTimeZone.default = savedTZ
        super.tearDown()
    }

    /// 見つかった不具合を「既知の失敗」として扱う（直ったら自然に通る：strict ではない）
    func knownBug(_ reason: String, _ body: () -> Void) {
        let o = XCTExpectedFailure.Options()
        o.isStrict = false
        XCTExpectFailure(reason, options: o, failingBlock: body)
    }
}

final class EnvironmentTests: TokyoTestCase {
    func testTimeZoneIsTokyo() {
        XCTAssertEqual(TimeZone.current.identifier, "Asia/Tokyo")
        XCTAssertEqual(Calendar.current.component(.weekday, from: T.now), 6, "2026-10-09 は金曜")
    }
}
