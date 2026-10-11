import XCTest
@testable import TodoApp

/// 起床の見張り（WakeWatchLogic）。2026-10-09（金）7:00 起床・段階は 0/10/20/30 分後。
final class WakeWatchLogicTests: TokyoTestCase {
    private let stop = T.d(2026, 10, 9, 7, 1)

    private func record(rangAt: Date? = nil, stepsAtRing: Int? = nil, rearms: Int = 0) -> WakeWatchRecord {
        var r = WakeWatchRecord(day: "2026-10-09", stopAt: stop, stoppedStage: 1)
        r.rangAt = rangAt
        r.stepsAtRing = stepsAtRing
        r.rearms = rearms
        return r
    }

    func testWatchTimes() {
        XCTAssertEqual(WakeWatchLogic.watchTimes(stopAt: stop), [T.d(2026, 10, 9, 7, 11), T.d(2026, 10, 9, 7, 21)])
    }

    func testOriginalsToCancel() throws {
        let plan = try XCTUnwrap(WakeLogic.plan(for: stop, settings: WakeSettings(), state: WakeDayState()))
        let later = WakeWatchLogic.originalsToCancel(plan, stoppedAt: stop)
        XCTAssertEqual(later.map(\.number), [2, 3, 4], "止めた後に鳴るはずだった元のアラーム")
        XCTAssertTrue(WakeWatchLogic.originalsToCancel(plan, stoppedAt: T.d(2026, 10, 9, 7, 31)).isEmpty)
    }

    // MARK: 歩数での判定

    func testDecideAwakeAt100Steps() {
        let r = record()
        XCTAssertEqual(WakeWatchLogic.decide(r, steps: 99), .keep)
        XCTAssertEqual(WakeWatchLogic.decide(r, steps: 100), .awake)
        XCTAssertEqual(WakeWatchLogic.decide(r, steps: 0), .keep)
    }

    func testDecideRingNeeds30StepsSinceRing() {
        let r = record(rangAt: T.d(2026, 10, 9, 7, 11), stepsAtRing: 10)
        XCTAssertEqual(WakeWatchLogic.decide(r, steps: 39), .keep)
        XCTAssertEqual(WakeWatchLogic.decide(r, steps: 40), .ringPassed)
        XCTAssertEqual(WakeWatchLogic.decide(r, steps: 120), .awake)
        XCTAssertEqual(WakeWatchLogic.decide(record(), steps: 40), .keep, "鳴る前は30歩では終わらない")
    }

    func testStopOnWatchAlarm() {
        let now = T.d(2026, 10, 9, 7, 11)
        let r = record(rangAt: now, stepsAtRing: 0)
        XCTAssertEqual(WakeWatchLogic.onWatchAlarmStop(r, missionPassed: true, stepsSinceRing: 0, now: now), .resolve)
        XCTAssertEqual(WakeWatchLogic.onWatchAlarmStop(r, missionPassed: false, stepsSinceRing: 30, now: now), .resolve)
        XCTAssertEqual(WakeWatchLogic.onWatchAlarmStop(r, missionPassed: false, stepsSinceRing: 5, now: now),
                       .rearm(T.d(2026, 10, 9, 7, 14)), "止めただけなら3分後にまた鳴る")
        let worn = record(rangAt: now, stepsAtRing: 0, rearms: 5)
        XCTAssertEqual(WakeWatchLogic.onWatchAlarmStop(worn, missionPassed: false, stepsSinceRing: 0, now: now), .exhausted)
        XCTAssertEqual(WakeWatchLogic.onWatchAlarmStop(worn, missionPassed: false, stepsSinceRing: 0, now: now, maxRearms: 6),
                       .rearm(T.d(2026, 10, 9, 7, 14)))
    }

    func testIsActive() {
        var r = record()
        XCTAssertTrue(WakeWatchLogic.isActive(r, now: T.d(2026, 10, 9, 7, 30)))
        XCTAssertFalse(WakeWatchLogic.isActive(r, now: T.d(2026, 10, 9, 10, 30)), "3時間たったら終わり")
        XCTAssertFalse(WakeWatchLogic.isActive(r, now: T.d(2026, 10, 10, 7, 30)), "次の日には持ち越さない")
        r.endedAt = T.d(2026, 10, 9, 7, 20)
        XCTAssertFalse(WakeWatchLogic.isActive(r, now: T.d(2026, 10, 9, 7, 30)))
        XCTAssertFalse(WakeWatchLogic.isActive(nil, now: T.now))
    }

    // MARK: 二度寝と点数

    func testStepStart() {
        let b: [(start: Date, steps: Int)] = [(T.d(2026, 10, 9, 7, 1), 0), (T.d(2026, 10, 9, 7, 3), 4),
                                              (T.d(2026, 10, 9, 7, 5), 30), (T.d(2026, 10, 9, 7, 7), 50)]
        XCTAssertEqual(WakeWatchLogic.stepStart(buckets: b), T.d(2026, 10, 9, 7, 5))
        XCTAssertNil(WakeWatchLogic.stepStart(buckets: [(stop, 3)]))
    }

    func testOversleepMinutes() {
        XCTAssertEqual(WakeWatchLogic.oversleepMinutes(stopAt: stop, stepStart: T.d(2026, 10, 9, 7, 4), awakeAt: T.d(2026, 10, 9, 7, 8)), 0,
                       "5分以内に歩き始めたら二度寝なし")
        XCTAssertEqual(WakeWatchLogic.oversleepMinutes(stopAt: stop, stepStart: T.d(2026, 10, 9, 7, 13), awakeAt: T.d(2026, 10, 9, 7, 15)), 12)
        XCTAssertEqual(WakeWatchLogic.oversleepMinutes(stopAt: stop, stepStart: nil, awakeAt: T.d(2026, 10, 9, 7, 21)), 20,
                       "歩数が読めなければ起きたと確かめた時刻で数える")
        XCTAssertEqual(WakeWatchLogic.oversleepMinutes(stopAt: stop, stepStart: T.d(2026, 10, 9, 7, 40), awakeAt: T.d(2026, 10, 9, 7, 3)), 0)
    }

    func testScore() {
        XCTAssertEqual(WakeWatchLogic.score(stage: 1, oversleepMinutes: 0), 100)
        XCTAssertEqual(WakeWatchLogic.score(stage: 2, oversleepMinutes: 0), 85)
        XCTAssertEqual(WakeWatchLogic.score(stage: 1, oversleepMinutes: 12), 78)
        XCTAssertEqual(WakeWatchLogic.score(stage: 1, oversleepMinutes: 90), 50, "引くのは最大50点")
        XCTAssertEqual(WakeWatchLogic.score(stage: 4, oversleepMinutes: 30), 0)
    }

    // MARK: 計算のミッション

    func testMission() {
        let m = WakeWatchLogic.mission(seed: 42)
        XCTAssertEqual(m.count, 3)
        XCTAssertEqual(m, WakeWatchLogic.mission(seed: 42), "同じ seed なら同じ問題")
        XCTAssertNotEqual(m, WakeWatchLogic.mission(seed: 43))
        for q in m {
            XCTAssertEqual(q.answer, q.plus ? q.a + q.b : q.a * q.b)
            XCTAssertTrue(q.answer >= 10 && q.answer < 1000)
        }
        XCTAssertEqual(WakeWatchLogic.MathQuestion(a: 23, b: 48, plus: true).text, "23 + 48")
    }

    // MARK: ウィジェット向け

    func testWatchState() {
        XCTAssertFalse(WakeWatchState.make(nil, now: T.now).isWatching)
        var r = record()
        r.steps = 34
        r.alarms = WakeWatchLogic.watchTimes(stopAt: stop).enumerated().map {
            WakeScheduledAlarm(id: "w\($0.offset)", at: $0.element, day: r.day, stage: $0.offset + 1)
        }
        let a = WakeWatchState.make(r, now: T.d(2026, 10, 9, 7, 6))
        XCTAssertTrue(a.isWatching)
        XCTAssertEqual(a.steps, 34)
        XCTAssertEqual(a.requiredSteps, 100)
        XCTAssertEqual(a.nextWatchAt, T.d(2026, 10, 9, 7, 11))
        XCTAssertFalse(a.needsProof)
        r.rangAt = T.d(2026, 10, 9, 7, 11)
        r.stepsAtRing = 30
        let b = WakeWatchState.make(r, now: T.d(2026, 10, 9, 7, 12))
        XCTAssertTrue(b.needsProof)
        XCTAssertEqual(b.requiredSteps, 30)
        XCTAssertEqual(b.steps, 4, "鳴ってからの歩数")
        XCTAssertEqual(b.nextWatchAt, T.d(2026, 10, 9, 7, 21))
    }

    // MARK: 古い保存データ

    func testOldSettingsAndSessionsDecode() throws {
        let s = try JSONDecoder.iso.decode(WakeSettings.self, from: Data(#"{"paused": false}"#.utf8))
        XCTAssertTrue(s.watch, "前の版の設定では見張りはオン")
        XCTAssertEqual(s.watchRearms, 5)
        let old = #"[{"day":"2026-10-08","stage":1,"score":100}]"#
        let sessions = try JSONDecoder.iso.decode([WakeSession].self, from: Data(old.utf8))
        XCTAssertNil(sessions.first?.oversleep)
        let r = try JSONDecoder.iso.decode(WakeWatchRecord.self, from: Data(#"{"day":"2026-10-09","stopAt":"2026-10-08T22:01:00Z"}"#.utf8))
        XCTAssertEqual(r.stoppedStage, 1)
        XCTAssertTrue(r.alarms.isEmpty)
        XCTAssertFalse(r.replacedOriginals)
    }
}
