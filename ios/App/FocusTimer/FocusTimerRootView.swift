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

    /// 今日の集中（分）。日付をまたいだ集中は今日の分だけ数える
    var todayMinutes: Int {
        let day: Date = now
        let total: Double = sessions.reduce(0.0) { $0 + $1.minutes(on: day) }
        return Int(total.rounded())
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
            let m: Double = sessions.reduce(0.0) { $0 + $1.minutes(on: day, calendar: cal) }
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
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-focussettings")
    @State private var actionFeedback = 0
    @State private var viewHeight: CGFloat = 800   // 見えている高さ（小さい画面で操作ボタンまで1画面に収める）
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
        .onGeometryChange(for: CGFloat.self) { (proxy: GeometryProxy) -> CGFloat in
            proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
        } action: { (h: CGFloat) in
            viewHeight = h
        }
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
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(JP.date(.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text("集中").font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
            }
            Spacer(minLength: 8)
            HabitCircleButton(icon: "slider.horizontal.3", label: "時間の設定") { showSettings = true }
            SettingsButton()
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskCard: some View {
        Button { if !model.state.isRunning { picking = true } } label: {
            HStack(spacing: 14) {
                Image(systemName: todoID != nil ? "checklist" : "scope").font(.title3.weight(.bold))
                    .foregroundStyle(p.accent).frame(width: 44, height: 44)
                    .background(p.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("取り組むこと").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                    Text(displayTitle.isEmpty ? "タップして選ぶ" : displayTitle)
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

    /// 文字盤の直径。上の見出し・カードと下のボタンを除いた高さに合わせる（最大 320）
    private var dialSize: CGFloat {
        let room: CGFloat = viewHeight - 350
        return min(320, max(210, room))
    }

    /// 文字盤とボタンの色（色合いの強調色。休憩中も同じ色で、表示の文字とアイコンで区別する）
    private var phaseColor: Color { p.accent }
    private var onPhaseColor: Color { p.onAccent }

    private var dial: some View {
        let s = model.state
        let every = max(2, model.settings.longBreakEvery)
        let size: CGFloat = dialSize
        let line: CGFloat = size >= 280 ? 22 : 16
        let clockSize: CGFloat = (size * 0.225).rounded()
        let ringStyle: StrokeStyle = StrokeStyle(lineWidth: line, lineCap: .round)
        return ZStack {
            Circle().stroke(phaseColor.opacity(0.14), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, 1 - model.progress)))
                .stroke(phaseColor, style: ringStyle)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.progress)
            VStack(spacing: 8) {
                Label(s.isPaused ? "一時停止中" : s.phase.name, systemImage: s.isPaused ? "pause.circle.fill" : s.phase.icon)
                    .font(.headline).foregroundStyle(s.isPaused ? p.sub : phaseColor)
                Text(FocusTimerFormat.clock(model.remaining))
                    .font(.system(size: clockSize, weight: .heavy, design: p.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(p.text)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1).minimumScaleFactor(0.5)
                if let end = s.endAt, s.isRunning, !s.isPaused {
                    Text("\(JP.time(end))に終了").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
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
            .padding(size * 0.125)
        }
        .frame(width: size, height: size)
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
        let week: [FocusTimerModel.DayStat] = model.week
        let weekTotal: Int = Int(week.reduce(0.0) { $0 + $1.minutes }.rounded())
        return VStack(alignment: .leading, spacing: 12) {
            HabitSectionTitle(text: "記録")
            HStack(spacing: 12) {
                tile("今日の集中", FocusTimerFormat.durationParts(model.todayMinutes))
                tile("終えた回数", [("\(model.todaySessions)", "回")])
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("この7日間").font(.headline).foregroundStyle(p.text)
                    Spacer(minLength: 8)
                    Text("合計 " + FocusTimerFormat.duration(weekTotal))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                }
                if weekTotal == 0 {
                    Text("まだ記録がありません。\n集中を終えると、日ごとの時間がここに出ます。")
                        .font(.subheadline).foregroundStyle(p.sub)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    weekChart(week)
                    Text("棒の上の数字は分。日付をまたいだ集中は、それぞれの日に分けて数えます。")
                        .font(.caption2).foregroundStyle(p.sub)
                }
            }
            .paletteCard(p)
        }
        .padding(.top, 8)
    }

    private func weekChart(_ week: [FocusTimerModel.DayStat]) -> some View {
        let strong: Color = p.accent
        let soft: Color = p.accent.opacity(0.35)
        let label: Color = p.sub
        return Chart(week) { d in
            BarMark(x: .value("日", d.label), y: .value("分", d.minutes))
                .foregroundStyle(d.isToday ? strong : soft)
                .cornerRadius(6)
                .annotation(position: .top) {
                    if d.minutes >= 1 {
                        Text("\(Int(d.minutes.rounded()))").font(.caption2.weight(.semibold)).foregroundStyle(label)
                    }
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption.weight(.semibold)).foregroundStyle(label)
            }
        }
        .frame(height: 150)
        .accessibilityLabel("この7日間の集中時間")
    }

    /// 数字の大きなタイル。parts は（数字, 単位）の並び：「1 時間 40 分」など
    private func tile(_ title: String, _ parts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    Text(parts[i].0).font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                        .contentTransition(.numericText())
                    Text(parts[i].1).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .paletteCard(p, padding: 16)
    }
}

enum FocusTimerFormat {
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// 「45分」「2時間」「1時間40分」
    static func duration(_ minutes: Int) -> String {
        durationParts(minutes).map { $0.0 + $0.1 }.joined()
    }

    /// 数字と単位に分けた時間（大きな数字の表示用）
    static func durationParts(_ minutes: Int) -> [(String, String)] {
        let m: Int = max(0, minutes)
        if m < 60 { return [("\(m)", "分")] }
        let h: Int = m / 60
        let rest: Int = m % 60
        if rest == 0 { return [("\(h)", "時間")] }
        return [("\(h)", "時間"), ("\(rest)", "分")]
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
                Section {
                    HStack {
                        TextField("例：資料を読む", text: $text)
                            .foregroundStyle(p.text)
                            .submitLabel(.done)
                            .onSubmit(useText)
                        Button("決定", action: useText).fontWeight(.bold)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .listRowBackground(p.card)
                } header: {
                    Text("自由に入力").foregroundStyle(p.sub)
                }
                Section {
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
                                    Text(item.title).font(.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(2)
                                    Text(DueText.label(item)).font(.caption).foregroundStyle(item.isOverdue() ? p.overdue : p.sub)
                                }
                                Spacer()
                                if todoID == item.id { Image(systemName: "checkmark").foregroundStyle(p.accent) }
                            }
                        }
                        .listRowBackground(p.card)
                    }
                } header: {
                    Text("TODOから選ぶ").foregroundStyle(p.sub)
                }
                if !title.isEmpty {
                    Section {
                        Button("選択を外す") {
                            title = ""
                            todoID = nil
                            dismiss()
                        }
                        .foregroundStyle(p.accent)
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
        .tint(p.accent)
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

/// 時間の設定（色合いに合わせたカードで組む）
struct FocusSettingsSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State var settings: FocusTimerSettings
    let onSave: (FocusTimerSettings) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    card("時間") {
                        stepRow("集中", "\(settings.focusMinutes)分", $settings.focusMinutes, 5...90, 5)
                        divider
                        stepRow("短い休憩", "\(settings.shortBreakMinutes)分", $settings.shortBreakMinutes, 1...30, 1)
                        divider
                        stepRow("長い休憩", "\(settings.longBreakMinutes)分", $settings.longBreakMinutes, 5...60, 5)
                    }
                    card("長い休憩") {
                        stepRow("長い休憩までの集中", "\(settings.longBreakEvery)回", $settings.longBreakEvery, 2...8, 1)
                        Text("集中を\(settings.longBreakEvery)回終えるごとに、長い休憩になります。")
                            .font(.footnote).foregroundStyle(p.sub)
                    }
                    card("自動") {
                        Toggle(isOn: $settings.autoStartBreak) {
                            Text("集中のあと、休憩を自動で始める").font(.body.weight(.semibold)).foregroundStyle(p.text)
                        }
                        .tint(p.accent)
                    }
                    Button { settings = FocusTimerSettings() } label: {
                        Text("初期設定に戻す（集中25分・休憩5分）").font(.subheadline.weight(.semibold)).foregroundStyle(p.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
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
        .tint(p.accent)
    }

    private var divider: some View {
        Rectangle().fill(p.sub.opacity(0.15)).frame(height: 1)
    }

    /// 見出し付きのカード
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
            content()
        }
        .paletteCard(p)
    }

    /// 名前・値・−＋ボタンの1行
    private func stepRow(_ title: String, _ value: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int) -> some View {
        let v: Int = binding.wrappedValue
        let canMinus: Bool = v - step >= range.lowerBound
        let canPlus: Bool = v + step <= range.upperBound
        return HStack(spacing: 10) {
            Text(title).font(.body.weight(.semibold)).foregroundStyle(p.text)
                .lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            HabitStepButton(icon: "minus", enabled: canMinus) { binding.wrappedValue = max(range.lowerBound, v - step) }
            Text(value).font(.system(size: 20, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 56)
            HabitStepButton(icon: "plus", enabled: canPlus) { binding.wrappedValue = min(range.upperBound, v + step) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: binding.wrappedValue = min(range.upperBound, binding.wrappedValue + step)
            case .decrement: binding.wrappedValue = max(range.lowerBound, binding.wrappedValue - step)
            @unknown default: break
            }
        }
    }
}
