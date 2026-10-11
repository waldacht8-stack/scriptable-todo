import SwiftUI
#if canImport(CoreMotion)
import CoreMotion
#endif

// 起床の見張り（二度寝の防止）の画面：見張り中のカード・止める画面（30歩か計算3問）・夜の確認・朝の見返しの入口。
// データと判定は Shared/WakeWatch.swift。

extension Notification.Name {
    /// 見張りの状態が変わった（起床タブを描き直す）
    static let wakeWatchChanged = Notification.Name("wakeWatchChanged")
}

// MARK: - 止める画面を出す仕組み

/// 見張りのアラームが鳴った後にアプリを開いたら、止める画面を出す。
/// TODO と起床のどちらのタブからでも出せるように、いま見えている方だけが出す
@MainActor
final class WakeWatchPresenter: ObservableObject {
    static let shared = WakeWatchPresenter()
    enum Host { case todo, wake }
    @Published var visible: Host?
    @Published var showStop = false

    func check() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-wakewatchstop") { showStop = true; return }
        if args.contains("-demo") { return }
        let r = WakeWatchStore.active(now: .now)
        showStop = r?.needsProof ?? false
    }
}

private struct WakeWatchCover: ViewModifier {
    let host: WakeWatchPresenter.Host
    @ObservedObject private var presenter = WakeWatchPresenter.shared
    @Environment(\.scenePhase) private var scene
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        let shown = Binding<Bool>(
            get: { presenter.showStop && presenter.visible == host },
            set: { v in if !v { presenter.showStop = false } })
        return content
            .onAppear {
                presenter.visible = host
                presenter.check()
            }
            .onDisappear { if presenter.visible == host { presenter.visible = nil } }
            .onChange(of: scene) { _, s in if s == .active { presenter.check() } }
            .background {
                Color.clear.fullScreenCover(isPresented: shown) {
                    WakeWatchStopView()
                        .environment(\.palette, p)
                        .environment(\.motion, motion)
                        .preferredColorScheme(p.scheme)
                }
            }
    }
}

extension View {
    /// 見張りの止める画面（30歩か計算3問）を、このタブが見えているときに出す
    func wakeWatchStopCover(_ host: WakeWatchPresenter.Host) -> some View {
        modifier(WakeWatchCover(host: host))
    }
}

// MARK: - 歩数（その場で数える）

@MainActor
final class WakeStepCounter: ObservableObject {
    @Published var steps = 0
    @Published var available = true
    #if canImport(CoreMotion)
    private let pedometer = CMPedometer()
    #endif

    func start(from: Date) {
        #if canImport(CoreMotion)
        guard WakeSteps.isAvailable, !WakeSteps.isDenied else { available = false; return }
        pedometer.startUpdates(from: from) { [weak self] data, _ in
            guard let n = data?.numberOfSteps.intValue else { return }
            Task { @MainActor in self?.steps = n }
        }
        #else
        available = false
        #endif
    }

    func stop() {
        #if canImport(CoreMotion)
        pedometer.stopUpdates()
        #endif
    }
}

// MARK: - 止める画面

struct WakeWatchStopView: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss
    @StateObject private var counter = WakeStepCounter()
    @State private var mission = false
    @State private var questions: [WakeWatchLogic.MathQuestion] = []
    @State private var q = 0
    @State private var answer = ""
    @State private var wrong = 0
    @State private var passed = false
    @FocusState private var focused: Bool

    private let demo = ProcessInfo.processInfo.arguments.contains("-demo")
    private var need: Int { WakeWatchLogic.ringSteps }
    private var steps: Int {
        if demo { return WakeWatchState.load(now: WakeClock.now).steps }
        return counter.steps
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Image(systemName: "eye.fill").font(Font.title.weight(.bold)).foregroundStyle(p.accent)
                Text("二度寝の見張り").font(Font.system(size: 30, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                Text(passed ? "おはようございます。見張りを終えました" : "起きているか確かめます")
                    .font(Font.headline).foregroundStyle(p.sub)
            }
            .padding(.top, 36)
            if passed {
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(Font.system(size: 96, weight: .bold)).foregroundStyle(p.accent)
                    .transition(motion.appear(reduce: reduce))
                Spacer()
            } else if mission {
                missionPanel
            } else {
                stepsPanel
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .sensoryFeedback(.success, trigger: passed)
        .sensoryFeedback(.error, trigger: wrong)
        .onAppear {
            WakeWatchActions.clearOpenRequest()
            if !demo, let r = WakeWatchStore.active(now: .now) {
                counter.start(from: r.rangAt ?? .now)
            }
            questions = WakeWatchLogic.mission(seed: Int(Date().timeIntervalSince1970 / 60))
        }
        .onDisappear { counter.stop() }
        .onChange(of: counter.steps) { _, n in if n >= need { pass("walk") } }
    }

    private var stepsPanel: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(p.accent.opacity(0.15), lineWidth: 18)
                Circle().trim(from: 0, to: CGFloat(min(1, Double(steps) / Double(need))))
                    .stroke(p.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(motion.change(reduce: reduce), value: steps)
                VStack(spacing: 0) {
                    Text("\(min(steps, need))").font(Font.system(size: 72, weight: .heavy, design: p.fontDesign))
                        .monospacedDigit().foregroundStyle(p.text)
                        .contentTransition(.numericText(value: Double(steps)))
                    Text("/ \(need)歩").font(Font.headline).foregroundStyle(p.sub)
                }
            }
            .frame(width: 230, height: 230)
            Text(counter.available || demo ? "スマホを持って\(need)歩 歩くと止まります" : "歩数が読めません。計算で止めてください")
                .font(Font.headline).foregroundStyle(p.text).multilineTextAlignment(.center)
            Button {
                withAnimation(motion.change(reduce: reduce)) { mission = true }
                focused = true
            } label: {
                Label("計算3問で止める", systemImage: "function")
                    .font(Font.headline.weight(.bold)).foregroundStyle(p.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { dismiss() } label: {
                Text("あとで（\(WakeWatchLogic.rearmMinutes)分後にまた鳴ります）").font(Font.subheadline.weight(.semibold))
                    .foregroundStyle(p.sub)
            }
            .buttonStyle(.plain)
        }
    }

    private var missionPanel: some View {
        VStack(spacing: 18) {
            Text("\(min(q + 1, questions.count)) / \(questions.count)問").font(Font.subheadline.weight(.bold)).foregroundStyle(p.sub)
            if q < questions.count {
                Text("\(questions[q].text) =").font(Font.system(size: 48, weight: .heavy, design: p.fontDesign))
                    .monospacedDigit().foregroundStyle(p.text)
                    .modifier(Shake(amount: CGFloat(wrong)))
                    .animation(reduce ? nil : Animation.default, value: wrong)
            }
            TextField("答え", text: $answer)
                .keyboardType(.numberPad)
                .focused($focused)
                .font(Font.system(size: 36, weight: .bold, design: p.fontDesign))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(p.card, in: RoundedRectangle(cornerRadius: min(p.radius, 18), style: .continuous))
                .onChange(of: answer) { _, v in check(v) }
            Button { withAnimation(motion.change(reduce: reduce)) { mission = false } } label: {
                Text("歩いて止めるに戻る").font(Font.subheadline.weight(.semibold)).foregroundStyle(p.sub)
            }
            .buttonStyle(.plain)
        }
    }

    /// 答えの桁がそろったら判定する
    private func check(_ v: String) {
        guard q < questions.count else { return }
        let target = questions[q].answer
        guard v.count >= String(target).count else { return }
        if Int(v) == target {
            answer = ""
            q += 1
            if q >= questions.count { pass("mission") }
        } else {
            wrong += 1
            answer = ""
        }
    }

    private func pass(_ by: String) {
        guard !passed else { return }
        withAnimation(motion.change(reduce: reduce)) { passed = true }
        focused = false
        Task {
            if !demo { await WakeWatchActions.finish(by: by) }
            NotificationCenter.default.post(name: .wakeWatchChanged, object: nil)
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
        }
    }
}

/// まちがえたときに横にゆれる
private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 4), y: 0))
    }
}

// MARK: - 見張り中のカード（起床中の画面の上）

struct WakeWatchCard: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let w = model.watch
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WakeCardTitle(text: "二度寝の見張り中", icon: "eye.fill")
                Spacer(minLength: 0)
                if let next = w.nextWatchAt {
                    Text("次 \(JP.time(next))").font(Font.subheadline.weight(.bold)).foregroundStyle(p.accent).monospacedDigit()
                }
            }
            if let stop = w.stopAt {
                let stage: String = w.stoppedStage.map { "（\($0)回目）" } ?? ""
                Text("\(JP.time(stop)) にアラームを止めました\(stage)").font(Font.headline).foregroundStyle(p.text)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(min(w.steps, w.requiredSteps))").font(Font.system(size: 40, weight: .heavy, design: p.fontDesign))
                    .monospacedDigit().foregroundStyle(p.text)
                    .contentTransition(.numericText(value: Double(w.steps)))
                Text("/ \(w.requiredSteps)歩").font(Font.headline).foregroundStyle(p.sub)
            }
            ProgressView(value: Double(min(w.steps, w.requiredSteps)), total: Double(max(1, w.requiredSteps)))
                .tint(p.accent)
                .animation(motion.change(reduce: reduce), value: w.steps)
            let hint: String = w.needsProof
                ? "見張りのアラームが鳴りました。\(WakeWatchLogic.ringSteps)歩 歩くか、計算3問で止めます"
                : "約\(WakeWatchLogic.awakeSteps)歩 歩くと見張りが終わります。下の「起きてるよ」でも終わります"
            Text(hint).font(Font.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            if WakeSteps.isDenied && !model.demo {
                Label("歩数の許可がありません（設定アプリ → 日和 → モーションとフィットネス）", systemImage: "exclamationmark.triangle.fill")
                    .font(Font.caption.weight(.semibold)).foregroundStyle(p.overdue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .paletteCard(p)
    }
}

// MARK: - 夜の確認（明日のアラームが入っているか）

struct WakeEveningCheck: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        let plan = model.nextPlan
        let scheduled: Int = plan.map { pl in model.liveAlarmCount ?? model.state.alarms.filter { $0.day == pl.day }.count } ?? 0
        let ok: Bool = plan != nil && scheduled > 0
        let tint: Color = ok ? p.accent : p.overdue
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(Font.title2.weight(.bold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(plan, scheduled: scheduled)).font(Font.headline).foregroundStyle(ok ? p.text : p.overdue)
                    .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                Text(detail(plan, ok: ok)).font(Font.caption).foregroundStyle(p.sub)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !ok && plan != nil {
                Button { model.scheduleAll() } label: {
                    Text("入れ直す").font(Font.subheadline.weight(.heavy)).foregroundStyle(p.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(p.overdue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .paletteCard(p, padding: 16)
        .overlay {
            if !ok {
                RoundedRectangle(cornerRadius: p.radius, style: .continuous).strokeBorder(p.overdue, lineWidth: 2)
            }
        }
        .onAppear { model.checkAlarms() }
    }

    private func title(_ plan: WakePlan?, scheduled: Int) -> String {
        guard let plan else { return "次のアラームが入っていません" }
        let day: String = WakeLogic.dayLabel(plan.first, now: model.now)
        if scheduled > 0 { return "\(day) \(JP.time(plan.first))・アラーム\(scheduled)回 入っています ✓" }
        return "\(day) \(JP.time(plan.first)) のアラームが入っていません"
    }

    private func detail(_ plan: WakePlan?, ok: Bool) -> String {
        if ok { return model.settings.watch ? "「止める」で二度寝の見張りが始まります" : "スマホを充電しておきましょう" }
        if plan == nil { return model.settings.paused ? "すべてのアラームを止めています" : "「アラームの設定」で起きる曜日を決めてください" }
        return "アラームの許可を確かめて、入れ直してください"
    }
}

// MARK: - 朝の見返しの入口（チェックインの後）

struct WakeMorningReviewCard: View {
    @Environment(\.palette) private var p
    @Environment(\.openReview) private var openReview
    @ObservedObject private var presenter = ReviewPresenter.shared
    let items: [TodoItem]

    var body: some View {
        let _ = presenter.revision
        let state = ReviewState.make(log: ReviewStore.log(), settings: ReviewStore.settings(), items: items, now: .now)
        if !state.morningDone {
            let plan = ReviewLogic.plan(.morning, items: items, seen: ReviewStore.log().seen, now: .now, weekly: false)
            Button { openReview(.morning) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sunrise.fill").font(Font.title2).foregroundStyle(p.onAccent)
                        .frame(width: 48, height: 48).background(p.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("朝の見返し・30秒").font(Font.headline).foregroundStyle(p.text)
                        let line: String = plan.cards.isEmpty ? "今日のTODOはありません。確認だけ" : "今日のTODO \(plan.cards.count)件を1枚ずつ"
                        Text(line).font(Font.caption).foregroundStyle(p.sub)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(Font.footnote.weight(.bold)).foregroundStyle(p.sub)
                }
                .paletteCard(p, padding: 16)
            }
            .buttonStyle(.plain)
        }
    }
}
