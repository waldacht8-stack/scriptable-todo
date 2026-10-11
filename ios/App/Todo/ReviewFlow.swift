import SwiftUI

// TODO の見返し（全画面。フォーカスと同じく1枚ずつめくる）。
// 朝・昼：右へ＝確認した、左へ＝明日へ。夜：右へ＝明日、左へ＝やめる、上へ＝今週。
// データと判定は Shared/ReviewData.swift。

/// 通知から見返しを開く（TodoNotifier が request を入れ、HomeView が開く）
@MainActor
final class ReviewPresenter: ObservableObject {
    static let shared = ReviewPresenter()
    /// 開いてほしい見返し
    @Published var request: ReviewSlot?
    /// 見返しの記録が変わった（見出しの1行を描き直す）
    @Published var revision = 0
}

/// 見返しを開くときの指定
struct ReviewLaunch: Identifiable {
    let id = UUID()
    let slot: ReviewSlot
    let weekly: Bool

    static func make(_ slot: ReviewSlot? = nil, now: Date = .now, forceWeekly: Bool = false) -> ReviewLaunch {
        let s = ReviewStore.settings()
        let chosen: ReviewSlot = slot ?? ReviewLogic.slot(at: now, settings: s)
        let weekly: Bool = chosen == .night && (forceWeekly || ReviewLogic.isWeekly(now: now, settings: s))
        return ReviewLaunch(slot: chosen, weekly: weekly)
    }
}

struct OpenReviewAction {
    var run: (ReviewSlot?) -> Void = { _ in }
    func callAsFunction(_ slot: ReviewSlot? = nil) { run(slot) }
}

struct OpenReviewSettingsAction {
    var run: () -> Void = {}
    func callAsFunction() { run() }
}

private struct OpenReviewKey: EnvironmentKey { static let defaultValue = OpenReviewAction() }
private struct OpenReviewSettingsKey: EnvironmentKey { static let defaultValue = OpenReviewSettingsAction() }

extension EnvironmentValues {
    var openReview: OpenReviewAction {
        get { self[OpenReviewKey.self] }
        set { self[OpenReviewKey.self] = newValue }
    }
    var openReviewSettings: OpenReviewSettingsAction {
        get { self[OpenReviewSettingsKey.self] }
        set { self[OpenReviewSettingsKey.self] = newValue }
    }
}

// MARK: - 見返しの画面

struct ReviewFlowView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dismiss) private var dismiss
    let launch: ReviewLaunch

    @State private var plan: ReviewLogic.Plan? = nil
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var dragID: String?
    @State private var fly: CGSize = CGSize(width: 600, height: 0)
    @State private var feedback = 0
    @State private var missed: ReviewSlot? = nil
    /// 直前の操作が TODO を変えたか（元に戻すを出す）
    @State private var lastChanged = false
    @State private var finished = false
    @State private var streak = 0

    private var slot: ReviewSlot { launch.slot }
    private var cards: [ReviewLogic.Card] { plan?.cards ?? [] }
    private var atEnd: Bool { plan != nil && index >= cards.count }

    var body: some View {
        VStack(spacing: 14) {
            header
            if let missed, !atEnd {
                Label("前回の見返し（\(missed.name)）がまだです", systemImage: "exclamationmark.circle.fill")
                    .font(Font.footnote.weight(.bold))
                    .foregroundStyle(p.overdue)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(p.overdue.opacity(0.12), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            progress.padding(.horizontal, 24)
            ZStack {
                if atEnd {
                    endPanel.transition(motion.appear(reduce: reduce))
                } else {
                    ForEach(Array(cards.enumerated().filter { $0.offset >= index && $0.offset < index + 3 }.reversed()),
                            id: \.element.id) { i, card in
                        let depth: Int = i - index
                        ReviewCardView(card: card, item: current(card), depth: depth, slot: slot,
                                       drag: depth == 0 && card.id == dragID ? drag : .zero)
                            .gesture(swipe(card), including: depth == 0 ? .all : .none)
                            .transition(cardTransition)
                    }
                }
            }
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity)
            if !atEnd && !cards.isEmpty { buttons.padding(.horizontal, 24).padding(.bottom, 12) }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .sensoryFeedback(.selection, trigger: feedback)
        .onAppear(perform: start)
    }

    // MARK: 見出し

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: slot.icon).font(Font.title2.weight(.bold)).foregroundStyle(p.accent)
                .frame(width: 44, height: 44)
                .background(p.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                let title: String = launch.weekly ? "\(slot.title)・棚卸し" : slot.title
                Text(title).font(Font.system(size: 26, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(Font.footnote.weight(.semibold)).foregroundStyle(p.sub).lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            if lastChanged && !atEnd {
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(Font.headline.weight(.bold)).foregroundStyle(p.text)
                        .frame(width: 44, height: 44).background(p.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("元に戻す")
            }
            Button { close() } label: {
                Image(systemName: "xmark").font(Font.headline.weight(.bold)).foregroundStyle(p.text)
                    .frame(width: 44, height: 44).background(p.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 24)
    }

    private var subtitle: String {
        guard plan != nil else { return "" }
        if atEnd { return cards.isEmpty ? "見返すTODOはありません" : "\(cards.count)件 見返しました" }
        let more: String = (plan?.more ?? 0) > 0 ? "（ほか\(plan?.more ?? 0)件）" : ""
        return "\(index + 1) / \(cards.count)・30秒ほど\(more)"
    }

    /// 進み具合（区切りの棒）
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, cards.count), id: \.self) { i in
                let done: Bool = i < index || atEnd
                Capsule().fill(done ? p.accent : p.sub.opacity(0.22)).frame(height: 5)
            }
        }
        .animation(motion.change(reduce: reduce), value: index)
    }

    // MARK: ボタン

    private var buttons: some View {
        HStack(spacing: 10) {
            if slot == .night {
                choice("やめる", icon: "xmark", color: p.overdue) { act(.drop) }
                choice("今週", icon: "arrow.up", color: p.sub) { act(.week) }
                choice("明日", icon: "arrow.right", color: p.accent, filled: true) { act(.tomorrow) }
            } else {
                choice(p.world.postponeWord, icon: "arrow.left", color: p.overdue) { act(.postpone) }
                choice("確認した", icon: "arrow.right", color: p.accent, filled: true) { act(.ok) }
            }
        }
    }

    private func choice(_ title: String, icon: String, color: Color, filled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        let fg: Color = filled ? p.onAccent : color
        let bg: Color = filled ? color : color.opacity(0.12)
        return Button(action: action) {
            Label(title, systemImage: icon)
                .font(Font.headline.weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 最後

    @ViewBuilder
    private var endPanel: some View {
        if slot == .night, let preview = plan?.preview, !preview.isEmpty, !finished {
            VStack(alignment: .leading, spacing: 14) {
                Label("明日の最初の\(preview.count)件", systemImage: "sunrise.fill")
                    .font(Font.headline.weight(.bold)).foregroundStyle(p.sub)
                ForEach(preview) { t in
                    HStack(spacing: 12) {
                        Text(JP.clock(t, none: "―")).font(Font.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(p.accent).frame(width: 52, alignment: .leading)
                        Text(t.title).font(Font.title3.weight(.bold)).foregroundStyle(p.text).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
                Button { finish() } label: {
                    Text("見返しを終える").font(Font.headline.weight(.bold)).foregroundStyle(p.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(p.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .paletteCard(p, padding: 24)
            .padding(.horizontal, 24)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(Font.system(size: 72, weight: .bold)).foregroundStyle(p.accent)
                    .symbolEffect(.bounce, value: finished)
                Text("見返しました").font(Font.title.weight(.heavy)).foregroundStyle(p.text)
                let line: String = streak > 0 ? "見返し \(streak)日連続" : "3回そろうと連続日数が増えます"
                Text(line).font(Font.headline).foregroundStyle(p.sub)
                Button { dismiss() } label: {
                    Text("閉じる").font(Font.headline.weight(.bold)).foregroundStyle(p.onAccent)
                        .padding(.horizontal, 40).frame(height: 52)
                        .background(p.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .onAppear { finish() }
        }
    }

    // MARK: 操作

    private enum Choice { case ok, postpone, tomorrow, week, drop }

    private func start() {
        guard plan == nil else { return }
        let now = Date.now
        let log = ReviewStore.log()
        plan = ReviewLogic.plan(slot, items: store.items, seen: log.seen, now: now, weekly: launch.weekly)
        missed = ReviewLogic.previousMissed(before: slot, now: now, log: log)
        streak = ReviewLogic.streak(log, now: now)
        Task { await ReviewActions.opened(slot) }
    }

    /// カードの元の TODO（見返しの途中で変わっていれば新しい方）
    private func current(_ card: ReviewLogic.Card) -> TodoItem {
        store.items.first { $0.id == card.id } ?? card.item
    }

    private func act(_ c: Choice) {
        guard index < cards.count else { return }
        let card = cards[index]
        let item = current(card)
        switch c {
        case .ok, .tomorrow: fly = CGSize(width: 600, height: 0)
        case .postpone, .drop: fly = CGSize(width: -600, height: 0)
        case .week: fly = CGSize(width: 0, height: -800)
        }
        withAnimation(motion.change(reduce: reduce)) {
            switch c {
            case .ok: lastChanged = false
            case .postpone: store.postpone(item); lastChanged = true
            case .tomorrow: store.move(item, to: .tomorrow); lastChanged = true
            case .week: store.move(item, to: .thisWeek); lastChanged = true
            case .drop: store.delete(item); lastChanged = true
            }
            index += 1
        }
        ReviewActions.reviewed(slot, id: card.id)
        feedback += 1
    }

    private func undo() {
        guard lastChanged, index > 0 else { return }
        withAnimation(motion.change(reduce: reduce)) {
            store.undoLast()
            index -= 1
            lastChanged = false
        }
    }

    private func finish() {
        guard !finished else { return }
        withAnimation(motion.change(reduce: reduce)) { finished = true }
        Task {
            await ReviewActions.finished(slot)
            streak = ReviewLogic.streak(ReviewStore.log(), now: .now)
            ReviewPresenter.shared.revision += 1
        }
    }

    private func close() {
        ReviewPresenter.shared.revision += 1
        dismiss()
    }

    private var cardTransition: AnyTransition {
        let away: AnyTransition = AnyTransition.offset(fly).combined(with: .opacity)
        return .asymmetric(insertion: motion.appear(reduce: reduce), removal: reduce ? AnyTransition.opacity : away)
    }

    private func swipe(_ card: ReviewLogic.Card) -> some Gesture {
        DragGesture()
            .onChanged { v in
                dragID = card.id
                drag = v.translation
            }
            .onEnded { v in
                let w: CGFloat = v.translation.width
                let h: CGFloat = v.translation.height
                var choice: Choice? = nil
                if slot == .night && h < -120 && abs(w) < 90 { choice = .week }
                else if w > 110 { choice = slot == .night ? .tomorrow : .ok }
                else if w < -110 { choice = slot == .night ? .drop : .postpone }
                if let choice {
                    act(choice)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        drag = .zero
                        dragID = nil
                    }
                } else {
                    withAnimation(motion.tap(reduce: reduce)) { drag = .zero }
                }
            }
    }
}

// MARK: - 1枚のカード

struct ReviewCardView: View {
    @Environment(\.palette) private var p
    let card: ReviewLogic.Card
    let item: TodoItem
    let depth: Int
    let slot: ReviewSlot
    let drag: CGSize

    var body: some View {
        let kindColor: Color = card.kind == .overdue ? p.overdue : (card.kind == .forgotten ? Color.orange : p.accent)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(card.kind.label, systemImage: kindIcon)
                    .font(Font.subheadline.weight(.bold)).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(kindColor.opacity(0.14), in: Capsule()).foregroundStyle(kindColor)
                Spacer(minLength: 0)
                if item.isImportant { Image(systemName: "star.fill").foregroundStyle(Color.yellow) }
            }
            Spacer(minLength: 0)
            Text(item.title).font(Font.system(size: 32, weight: .bold, design: p.fontDesign)).foregroundStyle(p.text)
                .lineLimit(3).minimumScaleFactor(0.6)
            let due: String = item.isOverdue() ? "期限切れ・" + DueText.label(item) : DueText.label(item)
            Label(due, systemImage: "calendar").font(Font.callout.weight(.semibold)).foregroundStyle(p.sub)
            if card.kind == .forgotten {
                Text("3日以上前からあるTODOです。まだ要りますか？").font(Font.footnote).foregroundStyle(p.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220, maxHeight: 360)
        .background(surface)
        .overlay(alignment: .topTrailing) { stampView }
        .padding(.horizontal, 24)
        .scaleEffect(1 - CGFloat(depth) * 0.05)
        .offset(x: drag.width, y: CGFloat(depth) * 16 + drag.height * (slot == .night ? 0.6 : 0.1))
        .rotationEffect(.degrees(Double(drag.width) / 20))
        .accessibilityElement(children: .combine)
    }

    private var kindIcon: String {
        switch card.kind {
        case .overdue: "exclamationmark.triangle.fill"
        case .today: "sun.max"
        case .afternoon: "clock"
        case .unfinished: "moon"
        case .noDue: "tray"
        case .stale: "hourglass"
        case .forgotten: "lightbulb.fill"
        }
    }

    @ViewBuilder
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: p.radius + 4, style: .continuous)
        if p.world.isOn {
            let q: Palette = { var q = p; q.radius = p.radius + 4; return q }()
            WorldCardSurface(p: q)
        } else {
            shape.fill(p.card).shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    private var stampView: some View {
        if slot == .night && drag.height < -40 && abs(drag.width) < 90 {
            stamp("今週", p.sub)
        } else if drag.width > 30 {
            stamp(slot == .night ? "明日" : "確認した", p.accent)
        } else if drag.width < -30 {
            stamp(slot == .night ? "やめる" : p.world.postponeWord, p.overdue)
        }
    }

    private func stamp(_ text: String, _ color: Color) -> some View {
        let label: Text = Text(verbatim: text).font(Font.title2.weight(.bold))
        let angle: Double = drag.width >= 0 ? -12 : 12
        let fade: Double = Double(min(1, max(abs(drag.width), abs(drag.height)) / 120))
        return label.foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
            .padding(22)
            .opacity(fade)
    }
}

// MARK: - 見出しの1行（連続日数・今週の期限内・次の見返し）

struct ReviewStatusLine: View {
    @EnvironmentObject var store: TodoStore
    @ObservedObject private var presenter = ReviewPresenter.shared
    @Environment(\.palette) private var p
    @Environment(\.openReview) private var openReview
    @Environment(\.openReviewSettings) private var openReviewSettings

    var body: some View {
        let _ = presenter.revision
        let now = Date.now
        let st = ReviewState.make(log: ReviewStore.log(), settings: ReviewStore.settings(), items: store.items, now: now)
        HStack(spacing: 8) {
            Button { openReview(st.dueSlot) } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(ReviewSlot.allCases) { s in
                            Circle().fill(st.isDone(s) ? p.accent : p.sub.opacity(0.25)).frame(width: 7, height: 7)
                        }
                    }
                    Text(summary(st)).font(Font.footnote.weight(.semibold)).foregroundStyle(p.sub)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    cta(st)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("見返しを始める")
            Button { openReviewSettings() } label: {
                Image(systemName: "slider.horizontal.3").font(Font.footnote.weight(.bold)).foregroundStyle(p.sub)
                    .frame(width: 30, height: 30)
                    .background(p.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("見返しの設定")
        }
    }

    private func summary(_ st: ReviewState) -> String {
        var parts: [String] = ["見返し \(st.streak)日連続"]
        if let r = st.onTimePercent { parts.append("今週の期限内 \(r)%") }
        return parts.joined(separator: "・")
    }

    @ViewBuilder
    private func cta(_ st: ReviewState) -> some View {
        if let due = st.dueSlot {
            let text: String = "\(due.name)の見返し"
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                Text(text)
            }
                .font(Font.caption.weight(.heavy)).lineLimit(1).fixedSize()
                .foregroundStyle(p.onAccent)
                .padding(.horizontal, 10).frame(height: 28)
                .background(p.accent, in: Capsule())
        } else if let at = st.nextAt, let s = st.nextSlot {
            let text: String = "次は\(s.name) \(JP.time(at))"
            Text(text).font(Font.caption.weight(.bold)).foregroundStyle(p.sub).lineLimit(1).fixedSize()
        }
    }
}

// MARK: - 見返しの設定（TODO の見出しから開く）

struct ReviewSettingsSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var s = ReviewStore.settings()

    static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("見返しを通知する", isOn: $s.on)
                    Toggle("30分たっても開かなければ、もう一度知らせる", isOn: $s.renotify).disabled(!s.on)
                } footer: {
                    Text("1回30秒ほど。右へめくると確認した、左へめくると明日へ。夜は 明日・今週・やめる から選びます。")
                }
                .listRowBackground(p.card)

                Section {
                    timeRow("朝（アラームを止めなかった日）", \.morningMinute)
                    timeRow("昼", \.noonMinute)
                    timeRow("夜", \.nightMinute)
                } header: {
                    Text("時刻")
                } footer: {
                    Text("朝は、起床アラームを「止める」か「起きた！」を押した直後に始まります。アラームの無い日は上の時刻に知らせます。")
                }
                .listRowBackground(p.card)

                Section {
                    Picker("棚卸しの曜日", selection: $s.weeklyDay) {
                        ForEach(0..<7, id: \.self) { i in Text("\(Self.weekdayNames[i])曜日").tag(i) }
                    }
                } footer: {
                    Text("この曜日の夜は、期限のないTODOと7日以上前からあるTODOも見返します。")
                }
                .listRowBackground(p.card)
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle("見返しの設定").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .onChange(of: s) { _, v in
                ReviewStore.save(v)
                ReviewPresenter.shared.revision += 1
                Task { await ReviewActions.reschedule() }
            }
        }
        .presentationDetents([.large])
    }

    private func timeRow(_ title: String, _ key: WritableKeyPath<ReviewSettings, Int>) -> some View {
        let binding = Binding<Date>(
            get: {
                let start = Calendar.current.startOfDay(for: .now)
                return Calendar.current.date(byAdding: .minute, value: s[keyPath: key], to: start) ?? start
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                s[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
        return DatePicker(title, selection: binding, displayedComponents: .hourAndMinute)
            .environment(\.locale, Locale(identifier: "ja_JP"))
    }
}

// MARK: - 画面確認用の見本（-demo）

enum ReviewDemo {
    static func install(now: Date = .now) {
        let items = TodoData.all()
        var log = ReviewLog()
        let ages: [Int: Int] = [0: 9, 3: 5, 5: 4]   // 何日前から あるか（見本のTODOの並び順）
        for (i, t) in items.enumerated() {
            log.seen[t.id] = now.addingTimeInterval(TimeInterval(-(ages[i] ?? 0) * 86400))
        }
        let today = ReviewLogic.reviewDay(now)
        for i in 1...6 {
            let day = ReviewLogic.addDays(-i, today)
            var d = ReviewDay()
            for s in ReviewSlot.allCases {
                d.done[s.rawValue] = Calendar.current.date(byAdding: .minute, value: ReviewSettings().minute(s) + 4, to: day)
            }
            log.days[WakeLogic.key(day)] = d
        }
        var d = ReviewDay()
        d.morningAt = Calendar.current.date(byAdding: .minute, value: 7 * 60 + 2, to: today)
        if let at = d.morningAt, at < now { d.done[ReviewSlot.morning.rawValue] = at.addingTimeInterval(60) }
        log.days[WakeLogic.key(today)] = d
        ReviewStore.save(log)
        ReviewStore.save(ReviewSettings())
    }
}

// MARK: - 見返しを開く仕組み（TODO・起床の画面に付ける）

/// 見返しの全画面と設定のシートを出す。handlesRequests の画面（TODO）だけが通知からの依頼を受ける
struct ReviewHost: ViewModifier {
    var handlesRequests = true
    @EnvironmentObject var store: TodoStore
    @ObservedObject private var presenter = ReviewPresenter.shared
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @State private var launch: ReviewLaunch?
    @State private var showSettings = false
    @State private var demoApplied = false

    func body(content: Content) -> some View {
        content
            .environment(\.openReview, OpenReviewAction { slot in launch = ReviewLaunch.make(slot) })
            .environment(\.openReviewSettings, OpenReviewSettingsAction { showSettings = true })
            // 全画面は背景の透明な部品から出す（同じ並びに見張りの全画面もあり、同じ所に2つ付けると片方しか開かない）
            .background {
                Color.clear.fullScreenCover(item: $launch) { l in
                    ReviewFlowView(launch: l)
                        .environmentObject(store)
                        .environment(\.palette, p)
                        .environment(\.motion, motion)
                        .preferredColorScheme(p.scheme)
                }
            }
            .sheet(isPresented: $showSettings) {
                ReviewSettingsSheet().environment(\.palette, p).preferredColorScheme(p.scheme)
            }
            .onChange(of: presenter.request) { _, s in take(s) }
            .onAppear {
                take(presenter.request)
                applyDemo()
            }
    }

    private func take(_ s: ReviewSlot?) {
        guard handlesRequests, let s else { return }
        presenter.request = nil
        launch = ReviewLaunch.make(s)
    }

    /// 画面写真用：-reviewdemo [morning|noon|night]（-reviewweekly で棚卸しも）、-reviewsettings
    private func applyDemo() {
        guard handlesRequests, !demoApplied else { return }
        demoApplied = true
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-reviewdemo") || args.contains("-reviewsettings") else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if args.contains("-reviewsettings") { showSettings = true; return }
            var slot: ReviewSlot? = nil
            if let i = args.firstIndex(of: "-reviewdemo"), i + 1 < args.count { slot = ReviewSlot(rawValue: args[i + 1]) }
            launch = ReviewLaunch.make(slot, forceWeekly: args.contains("-reviewweekly"))
        }
    }
}
