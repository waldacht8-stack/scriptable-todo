import SwiftUI
import WidgetKit

/// ウィジェットの見本（起動引数 -widgetpreview のときだけ表示。スクリーンショット用）
/// 色合いは -theme、世界観は -world に従う。-widgetsize large で大サイズ、-widgetsize other で起床・習慣、-widgetsize lock でロック画面を並べる
struct WidgetPreviewScreen: View {
    @Environment(\.palette) private var p
    private let size: String = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-widgetsize"), i + 1 < args.count else { return "" }
        return args[i + 1]
    }()

    private var title: String {
        let kind: String
        switch size {
        case "large": kind = "大"
        case "other": kind = "起床・習慣"
        case "lock": kind = "ロック画面"
        default: kind = "小・中"
        }
        let world: String = p.world.isOn ? "・\(p.world.name)" : ""
        return "ウィジェットの見本（\(kind)）\(world)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.bold)).foregroundStyle(p.text)
                switch size {
                case "large": largePage
                case "other": otherPage
                case "lock": lockPage
                default: smallMediumPage
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paletteBackground(p)
    }

    // MARK: TODO（小・中・大）

    private var smallMediumPage: some View {
        let items: [TodoItem] = Self.sampleItems()
        return ForEach(TodayLayout.allCases) { layout in
            let data: TodoWidgetData = Self.data(items, layout: layout, palette: p)
            VStack(alignment: .leading, spacing: 4) {
                caption(layout.name)
                HStack(alignment: .top, spacing: 6) {
                    frame(TodoWidgetView(data: data, familyOverride: .systemSmall), Self.small, scale: 0.55)
                    frame(TodoWidgetView(data: data, familyOverride: .systemMedium), Self.medium, scale: 0.55)
                }
            }
        }
    }

    private var largePage: some View {
        let items: [TodoItem] = Self.sampleItems()
        let pairs: [[TodayLayout]] = [[TodayLayout.focus, TodayLayout.board], [TodayLayout.thumb, TodayLayout.timeline]]
        return ForEach(pairs, id: \.self) { pair in
            HStack(alignment: .top, spacing: 8) {
                ForEach(pair) { layout in
                    VStack(alignment: .leading, spacing: 4) {
                        caption(layout.name)
                        frame(TodoWidgetView(data: Self.data(items, layout: layout, palette: p), familyOverride: .systemLarge),
                              Self.large, scale: 0.47)
                    }
                }
            }
        }
    }

    // MARK: 起床・習慣・ロック画面

    private var otherPage: some View {
        let before: WakeEntry = WakeEntry(date: .now, snap: Self.wakeBefore(), palette: p)
        let after: WakeEntry = WakeEntry(date: .now, snap: Self.wakeAfter(), palette: p)
        let habit: HabitWidgetData = Self.habitData(p)
        return VStack(alignment: .leading, spacing: 10) {
            caption("起床（起きる前）")
            HStack(alignment: .top, spacing: 6) {
                frame(WakeWidgetView(entry: before, familyOverride: .systemSmall), Self.small, scale: 0.55)
                frame(WakeWidgetView(entry: before, familyOverride: .systemMedium), Self.medium, scale: 0.55)
            }
            caption("起床（起きた後）")
            HStack(alignment: .top, spacing: 6) {
                frame(WakeWidgetView(entry: after, familyOverride: .systemSmall), Self.small, scale: 0.55)
                frame(WakeWidgetView(entry: after, familyOverride: .systemMedium), Self.medium, scale: 0.55)
            }
            caption("習慣")
            HStack(alignment: .top, spacing: 6) {
                frame(HabitWidgetView(data: habit, familyOverride: .systemSmall), Self.small, scale: 0.55)
                frame(HabitWidgetView(data: habit, familyOverride: .systemMedium), Self.medium, scale: 0.55)
            }
        }
    }

    private var lockPage: some View {
        let before: WakeEntry = WakeEntry(date: .now, snap: Self.wakeBefore(), palette: p)
        let after: WakeEntry = WakeEntry(date: .now, snap: Self.wakeAfter(), palette: p)
        let habit: HabitWidgetData = Self.habitData(p)
        let todo: TodoWidgetData = Self.data(Self.sampleItems(), layout: .focus, palette: p)
        return VStack(alignment: .leading, spacing: 10) {
            caption("単色で表示されるので、世界観は形と文字だけで出す")
            lockPanel(todo: todo, before: before, after: after, habit: habit)
        }
    }

    /// ロック画面の見本（暗い面に白い文字。実機では壁紙の上に半透明で描かれる）
    private func lockPanel(todo: TodoWidgetData, before: WakeEntry, after: WakeEntry, habit: HabitWidgetData) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let circle = CGSize(width: 68, height: 68)
        let rect = CGSize(width: 154, height: 72)
        let panel: Color = Color(uiColor: .secondarySystemBackground)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                accessory(TodoWidgetView(data: todo, familyOverride: .accessoryCircular), circle, round: true)
                accessory(WakeWidgetView(entry: before, familyOverride: .accessoryCircular), circle, round: true)
                accessory(WakeWidgetView(entry: after, familyOverride: .accessoryCircular), circle, round: true)
                accessory(HabitWidgetView(data: habit, familyOverride: .accessoryCircular), circle, round: true)
            }
            HStack(spacing: 10) {
                accessory(TodoWidgetView(data: todo, familyOverride: .accessoryRectangular), rect, round: false)
                accessory(WakeWidgetView(entry: before, familyOverride: .accessoryRectangular), rect, round: false)
            }
            HStack(spacing: 10) {
                accessory(HabitWidgetView(data: habit, familyOverride: .accessoryRectangular), rect, round: false)
                accessory(WakeWidgetView(entry: after, familyOverride: .accessoryRectangular), rect, round: false)
            }
            TodoWidgetView(data: todo, familyOverride: .accessoryInline)
                .font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .background(panel, in: shape)
        .environment(\.colorScheme, .dark)
    }

    private func accessory<V: View>(_ view: V, _ size: CGSize, round: Bool) -> some View {
        view
            .frame(width: size.width, height: size.height)
            .background {
                if round { Circle().fill(.quaternary) }
            }
    }

    // MARK: 共通

    private static let small = CGSize(width: 170, height: 170)
    private static let medium = CGSize(width: 364, height: 170)
    private static let large = CGSize(width: 364, height: 382)

    private func caption(_ s: String) -> some View {
        Text(s).font(.caption.weight(.bold)).foregroundStyle(p.sub)
    }

    /// ウィジェットの枠（余白 16・角丸 22。背景は containerBackground と同じもの）
    private func frame<V: View>(_ view: V, _ size: CGSize, scale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return view
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetPaletteBackground(p: p))
            .containerShape(shape)
            .clipShape(shape)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    // MARK: 見本のデータ（一般的な内容のみ）

    /// 見本：長めの題名で、切れ方や折り返しが見えるようにする
    private static func sampleItems() -> [TodoItem] {
        let cal = Calendar.current
        let now = Date.now
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, _ h: Int, _ m: Int = 0) -> Date {
            let d: Date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return cal.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
        }
        func later(_ minutes: Int) -> Date {
            let d: Date = cal.date(byAdding: .minute, value: minutes, to: now) ?? now
            return min(max(d, today), day(0, 23, 50))
        }
        return [
            TodoItem(title: "図書館に本を返却する", due: day(-1, 17)),
            TodoItem(title: "朝のストレッチを10分", done: true, due: later(-50), doneAt: later(-50)),
            TodoItem(title: "ゴミ出し（燃えるゴミ）", done: true, due: later(-20), doneAt: later(-20)),
            TodoItem(title: "牛乳と卵とパンを買う", due: later(60), important: true),
            TodoItem(title: "部屋の掃除と洗濯をする", due: today, allDay: true),
            TodoItem(title: "請求書の内容を確認する", due: later(180)),
            TodoItem(title: "美容院に電話して予約する", due: day(1, 11)),
            TodoItem(title: "車検の見積もりをもらう", due: day(5, 0), allDay: true),
            TodoItem(title: "旅行の持ち物リストを作る"),
        ]
    }

    private static func data(_ all: [TodoItem], layout: TodayLayout, palette: Palette) -> TodoWidgetData {
        let now = Date.now
        let cal = Calendar.current
        let open: [TodoItem] = TodoData.sorted(all.filter { !$0.done })
        let done: [TodoItem] = all.filter { item in item.done && (item.doneAt.map { cal.isDateInToday($0) } ?? false) }
        let timed: [TodoItem] = open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > now }
        return TodoWidgetData(
            items: open,
            overdue: open.filter { $0.isOverdue(now) }.count,
            doneToday: done.count,
            next: timed.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) },
            layout: layout,
            palette: palette,
            groupOK: true,
            doneItems: done
        )
    }

    /// 起床の見本：明日の朝 6:30 から3回鳴る（まだ押せない時間）
    private static func wakeBefore() -> WakeSnapshot {
        let cal = Calendar.current
        let tomorrow: Date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow) ?? tomorrow }
        let stages: [WakePlan.Stage] = [
            WakePlan.Stage(number: 1, name: "1回目", at: at(6, 30), score: 100),
            WakePlan.Stage(number: 2, name: "2回目", at: at(6, 40), score: 80),
            WakePlan.Stage(number: 3, name: "3回目", at: at(6, 50), score: 60),
        ]
        let plan = WakePlan(day: "preview", dayStart: tomorrow, stages: stages, departure: at(8, 0), skipReason: nil)
        return WakeSnapshot(phase: .before, next: plan, today: nil, reached: 0, nextStage: nil,
                            checkInAt: nil, score: nil, departure: nil, nextStep: nil, stepsLeft: 0,
                            bedtime: nil, canCheckIn: false, checkInFrom: at(4, 30))
    }

    /// 起床の見本：20分前に起きて、出発まで45分。次は朝ごはん
    private static func wakeAfter() -> WakeSnapshot {
        let now = Date.now
        let step = WakeRoutineItem(name: "朝ごはんを食べる", minutes: 15)
        return WakeSnapshot(phase: .morning, next: nil, today: nil, reached: 3, nextStage: nil,
                            checkInAt: now.addingTimeInterval(-20 * 60), score: 90,
                            departure: now.addingTimeInterval(45 * 60), nextStep: step, stepsLeft: 2,
                            bedtime: nil, canCheckIn: false, checkInFrom: nil)
    }

    /// 習慣の見本：4つのうち2つ達成
    private static func habitData(_ p: Palette) -> HabitWidgetData {
        let rows: [HabitWidgetRow] = [
            HabitWidgetRow(habit: Habit(name: "水を飲む", icon: "drop.fill", color: .sky, target: 8, unit: "杯"), count: 5),
            HabitWidgetRow(habit: Habit(name: "散歩する", icon: "figure.walk", color: .green), count: 1),
            HabitWidgetRow(habit: Habit(name: "本を読む", icon: "book.fill", color: .amber), count: 1),
            HabitWidgetRow(habit: Habit(name: "早めに寝る", icon: "moon.fill", color: .indigo), count: 0),
        ]
        return HabitWidgetData(rows: rows, progress: 0.66, palette: p, motion: p.world.motion ?? .snappy)
    }
}
