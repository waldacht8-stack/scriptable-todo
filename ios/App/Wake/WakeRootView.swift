import SwiftUI

/// 起床タブの入口。時間帯（起床前・起床中・朝・夜）で画面が変わる。色は palette に従う。
struct WakeRootView: View {
    @StateObject private var model = WakeViewModel()
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var scene

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                ScrollView {
                    VStack(spacing: 16) {
                        WakeHeader(model: model)
                        switch model.phase {
                        case .before: WakeBeforeView(model: model)
                        case .window: WakeWindowView(model: model)
                        case .morning, .day: WakeMorningView(model: model)
                        case .evening: WakeEveningView(model: model)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .paletteBackground(p)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WakeRoute.self) { route in
                switch route {
                case .settings: WakeSettingsView(model: model)
                case .records: WakeRecordsView(model: model)
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.feedback)
        .onAppear { model.refresh(reschedule: true) }
        .onChange(of: scene) { _, s in if s == .active { model.refresh(reschedule: true) } }
    }
}

enum WakeRoute: Hashable {
    case settings
    case records
}

// MARK: - 見出し

struct WakeHeader: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    private var title: String {
        switch model.phase {
        case .before: return "次の起床"
        case .window: return "おはよう"
        case .morning: return "出発の準備"
        case .day: return "今日の起床"
        case .evening: return "おやすみ前"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(JP.date(model.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text(title).font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            NavigationLink(value: WakeRoute.records) { WakeRoundIcon(name: "chart.bar.fill") }
                .accessibilityLabel("記録")
            NavigationLink(value: WakeRoute.settings) { WakeRoundIcon(name: "gearshape.fill") }
                .accessibilityLabel("起床の設定")
        }
        .padding(.top, 16)
    }
}

struct WakeRoundIcon: View {
    @Environment(\.palette) private var p
    let name: String
    var body: some View {
        Image(systemName: name).font(.headline).foregroundStyle(p.text)
            .frame(width: 44, height: 44)
            .background(p.card, in: Circle())
    }
}

/// カードの小見出し
struct WakeCardTitle: View {
    @Environment(\.palette) private var p
    let text: String
    let icon: String
    var body: some View {
        Label(text, systemImage: icon).font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
    }
}

// MARK: - 起床前

struct WakeBeforeView: View {
    @ObservedObject var model: WakeViewModel
    var body: some View {
        WakeNextCard(model: model)
        if let plan = model.nextPlan { WakeStageTimeline(plan: plan, reached: 0) }
        WakeSkipCard(model: model)
        WakeSummaryRow(model: model)
        if !model.message.isEmpty { WakeMessage(text: model.message) }
    }
}

/// 次の起床時刻（大きな数字）
struct WakeNextCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WakeCardTitle(text: "次のアラーム", icon: "alarm.fill")
            if let plan = model.nextPlan {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(WakeLogic.dayLabel(plan.first, now: model.now)).font(.title3.weight(.bold)).foregroundStyle(p.sub)
                    Text(JP.time(plan.first)).font(.system(size: 72, weight: .heavy, design: p.fontDesign))
                        .foregroundStyle(p.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                Text("あと \(WakeLogic.duration(plan.first.timeIntervalSince(model.now)))・段階\(plan.stages.count)つ（\(JP.time(plan.last))まで）")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(p.accent)
                if let dep = plan.departure {
                    Text("出発 \(JP.time(dep))").font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
                }
            } else {
                Text("予定はありません").font(.title.bold()).foregroundStyle(p.text)
                Text("設定で起きる曜日と時刻を決めてください").font(.footnote).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p, padding: 22)
    }
}

/// 段階の一覧（鳴った段階に印）
struct WakeStageTimeline: View {
    @Environment(\.palette) private var p
    let plan: WakePlan
    let reached: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WakeCardTitle(text: "段階アラーム", icon: "bell.and.waves.left.and.right.fill")
            ForEach(plan.stages, id: \.number) { st in
                let done = st.number <= reached
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(done ? p.accent : p.accent.opacity(0.14))
                        Text("\(st.number)").font(.headline.weight(.heavy)).foregroundStyle(done ? p.onAccent : p.accent)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.name).font(.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Text("\(st.score)点").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                    }
                    Spacer(minLength: 0)
                    Text(JP.time(st.at)).font(.system(size: 26, weight: .bold, design: p.fontDesign))
                        .monospacedDigit().foregroundStyle(done ? p.sub : p.text)
                }
            }
        }
        .paletteCard(p)
    }
}

/// 「明日だけオフ」
struct WakeSkipCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let skipped = model.isNextSkipped
        Button { model.toggleSkipNext() } label: {
            HStack(spacing: 14) {
                Image(systemName: skipped ? "moon.zzz.fill" : "moon.zzz")
                    .font(.title2).foregroundStyle(skipped ? p.onAccent : p.accent)
                    .frame(width: 48, height: 48)
                    .background(skipped ? p.accent : p.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(skipped ? "明日だけオフにしています" : "明日だけオフ").font(.headline).foregroundStyle(p.text)
                    Text(skipText).font(.caption).foregroundStyle(p.sub).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: skipped ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(skipped ? p.accent : p.sub)
            }
            .paletteCard(p)
        }
        .buttonStyle(.plain)
    }

    private var skipText: String {
        if model.isNextSkipped, let plan = model.nextPlanAny { return "\(JP.date(plan.dayStart)) は鳴りません。押すと元に戻します" }
        if let plan = model.nextPlan { return "\(JP.date(plan.dayStart)) の分だけ鳴らしません。繰り返しはそのまま" }
        return "次の起床日がありません"
    }
}

/// 平均・連続・回数の小さなタイル
struct WakeSummaryRow: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        NavigationLink(value: WakeRoute.records) {
            HStack(spacing: 10) {
                tile("7日の平均", WakeLogic.average(model.sessions, days: 7, now: model.now).map { "\($0)" } ?? "―", "点")
                tile("連続", "\(WakeLogic.streak(model.sessions))", "日")
                tile("記録", "\(model.sessions.count)", "日")
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p, padding: 14)
    }
}

struct WakeMessage: View {
    @Environment(\.palette) private var p
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(p.sub).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }
}

// MARK: - 起床中（チェックイン待ち）

struct WakeWindowView: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let plan = model.todayPlan
        let reached = plan.map { WakeLogic.reached($0, at: model.now) } ?? 0
        VStack(spacing: 18) {
            Text(statusText(plan: plan, reached: reached)).font(.headline).foregroundStyle(p.sub)
                .multilineTextAlignment(.center)
            Button { model.checkIn() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").font(.system(size: 44, weight: .bold))
                    Text("起きた！").font(.system(size: 46, weight: .heavy, design: p.fontDesign))
                    Text("今なら \(WakeLogic.score(stage: reached))点").font(.headline)
                }
                .foregroundStyle(p.onAccent)
                .frame(width: 240, height: 240)
                .background(Circle().fill(p.accent).shadow(color: p.accent.opacity(0.4), radius: 20, y: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("起きた！チェックイン")
            Text("押すと残りのアラームが止まります").font(.footnote).foregroundStyle(p.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .paletteCard(p)
        if let plan { WakeStageTimeline(plan: plan, reached: reached) }
    }

    private func statusText(plan: WakePlan?, reached: Int) -> String {
        guard let plan, !plan.stages.isEmpty else { return "チェックインを待っています" }
        if reached == 0 { return "最初のアラームは \(JP.time(plan.first))" }
        let st = plan.stages[min(reached, plan.stages.count) - 1]
        if let next = plan.stages.first(where: { $0.at > model.now }) {
            return "段階\(st.number)「\(st.name)」が鳴りました\n次は \(JP.time(next.at))（段階\(next.number)）"
        }
        return "最終段階が鳴りました"
    }
}

// MARK: - 朝（チェックイン後）

struct WakeMorningView: View {
    @ObservedObject var model: WakeViewModel

    var body: some View {
        WakeResultCard(model: model)
        if let dep = model.departure, dep > model.now { WakeCountdownCard(model: model, departure: dep) }
        if !model.settings.routine.isEmpty { WakeRoutineCard(model: model) }
        if !model.settings.belongings.isEmpty { WakeBelongingsCard(model: model) }
        WakeTodoCard(now: model.now)
    }
}

/// 今朝の結果（スコア）
struct WakeResultCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let s = model.todaySession
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                WakeCardTitle(text: "今朝の起床", icon: "sun.max.fill")
                Text(model.checkInAt.map { JP.time($0) } ?? "--:--")
                    .font(.system(size: 44, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text).monospacedDigit()
                Text(stageText(s)).font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text("\(s?.score ?? 0)").font(.system(size: 40, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.onAccent)
                Text("点").font(.caption.weight(.bold)).foregroundStyle(p.onAccent)
            }
            .frame(width: 96, height: 96)
            .background(Circle().fill(p.accent))
        }
        .paletteCard(p, padding: 22)
    }

    private func stageText(_ s: WakeSession?) -> String {
        guard let s else { return "" }
        let streak = WakeLogic.streak(model.sessions)
        let st = s.stage == 0 ? "アラームの前に起床" : "段階\(s.stage)で起床"
        return streak > 1 ? "\(st)・\(streak)日連続" : st
    }
}

/// 出発までのカウントダウン
struct WakeCountdownCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p
    let departure: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = WakeClock.now
            let left = max(0, departure.timeIntervalSince(now))
            let need = model.remainingRoutine.map(\.minutes).reduce(0, +)
            let late = Int((now.addingTimeInterval(Double(need) * 60).timeIntervalSince(departure) / 60).rounded(.up))
            VStack(alignment: .leading, spacing: 6) {
                WakeCardTitle(text: "出発まで", icon: "figure.walk.departure")
                Text(format(left)).font(.system(size: 64, weight: .heavy, design: p.fontDesign))
                    .monospacedDigit().foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                HStack {
                    Text("出発 \(JP.time(departure))").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                    Spacer(minLength: 0)
                    if late > 0 {
                        Label("\(late)分遅れそう", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(p.overdue)
                    } else if need > 0 {
                        Text("ルーティン残り \(need)分").font(.subheadline.weight(.semibold)).foregroundStyle(p.accent)
                    } else {
                        Label("出発準備OK", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                    }
                }
            }
            .paletteCard(p, padding: 22)
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 朝のルーティン（順番に。次の項目を強調）
struct WakeRoutineCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let next = model.remainingRoutine.first?.id
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                WakeCardTitle(text: "朝のルーティン", icon: "list.number")
                Spacer()
                Text("\(model.settings.routine.count - model.remainingRoutine.count)/\(model.settings.routine.count)")
                    .font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
            }
            ForEach(model.settings.routine) { item in
                let done = model.state.routineDone.contains(item.id)
                let isNext = item.id == next
                Button { model.toggleRoutine(item) } label: {
                    HStack(spacing: 14) {
                        CheckMark(done: done, size: 30)
                        Text(item.name).font(isNext ? .title3.weight(.bold) : .body.weight(.semibold))
                            .foregroundStyle(done ? p.sub : p.text).strikethrough(done).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(item.minutes)分").font(.subheadline.weight(.semibold)).foregroundStyle(isNext ? p.accent : p.sub)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .paletteCard(p)
    }
}

/// 持ち物
struct WakeBelongingsCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WakeCardTitle(text: "持ち物", icon: "bag.fill")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.settings.belongings) { item in
                    let done = model.state.belongingsDone.contains(item.id)
                    Button { model.toggleBelonging(item) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3)
                            Text(item.name).font(.body.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(done ? p.onAccent : p.text)
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(done ? p.accent : p.accent.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: min(p.radius, 16), style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .paletteCard(p)
    }
}

/// 今日のTODO（読み取りだけ）
struct WakeTodoCard: View {
    @Environment(\.palette) private var p
    let now: Date

    private var items: [TodoItem] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return TodoData.sorted(TodoData.all().filter { t in
            guard !t.done, let due = t.due else { return false }
            return due < end
        })
    }

    var body: some View {
        let list = items
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WakeCardTitle(text: "今日のTODO", icon: "checklist")
                Spacer()
                Text("\(list.count)件").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
            }
            if list.isEmpty {
                Text("今日のTODOはありません").font(.body).foregroundStyle(p.sub)
            }
            ForEach(Array(list.prefix(5))) { t in
                HStack(spacing: 10) {
                    Text(t.isOverdue(now) ? "期限切れ" : JP.clock(t, none: "―"))
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(t.isOverdue(now) ? p.overdue : p.accent)
                        .frame(width: 56, alignment: .leading)
                    Text(t.title).font(.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .paletteCard(p)
    }
}

// MARK: - 夜

struct WakeEveningView: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        if let plan = model.nextPlan {
            WakeBedtimeCard(plan: plan, bed: WakeLogic.bedtime(before: plan, settings: model.settings), now: model.now)
        }
        WakeNextCard(model: model)
        WakeSkipCard(model: model)
        if model.todaySession != nil { WakeResultCard(model: model) }
        WakeSummaryRow(model: model)
    }
}

struct WakeBedtimeCard: View {
    @Environment(\.palette) private var p
    let plan: WakePlan
    let bed: Date
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WakeCardTitle(text: "就寝", icon: "bed.double.fill")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(JP.time(bed)).font(.system(size: 64, weight: .heavy, design: p.fontDesign))
                    .monospacedDigit().foregroundStyle(p.text)
                Text(bed > now ? "まで あと\(WakeLogic.duration(bed.timeIntervalSince(now)))" : "を過ぎました")
                    .font(.headline).foregroundStyle(bed > now ? p.accent : p.overdue)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("今寝ると \(WakeLogic.duration(plan.first.timeIntervalSince(now))) 眠れます")
                .font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 22)
    }
}
