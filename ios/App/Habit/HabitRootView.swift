import SwiftUI
import UserNotifications

/// 習慣の画面の状態。保存は HabitData（ウィジェットと共有）
@MainActor
final class HabitModel: ObservableObject {
    @Published var habits: [Habit] = []
    @Published var log: HabitLog = [:]
    private static var demoInstalled = false

    init() {
        if ProcessInfo.processInfo.arguments.contains("-demo") && !Self.demoInstalled {
            Self.demoInstalled = true
            let (h, l) = HabitData.demo()
            HabitData.saveHabits(h)
            HabitData.saveLog(l)
        }
        reload()
    }

    func reload() {
        habits = HabitData.habits()
        log = HabitData.log()
    }

    var today: [Habit] { habits.filter { $0.isActive(on: .now) } }
    var resting: [Habit] { habits.filter { !$0.isActive(on: .now) } }
    var doneCount: Int { today.filter { HabitData.isDone(log, $0, .now) }.count }
    var progress: Double { HabitData.dayProgress(habits, log) }

    func count(_ h: Habit) -> Int { HabitData.count(log, h, .now) }

    /// タップ1回分。目標に届いたら true
    func tap(_ h: Habit) -> Bool {
        let before = HabitData.isDone(log, h, .now)
        let cur = count(h)
        let next = h.isCount ? min(cur + 1, 999) : (cur >= 1 ? 0 : 1)
        HabitData.set(&log, h, .now, next)
        HabitData.saveLog(log)
        return !before && next >= h.target
    }

    func decrement(_ h: Habit) {
        HabitData.set(&log, h, .now, max(0, count(h) - 1))
        HabitData.saveLog(log)
    }

    func resetToday(_ h: Habit) {
        HabitData.set(&log, h, .now, 0)
        HabitData.saveLog(log)
    }

    func upsert(_ h: Habit) {
        if let i = habits.firstIndex(where: { $0.id == h.id }) { habits[i] = h } else { habits.append(h) }
        persist()
    }

    func delete(_ h: Habit) {
        habits.removeAll { $0.id == h.id }
        persist()
    }

    func move(from: IndexSet, to: Int) {
        habits.move(fromOffsets: from, toOffset: to)
        persist()
    }

    private func persist() {
        HabitData.saveHabits(habits)
        HabitReminders.reschedule(habits)
    }
}

/// 習慣のリマインダー（通知の識別子は habit- で始める）
enum HabitReminders {
    static func reschedule(_ habits: [Habit]) {
        let c = UNUserNotificationCenter.current()
        if habits.contains(where: { $0.remindHour != nil }) {
            c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        c.getPendingNotificationRequests { reqs in
            c.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("habit-") })
            for h in habits {
                guard let hour = h.remindHour else { continue }
                let days = (h.weekdays.isEmpty || h.weekdays.count >= 7) ? Array(1...7) : h.weekdays
                for wd in days {
                    var dc = DateComponents()
                    dc.weekday = wd
                    dc.hour = hour
                    dc.minute = h.remindMinute ?? 0
                    let content = UNMutableNotificationContent()
                    content.title = h.name
                    content.body = h.isCount ? "今日の目標は \(h.target)\(h.unit) です。" : "今日の「\(h.name)」はできましたか？"
                    content.sound = .default
                    let req = UNNotificationRequest(identifier: "habit-\(h.id)-\(wd)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
                    c.add(req)
                }
            }
        }
    }
}

/// 習慣タブの入口
struct HabitRootView: View {
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var phase
    @StateObject private var model = HabitModel()
    @State private var editing: HabitEditTarget?
    @State private var reordering = false
    @State private var deleting: Habit?
    @State private var tapFeedback = 0
    @State private var doneFeedback = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if model.habits.isEmpty { empty }
                ForEach(model.today) { h in
                    HabitTodayCard(habit: h, count: model.count(h), streak: HabitData.currentStreak(h, model.log)) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            if model.tap(h) { doneFeedback += 1 } else { tapFeedback += 1 }
                        }
                    }
                    .contextMenu { menu(h) }
                }
                if !model.resting.isEmpty {
                    sectionTitle("今日はお休み")
                    ForEach(model.resting) { h in
                        restingRow(h).contextMenu { menu(h) }
                    }
                }
                if !model.habits.isEmpty {
                    sectionTitle("記録")
                    ForEach(model.habits) { h in
                        HabitStatsCard(habit: h, log: model.log)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .sensoryFeedback(.increase, trigger: tapFeedback)
        .sensoryFeedback(.success, trigger: doneFeedback)
        .onChange(of: phase) { _, ph in if ph == .active { model.reload() } }
        .sheet(item: $editing) { target in
            HabitEditSheet(habit: target.habit, isNew: target.isNew) { model.upsert($0) }
                .environment(\.palette, p)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $reordering) {
            NavigationStack {
                List {
                    ForEach(model.habits) { h in
                        Label(h.name, systemImage: h.icon).foregroundStyle(p.text)
                            .listRowBackground(p.card)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .environment(\.editMode, .constant(.active))
                .scrollContentBackground(.hidden).paletteBackground(p)
                .navigationTitle("並べ替え").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { reordering = false } } }
            }
            .environment(\.palette, p)
        }
        .confirmationDialog("「\(deleting?.name ?? "")」を削除しますか？",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let d = deleting { withAnimation { model.delete(d) } }
                deleting = nil
            }
            Button("やめる", role: .cancel) { deleting = nil }
        }
    }

    // MARK: 部品

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(JP.date(.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Spacer()
                if model.habits.count > 1 {
                    circleButton("arrow.up.arrow.down", label: "並べ替え") { reordering = true }
                }
                circleButton("plus", label: "習慣を追加", filled: true) {
                    editing = HabitEditTarget(habit: Habit(name: ""), isNew: true)
                }
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今日の習慣").font(.title3.weight(.semibold)).foregroundStyle(p.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(model.doneCount)").font(.system(size: 56, weight: .heavy, design: p.fontDesign))
                            .foregroundStyle(p.text).contentTransition(.numericText())
                        Text("/ \(model.today.count) 達成").font(.title3.weight(.semibold)).foregroundStyle(p.sub)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    HabitRing(fraction: model.progress, color: p.accent, lineWidth: 12)
                    Text("\(Int((model.progress * 100).rounded()))%")
                        .font(.system(size: 22, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                        .contentTransition(.numericText())
                }
                .frame(width: 92, height: 92)
                .animation(.spring(duration: 0.5), value: model.progress)
            }
            if !model.today.isEmpty && model.doneCount == model.today.count {
                Label("今日の習慣はすべて達成しました", systemImage: "sparkles")
                    .font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circleButton(_ icon: String, label: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.headline.weight(.bold)).frame(width: 44, height: 44)
                .foregroundStyle(filled ? p.onAccent : p.text)
                .background(filled ? p.accent : p.card, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.fill").font(.system(size: 56)).foregroundStyle(p.accent)
            Text("習慣を追加しましょう").font(.title3.bold()).foregroundStyle(p.text)
            Text("右上の ＋ から、毎日続けたいことを登録できます。").font(.subheadline).foregroundStyle(p.sub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .paletteCard(p)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.headline).foregroundStyle(p.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    private func restingRow(_ h: Habit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: h.icon).font(.headline).foregroundStyle(h.tint.color(p))
                .frame(width: 36, height: 36).background(h.tint.color(p).opacity(0.15), in: Circle())
            Text(h.name).font(.body.weight(.semibold)).foregroundStyle(p.text)
            Spacer()
            Text(h.weekdayText).font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 14)
    }

    @ViewBuilder
    private func menu(_ h: Habit) -> some View {
        Button { editing = HabitEditTarget(habit: h, isNew: false) } label: { Label("編集", systemImage: "pencil") }
        if h.isCount && model.count(h) > 0 {
            Button { withAnimation { model.decrement(h) } } label: { Label("1つ戻す", systemImage: "minus.circle") }
        }
        Button { withAnimation { model.resetToday(h) } } label: { Label("今日をリセット", systemImage: "arrow.counterclockwise") }
        Button(role: .destructive) { deleting = h } label: { Label("削除", systemImage: "trash") }
    }
}

struct HabitEditTarget: Identifiable {
    let id = UUID()
    var habit: Habit
    var isNew: Bool
}

/// 押すと少し縮むボタン
struct HabitPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 今日の習慣の大きなカード。タップで1回分チェック
struct HabitTodayCard: View {
    @Environment(\.palette) private var p
    let habit: Habit
    let count: Int
    let streak: Int
    let onTap: () -> Void

    var body: some View {
        let c = habit.tint.color(p)
        let done = count >= habit.target
        let frac = min(1, Double(count) / Double(max(1, habit.target)))
        let on: Color = habit.tint.onColor(p)
        let fg: Color = done ? on : p.text
        let subColor: Color = done ? on.opacity(0.8) : p.sub
        let ringColor: Color = done ? on : c
        let ringTrack: Color? = done ? on.opacity(0.25) : nil
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    HabitRing(fraction: frac, color: ringColor, track: ringTrack, lineWidth: 6)
                    Image(systemName: done ? "checkmark" : habit.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(ringColor)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: count)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name).font(.title3.weight(.bold)).foregroundStyle(fg)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    HStack(spacing: 10) {
                        Label("\(streak)日連続", systemImage: "flame.fill")
                        if let r = habit.reminderText { Label(r, systemImage: "bell.fill") }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(subColor)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if habit.isCount {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(count)").font(.system(size: 34, weight: .heavy, design: p.fontDesign))
                            .contentTransition(.numericText())
                        Text("/\(habit.target)\(habit.unit)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(subColor)
                    }
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: p.radius, style: .continuous)
                    .fill(done ? c : p.card)
                    .shadow(color: .black.opacity(p.scheme == .dark ? 0 : 0.06), radius: 12, y: 4)
            )
            .contentShape(RoundedRectangle(cornerRadius: p.radius, style: .continuous))
        }
        .buttonStyle(HabitPressStyle())
        .accessibilityLabel("\(habit.name) \(habit.progressText(count))")
    }
}

/// 連続日数・達成率・ヒートマップ（直近12週）
struct HabitStatsCard: View {
    @Environment(\.palette) private var p
    let habit: Habit
    let log: HabitLog

    var body: some View {
        let c = habit.tint.color(p)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: habit.icon).font(.subheadline.weight(.bold)).foregroundStyle(c)
                    .frame(width: 32, height: 32).background(c.opacity(0.15), in: Circle())
                Text(habit.name).font(.headline).foregroundStyle(p.text).lineLimit(1)
                Spacer()
                Text(habit.weekdayText).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
            HStack(spacing: 0) {
                stat("連続", "\(HabitData.currentStreak(habit, log))", "日")
                stat("最高", "\(HabitData.bestStreak(habit, log))", "日")
                stat("この7日", HabitData.weekRate(habit, log).map { "\(Int(($0 * 100).rounded()))" } ?? "―", "%")
            }
            HabitHeatmap(habit: habit, log: log, color: c)
        }
        .paletteCard(p)
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 26, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// GitHub 風の記録表。列が週（左が古い）、行が曜日（月〜日）
struct HabitHeatmap: View {
    @Environment(\.palette) private var p
    let habit: Habit
    let log: HabitLog
    let color: Color
    var weeks = 12

    private static let labels = ["月", " ", "水", " ", "金", " ", "日"]

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let wd = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: -((wd + 5) % 7), to: today) ?? today
        let first = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: monday) ?? monday
        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { r in
                    Text(Self.labels[r])
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(p.sub)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { r in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(cellColor(cal.date(byAdding: .day, value: w * 7 + r, to: first) ?? first, today: today))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cellColor(_ d: Date, today: Date) -> Color {
        if d > today { return .clear }
        if !habit.isActive(on: d) { return p.sub.opacity(0.05) }
        let n = HabitData.count(log, habit, d)
        if n == 0 { return p.sub.opacity(0.13) }
        let frac = min(1, Double(n) / Double(habit.target))
        return color.opacity(0.3 + 0.7 * frac)
    }
}
