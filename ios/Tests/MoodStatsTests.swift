import XCTest
@testable import TodoApp

/// 気分の記録の集計（MoodStats）。いま＝2026-10-09（金）10:00
final class MoodStatsTests: TokyoTestCase {
    private func day(_ offset: Int, _ mood: ConsultMood, wake: Int? = nil) -> MoodDay {
        let d = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: T.now))!
        return MoodDay(date: d, mood: mood, wake: wake, habitRate: nil, doneCount: 0, focusMinutes: 0)
    }

    func testScoreRoundTrip() {
        for m in ConsultMood.allCases {
            XCTAssertEqual(ConsultMood.from(score: m.score), m)
        }
        XCTAssertEqual(ConsultMood.great.score, 5)
        XCTAssertEqual(ConsultMood.bad.score, 1)
    }

    func testAverageAndStreak() {
        let s = MoodStats.make([day(0, .great), day(1, .okay), day(2, .bad), day(4, .good)], now: T.now)
        XCTAssertEqual(s.average!, 3.25, accuracy: 0.001)
        XCTAssertEqual(s.streak, 3)   // 今日・昨日・おととい（4日前は続いていない）
        XCTAssertEqual(s.counts[.great], 1)
    }

    func testStreakStartsFromYesterday() {
        let s = MoodStats.make([day(1, .okay), day(2, .okay)], now: T.now)
        XCTAssertEqual(s.streak, 2)
    }

    func testRecentVersusPrevious() {
        let days = (0..<7).map { day($0, .great) } + (7..<14).map { day($0, .low) }
        let s = MoodStats.make(days, now: T.now)
        XCTAssertEqual(s.recent7!, 5, accuracy: 0.001)
        XCTAssertEqual(s.previous7!, 2, accuracy: 0.001)
        XCTAssertTrue(s.insights.first?.contains("上向き") ?? false)
    }

    func testWakeFactorNeedsThreeDaysEachSide() {
        let few = MoodStats.make([day(0, .great, wake: 90), day(1, .bad, wake: 50)], now: T.now)
        XCTAssertFalse(few.factors.contains { $0.title.hasPrefix("起床") })

        let days = [day(0, .great, wake: 90), day(1, .good, wake: 85), day(2, .great, wake: 95),
                    day(3, .low, wake: 60), day(4, .bad, wake: 55), day(5, .low, wake: 70)]
        let s = MoodStats.make(days, now: T.now)
        let f = s.factors.first { $0.title.hasPrefix("起床") }
        XCTAssertNotNil(f)
        XCTAssertEqual(f!.diff, (14.0 / 3) - (5.0 / 3), accuracy: 0.001)
    }
}
