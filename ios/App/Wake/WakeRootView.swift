import SwiftUI

/// 起床タブの入口。時間帯（起床前・起床中・朝・夜）で画面が変わる。色は palette に従う。
struct WakeRootView: View {
    @StateObject private var model = WakeViewModel()
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var scene
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 起動引数 -wakeShot settings|records で、その画面を開いた状態にする（画面写真用）
    @State private var path: [WakeRoute] = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-wakeShot"), i + 1 < args.count else { return [] }
        switch args[i + 1] {
        case "settings": return [.settings]
        case "records": return [.records]
        default: return []
        }
    }()

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                ScrollView {
                    VStack(spacing: 16) {
                        WakeHeader(model: model)
                        // 時間帯が変わる（チェックイン・取り消し）ときは、テーマの動き方で入れ替える
                        VStack(spacing: 16) {
                            switch model.phase {
                            case .before: WakeBeforeView(model: model)
                            case .window: WakeWindowView(model: model)
                            case .morning, .day: WakeMorningView(model: model)
                            case .evening: WakeEveningView(model: model)
                            }
                        }
                        .id(model.phase)
                        .transition(reduceMotion ? AnyTransition.opacity : motion.appear)
                    }
                    .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : motion.change, value: model.phase)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .paletteBackground(p)
                .overlay(alignment: .bottom) {
                    if model.undoToast {
                        WakeUndoToast(model: model)
                            .transition(reduceMotion ? AnyTransition.opacity
                                        : AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : motion.change, value: model.undoToast)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(JP.date(model.now)).font(Font.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                    Text(title).font(Font.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                SettingsButton()   // アプリ全体の設定（歯車）
            }
            // 起床だけの設定と記録（アプリの設定の歯車と区別するため、文字つきのボタンにする）
            HStack(spacing: 8) {
                NavigationLink(value: WakeRoute.settings) { WakePill(text: "アラームの設定", icon: "alarm") }
                NavigationLink(value: WakeRoute.records) { WakePill(text: "起床の記録", icon: "chart.bar.fill") }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 16)
    }
}

/// 見出しの下の小さなボタン
struct WakePill: View {
    @Environment(\.palette) private var p
    let text: String
    let icon: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(Font.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(p.text)
            .background(p.card, in: Capsule())
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
        // 夜中（就寝の3時間前から最初のアラームまで）は就寝を先頭に
        if let plan = model.nextPlan, model.now > WakeLogic.bedtime(before: plan, settings: model.settings).addingTimeInterval(-3 * 3600) {
            WakeBedtimeCard(plan: plan, bed: WakeLogic.bedtime(before: plan, settings: model.settings), now: model.now)
        }
        WakeNextCard(model: model)
        if let plan = model.nextPlan { WakeStageTimeline(plan: plan, reached: 0) }
        if model.nextPlanAny != nil { WakeSkipCard(model: model) }
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
                let left: String = "あと \(WakeLogic.duration(plan.first.timeIntervalSince(model.now)))"
                Text(left).font(Font.headline).foregroundStyle(p.accent)
                let detail: String = "アラーム\(plan.stages.count)回（\(JP.time(plan.last))まで）"
                    + (plan.departure.map { "・出発 \(JP.time($0))" } ?? "")
                Text(detail).font(Font.footnote.weight(.semibold)).foregroundStyle(p.sub)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                let empty: String = model.settings.paused ? "アラームを止めています" : "アラームはありません"
                let hint: String = model.settings.paused
                    ? "「アラームの設定」で「すべてのアラームを止める」をオフにすると鳴ります"
                    : "「アラームの設定」で、起きる曜日と時刻を決めてください"
                Text(empty).font(Font.title2.weight(.bold)).foregroundStyle(p.text)
                Text(hint).font(Font.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                NavigationLink(value: WakeRoute.settings) {
                    Label("アラームの設定を開く", systemImage: "alarm").font(Font.subheadline.weight(.bold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .foregroundStyle(p.onAccent)
                        .background(p.accent, in: Capsule())
                }
                .padding(.top, 4)
            }
            if let note = todayNote {
                Label(note, systemImage: "moon.zzz.fill").font(Font.footnote.weight(.semibold)).foregroundStyle(p.sub)
                    .padding(.top, 2)
            }
            WakeLockedCheckIn(model: model)
        }
        .paletteCard(p, padding: 22)
    }

    /// 今日のアラームがオフのとき、その理由（例：今日は鳴りません（祝日））
    private var todayNote: String? {
        guard let t = model.todayPlan, let reason = t.skipReason, model.now < t.last,
              !model.settings.paused else { return nil }
        if reason.hasPrefix("祝日") { return "今日は\(reason)のため鳴りません" }
        return "今日のアラームはオフにしています"
    }
}

/// 段階の一覧（鳴った段階に印）
struct WakeStageTimeline: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let plan: WakePlan
    let reached: Int
    /// 鳴った回の丸を順番に塗る（表示した数）
    @State private var shown = 0

    /// 1つずつ間をあけて塗る
    private func fill(to target: Int) {
        if reduceMotion || target <= shown {
            withAnimation(Animation.easeInOut(duration: 0.2)) { shown = target }
            return
        }
        let start = shown
        let anim: Animation = motion.change
        Task { @MainActor in
            for n in (start + 1)...target {
                withAnimation(anim) { shown = n }
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WakeCardTitle(text: "アラーム", icon: "bell.and.waves.left.and.right.fill")
            ForEach(plan.stages, id: \.number) { st in
                let done = st.number <= shown
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(done ? p.accent : p.accent.opacity(0.14))
                        Text("\(st.number)").font(.headline.weight(.heavy)).foregroundStyle(done ? p.onAccent : p.accent)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.name.isEmpty ? "\(st.number)回目" : st.name).font(.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Text("\(st.score)点").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                    }
                    Spacer(minLength: 0)
                    Text(JP.time(st.at)).font(.system(size: 26, weight: .bold, design: p.fontDesign))
                        .monospacedDigit().foregroundStyle(done ? p.sub : p.text)
                }
            }
            Divider().padding(.vertical, 2)
            WakeAlarmHint()
        }
        .paletteCard(p)
        .onAppear { fill(to: reached) }
        .onChange(of: reached) { _, r in fill(to: r) }
    }
}

/// 「起きた！」を押したときの朝日の広がり（光の輪と光線）。表示されたら外へ広がって消える
struct WakeSunBurst: View {
    let color: Color
    @State private var go = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(go ? 0 : 0.35))
                .scaleEffect(go ? 1.9 : 1)
            Circle().strokeBorder(color.opacity(go ? 0 : 0.6), lineWidth: 6)
                .scaleEffect(go ? 1.6 : 1)
            ForEach(0..<12, id: .self) { i in
                Capsule().fill(color.opacity(go ? 0 : 0.8))
                    .frame(width: 6, height: 26)
                    .offset(y: go ? -190 : -110)
                    .rotationEffect(Angle.degrees(Double(i) * 30))
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(Animation.easeOut(duration: 0.6)) { go = true } }
    }
}

/// アラーム画面の2つのボタンの違い（「止める」では次のアラームが止まらない）
struct WakeAlarmHint: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(icon: "stop.circle", title: "止める", text: "今の音だけ止まります。次のアラームは鳴ります")
            row(icon: "sun.max.fill", title: "起きた！", text: "残りのアラームがすべて止まり、起床を記録します")
        }
    }

    private func row(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(Font.footnote.weight(.bold)).foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("「\(title)」").font(Font.footnote.weight(.bold)).foregroundStyle(p.text)
                Text(text).font(Font.footnote).foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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
                    Text(skipTitle(skipped)).font(Font.headline).foregroundStyle(p.text)
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

    /// 「明日だけオフ」。夜中に今朝の分を止めるときは「今日だけオフ」
    private func skipTitle(_ skipped: Bool) -> String {
        let plan: WakePlan? = skipped ? model.nextPlanAny : model.nextPlan
        let day: String = plan.map { WakeLogic.dayLabel($0.dayStart, now: model.now) } ?? "明日"
        let d: String = (day == "今日" || day == "明日") ? day : "次の起床日"
        return skipped ? "\(d)だけオフにしています" : "\(d)だけオフ"
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
                tile("記録した日", "\(model.sessions.count)", "日")
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
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    /// 押したら朝日が広がるように光らせてから、チェックインする
    private func tapCheckIn() {
        guard !burst else { return }
        if reduceMotion {
            model.checkIn()
            return
        }
        withAnimation(motion.tap) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { model.checkIn() }
    }

    var body: some View {
        let plan = model.todayPlan
        let reached = plan.map { WakeLogic.reached($0, at: model.now) } ?? 0
        VStack(spacing: 18) {
            Text(statusText(plan: plan, reached: reached)).font(.headline).foregroundStyle(p.sub)
                .multilineTextAlignment(.center)
            Button { tapCheckIn() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").font(.system(size: 44, weight: .bold))
                        .symbolEffect(.bounce, value: burst)
                    Text("起きた！").font(.system(size: 46, weight: .heavy, design: p.fontDesign))
                    Text("今なら \(WakeLogic.score(stage: reached))点").font(.headline)
                }
                .foregroundStyle(p.onAccent)
                .frame(width: 240, height: 240)
                .background(Circle().fill(p.accent).shadow(color: p.accent.opacity(0.4), radius: 20, y: 8))
                .scaleEffect(burst ? 1.06 : 1)
                .background { if burst { WakeSunBurst(color: p.accent) } }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("起きた！チェックイン")
            Text("押すと、残りのアラームがすべて止まります").font(Font.footnote).foregroundStyle(p.sub)
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
            return "\(st.number)回目のアラームが鳴りました\n次は \(JP.time(next.at))（\(next.number)回目）"
        }
        return "最後のアラームが鳴りました"
    }
}

// MARK: - 朝（チェックイン後）

struct WakeMorningView: View {
    @ObservedObject var model: WakeViewModel
    @StateObject private var weather = WakeWeatherModel()

    var body: some View {
        // 出発前は「出発まで」とルーティンを先頭に。起床の結果は小さく
        if let dep = model.departure, dep > model.now {
            WakeResultStrip(model: model)
            WakeCountdownCard(model: model, departure: dep)
            if !model.settings.routine.isEmpty { WakeRoutineCard(model: model) }
            if !model.settings.belongings.isEmpty { WakeBelongingsCard(model: model) }
            WakeWeatherCard(weather: weather).onAppear { weather.load(demo: model.demo) }
        } else {
            WakeResultCard(model: model)
            WakeWeatherCard(weather: weather).onAppear { weather.load(demo: model.demo) }
        }
        WakeTodoCard(now: model.now)
        WakeUndoCard(model: model)
    }
}

/// 今朝の結果（出発前の小さな表示）
struct WakeResultStrip: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let s = model.todaySession
        let time: String = model.checkInAt.map { JP.time($0) } ?? "--:--"
        let streak: Int = WakeLogic.streak(model.sessions)
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill").font(Font.title3).foregroundStyle(p.accent)
            Text("\(time) に起床").font(Font.headline).foregroundStyle(p.text).monospacedDigit()
            if streak > 1 {
                Text("\(streak)日連続").font(Font.footnote.weight(.semibold)).foregroundStyle(p.sub)
            }
            Spacer(minLength: 0)
            HStack(spacing: 1) {
                WakeCountUp(value: s?.score ?? 0, font: Font.headline.weight(.heavy), color: p.onAccent)
                Text("点").font(Font.caption.weight(.bold)).foregroundStyle(p.onAccent)
            }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(p.accent, in: Capsule())
        }
        .paletteCard(p, padding: 16)
    }
}

/// 数字を0から数え上げて見せる（点数など）。動きを減らす設定のときはすぐに表示
struct WakeCountUp: View {
    let value: Int
    let font: Font
    let color: Color
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text("\(shown)").font(font).foregroundStyle(color).monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear { count() }
            .onChange(of: value) { _, _ in count() }
    }

    private func count() {
        let target = value
        if reduceMotion || target == 0 { shown = target; return }
        let anim: Animation = motion.tap
        Task { @MainActor in
            for i in 1...8 {
                withAnimation(anim) { shown = target * i / 8 }
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
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
                WakeCountUp(value: s?.score ?? 0, font: Font.system(size: 40, weight: .heavy, design: p.fontDesign), color: p.onAccent)
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
        let st = s.stage == 0 ? "アラームの前に起床" : "\(s.stage)回目で起床"
        return streak > 1 ? "\(st)・\(streak)日連続" : st
    }
}

/// 出発までのカウントダウン
struct WakeCountdownCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let departure: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = WakeClock.now
            let left = max(0, departure.timeIntervalSince(now))
            let need = model.remainingRoutine.map(\.minutes).reduce(0, +)
            let late = Int((now.addingTimeInterval(Double(need) * 60).timeIntervalSince(departure) / 60).rounded(.up))
            VStack(alignment: .leading, spacing: 6) {
                WakeCardTitle(text: "出発まで", icon: "figure.walk.departure")
                Text(format(left)).font(Font.system(size: 64, weight: .heavy, design: p.fontDesign))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : motion.tap, value: Int(left))
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
    @Environment(\.motion) private var motion

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
                Button { withAnimation(motion.tap) { model.toggleRoutine(item) } } label: {
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
    @Environment(\.motion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WakeCardTitle(text: "持ち物", icon: "bag.fill")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.settings.belongings) { item in
                    let done = model.state.belongingsDone.contains(item.id)
                    Button { withAnimation(motion.tap) { model.toggleBelonging(item) } } label: {
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
        if model.nextPlanAny != nil { WakeSkipCard(model: model) }
        if model.todaySession != nil { WakeResultCard(model: model) }
        WakeSummaryRow(model: model)
        if model.checkInAt != nil { WakeUndoCard(model: model) }
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
            Text(JP.time(bed)).font(Font.system(size: 64, weight: .heavy, design: p.fontDesign))
                .monospacedDigit().foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
            let status: String = bed > now ? "あと \(WakeLogic.duration(bed.timeIntervalSince(now)))" : "就寝の時刻を過ぎています"
            let statusColor: Color = bed > now ? p.accent : p.overdue
            Text(status).font(Font.headline).foregroundStyle(statusColor)
            let sleep: String = "今寝ると \(WakeLogic.duration(plan.first.timeIntervalSince(now))) 眠れます"
            Text(sleep).font(Font.subheadline.weight(.semibold)).foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 22)
    }
}
