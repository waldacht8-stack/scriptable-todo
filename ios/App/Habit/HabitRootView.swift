import SwiftUI
import UserNotifications

/// 習慣の画面の状態。保存は HabitData（ウィジェットと共有）
@MainActor
final class HabitModel: ObservableObject {
    @Published var habits: [Habit] = []
    @Published var log: HabitLog = [:]
    private static var demoInstalled = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        if !Self.demoInstalled {
            // 画面確認用の起動引数：-habitempty（習慣なし）、-habitmany（20件・長い名前）、-demo（見本）
            if args.contains("-habitempty") {
                Self.demoInstalled = true
                HabitData.saveHabits([])
                HabitData.saveLog([:])
            } else if args.contains("-habitmany") {
                Self.demoInstalled = true
                let (h, l) = HabitData.demoMany()
                HabitData.saveHabits(h)
                HabitData.saveLog(l)
            } else if args.contains("-demo") {
                Self.demoInstalled = true
                let (h, l) = HabitData.demo()
                HabitData.saveHabits(h)
                HabitData.saveLog(l)
            }
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
                    content.body = h.isCount ? "今日の目標は\(h.target)\(h.unit)です。" : "今日の「\(h.name)」はできましたか？"
                    content.sound = .default
                    let req = UNNotificationRequest(identifier: "habit-\(h.id)-\(wd)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
                    c.add(req)
                }
            }
        }
    }
}

/// 習慣タブの表示の切り替え
enum HabitPage: Hashable {
    case today, records
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
    @State private var page: HabitPage = ProcessInfo.processInfo.arguments.contains("-habitrecords") ? .records : .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.habits.isEmpty {
                    empty
                } else {
                    summary
                    HabitSegment(selection: $page, options: [(HabitPage.today, "今日"), (HabitPage.records, "記録")])
                    if page == .today { todayList } else { records }
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
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-habitedit"), editing == nil, let h = model.habits.first {
                editing = HabitEditTarget(habit: h, isNew: false)
            }
        }
        .sheet(item: $editing) { target in
            HabitEditSheet(habit: target.habit, isNew: target.isNew) { model.upsert($0) }
                .environment(\.palette, p)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $reordering) {
            NavigationStack {
                List {
                    ForEach(model.habits) { h in
                        Label(h.name, systemImage: h.icon).foregroundStyle(p.text).lineLimit(1)
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
            .tint(p.accent)
        }
        .confirmationDialog("「\(deleting?.name ?? "")」を削除しますか？",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let d = deleting { withAnimation { model.delete(d) } }
                deleting = nil
            }
            Button("キャンセル", role: .cancel) { deleting = nil }
        } message: {
            Text("これまでの記録も見られなくなります。")
        }
    }

    // MARK: 部品

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(JP.date(.now)).font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text("習慣").font(.system(size: 34, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
            }
            Spacer(minLength: 8)
            HabitCircleButton(icon: "plus", label: "習慣を追加", filled: true) { addNew() }
            SettingsButton()
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addNew() {
        editing = HabitEditTarget(habit: Habit(name: ""), isNew: true)
    }

    /// 今日の達成（数と輪は同じ数え方：達成した習慣 ÷ 今日する習慣）
    private var summary: some View {
        let total: Int = model.today.count
        let done: Int = model.doneCount
        let percent: Int = Int((model.progress * 100).rounded())
        let allDone: Bool = total > 0 && done == total
        let note: String = total == 0 ? "今日する習慣はありません" : (allDone ? "すべて達成しました" : "あと\(total - done)つ")
        let noteColor: Color = allDone ? p.accent : p.sub
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日の達成").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(done)").font(.system(size: 44, weight: .heavy, design: p.fontDesign))
                        .foregroundStyle(p.text).contentTransition(.numericText())
                    Text("/ \(total)").font(.title3.weight(.bold)).foregroundStyle(p.sub)
                }
                Label(note, systemImage: allDone ? "sparkles" : "flag.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(noteColor)
            }
            Spacer(minLength: 0)
            ZStack {
                HabitRing(fraction: model.progress, color: p.accent, lineWidth: 10)
                Text("\(percent)%").font(.system(size: 17, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .contentTransition(.numericText())
            }
            .frame(width: 76, height: 76)
            .animation(.spring(duration: 0.5), value: model.progress)
            .accessibilityHidden(true)
        }
        .paletteCard(p)
    }

    @ViewBuilder
    private var todayList: some View {
        if model.today.isEmpty {
            HabitNote(icon: "moon.zzz.fill", title: "今日はお休みの日です", detail: "する曜日の習慣はありません。")
        }
        ForEach(model.today) { h in
            HabitTodayCard(habit: h, count: model.count(h), streak: HabitData.currentStreak(h, model.log)) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    if model.tap(h) { doneFeedback += 1 } else { tapFeedback += 1 }
                }
            }
            .contextMenu { menu(h) }
        }
        if !model.resting.isEmpty {
            HabitSectionTitle(text: "今日はお休み")
            ForEach(model.resting) { h in
                restingRow(h).contextMenu { menu(h) }
            }
        }
        Text("長押しで編集・削除できます").font(.caption).foregroundStyle(p.sub)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var records: some View {
        if model.habits.count > 1 {
            HStack {
                Spacer()
                Button { reordering = true } label: {
                    Label("並べ替え", systemImage: "arrow.up.arrow.down").font(.subheadline.weight(.semibold))
                        .foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
            }
        }
        ForEach(model.habits) { h in
            HabitStatsCard(habit: h, log: model.log)
                .contextMenu { menu(h) }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf.fill").font(.system(size: 38, weight: .semibold)).foregroundStyle(p.accent)
                .frame(width: 84, height: 84)
                .background(p.accent.opacity(0.12), in: Circle())
            Text("まだ習慣がありません").font(.title3.weight(.bold)).foregroundStyle(p.text)
            Text("毎日続けたいことを登録すると、\nここで毎日の記録をつけられます。")
                .font(.subheadline).foregroundStyle(p.sub)
                .multilineTextAlignment(.center)
            Button { addNew() } label: {
                Label("習慣を追加", systemImage: "plus").font(.headline).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(HabitPressStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .paletteCard(p)
        .padding(.top, 8)
    }

    private func restingRow(_ h: Habit) -> some View {
        let c: Color = h.tint.color(p)
        return HStack(spacing: 12) {
            Image(systemName: h.icon).font(.headline).foregroundStyle(c)
                .frame(width: 36, height: 36).background(c.opacity(0.15), in: Circle())
            Text(h.name).font(.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
            Spacer(minLength: 8)
            Text(h.weekdayText).font(.footnote.weight(.semibold)).foregroundStyle(p.sub).fixedSize()
        }
        .paletteCard(p, padding: 14)
    }

    @ViewBuilder
    private func menu(_ h: Habit) -> some View {
        Button { editing = HabitEditTarget(habit: h, isNew: false) } label: { Label("編集", systemImage: "pencil") }
        if h.isCount && model.count(h) > 0 {
            Button { withAnimation { model.decrement(h) } } label: { Label("1つ戻す", systemImage: "minus.circle") }
        }
        if model.count(h) > 0 {
            Button { withAnimation { model.resetToday(h) } } label: { Label("今日の記録を消す", systemImage: "arrow.counterclockwise") }
        }
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

/// 見出しの右の丸いボタン（SettingsButton と同じ大きさ）
struct HabitCircleButton: View {
    @Environment(\.palette) private var p
    let icon: String
    let label: String
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        let fg: Color = filled ? p.onAccent : p.text
        let bg: Color = filled ? p.accent : p.card
        return Button(action: action) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(fg)
                .frame(width: 44, height: 44)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 2〜3択の切り替え（色合いに合わせた見た目）
struct HabitSegment<Value: Hashable>: View {
    @Environment(\.palette) private var p
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i].0, options[i].1)
            }
        }
        .padding(4)
        .background(p.card, in: Capsule())
    }

    private func segment(_ value: Value, _ title: String) -> some View {
        let on: Bool = value == selection
        let fg: Color = on ? p.onAccent : p.sub
        let bg: Color = on ? p.accent : Color.clear
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(fg)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(bg, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 一覧の小見出し
struct HabitSectionTitle: View {
    @Environment(\.palette) private var p
    let text: String

    var body: some View {
        Text(text).font(.headline).foregroundStyle(p.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// 一覧が空のときなどの小さな案内カード
struct HabitNote: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(p.accent)
                .frame(width: 44, height: 44)
                .background(p.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(p.text)
                Text(detail).font(.subheadline).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p)
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
        let c: Color = habit.tint.color(p)
        let done: Bool = count >= habit.target
        let frac: Double = min(1, Double(count) / Double(max(1, habit.target)))
        let on: Color = habit.tint.onColor(p)
        let fg: Color = done ? on : p.text
        let subColor: Color = done ? on.opacity(0.8) : p.sub
        let ringColor: Color = done ? on : c
        let ringTrack: Color? = done ? on.opacity(0.25) : nil
        let fill: Color = done ? c : p.card
        let shape = RoundedRectangle(cornerRadius: p.radius, style: .continuous)
        return Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    HabitRing(fraction: frac, color: ringColor, track: ringTrack, lineWidth: 6)
                    Image(systemName: done ? "checkmark" : habit.icon)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(ringColor)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: count)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name).font(.headline).foregroundStyle(fg)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        if streak > 0 {
                            Label("\(streak)日連続", systemImage: "flame.fill")
                        } else {
                            Text(habit.weekdayText)
                        }
                        if let r = habit.reminderText { Label(r, systemImage: "bell.fill") }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(subColor)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                if habit.isCount {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(count)").font(.system(size: 30, weight: .heavy, design: p.fontDesign))
                            .foregroundStyle(fg)
                            .contentTransition(.numericText())
                        Text("/\(habit.target)\(habit.unit)").font(.subheadline.weight(.semibold))
                            .foregroundStyle(subColor)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(fill)
                    .shadow(color: .black.opacity(p.scheme == .dark ? 0 : 0.06), radius: 12, y: 4)
            )
            .contentShape(shape)
        }
        .buttonStyle(HabitPressStyle())
        .accessibilityLabel("\(habit.name) \(habit.progressText(count))")
        .accessibilityHint(habit.isCount ? "タップで1つ記録します" : "タップで記録を切り替えます")
    }
}

/// 連続日数・達成率・ヒートマップ（直近12週）
struct HabitStatsCard: View {
    @Environment(\.palette) private var p
    let habit: Habit
    let log: HabitLog

    var body: some View {
        let c: Color = habit.tint.color(p)
        let rate: String? = HabitData.weekRate(habit, log).map { "\(Int(($0 * 100).rounded()))" }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: habit.icon).font(.subheadline.weight(.bold)).foregroundStyle(c)
                    .frame(width: 32, height: 32).background(c.opacity(0.15), in: Circle())
                Text(habit.name).font(.headline).foregroundStyle(p.text).lineLimit(1)
                Spacer(minLength: 8)
                Text(habit.weekdayText).font(.caption.weight(.semibold)).foregroundStyle(p.sub).fixedSize()
            }
            HStack(spacing: 0) {
                stat("いまの連続", "\(HabitData.currentStreak(habit, log))", "日")
                stat("最長", "\(HabitData.bestStreak(habit, log))", "日")
                stat("直近7日", rate ?? "―", rate == nil ? "" : "%")
            }
            HabitHeatmap(habit: habit, log: log, color: c)
            HabitHeatmapLegend(color: c)
        }
        .paletteCard(p)
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub).lineLimit(1)
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
        .accessibilityHidden(true)
    }

    private func cellColor(_ d: Date, today: Date) -> Color {
        if d > today { return .clear }
        if !habit.isActive(on: d) { return p.sub.opacity(0.05) }
        let n = HabitData.count(log, habit, d)
        if n == 0 { return p.sub.opacity(0.15) }
        let frac = min(1, Double(n) / Double(habit.target))
        return color.opacity(0.3 + 0.7 * frac)
    }
}

/// 記録表の見方（12週間・少ない〜多い）
struct HabitHeatmapLegend: View {
    @Environment(\.palette) private var p
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("12週間").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
            Spacer(minLength: 4)
            Text("できなかった").font(.caption2).foregroundStyle(p.sub)
            cell(p.sub.opacity(0.15))
            cell(color.opacity(0.5))
            cell(color)
            Text("できた").font(.caption2).foregroundStyle(p.sub)
        }
    }

    private func cell(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(c).frame(width: 10, height: 10)
    }
}
