import Foundation
import SwiftUI
import UserNotifications
import AppIntents
#if canImport(AlarmKit)
import AlarmKit
#endif

// 起床の段階アラーム（AlarmKit）の予約・取り消しと、チェックイン・通知。
// アプリ本体と、チェックインの AppIntent（アプリの中で動く LiveActivityIntent）から呼ぶ。

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct WakeAlarmMetadata: AlarmMetadata {
    var stage: Int = 1
}
#endif

enum WakeActions {
    /// 予約する日数（アプリを開かない日が続いても鳴るように、少し先まで）
    static let horizonDays = 6

    // MARK: アラーム

    /// アラームの許可を求める。許可されていれば true
    static func authorizeAlarms() async -> Bool {
        if LaunchArguments.isScripted { return false }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    /// 設定に合わせて、これから鳴る段階アラームを予約し直す。結果の説明を返す
    @discardableResult
    static func reschedule(now: Date = .now) async -> String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await rescheduleAlarmKit(now: now)
        }
        return "このiOSではアラームを使えません（iOS 26以上が必要）"
        #else
        return "このビルドにはAlarmKitが入っていません"
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func rescheduleAlarmKit(now: Date) async -> String {
        let manager = AlarmManager.shared
        guard await authorizeAlarms() else { return "アラームの許可がありません（設定アプリで許可してください）" }
        let settings = WakeStore.settings()
        var state = WakeStore.state()

        // 鳴っている最中のものと、二度寝の見張りのアラーム以外は、いったんすべて取り消す
        let existing: [Alarm] = (try? manager.alarms) ?? []
        let watch: WakeWatchRecord? = WakeWatchStore.active(now: now)
        let watchIDs: Set<String> = Set((watch?.alarms ?? []).map(\.id))
        for a in existing where a.state != .alerting && !watchIDs.contains(a.id.uuidString) {
            try? manager.cancel(id: a.id)
        }
        let alerting = Set(existing.filter { $0.state == .alerting }.map { $0.id.uuidString })
        state.alarms = state.alarms.filter { alerting.contains($0.id) }

        let todayKey = WakeLogic.key(now)
        let checked = WakeLogic.checkedIn(state, now: now) != nil
        // 見張りがこれから鳴る見張りのアラームを持っているときだけ、今日の元のアラームを入れ直さない。
        // 見張りのアラームが消えていたら（失敗・上限）、元のアラームの残りを入れ直す（元の動きに戻る）
        let liveIDs: Set<String> = Set(existing.map { $0.id.uuidString })
        let watching: Bool = watch.map { w in
            w.replacedOriginals && w.alarms.contains { $0.at > now && liveIDs.contains($0.id) }
        } ?? false
        var count = 0
        var firstAt: Date? = nil
        for plan in WakeLogic.plans(from: now, days: horizonDays, settings: settings, state: state) where !plan.isSkipped {
            if plan.day == todayKey && (checked || watching) { continue }
            var any = false
            for stage in plan.stages where stage.at > now {
                let id = UUID()
                do {
                    let next: Date? = plan.stages.first(where: { $0.number == stage.number + 1 })?.at
                    try await scheduleOne(id: id, stage: stage, total: plan.stages.count, next: next, day: plan.day, watch: settings.watch)
                    state.alarms.append(WakeScheduledAlarm(id: id.uuidString, at: stage.at, day: plan.day, stage: stage.number))
                    count += 1
                    any = true
                    if firstAt == nil { firstAt = stage.at }
                } catch {
                    continue
                }
            }
            if any && !state.pendingDays.contains(plan.day) { state.pendingDays.append(plan.day) }
        }
        WakeStore.save(state)
        guard let firstAt else { return "予約したアラームはありません" }
        return "次は \(WakeLogic.dayLabel(firstAt, now: now)) \(JP.time(firstAt))。\(count)件のアラームを予約しました"
    }

    @available(iOS 26.0, *)
    private static func scheduleOne(id: UUID, stage: WakePlan.Stage, total: Int, next: Date?,
                                    day: String, watch: Bool) async throws {
        let stop = AlarmButton(text: "止める", textColor: .white, systemImageName: "stop.circle")
        let up = AlarmButton(text: "起きた！", textColor: .white, systemImageName: "sun.max.fill")
        // 「止める」は今の音を止めるだけで、次のアラームは鳴る。そのことを題名で伝える
        let head: String = stage.name.isEmpty ? "起床アラーム \(stage.number)/\(total)" : "\(stage.name)（\(stage.number)/\(total)）"
        let tail: String
        if watch {
            tail = "止めると二度寝の見張りが始まります"
        } else if let next {
            tail = "止めても\(JP.time(next))にまた鳴ります"
        } else {
            tail = "最後のアラームです"
        }
        let title = "\(head)・\(tail)"
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stop,
            secondaryButton: up,
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<WakeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeAlarmMetadata(stage: stage.number),
            tintColor: Color(red: 0.91, green: 0.38, blue: 0.36)
        )
        // 「止める」で二度寝の見張りを始める（見張りがオフなら今までどおり、音を止めるだけ）。
        // 見張りの処理が失敗しても、元のアラームは取り消されずに鳴る
        let stopIntent: (any LiveActivityIntent)? = watch
            ? WakeStopIntent(alarmID: id.uuidString, stage: stage.number, day: day) : nil
        let config = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>(
            countdownDuration: nil,
            schedule: .fixed(stage.at),
            attributes: attributes,
            stopIntent: stopIntent,
            secondaryIntent: WakeCheckInIntent(),
            sound: .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
    }
    #endif

    /// 指定した日のアラームを止めて取り消す
    static func cancelAlarms(day: String) {
        var state = WakeStore.state()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for a in state.alarms where a.day == day {
                if let id = UUID(uuidString: a.id) {
                    try? AlarmManager.shared.stop(id: id)
                    try? AlarmManager.shared.cancel(id: id)
                }
            }
        }
        #endif
        state.alarms.removeAll { $0.day == day }
        WakeStore.save(state)
    }

    // MARK: チェックイン

    /// 起床チェックイン：今日の残りのアラームを取り消し、記録を保存し、持ち物の通知を予約する。
    /// 受付時間（最初のアラームの2時間前〜その日の受付終わり）の外では何もしない（nil を返す）
    @discardableResult
    static func checkIn(at now: Date = .now, fromApp: Bool = false) async -> WakeSession? {
        let todayKey = WakeLogic.key(now)
        var sessions = WakeStore.sessions()
        var state = WakeStore.state()
        let settings = WakeStore.settings()
        if state.day == todayKey, state.checkInAt != nil, let s = sessions.first(where: { $0.day == todayKey }) {
            _ = await WakeWatchActions.closeForCheckIn(now: now)   // 見張りが残っていたら止める
            return s
        }
        guard WakeLogic.canCheckIn(now: now, settings: settings, state: state) else { return nil }
        let plan = WakeLogic.plan(for: now, settings: settings, state: state)
        // 二度寝の見張り中なら、見張りを止めて「何回目で止めたか・二度寝の分」を記録する
        let watch: WakeWatchRecord? = await WakeWatchActions.closeForCheckIn(now: now)
        var session: WakeSession
        if let watch {
            let over: Int = WakeWatchLogic.oversleepMinutes(stopAt: watch.stopAt, stepStart: watch.stepStartAt, awakeAt: now)
            session = WakeSession(day: todayKey, checkInAt: now, stage: watch.stoppedStage)
            session.oversleep = over
            session.stopAt = watch.stopAt
            session.watchedBy = watch.endedBy
        } else {
            let stage = plan.map { WakeLogic.reached($0, at: now) } ?? 0
            session = WakeSession(day: todayKey, checkInAt: now, stage: stage)
        }
        sessions.removeAll { $0.day == todayKey }
        sessions.append(session)
        WakeStore.save(sessions)

        state.day = todayKey
        state.checkInAt = now
        state.routineDone = []
        state.belongingsDone = []
        state.pendingDays.removeAll { $0 == todayKey }
        if settings.skipDay != nil && settings.skipDay! <= todayKey {
            var s2 = settings
            s2.skipDay = nil
            WakeStore.save(s2)
        }
        WakeStore.save(state)

        cancelAlarms(day: todayKey)
        await scheduleBelongings(now: now)
        await WakeActivityControl.sync(now: now)
        await reschedule(now: now)
        // 朝の見返し（アプリの中で押したときは通知を出さず、画面のカードから始める）
        await ReviewActions.morningTriggered(now: now, notify: !fromApp)
        return session
    }

    /// 予約されているアラームの数（AlarmKit に実際に入っているもの）。分からなければ nil
    static func liveAlarmCount(day: String) -> Int? {
        let state = WakeStore.state()
        let ids = Set(state.alarms.filter { $0.day == day }.map(\.id))
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard let live = try? AlarmManager.shared.alarms else { return nil }
            return live.filter { ids.contains($0.id.uuidString) }.count
        }
        #endif
        return nil
    }
}

/// アラームの音を止める（AppIntent の最初に呼ぶ。失敗しても気にしない）
enum WakeAlarmStop {
    static func stop(_ alarmID: String) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        #endif
    }
}

extension WakeActions {

    /// チェックインの取り消し：今日の記録を消して状態を戻し、今日の残りのアラームを予約し直す
    static func undoCheckIn(now: Date = .now) async {
        let todayKey = WakeLogic.key(now)
        var sessions = WakeStore.sessions()
        sessions.removeAll { $0.day == todayKey }
        WakeStore.save(sessions)

        var state = WakeStore.state()
        state.checkInAt = nil
        state.routineDone = []
        state.belongingsDone = []
        let settings = WakeStore.settings()
        if let plan = WakeLogic.plan(for: now, settings: settings, state: state), !plan.isSkipped,
           !state.pendingDays.contains(todayKey) {
            state.pendingDays.append(todayKey)
        }
        WakeStore.save(state)

        await remove(prefix: "wake-belongings")
        await WakeActivityControl.sync(now: now)
        await reschedule(now: now)
    }

    // MARK: 通知（識別子は wake- で始める）

    static func authorizeNotifications() async {
        if LaunchArguments.isScripted { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private static func remove(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func add(id: String, title: String, body: String, at: Date, now: Date) async {
        let interval = at.timeIntervalSince(now)
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// 出発5分前の持ち物の確認
    static func scheduleBelongings(now: Date = .now) async {
        await remove(prefix: "wake-belongings")
        let s = WakeStore.settings()
        guard let dep = WakeLogic.departure(now: now, settings: s), !s.belongings.isEmpty else { return }
        let items = s.belongings.map(\.name).joined(separator: "・")
        await add(id: "wake-belongings", title: "出発まで5分", body: "持ち物を確認：\(items)",
                  at: dep.addingTimeInterval(-5 * 60), now: now)
    }

    /// 就寝の30分前に、次の起床時刻と段階の数を知らせる
    static func scheduleBedtime(now: Date = .now) async {
        await remove(prefix: "wake-bedtime")
        let s = WakeStore.settings()
        let state = WakeStore.state()
        for plan in WakeLogic.plans(from: now, days: horizonDays, settings: s, state: state).dropFirst(0) where !plan.isSkipped {
            let bed = WakeLogic.bedtime(before: plan, settings: s)
            await add(id: "wake-bedtime-\(plan.day)", title: "そろそろ寝る時間です",
                      body: "\(JP.date(plan.dayStart)) は \(JP.time(plan.first)) 起床・アラーム\(plan.stages.count)回。スマホを充電しておきましょう。",
                      at: bed.addingTimeInterval(-30 * 60), now: now)
        }
    }
}
