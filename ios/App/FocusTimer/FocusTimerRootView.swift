import SwiftUI
import Charts
import UserNotifications

/// 集中タイマーの画面の状態
@MainActor
final class FocusTimerModel: ObservableObject {
    @Published var state = FocusTimerState()
    @Published var settings = FocusTimerSettings()
    @Published var sessions: [FocusSessionRecord] = []
    @Published var now = Date.now
    @Published var finishedTodo: FocusTimerState?   // 集中が終わったTODO（完了にするか聞く）
    @Published var finishCount = 0
    private static var demoInstalled = false

    init() {
        if ProcessInfo.processInfo.arguments.contains("-demo") && !Self.demoInstalled {
            Self.demoInstalled = true
            FocusTimerData.installDemo()
        }
        reload()
    }

    func reload() {
        settings = FocusTimerData.settings()
        _ = FocusTimerEngine.settle(autoStart: false)
        state = FocusTimerData.state()
        sessions = FocusTimerData.sessions()
        now = .now
    }

    /// 1秒ごと：表示を進め、終わる時刻を過ぎたら次へ
    func tick() {
        now = .now
        let r = FocusTimerEngine.settle(now: now, autoStart: true)
        if let f = r.finished {
            state = r.state
            sessions = FocusTimerData.sessions()
            finishCount += 1
            live()
            if f.phase == .focus, f.todoID != nil { finishedTodo = f }
        } else {
            let s = FocusTimerData.state()   // ほかの場所（ウィジェットなど）で変わった分も反映
            if s != state { state = s }
        }
    }

    var remaining: Double { state.left(at: now) ?? settings.seconds(state.phase) }
    var total: Double { state.isRunning ? max(1, state.total) : settings.seconds(state.phase) }
    var progress: Double { 1 - remaining / total }

    func start(title: String, todoID: String?) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        state = FocusTimerEngine.start(title: title, todoID: todoID)
        live()
    }

    func togglePause() {
        state = FocusTimerEngine.togglePause()
        live()
    }

    func stop() {
        state = FocusTimerEngine.stop()
        sessions = FocusTimerData.sessions()
        live()
    }

    func skip() {
        state = FocusTimerEngine.skip()
        sessions = FocusTimerData.sessions()
        live()
    }

    /// ライブアクティビティを今の状態に合わせる
    func live() {
        let s = state
        Task { await FocusTimerLive.sync(s) }
    }

    func saveSettings(_ s: FocusTimerSettings) {
        settings = s
        FocusTimerData.saveSettings(s)
        if !state.isRunning { state.total = s.seconds(state.phase) }
    }

    // MARK: 集計

    var todayMinutes: Int {
        Int(sessions.filter { Calendar.current.isDateInToday($0.end) }.reduce(0) { $0 + $1.minutes }.rounded())
    }

    var todaySessions: Int { sessions.filter { $0.completed && Calendar.current.isDateInToday($0.end) }.count }

    struct DayStat: Identifiable {
        let id: Int
        let label: String
        let minutes: Double
        let isToday: Bool
    }

    var week: [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0..<7).map { i in
            let back = 6 - i
            let day = cal.date(byAdding: .day, value: -back, to: today) ?? today
            let m = sessions.filter { cal.isDate($0.end, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
            let label = back == 0 ? "今日" : HabitData.weekdaySymbol(cal.component(.weekday, from: day))
            return DayStat(id: i, label: label, minutes: m, isToday: back == 0)
        }
    }
}

/// 集中タブの入口
struct FocusTimerRootView: View {
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var scene
    @EnvironmentObject private var store: TodoStore
    @StateObject private var model = FocusTimerModel()
    @State private var title = ""
    @State private var todoID: String?
    @State private var picking = false
    @State private var showSettings = false
    @State private var actionFeedback = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                taskCard
                dial
                controls
                stats
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .onReceive(ticker) { _ in model.tick() }
        .onChange(of: scene) { _, s in if s == .active { model.reload() } }
        .onAppear {
            if model.state.isRunning || !model.state.title.isEmpty {
                title = model.state.title
                todoID = model.state.todoID
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: actionFeedback)
        .sensoryFeedback(.success, trigger: model.finishCount)
        .sheet(isPresented: $picking) {
            FocusTaskPicker(title: $title, todoID: $todoID)
                .environment(\.palette, p)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            FocusSettingsSheet(settings: model.settings) { model.saveSettings($0) }
                .environment(\.palette, p)
                .presentationDetents([.medium, .large])
        }
        .alert("おつかれさまでした", isPresented: Binding(get: { model.finishedTodo != nil }, set: { if !$0 { model.finishedTodo = nil } })) {
            Button("完了にする") {
                if let id = model.finishedTodo?.todoID, let item = store.items.first(where: { $0.id == id }) {
                    store.complete(item)
                    if todoID == id { todoID = nil; title = "" }
                }
                model.finishedTodo = nil
            }
            Button("まだ続ける", role: .cancel) { model.finishedTodo = nil }
        } message: {
            Text("「\(model.finishedTodo?.title ?? "")」は終わりましたか？")
        }
    }

    // MARK: 部品

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(JP.date(.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text("集中").font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.headline.weight(.bold)).frame(width: 44, height: 44)
                    .foregroundStyle(p.text).background(p.card, in: Circle())
            }
            .accessibilityLabel("時間の設定")
        }
        .padding(.top, 20)
    }

    private var taskCard: some View {
        Button { if !model.state.isRunning { picking = true } } label: {
            HStack(spacing: 14) {
                Image(systemName: todoID != nil ? "checklist" : "scope").font(.title3.weight(.bold))
                    .foregroundStyle(p.accent).frame(width: 44, height: 44)
                    .background(p.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("取り組むこと").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                    Text(displayTitle.isEmpty ? "タップして選ぶ（なしでも始められます）" : displayTitle)
                        .font(displayTitle.isEmpty ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(displayTitle.isEmpty ? p.sub : p.text)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !model.state.isRunning {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                }
            }
            .paletteCard(p, padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String { model.state.isRunning ? model.state.title : title }

    private var phaseColor: Color {
        model.state.phase.isBreak ? HabitColor.teal.color(p) : p.accent
    }

    /// phaseColor の上に載せる記号の色
    private var onPhaseColor: Color {
        model.state.phase.isBreak ? HabitColor.teal.onColor(p) : p.onAccent
    }

    private var dial: some View {
        let s = model.state
        let every = max(2, model.settings.longBreakEvery)
        return ZStack {
            Circle().stroke(phaseColor.opacity(0.14), lineWidth: 22)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, 1 - model.progress)))
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.progress)
            VStack(spacing: 8) {
                Label(s.phase.name + (s.isPaused ? "・一時停止中" : ""), systemImage: s.phase.icon)
                    .font(.headline).foregroundStyle(phaseColor)
                Text(FocusTimerFormat.clock(model.remaining))
                    .font(.system(size: 72, weight: .heavy, design: p.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(p.text)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let end = s.endAt, s.isRunning, !s.isPaused {
                    Text("\(JP.time(end)) に終了").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                } else {
                    Text("\(model.settings.minutes(s.phase))分").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                }
                HStack(spacing: 6) {
                    ForEach(0..<every, id: \.self) { i in
                        Circle().fill(i < s.cycleCount % every || (s.phase == .longBreak) ? p.accent : p.sub.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)
            }
            .padding(40)
        }
        .frame(maxWidth: 320)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var controls: some View {
        let s = model.state
        return HStack(spacing: 28) {
            roundButton("stop.fill", size: 64, label: "終了", enabled: s.isRunning) {
                actionFeedback += 1
                withAnimation { model.stop() }
            }
            Button {
                actionFeedback += 1
                withAnimation(.spring(duration: 0.35)) {
                    if s.isRunning { model.togglePause() } else { model.start(title: title, todoID: todoID) }
                }
            } label: {
                Image(systemName: s.isRunning && !s.isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 96, height: 96)
                    .foregroundStyle(onPhaseColor)
                    .background(phaseColor, in: Circle())
                    .shadow(color: phaseColor.opacity(0.35), radius: 14, y: 6)
            }
            .accessibilityLabel(s.isRunning ? (s.isPaused ? "再開" : "一時停止") : "開始")
            roundButton("forward.end.fill", size: 64, label: "スキップ", enabled: true) {
                actionFeedback += 1
                withAnimation { model.skip() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func roundButton(_ icon: String, size: CGFloat, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 22, weight: .bold))
                .frame(width: size, height: size)
                .foregroundStyle(enabled ? p.text : p.sub.opacity(0.5))
                .background(p.card, in: Circle())
                .shadow(color: .black.opacity(p.scheme == .dark ? 0 : 0.06), radius: 8, y: 3)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var stats: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile("今日の集中", "\(model.todayMinutes)", "分")
                tile("セッション", "\(model.todaySessions)", "回")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("この7日間").font(.headline).foregroundStyle(p.text)
                    Spacer()
                    Text("合計 \(Int(model.week.reduce(0) { $0 + $1.minutes }.rounded()))分")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                }
                Chart(model.week) { d in
                    BarMark(x: .value("日", d.label), y: .value("分", d.minutes))
                        .foregroundStyle(d.isToday ? p.accent : p.accent.opacity(0.35))
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            if d.minutes > 0 {
                                Text("\(Int(d.minutes.rounded()))").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
                            }
                        }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                    }
                }
                .frame(height: 150)
            }
            .paletteCard(p)
        }
        .padding(.top, 10)
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .contentTransition(.numericText())
                Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p, padding: 16)
    }
}

enum FocusTimerFormat {
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 取り組むことを選ぶ（TODOから、または自由に入力）
struct FocusTaskPicker: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TodoStore
    @Binding var title: String
    @Binding var todoID: String?
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                Section("自由に入力") {
                    HStack {
                        TextField("例：資料を読む", text: $text)
                            .submitLabel(.done)
                            .onSubmit(useText)
                        Button("決定", action: useText).fontWeight(.bold)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .listRowBackground(p.card)
                }
                Section("TODOから選ぶ") {
                    if store.open.isEmpty {
                        Text("未完了のTODOはありません").foregroundStyle(p.sub).listRowBackground(p.card)
                    }
                    ForEach(store.open) { item in
                        Button {
                            title = item.title
                            todoID = item.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(p.text)
                                    Text(DueText.label(item)).font(.caption).foregroundStyle(item.isOverdue() ? p.overdue : p.sub)
                                }
                                Spacer()
                                if todoID == item.id { Image(systemName: "checkmark").foregroundStyle(p.accent) }
                            }
                        }
                        .listRowBackground(p.card)
                    }
                }
                if !title.isEmpty {
                    Section {
                        Button("選ばずに始める", role: .destructive) {
                            title = ""
                            todoID = nil
                            dismiss()
                        }
                        .listRowBackground(p.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle("取り組むこと")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .onAppear { if todoID == nil { text = title } }
    }

    private func useText() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        title = t
        todoID = nil
        dismiss()
    }
}

/// 時間の設定
struct FocusSettingsSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State var settings: FocusTimerSettings
    let onSave: (FocusTimerSettings) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("時間") {
                    Stepper(value: $settings.focusMinutes, in: 5...90, step: 5) { row("集中", "\(settings.focusMinutes)分") }
                        .listRowBackground(p.card)
                    Stepper(value: $settings.shortBreakMinutes, in: 1...30) { row("小休憩", "\(settings.shortBreakMinutes)分") }
                        .listRowBackground(p.card)
                    Stepper(value: $settings.longBreakMinutes, in: 5...60, step: 5) { row("長い休憩", "\(settings.longBreakMinutes)分") }
                        .listRowBackground(p.card)
                    Stepper(value: $settings.longBreakEvery, in: 2...8) { row("長い休憩の間隔", "集中\(settings.longBreakEvery)回ごと") }
                        .listRowBackground(p.card)
                }
                Section {
                    Toggle("集中が終わったら休憩を自動で始める", isOn: $settings.autoStartBreak)
                        .listRowBackground(p.card)
                }
                Section {
                    Button("標準に戻す（25分・5分）") { settings = FocusTimerSettings() }
                        .listRowBackground(p.card)
                }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle("時間の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(settings); dismiss() }.fontWeight(.bold)
                }
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(p.text)
            Spacer()
            Text(value).font(.body.weight(.bold)).foregroundStyle(p.accent)
        }
    }
}
