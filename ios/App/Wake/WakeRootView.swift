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
    /// 行から開くシート（段階・天気・ルーティン・TODO）
    @State private var sheet: WakeSheet? = WakeSheet.launch
    @StateObject private var weather = WakeWeatherModel()

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                ScrollView {
                    VStack(spacing: 16) {
                        WakeHeader(model: model)
                        // 時間帯が変わる（チェックイン・取り消し）ときは、テーマの動き方で入れ替える
                        VStack(spacing: 16) {
                            let open: (WakeSheet) -> Void = { sheet = $0 }
                            switch model.phase {
                            case .before: WakeBeforeView(model: model, open: open)
                            case .window: WakeWindowView(model: model, open: open)
                            case .morning, .day: WakeMorningView(model: model, weather: weather, open: open)
                            case .evening: WakeEveningView(model: model, open: open)
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
        .sheet(item: $sheet) { s in
            WakeSheetContent(model: model, weather: weather, sheet: s)
                .environment(\.palette, p)
                .environment(\.motion, motion)
        }
        .sensoryFeedback(.success, trigger: model.feedback)
        .onAppear { model.refresh(reschedule: true) }
        .onChange(of: scene) { _, s in if s == .active { model.refresh(reschedule: true) } }
        .modifier(WakeWatchHosting(model: model))
    }
}

/// 二度寝の見張り（止める画面・歩数の見回り）と、朝の見返しの全画面
private struct WakeWatchHosting: ViewModifier {
    @ObservedObject var model: WakeViewModel

    func body(content: Content) -> some View {
        content
            .modifier(ReviewHost(handlesRequests: false))
            .wakeWatchStopCover(.wake)
            .onReceive(NotificationCenter.default.publisher(for: .wakeWatchChanged)) { _ in model.refresh(reschedule: false) }
            // 見張り中は20秒ごとに歩数を確かめる（約100歩で見張りが終わる）
            .task(id: model.watch.isWatching) {
                guard model.watch.isWatching, !model.demo else { return }
                while !Task.isCancelled && model.watch.isWatching {
                    try? await Task.sleep(for: .seconds(20))
                    if Task.isCancelled { break }
                    model.pollWatch()
                }
            }
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
        // 起床だけの設定と記録は、ホームの下の行（WakeMoreRows）から開く
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(JP.date(model.now)).font(Font.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text(title).font(Font.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            // 残光・呼吸は見出しの横の空きに絵を置く（ほかの世界観ではただの空き）
            WorldWakeHeaderArt(p: p, alarm: model.nextPlan?.first)
            SettingsButton()   // アプリ全体の設定（歯車）
        }
        .padding(.top, 16)
    }
}

/// ホームの下の行：アラームの詳細・起床の記録・アラームの設定（時間帯ごとに前へ行を足せる）
struct WakeMoreRows<Extra: View>: View {
    @ObservedObject var model: WakeViewModel
    /// 「アラームの詳細」の行を出すか
    var alarm: Bool = true
    /// 「起きたを取り消す」の行を出すか
    var undo: Bool = false
    let open: (WakeSheet) -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        WakeRowGroup {
            extra
            if alarm {
                Button { open(.alarm) } label: {
                    WakeRowLabel(icon: "bell.and.waves.left.and.right.fill", title: "アラームの詳細", detail: model.alarmRowDetail)
                }
                .buttonStyle(.plain)
                WakeRowDivider()
            }
            NavigationLink(value: WakeRoute.records) {
                WakeRowLabel(icon: "chart.bar.fill", title: "起床の記録", detail: model.recordsRowDetail)
            }
            .buttonStyle(.plain)
            WakeRowDivider()
            NavigationLink(value: WakeRoute.settings) {
                WakeRowLabel(icon: "alarm", title: "アラームの設定",
                             detail: model.settings.paused ? "すべてのアラームを止めています" : nil)
            }
            .buttonStyle(.plain)
            if undo {
                WakeRowDivider()
                WakeUndoRow(model: model)
            }
        }
    }
}

extension WakeMoreRows where Extra == EmptyView {
    init(model: WakeViewModel, alarm: Bool = true, undo: Bool = false, open: @escaping (WakeSheet) -> Void) {
        self.init(model: model, alarm: alarm, undo: undo, open: open, extra: { EmptyView() })
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
    let open: (WakeSheet) -> Void

    var body: some View {
        // ホームは次のアラーム（時刻・回数と入っているか・起きた！）と就寝の1行だけ。段階・明日だけオフは「アラームの詳細」へ
        let bed: Date? = model.nextPlan.map { WakeLogic.bedtime(before: $0, settings: model.settings) }
        // 就寝の1行は、就寝の前後（3時間前〜2時間後）だけ出す
        let nearBed: Bool = bed.map { model.now > $0.addingTimeInterval(-3 * 3600) && model.now < $0.addingTimeInterval(2 * 3600) } ?? false
        WakeNextCard(model: model)
        if nearBed, let plan = model.nextPlan, let bed {
            WakeBedtimeLine(plan: plan, bed: bed, now: model.now)
        }
        WakeMoreRows(model: model, open: open)
        if !model.message.isEmpty { WakeMessage(text: model.message) }
    }
}

/// 次の起床時刻（大きな数字）・アラームが入っているか・押せない「起きた！」
struct WakeNextCard: View {
    @ObservedObject var model: WakeViewModel
    /// 夜は数字を一回り小さく
    var compact: Bool = false
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WakeCardTitle(text: "次のアラーム", icon: "alarm.fill")
            if let plan = model.nextPlan {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(WakeLogic.dayLabel(plan.first, now: model.now)).font(Font.title3.weight(.bold)).foregroundStyle(p.sub)
                    Text(JP.time(plan.first)).font(Font.system(size: compact ? 52 : 72, weight: .heavy, design: p.fontDesign))
                        .foregroundStyle(p.text).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                let left: String = "あと \(WakeLogic.duration(plan.first.timeIntervalSince(model.now)))"
                    + (plan.departure.map { "・出発 \(JP.time($0))" } ?? "")
                Text(left).font(Font.headline).foregroundStyle(p.accent)
                    .lineLimit(1).minimumScaleFactor(0.8)
                // アラームの回数と、AlarmKit に入っているか（入っていなければ「入れ直す」）
                WakeEveningCheck(model: model, inline: true)
            } else {
                let empty: String = model.settings.paused ? "アラームを止めています" : "アラームはありません"
                let hint: String = model.settings.paused
                    ? "「すべてのアラームを止める」をオフにすると鳴ります"
                    : "起きる曜日と時刻を決めてください"
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
        .paletteCard(p, padding: 20)
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
                        if !st.name.isEmpty {
                            Text("\(st.number)回目").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                        }
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
            ForEach(0..<12, id: \.self) { i in
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
            row(icon: "stop.circle", title: "止める", text: WakeStore.settings().watch
                ? "二度寝の見張りが始まります。10分後・20分後に見張りのアラーム。約100歩 歩けば鳴りません"
                : "今の音だけ止まります。次のアラームは鳴ります")
            row(icon: "sun.max.fill", title: "起きた！", text: "残りのアラームがすべて止まり、起床を記録します。押し間違い防止のため、最初のアラームの2時間前から押せます")
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
    let open: (WakeSheet) -> Void
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst = false

    /// 押したら朝日が広がるように光らせてから、チェックインする。
    /// 見張りのアラームが鳴った後は、歩くか計算で止める画面を開く
    private func tapCheckIn() {
        if model.watch.needsProof && !model.demo {
            WakeWatchPresenter.shared.showStop = true
            return
        }
        guard !burst else { return }
        if reduceMotion {
            model.checkIn()
            return
        }
        withAnimation(motion.tap) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { model.checkIn() }
    }

    /// 見張り中は「起きてるよ」（見張りを止めて起床を記録する）
    private var bigLabel: String {
        guard model.watch.isWatching else { return "起きた！" }
        return model.watch.needsProof ? "歩いて止める" : "起きてるよ"
    }

    private func stageLine(reached: Int) -> String {
        if model.watch.isWatching {
            let stage: Int = model.watch.stoppedStage ?? reached
            return "\(stage)回目で止めた"
        }
        return "今なら" + WakeLogic.stageText(stage: reached)
    }

    private var footLine: String {
        guard model.watch.isWatching else { return "押すと、残りのアラームがすべて止まります" }
        return model.watch.needsProof ? "押すと、歩数か計算で止める画面を開きます" : "押すと、見張りが終わり起床を記録します"
    }

    var body: some View {
        let plan = model.todayPlan
        let reached = plan.map { WakeLogic.reached($0, at: model.now) } ?? 0
        let watching: Bool = model.watch.isWatching
        if watching { WakeWatchCard(model: model) }
        VStack(spacing: 18) {
            if !watching {
                Text(statusText(plan: plan, reached: reached)).font(.headline).foregroundStyle(p.sub)
                    .multilineTextAlignment(.center)
            }
            Button { tapCheckIn() } label: {
                VStack(spacing: 6) {
                    Image(systemName: watching ? "hand.wave.fill" : "sun.max.fill").font(.system(size: 44, weight: .bold))
                        .symbolEffect(.bounce, value: burst)
                    Text(bigLabel).font(.system(size: 46, weight: .heavy, design: p.fontDesign))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(stageLine(reached: reached)).font(.headline)
                }
                .foregroundStyle(p.onAccent)
                .padding(.horizontal, 16)
                .frame(width: 240, height: 240)
                .background(Circle().fill(p.accent).shadow(color: p.accent.opacity(0.4), radius: 20, y: 8))
                .scaleEffect(burst ? 1.06 : 1)
                .background { if burst { WakeSunBurst(color: p.accent) } }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(watching ? "\(bigLabel)。見張りを止めて起床を記録" : "起きた！チェックイン")
            Text(footLine).font(Font.footnote).foregroundStyle(p.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .paletteCard(p)
        // 段階の一覧（鳴った回に印）は「アラームの詳細」へ
        WakeMoreRows(model: model, alarm: plan != nil, open: open)
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
    @ObservedObject var weather: WakeWeatherModel
    let open: (WakeSheet) -> Void
    @EnvironmentObject var store: TodoStore

    var body: some View {
        // ホームは今朝の結果だけ。出発の準備・天気・TODO・記録・設定は下の行から開く
        WakeMorningReviewCard(items: store.items)   // 朝の見返し（まだなら）
        WakeResultCard(model: model)
            .onAppear { weather.load(demo: model.demo) }
        WakeMoreRows(model: model, alarm: false, undo: true, open: open, extra: {
            if model.showsPrepRow {
                Button { open(.prep) } label: {
                    WakeRowLabel(icon: "figure.walk.departure", title: "出発の準備", detail: model.prepRowDetail)
                }
                .buttonStyle(.plain)
                WakeRowDivider()
            }
            Button { open(.weather) } label: {
                WakeRowLabel(icon: "cloud.sun.fill", title: "今日の天気", detail: weather.rowDetail)
            }
            .buttonStyle(.plain)
            WakeRowDivider()
            Button { open(.todo) } label: {
                WakeRowLabel(icon: "checklist", title: "今日のTODO", detail: WakeTodoCard.countText(now: model.now))
            }
            .buttonStyle(.plain)
            WakeRowDivider()
        })
    }
}

/// 今日の結果（夜の小さな表示）
struct WakeResultStrip: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let s = model.todaySession
        let time: String = model.checkInAt.map { JP.time($0) } ?? "--:--"
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill").font(Font.title3).foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(time) に起床").font(Font.headline).foregroundStyle(p.text).monospacedDigit()
                if let s {
                    Text(WakeLogic.resultText(s)).font(Font.caption.weight(.semibold)).foregroundStyle(p.sub)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if let s {
                let badge: String = s.stage <= 0 ? "アラーム前" : "\(s.stage)回目"
                Text(badge).font(Font.subheadline.weight(.heavy)).foregroundStyle(p.onAccent).lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(p.accent, in: Capsule())
            }
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

/// 今朝の結果（何回目で起きたか・二度寝・連続）
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            stageBadge(s)
                .frame(width: 96, height: 96)
                .background(Circle().fill(p.accent))
        }
        .paletteCard(p, padding: 22)
    }

    /// 丸の中：「1 回目」か、アラームの前なら朝日と「前に」
    @ViewBuilder
    private func stageBadge(_ s: WakeSession?) -> some View {
        let stage: Int = s?.stage ?? 0
        VStack(spacing: 0) {
            if stage <= 0 {
                Image(systemName: "sunrise.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(p.onAccent)
                Text("アラーム前").font(.caption.weight(.bold)).foregroundStyle(p.onAccent)
            } else {
                Text("\(stage)").font(.system(size: 44, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.onAccent)
                Text("回目").font(.caption.weight(.bold)).foregroundStyle(p.onAccent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 例：「1回目で起床・二度寝なし」。連続の日数は「起床の記録」の行に
    private func stageText(_ s: WakeSession?) -> String {
        guard let s else { return "" }
        return WakeLogic.resultText(s)
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

    /// 「今日のTODO」の行のひとこと（例：3件）
    static func countText(now: Date) -> String {
        let n: Int = WakeTodoCard(now: now).items.count
        return n == 0 ? "ありません" : "\(n)件"
    }

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
    let open: (WakeSheet) -> Void

    var body: some View {
        // ホームは次のアラーム（入っているか）・就寝の1行・今日の結果だけ。明日だけオフは「アラームの詳細」へ
        WakeNextCard(model: model, compact: model.nextPlan != nil)
        if let plan = model.nextPlan {
            WakeBedtimeLine(plan: plan, bed: WakeLogic.bedtime(before: plan, settings: model.settings), now: model.now)
        }
        if model.todaySession != nil { WakeResultStrip(model: model) }
        WakeMoreRows(model: model, undo: model.checkInAt != nil, open: open)
    }
}

/// 就寝の1行（時刻・あと何分・眠れる長さ）
struct WakeBedtimeLine: View {
    @Environment(\.palette) private var p
    let plan: WakePlan
    let bed: Date
    let now: Date

    var body: some View {
        // 次の朝がお休み（土日・祝日など）なら、何十時間も先の「あと」「眠れます」は出さずに次の起床を出す
        let off: String? = WakeLogic.morningOffLine(next: plan, now: now)
        let status: String = bed > now ? "あと \(WakeLogic.duration(bed.timeIntervalSince(now)))" : "就寝の時刻を過ぎています"
        let statusColor: Color = bed > now ? p.accent : p.overdue
        let left: String = WakeLogic.duration(plan.first.timeIntervalSince(now))
        let sleep: String = off ?? "今寝ると \(left) 眠れます"
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill").font(Font.title3).foregroundStyle(p.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("就寝 \(JP.time(bed))").font(Font.system(size: 22, weight: .heavy, design: p.fontDesign))
                        .monospacedDigit().foregroundStyle(p.text).lineLimit(1)
                    if off == nil {
                        Text(status).font(Font.subheadline.weight(.bold)).foregroundStyle(statusColor)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Text(sleep).font(Font.caption.weight(.semibold)).foregroundStyle(off == nil ? p.sub : p.accent)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .paletteCard(p, padding: 16)
        .accessibilityElement(children: .combine)
    }
}
