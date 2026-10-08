import SwiftUI
import EventKit

/// 起床タブの状態。保存は WakeStore（ウィジェットと共有）
@MainActor
final class WakeViewModel: ObservableObject {
    @Published var settings: WakeSettings
    @Published var state: WakeDayState
    @Published var sessions: [WakeSession]
    @Published var message = ""
    @Published var feedback = 0
    let demo: Bool
    private var rescheduleTask: Task<Void, Never>?

    init() {
        let args = ProcessInfo.processInfo.arguments
        demo = args.contains("-demo")
        if demo {
            var phase = "after"
            if let i = args.firstIndex(of: "-wakePhase"), i + 1 < args.count { phase = args[i + 1] }
            WakeDemo.install(phase: phase)
        }
        settings = WakeStore.settings()
        state = WakeStore.state()
        sessions = WakeStore.sessions()
    }

    var now: Date { WakeClock.now }
    var phase: WakePhase { WakeLogic.phase(now: now, settings: settings, state: state) }
    var todayPlan: WakePlan? { WakeLogic.plan(for: now, settings: settings, state: state) }
    var nextPlan: WakePlan? { WakeLogic.nextPlan(now: now, settings: settings, state: state) }
    /// オフの日も含めた次の起床日（「明日だけオフ」の表示用）
    var nextPlanAny: WakePlan? { WakeLogic.nextPlan(now: now, settings: settings, state: state, includeSkipped: true) }
    var checkInAt: Date? { WakeLogic.checkedIn(state, now: now) }
    var todaySession: WakeSession? { sessions.first { $0.day == WakeLogic.key(now) } }
    var departure: Date? { WakeLogic.departure(now: now, settings: settings) }
    var remainingRoutine: [WakeRoutineItem] { WakeLogic.remainingRoutine(settings: settings, state: state) }

    /// 画面を開いたとき：最新を読み、未チェックインを記録し、アラームを予約し直す
    func refresh(reschedule: Bool) {
        if !demo { WakeLogic.recordMissed(now: now) }
        settings = WakeStore.settings()
        state = WakeStore.state()
        sessions = WakeStore.sessions()
        if reschedule && !demo { scheduleAll() }
    }

    func update(_ change: (inout WakeSettings) -> Void) {
        change(&settings)
        WakeStore.save(settings)
        if !demo {
            rescheduleTask?.cancel()
            rescheduleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                self?.scheduleAll()
            }
        }
    }

    func scheduleAll() {
        Task {
            await WakeHolidays.refresh(skip: settings.skipHolidays)
            let msg = await WakeActions.reschedule()
            await WakeActions.authorizeNotifications()
            await WakeActions.scheduleBedtime()
            await WakeActions.scheduleBelongings()
            message = msg
            state = WakeStore.state()
        }
    }

    func checkIn() {
        if demo {
            let k = WakeLogic.key(now)
            let stage = todayPlan.map { WakeLogic.reached($0, at: now) } ?? 0
            state.day = k
            state.checkInAt = now
            sessions.removeAll { $0.day == k }
            sessions.insert(WakeSession(day: k, checkInAt: now, stage: stage, score: WakeLogic.score(stage: stage)), at: 0)
            feedback += 1
            return
        }
        Task {
            await WakeActions.checkIn(at: .now)
            refresh(reschedule: false)
            feedback += 1
        }
    }

    func toggleRoutine(_ item: WakeRoutineItem) {
        if state.routineDone.contains(item.id) { state.routineDone.removeAll { $0 == item.id } }
        else { state.routineDone.append(item.id); feedback += 1 }
        if !demo { saveState() }
    }

    func toggleBelonging(_ item: WakeBelonging) {
        if state.belongingsDone.contains(item.id) { state.belongingsDone.removeAll { $0 == item.id } }
        else { state.belongingsDone.append(item.id) }
        if !demo { saveState() }
    }

    private func saveState() {
        var s = WakeStore.state()
        s.routineDone = state.routineDone
        s.belongingsDone = state.belongingsDone
        WakeStore.save(s)
    }

    /// 次の起床日だけオフ（もう一度押すと元に戻す）
    var isNextSkipped: Bool {
        guard let p = nextPlanAny else { return false }
        return settings.skipDay == p.day
    }

    func toggleSkipNext() {
        if settings.skipDay != nil && isNextSkipped {
            update { $0.skipDay = nil }
        } else if let p = nextPlan {
            update { $0.skipDay = p.day }
        }
    }
}

/// 祝日：カレンダーの名前に「祝日」か「Holiday」を含むものから読み取る
enum WakeHolidays {
    static func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return true }
        guard status == .notDetermined else { return false }
        return (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    static func refresh(skip: Bool) async {
        guard skip, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let store = EKEventStore()
        let cals = store.calendars(for: .event).filter {
            $0.title.contains("祝日") || $0.title.localizedCaseInsensitiveContains("holiday")
        }
        guard !cals.isEmpty else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 21, to: start) else { return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: cals)
        var map: [String: String] = [:]
        for e in store.events(matching: pred) {
            guard let d = e.startDate else { continue }
            map[WakeLogic.key(d)] = e.title ?? "祝日"
        }
        var state = WakeStore.state()
        state.holidays = map
        WakeStore.save(state)
    }
}

/// 画面確認用の見本（-demo）。一般的な内容だけ
enum WakeDemo {
    static func install(phase: String) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let minute: Int
        switch phase {
        case "before": minute = 4 * 60 + 40
        case "window": minute = 7 * 60 + 12
        case "evening": minute = 22 * 60 + 30
        default: minute = 7 * 60 + 31
        }
        let fake = cal.date(byAdding: .minute, value: minute, to: today) ?? .now
        WakeClock.offset = fake.timeIntervalSinceNow

        var s = WakeSettings()
        s.days = (0..<7).map { _ in WakeDay(on: true, wake: 420, departure: 490) }
        s.skipHolidays = false
        WakeStore.save(s)

        var st = WakeDayState()
        if phase == "after" {
            st.day = WakeLogic.key(fake)
            st.checkInAt = cal.date(byAdding: .minute, value: 7 * 60 + 8, to: today)
            st.routineDone = Array(s.routine.prefix(2).map(\.id))
            st.belongingsDone = Array(s.belongings.prefix(1).map(\.id))
        }
        WakeStore.save(st)

        var sessions: [WakeSession] = []
        let stages = [1, 2, 1, 1, 3, 0, 1, 2, 1, 4, 1, 1, 2]
        for (i, stage) in stages.enumerated() {
            guard let d = cal.date(byAdding: .day, value: -(i + 1), to: today) else { continue }
            let at = cal.date(byAdding: .minute, value: 420 + max(0, stage - 1) * 10 + 3, to: d)
            sessions.append(WakeSession(day: WakeLogic.key(d), checkInAt: at, stage: stage, score: WakeLogic.score(stage: stage)))
        }
        if phase == "after" || phase == "evening" {
            sessions.append(WakeSession(day: WakeLogic.key(today), checkInAt: cal.date(byAdding: .minute, value: 428, to: today),
                                        stage: 1, score: 100))
            if phase == "evening" {
                st.day = WakeLogic.key(today)
                st.checkInAt = cal.date(byAdding: .minute, value: 428, to: today)
                WakeStore.save(st)
            }
        }
        WakeStore.save(sessions)
    }
}
