import Foundation
import SwiftUI
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(AlarmKit)
import AlarmKit
#endif

// 起床の見張り（二度寝の防止）。
// 起床アラームの「止める」で見張りを始め、+10分・+20分に見張りのアラームを予約して、元のアラームの残りを取り消す。
// 歩数（CMPedometer）が約100歩に届いたら起きたとみなして見張りを終える。
// 見張りのアラームが鳴ったら、30歩 歩くか計算3問で止める。「止める」だけだと3分後にまた鳴る（上限あり）。
//
// 安全のための決まり：見張りの処理がどこかで失敗したら、元のアラームはそのまま残す（元の動きに戻る）。
// 元のアラームを取り消すのは、見張りのアラームをすべて予約できたあとだけ。
// 保存先：wake-watch.json

// MARK: - 記録

/// その日の見張りの記録（1日1件。新しい見張りが始まると上書き）
struct WakeWatchRecord: Codable, Hashable {
    var day: String
    /// 元のアラームを止めた時刻
    var stopAt: Date
    /// 止めたのは何回目のアラームか
    var stoppedStage: Int
    /// 予約した見張りのアラーム（stage は見張りの何回目か）
    var alarms: [WakeScheduledAlarm] = []
    /// 元のアラームの残りを取り消したか（false なら元のアラームも鳴る）
    var replacedOriginals = false
    /// 「止める」だけで止めたので鳴らし直した回数
    var rearms = 0
    /// 止めてからの歩数（最後に確かめた値）
    var steps = 0
    var stepsAt: Date? = nil
    /// 見張りのアラームが初めて鳴って止められた時刻（ここから30歩が必要）
    var rangAt: Date? = nil
    /// そのときの歩数（30歩はここからの差で数える）
    var stepsAtRing: Int? = nil
    /// 歩き始めた時刻（2分ごとの歩数から推定）
    var stepStartAt: Date? = nil
    /// 見張りの終わり
    var endedAt: Date? = nil
    /// steps（歩数で起床）/ walk（見張りのアラームを歩いて止めた）/ mission（計算で止めた）/ checkin（起きた・起きてるよ）/ timeout
    var endedBy: String? = nil
    /// 「歩いて止める」でアプリを開いた（止める画面を出す）
    var openRequested = false

    init(day: String, stopAt: Date, stoppedStage: Int) {
        self.day = day; self.stopAt = stopAt; self.stoppedStage = stoppedStage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        stopAt = try c.decode(Date.self, forKey: .stopAt)
        stoppedStage = (try? c.decodeIfPresent(Int.self, forKey: .stoppedStage)) ?? 1
        alarms = (try? c.decodeIfPresent([WakeScheduledAlarm].self, forKey: .alarms)) ?? []
        replacedOriginals = (try? c.decodeIfPresent(Bool.self, forKey: .replacedOriginals)) ?? false
        rearms = (try? c.decodeIfPresent(Int.self, forKey: .rearms)) ?? 0
        steps = (try? c.decodeIfPresent(Int.self, forKey: .steps)) ?? 0
        stepsAt = try? c.decodeIfPresent(Date.self, forKey: .stepsAt)
        rangAt = try? c.decodeIfPresent(Date.self, forKey: .rangAt)
        stepsAtRing = try? c.decodeIfPresent(Int.self, forKey: .stepsAtRing)
        stepStartAt = try? c.decodeIfPresent(Date.self, forKey: .stepStartAt)
        endedAt = try? c.decodeIfPresent(Date.self, forKey: .endedAt)
        endedBy = try? c.decodeIfPresent(String.self, forKey: .endedBy)
        openRequested = (try? c.decodeIfPresent(Bool.self, forKey: .openRequested)) ?? false
    }

    var isEnded: Bool { endedAt != nil }
    /// 見張りのアラームが鳴った（30歩か計算が必要）
    var needsProof: Bool { rangAt != nil && endedAt == nil }
    /// 鳴ってからの歩数
    var stepsSinceRing: Int { max(0, steps - (stepsAtRing ?? steps)) }
}

enum WakeWatchStore {
    static let file = "wake-watch.json"

    static func record() -> WakeWatchRecord? { SharedStore.load(WakeWatchRecord.self, from: file) }
    static func save(_ r: WakeWatchRecord) { SharedStore.save(r, to: file) }

    /// 今日の、まだ終わっていない見張り
    static func active(now: Date) -> WakeWatchRecord? {
        guard let r = record(), WakeWatchLogic.isActive(r, now: now) else { return nil }
        return r
    }
}

// MARK: - 判定（副作用なし。テストする）

enum WakeWatchLogic {
    /// 起きたとみなす歩数
    static let awakeSteps = 100
    /// 見張りのアラームを止めるのに必要な歩数
    static let ringSteps = 30
    /// 見張りのアラーム（止めてから何分後）
    static let watchOffsets = [10, 20]
    /// 「止める」だけで止めたときに鳴らし直すまでの分
    static let rearmMinutes = 3
    /// 鳴らし直しの上限（設定で変えられる）
    static let defaultMaxRearms = 5
    /// 二度寝とみなさない猶予（分）
    static let graceMinutes = 5
    /// 見張りを自動で終える長さ（止めてから）
    static let maxWatch: TimeInterval = 3 * 3600
    /// 歩き始めとみなす、2分あたりの歩数
    static let bucketMinutes = 2
    static let bucketThreshold = 8

    static func watchTimes(stopAt: Date) -> [Date] {
        watchOffsets.map { stopAt.addingTimeInterval(TimeInterval($0 * 60)) }
    }

    /// 今日の見張りが続いているか
    static func isActive(_ r: WakeWatchRecord?, now: Date) -> Bool {
        guard let r, r.endedAt == nil, r.day == WakeLogic.key(now) else { return false }
        return now.timeIntervalSince(r.stopAt) < maxWatch
    }

    /// 元のアラームのうち、止めた後に鳴るはずのもの（見張りに置き換えるので取り消す）
    static func originalsToCancel(_ plan: WakePlan, stoppedAt now: Date) -> [WakePlan.Stage] {
        plan.stages.filter { $0.at > now }
    }

    enum StepDecision: Equatable {
        case awake       // 約100歩：起きた
        case ringPassed  // 見張りのアラームのあと30歩
        case keep        // 見張りを続ける
    }

    /// 歩数での判定（steps は止めてからの合計）
    static func decide(_ r: WakeWatchRecord, steps: Int) -> StepDecision {
        if steps >= awakeSteps { return .awake }
        if r.rangAt != nil, steps - (r.stepsAtRing ?? steps) >= ringSteps { return .ringPassed }
        return .keep
    }

    enum StopDecision: Equatable {
        case resolve         // 30歩 歩いた・計算を済ませた → 見張りを終える
        case rearm(Date)     // 3分後にまた鳴らす
        case exhausted       // 上限に達した（これ以上は鳴らさない）
    }

    /// 見張りのアラームを「止める」で止めたとき
    static func onWatchAlarmStop(_ r: WakeWatchRecord, missionPassed: Bool, stepsSinceRing: Int,
                                 now: Date, maxRearms: Int = defaultMaxRearms) -> StopDecision {
        if missionPassed || stepsSinceRing >= ringSteps { return .resolve }
        guard r.rearms < maxRearms else { return .exhausted }
        return .rearm(now.addingTimeInterval(TimeInterval(rearmMinutes * 60)))
    }

    /// 2分ごとの歩数から、歩き始めた時刻（しきい値を超えた最初の区間の始まり）
    static func stepStart(buckets: [(start: Date, steps: Int)], threshold: Int = bucketThreshold) -> Date? {
        buckets.first { $0.steps >= threshold }?.start
    }

    /// 二度寝の分（猶予の5分以内なら0）。歩き始めが分からなければ、起きたと確かめた時刻で数える
    static func oversleepMinutes(stopAt: Date, stepStart: Date?, awakeAt: Date) -> Int {
        let start = min(stepStart ?? awakeAt, awakeAt)
        let m = Int(start.timeIntervalSince(stopAt) / 60)
        return m > graceMinutes ? m : 0
    }

    // MARK: 計算のミッション

    struct MathQuestion: Hashable {
        let a: Int
        let b: Int
        let plus: Bool
        var answer: Int { plus ? a + b : a * b }
        var text: String { plus ? "\(a) + \(b)" : "\(a) × \(b)" }
    }

    /// 3問（同じ seed なら同じ問題）。2けたの足し算2問と、かけ算1問
    static func mission(seed: Int) -> [MathQuestion] {
        var x = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 12_345)
        func next(_ range: ClosedRange<Int>) -> Int {
            x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int((x >> 33) % span)
        }
        return [
            MathQuestion(a: next(12...89), b: next(12...89), plus: true),
            MathQuestion(a: next(3...9), b: next(12...19), plus: false),
            MathQuestion(a: next(21...99), b: next(11...79), plus: true),
        ]
    }
}

// MARK: - ウィジェット向けの読み出し（ウィジェット担当はこれを読むだけ）

/// 見張りの状態
struct WakeWatchState: Hashable {
    /// 見張り中か
    var isWatching: Bool
    /// 元のアラームを止めた時刻
    var stopAt: Date?
    /// 歩数（見張りのアラームが鳴った後は、鳴ってからの歩数）
    var steps: Int
    /// 必要な歩数（ふだんは100、見張りのアラームが鳴った後は30）
    var requiredSteps: Int
    /// 次の見張りのアラーム
    var nextWatchAt: Date?
    /// 止めたのが何回目のアラームか
    var stoppedStage: Int?
    /// 見張りのアラームが鳴った（歩くか計算で止める）
    var needsProof: Bool
    /// 歩数を最後に確かめた時刻
    var stepsAt: Date?

    static let idle = WakeWatchState(isWatching: false, stopAt: nil, steps: 0, requiredSteps: WakeWatchLogic.awakeSteps,
                                     nextWatchAt: nil, stoppedStage: nil, needsProof: false, stepsAt: nil)

    static func load(now: Date = .now) -> WakeWatchState { make(WakeWatchStore.record(), now: now) }

    static func make(_ r: WakeWatchRecord?, now: Date) -> WakeWatchState {
        guard let r, WakeWatchLogic.isActive(r, now: now) else { return .idle }
        let proof = r.needsProof
        return WakeWatchState(
            isWatching: true, stopAt: r.stopAt,
            steps: proof ? r.stepsSinceRing : r.steps,
            requiredSteps: proof ? WakeWatchLogic.ringSteps : WakeWatchLogic.awakeSteps,
            nextWatchAt: r.alarms.map(\.at).filter { $0 > now }.min(),
            stoppedStage: r.stoppedStage, needsProof: proof, stepsAt: r.stepsAt)
    }
}

// MARK: - 歩数（CoreMotion）

enum WakeSteps {
    /// ウィジェット（拡張）の中では歩数を読まない（許可の説明が無く、落ちることがあるため）
    static var isExtension: Bool { Bundle.main.bundleURL.pathExtension == "appex" }

    #if canImport(CoreMotion)
    private static let pedometer = CMPedometer()
    #endif

    static var isAvailable: Bool {
        #if canImport(CoreMotion)
        return !isExtension && CMPedometer.isStepCountingAvailable()
        #else
        return false
        #endif
    }

    /// 許可がまだ決まっていない（アプリの中で一度だけ尋ねる）
    static var needsPermission: Bool {
        #if canImport(CoreMotion)
        return isAvailable && CMPedometer.authorizationStatus() == .notDetermined
        #else
        return false
        #endif
    }

    static var isDenied: Bool {
        #if canImport(CoreMotion)
        let s = CMPedometer.authorizationStatus()
        return s == .denied || s == .restricted
        #else
        return true
        #endif
    }

    /// 期間の歩数。読めなければ nil（数秒で打ち切る）
    static func count(from: Date, to: Date) async -> Int? {
        #if canImport(CoreMotion)
        guard isAvailable, !isDenied, to > from else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<Int?, Never>) in
            let once = ResumeOnce()
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                once.run { c.resume(returning: data?.numberOfSteps.intValue) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                once.run { c.resume(returning: nil) }
            }
        }
        #else
        return nil
        #endif
    }

    /// 歩数の許可を尋ねる（アプリの中で。ダミーの問い合わせで確認が出る）
    static func requestAccess() async {
        guard needsPermission, !LaunchArguments.isScripted else { return }
        _ = await count(from: Date().addingTimeInterval(-60), to: Date())
    }

    /// 歩き始めた時刻を、2分ごとの歩数から探す（最大60分）
    static func stepStart(from: Date, to: Date) async -> Date? {
        guard isAvailable, !isDenied else { return nil }
        let step = TimeInterval(WakeWatchLogic.bucketMinutes * 60)
        var t = from
        let end = min(to, from.addingTimeInterval(3600))
        while t < end {
            let u = min(end, t.addingTimeInterval(step))
            guard let n = await count(from: t, to: u) else { return nil }
            if let s = WakeWatchLogic.stepStart(buckets: [(t, n)]) { return s }
            t = u
        }
        return nil
    }
}

/// 続きを1度だけ呼ぶ（歩数の問い合わせと打ち切りのどちらか早い方）
final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func run(_ f: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        f()
    }
}

// MARK: - 見張りの操作（アプリと AppIntent から呼ぶ）

enum WakeWatchActions {
    /// 元の起床アラームの「止める」。見張りを始める。失敗したら元のアラームは残す
    static func originalStopped(stage: Int, day: String, now: Date = .now) async {
        let settings = WakeStore.settings()
        let state = WakeStore.state()
        let todayKey = WakeLogic.key(now)
        guard settings.watch, day == todayKey, WakeLogic.checkedIn(state, now: now) == nil else { return }
        if let r = WakeWatchStore.record(), r.day == todayKey { return }   // 今日はもう見張っている（終わった後も始め直さない）

        var r = WakeWatchRecord(day: todayKey, stopAt: now, stoppedStage: stage)
        WakeWatchStore.save(r)   // 先に記録（この後で落ちても、元のアラームは残っている）

        let times = WakeWatchLogic.watchTimes(stopAt: now)
        for (i, at) in times.enumerated() {
            if let id = await scheduleWatchAlarm(at: at, number: i + 1, last: false) {
                r.alarms.append(WakeScheduledAlarm(id: id, at: at, day: todayKey, stage: i + 1))
            }
        }
        WakeWatchStore.save(r)

        // 見張りのアラームがすべて入ったときだけ、元のアラームの残りを取り消す
        if r.alarms.count == times.count {
            cancelOriginals(day: todayKey, after: now)
            r.replacedOriginals = true
            WakeWatchStore.save(r)
        }
        await WakeActivityControl.sync(now: now)
        await ReviewActions.morningTriggered(now: now, notify: true)
    }

    /// 元のアラームのうち、これから鳴るものを取り消す
    private static func cancelOriginals(day: String, after now: Date) {
        var state = WakeStore.state()
        let later = state.alarms.filter { $0.day == day && $0.at > now.addingTimeInterval(5) }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for a in later {
                if let id = UUID(uuidString: a.id) { try? AlarmManager.shared.cancel(id: id) }
            }
        }
        #endif
        let ids = Set(later.map(\.id))
        state.alarms.removeAll { ids.contains($0.id) }
        WakeStore.save(state)
    }

    /// 見張りのアラームの「止める」：歩いていなければ3分後にまた鳴らす
    static func watchStopped(now: Date = .now) async {
        guard var r = WakeWatchStore.active(now: now) else { return }
        let steps = await WakeSteps.count(from: r.stopAt, to: now)
        if let steps { r.steps = steps; r.stepsAt = now }
        if r.rangAt == nil {
            r.rangAt = now
            r.stepsAtRing = r.steps
        }
        WakeWatchStore.save(r)
        if WakeWatchLogic.decide(r, steps: r.steps) == .awake {
            await finish(by: "steps", now: now)
            return
        }
        let maxRearms = WakeStore.settings().watchRearms
        switch WakeWatchLogic.onWatchAlarmStop(r, missionPassed: false, stepsSinceRing: r.stepsSinceRing,
                                               now: now, maxRearms: maxRearms) {
        case .resolve:
            await finish(by: "walk", now: now)
        case .rearm(let at):
            await rearm(&r, at: at, maxRearms: maxRearms)
        case .exhausted:
            break
        }
    }

    /// 見張りのアラームの「歩いて止める」：アプリを開いて止める画面を出す。念のため3分後にも鳴らしておく
    static func walkRequested(now: Date = .now) async {
        guard var r = WakeWatchStore.active(now: now) else { return }
        if r.rangAt == nil {
            r.rangAt = now
            r.stepsAtRing = r.steps
        }
        r.openRequested = true
        WakeWatchStore.save(r)
        let maxRearms = WakeStore.settings().watchRearms
        let hasSoon = r.alarms.contains { $0.at > now && $0.at <= now.addingTimeInterval(TimeInterval(WakeWatchLogic.rearmMinutes * 60 + 30)) }
        if !hasSoon && r.rearms < maxRearms {
            await rearm(&r, at: now.addingTimeInterval(TimeInterval(WakeWatchLogic.rearmMinutes * 60)), maxRearms: maxRearms)
        }
    }

    private static func rearm(_ r: inout WakeWatchRecord, at: Date, maxRearms: Int) async {
        let number = r.alarms.count + 1
        if let id = await scheduleWatchAlarm(at: at, number: number, last: r.rearms + 1 >= maxRearms) {
            r.alarms.append(WakeScheduledAlarm(id: id, at: at, day: r.day, stage: number))
            r.rearms += 1
            WakeWatchStore.save(r)
        }
    }

    /// 歩数を確かめる（アプリ・ウィジェットのボタン・AppIntent・バックグラウンド更新から）。約100歩で見張りを終える
    @discardableResult
    static func poll(now: Date = .now) async -> WakeWatchState {
        // 見本（-demo）の時計はずらしてあるので、見本の見張りには触らない
        if ProcessInfo.processInfo.arguments.contains("-demo") { return WakeWatchState.load(now: WakeClock.now) }
        guard let rec = WakeWatchStore.record() else { return .idle }
        if rec.endedAt == nil, !WakeWatchLogic.isActive(rec, now: now) {
            await end(by: "timeout", now: now)   // 長すぎる・日が変わった見張りは静かに終える
            return .idle
        }
        guard var r = WakeWatchStore.active(now: now) else { return .idle }
        if let steps = await WakeSteps.count(from: r.stopAt, to: now) {
            r.steps = steps
            r.stepsAt = now
            WakeWatchStore.save(r)
        }
        switch WakeWatchLogic.decide(r, steps: r.steps) {
        case .awake: await finish(by: "steps", now: now)
        case .ringPassed: await finish(by: "walk", now: now)
        case .keep: break
        }
        return WakeWatchState.load(now: now)
    }

    /// 見張りのアラームを歩いて・計算で止めた、または約100歩：起床として記録する
    static func finish(by: String, now: Date = .now) async {
        guard var r = WakeWatchStore.active(now: now) else { return }
        r.endedBy = by
        WakeWatchStore.save(r)
        // チェックイン（close で見張りのアラームを止め、二度寝の分を数える）
        if await WakeActions.checkIn(at: now) == nil {
            await end(by: by, now: now)   // 受付時間の外などでチェックインできなくても、見張りは終える
        }
    }

    /// チェックインのときに呼ぶ：見張りのアラームを止め、歩き始めを調べて記録を閉じる。今日の記録を返す
    static func closeForCheckIn(now: Date) async -> WakeWatchRecord? {
        guard var r = WakeWatchStore.record(), r.day == WakeLogic.key(now) else { return nil }
        guard r.endedAt == nil else { return r }
        cancelWatchAlarms(r)
        if let steps = await WakeSteps.count(from: r.stopAt, to: now) { r.steps = steps; r.stepsAt = now }
        r.stepStartAt = await WakeSteps.stepStart(from: r.stopAt, to: now)
        r.endedAt = now
        if r.endedBy == nil { r.endedBy = "checkin" }
        r.openRequested = false
        WakeWatchStore.save(r)
        return r
    }

    /// 見張りを終える（チェックインはしない）
    static func end(by: String, now: Date = .now) async {
        guard var r = WakeWatchStore.record(), r.endedAt == nil else { return }
        cancelWatchAlarms(r)
        r.endedAt = now
        r.endedBy = r.endedBy ?? by
        r.openRequested = false
        WakeWatchStore.save(r)
        await WakeActivityControl.sync(now: now)
    }

    private static func cancelWatchAlarms(_ r: WakeWatchRecord) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for a in r.alarms {
                if let id = UUID(uuidString: a.id) {
                    try? AlarmManager.shared.stop(id: id)
                    try? AlarmManager.shared.cancel(id: id)
                }
            }
        }
        #endif
    }

    /// 止める画面を出したので、「歩いて止める」の印を消す
    static func clearOpenRequest() {
        guard var r = WakeWatchStore.record(), r.openRequested else { return }
        r.openRequested = false
        WakeWatchStore.save(r)
    }

    // MARK: AlarmKit

    /// 見張りのアラームを1つ予約する。予約できたら識別子を返す
    static func scheduleWatchAlarm(at: Date, number: Int, last: Bool) async -> String? {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let id = UUID()
            do {
                try await scheduleWatchAlarmKit(id: id, at: at, number: number, last: last)
                return id.uuidString
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func scheduleWatchAlarmKit(id: UUID, at: Date, number: Int, last: Bool) async throws {
        let stop = AlarmButton(text: "止める", textColor: .white, systemImageName: "stop.circle")
        let walk = AlarmButton(text: "歩いて止める", textColor: .white, systemImageName: "figure.walk")
        let tail: String = last ? "これが最後の見張りです" : "止めるだけだと\(WakeWatchLogic.rearmMinutes)分後にまた鳴ります"
        let title = "二度寝の見張り・\(WakeWatchLogic.ringSteps)歩 歩くと止まります・\(tail)"
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stop,
            secondaryButton: walk,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<WakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeAlarmMetadata(stage: 100 + number),
            tintColor: Color(red: 0.91, green: 0.38, blue: 0.36)
        )
        let config = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(at),
            attributes: attributes,
            stopIntent: WakeWatchStopIntent(alarmID: id.uuidString),
            secondaryIntent: WakeWatchWalkIntent(alarmID: id.uuidString),
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
    }
    #endif
}
