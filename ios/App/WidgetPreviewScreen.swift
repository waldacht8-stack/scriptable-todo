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
        case "r4": kind = "リリース4"
        case "review": kind = "見返し"
        case "summary": kind = "今日のまとめ"
        case "wake4": kind = "起床・夜と見張り"
        case "lock4": kind = "ロック画面・時間帯"
        case "tabs": kind = "家計簿・相談・情報"
        case "tabslock": kind = "家計簿・相談・情報（大・ロック画面）"
        case "sunmoon": kind = "太陽と月・\(JP.time(Self.previewNow))"
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
                case "r4": r4Page
                case "review": reviewPage
                case "summary": summaryPage
                case "wake4": wake4Page
                case "lock4": lock4Page
                case "sunmoon": sunMoonPage
                case "tabs": tabsPage
                case "tabslock": tabsLockPage
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
        let before: WakeEntry = WakeEntry(date: Self.afternoon, snap: Self.wakeBefore(), palette: p)
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
        let before: WakeEntry = WakeEntry(date: Self.afternoon, snap: Self.wakeBefore(), palette: p)
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
    private func frame<V: View>(_ view: V, _ size: CGSize, scale: CGFloat, padded: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return view
            .padding(padded ? 16 : 0)
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

// MARK: - リリース4のウィジェット（太陽と月・見返し・今日のまとめ・起床の夜と見張り・ロック画面）
// -widgetsize r4 / review / summary / wake4 / lock4 / sunmoon。-widgettime HH:mm で時刻をずらす（太陽と月の位置の確認用）

extension WidgetPreviewScreen {
    /// 見本の時刻（-widgettime HH:mm。なければ今）
    static let previewNow: Date = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-widgettime"), i + 1 < args.count else { return .now }
        let parts: [Int] = args[i + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return .now }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) ?? .now
    }()

    /// 今日の決まった時刻（見本の状態をそろえる）
    static func today(_ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
    }

    /// 起床の見本（起きる前）は昼過ぎの時刻で描く（夜の表示にならないように）
    static var afternoon: Date { today(15) }

    /// 見本の TODO：今日の 8・10・14・18・23 時、昨日の期限切れ、明日、期限なし。now より前の今日の分は済み
    static func r4Items(now: Date) -> [TodoItem] {
        let cal = Calendar.current
        let start: Date = cal.startOfDay(for: now)
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: (day * 24 + h) * 60 + m, to: start) ?? start
        }
        func todays(_ title: String, _ h: Int, important: Bool = false) -> TodoItem {
            let due: Date = at(0, h)
            let done: Bool = due < now
            let doneAt: Date? = done ? due.addingTimeInterval(5 * 60) : nil
            return TodoItem(title: title, done: done, due: due, important: important ? true : nil, doneAt: doneAt)
        }
        return [
            TodoItem(title: "図書館に本を返却する", due: at(-1, 17)),
            todays("ゴミ出し", 8),
            todays("市役所に書類を提出", 10),
            todays("歯医者", 14, important: true),
            todays("牛乳と卵を買う", 18),
            todays("洗濯物を取りこむ", 23),
            TodoItem(title: "美容院", due: at(1, 11)),
            TodoItem(title: "旅行の持ち物リストを作る", due: at(1, 20)),
            TodoItem(title: "請求書を確認"),
        ]
    }

    /// 起床の見本（夜）：明日 7:00 から4回。就寝の目安 23:30。alarm が false なら入っていない
    static func wakeNight(alarm: Bool) -> WakeSnapshot {
        let cal = Calendar.current
        let tomorrow: Date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow) ?? tomorrow }
        let stages: [WakePlan.Stage] = (0..<4).map { i in
            WakePlan.Stage(number: i + 1, name: "\(i + 1)回目", at: at(7, i * 5), score: 100 - i * 15)
        }
        let plan = WakePlan(day: "preview", dayStart: tomorrow, stages: stages, departure: at(8, 10), skipReason: nil)
        let from: Date? = alarm ? at(5, 0) : nil
        return WakeSnapshot(phase: .evening, next: alarm ? plan : nil, today: nil, reached: 0, nextStage: nil,
                            checkInAt: nil, score: nil, departure: nil, nextStep: nil, stepsLeft: 0,
                            bedtime: today(23, 30), canCheckIn: false, checkInFrom: from)
    }

    /// 見張りの見本：7:08 に止めて、100歩のうち 37歩。次の見張り 7:18、最後 7:28
    static func watchSample() -> WakeWatchFeed {
        WakeWatchFeed(watching: true, stoppedAt: today(7, 8), steps: 37, requiredSteps: 100,
                      nextWatchAt: today(7, 18), lastWatchAt: today(7, 28))
    }

    /// 起床の見本（見張り中の朝）
    static func wakeMorning() -> WakeSnapshot {
        WakeSnapshot(phase: .window, next: nil, today: nil, reached: 4, nextStage: nil,
                     checkInAt: nil, score: nil, departure: nil, nextStep: nil, stepsLeft: 0,
                     bedtime: nil, canCheckIn: true, checkInFrom: nil)
    }

    func dayEntry(at now: Date, watch: WakeWatchFeed = .none, wake: WakeSnapshot? = nil) -> DayWidgetEntry {
        let snap: WakeSnapshot = wake ?? Self.wakeNight(alarm: true)
        return DayWidgetEntry(date: now, todos: Self.r4Items(now: now), palette: p, review: ReviewFeed.demo(now: now),
                              watch: watch, kakeibo: KakeiboFeed.demo(now: now), wake: snap,
                              consult: ConsultFeed.demo(now: now), info: InfoFeed.demo(now: now))
    }

    func wakeEntry(at now: Date, snap: WakeSnapshot, watch: WakeWatchFeed = .none) -> WakeEntry {
        let tomorrow: Int = DayTodos(Self.r4Items(now: now), now: now).tomorrow.count
        return WakeEntry(date: now, snap: snap, palette: p, watch: watch, tomorrowTodos: tomorrow)
    }

    // MARK: ページ

    /// タブごと（家計簿・相談・情報）の小・中。相談は 20:00（「今日の1枚 まだ」が出る時刻）
    var tabsPage: some View {
        let e: DayWidgetEntry = dayEntry(at: Self.today(20, 0))
        return VStack(alignment: .leading, spacing: 6) {
            caption("家計簿")
            HStack(alignment: .top, spacing: 6) {
                frame(KakeiboWidgetView(entry: e, familyOverride: .systemSmall), Self.small, scale: 0.55)
                frame(KakeiboWidgetView(entry: e, familyOverride: .systemMedium), Self.medium, scale: 0.55)
            }
            frame(KakeiboWidgetView(entry: e, familyOverride: .systemMedium), Self.medium, scale: 0.9)
            caption("相談（20:00）")
            HStack(alignment: .top, spacing: 6) {
                frame(ConsultWidgetView(entry: e, familyOverride: .systemSmall), Self.small, scale: 0.55)
                frame(InfoWidgetView(entry: e, familyOverride: .systemSmall), Self.small, scale: 0.55)
            }
            frame(ConsultWidgetView(entry: e, familyOverride: .systemMedium), Self.medium, scale: 0.9)
            caption("情報（小は上の右）")
            frame(InfoWidgetView(entry: e, familyOverride: .systemMedium), Self.medium, scale: 0.9)
        }
    }

    /// 情報（大）と、3つのロック画面
    var tabsLockPage: some View {
        let e: DayWidgetEntry = dayEntry(at: Self.today(20, 0))
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let circle = CGSize(width: 64, height: 64)
        let rect = CGSize(width: 160, height: 66)
        let panel: Color = Color(uiColor: .secondarySystemBackground)
        return VStack(alignment: .leading, spacing: 6) {
            caption("情報（大）")
            frame(InfoWidgetView(entry: e, familyOverride: .systemLarge), Self.large, scale: 0.8)
            caption("ロック画面：家計簿・相談・情報")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    accessory(KakeiboWidgetView(entry: e, familyOverride: .accessoryRectangular), rect, round: false)
                    accessory(KakeiboWidgetView(entry: e, familyOverride: .accessoryCircular), circle, round: true)
                    accessory(ConsultWidgetView(entry: e, familyOverride: .accessoryCircular), circle, round: true)
                }
                HStack(spacing: 10) {
                    accessory(ConsultWidgetView(entry: e, familyOverride: .accessoryRectangular), rect, round: false)
                    accessory(InfoWidgetView(entry: e, familyOverride: .accessoryCircular), circle, round: true)
                }
                accessory(InfoWidgetView(entry: e, familyOverride: .accessoryRectangular), rect, round: false)
                KakeiboWidgetView(entry: e, familyOverride: .accessoryInline).font(.subheadline.weight(.semibold)).lineLimit(1)
                ConsultWidgetView(entry: e, familyOverride: .accessoryInline).font(.subheadline.weight(.semibold)).lineLimit(1)
                InfoWidgetView(entry: e, familyOverride: .accessoryInline).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.primary)
            .background(panel, in: shape)
            .environment(\.colorScheme, .dark)
        }
    }

    /// 太陽と月の一日（小・中・大。-widgettime の時刻で）
    var sunMoonPage: some View {
        let e: DayWidgetEntry = dayEntry(at: Self.previewNow)
        let sky: SunMoonSky = SunMoonSky(period: SkyPeriod.of(e.date), world: p.world, accent: p.accent)
        let small = SunMoonWidgetView(entry: e, familyOverride: .systemSmall).background(sky)
        let medium = SunMoonWidgetView(entry: e, familyOverride: .systemMedium).background(sky)
        let large = SunMoonWidgetView(entry: e, familyOverride: .systemLarge).background(sky)
        return VStack(alignment: .leading, spacing: 6) {
            caption("小・中・大")
            frame(small, Self.small, scale: 0.9, padded: false)
            frame(medium, Self.medium, scale: 0.9, padded: false)
            frame(large, Self.large, scale: 0.9, padded: false)
        }
    }

    /// 全体の見本：見返し（中）・今日のまとめ（大）・起床（夜・見張り）
    var r4Page: some View {
        let evening: DayWidgetEntry = dayEntry(at: Self.today(19, 0))
        let night: WakeEntry = wakeEntry(at: Self.today(22, 40), snap: Self.wakeNight(alarm: true))
        let watch: WakeEntry = wakeEntry(at: Self.today(7, 12), snap: Self.wakeMorning(), watch: Self.watchSample())
        return VStack(alignment: .leading, spacing: 6) {
            caption("見返し（中）19:00")
            frame(ReviewWidgetView(entry: evening, familyOverride: .systemMedium), Self.medium, scale: 0.9)
            caption("今日のまとめ（大）19:00")
            frame(SummaryWidgetView(entry: evening), Self.large, scale: 0.9)
            caption("起床：夜 22:40 ／ 見張り中 7:12")
            HStack(spacing: 8) {
                frame(WakeWidgetView(entry: night, familyOverride: .systemSmall, standbyOverride: false), Self.small, scale: 0.9)
                frame(WakeWidgetView(entry: watch, familyOverride: .systemSmall), Self.small, scale: 0.9)
            }
        }
    }

    /// 見返し（中・大）
    var reviewPage: some View {
        let evening: DayWidgetEntry = dayEntry(at: Self.today(19, 0))
        let morning: DayWidgetEntry = dayEntry(at: Self.today(9, 30))
        return VStack(alignment: .leading, spacing: 6) {
            caption("中・19:00（朝と昼は済み）")
            frame(ReviewWidgetView(entry: evening, familyOverride: .systemMedium), Self.medium, scale: 0.92)
            caption("中・9:30（次は昼）")
            frame(ReviewWidgetView(entry: morning, familyOverride: .systemMedium), Self.medium, scale: 0.92)
            caption("大・19:00")
            frame(ReviewWidgetView(entry: evening, familyOverride: .systemLarge), Self.large, scale: 0.92)
        }
    }

    /// 今日のまとめ（大）：夜のアラーム確認と、見張り中
    var summaryPage: some View {
        let evening: DayWidgetEntry = dayEntry(at: Self.today(19, 0))
        let watching: DayWidgetEntry = dayEntry(at: Self.today(7, 12), watch: Self.watchSample(), wake: Self.wakeMorning())
        return VStack(alignment: .leading, spacing: 6) {
            caption("19:00・明日のアラームあり")
            frame(SummaryWidgetView(entry: evening), Self.large, scale: 1.0)
            caption("7:12・見張り中")
            frame(SummaryWidgetView(entry: watching), Self.large, scale: 0.9)
        }
    }

    /// 起床：夜（あり・なし）・中・見張り中・スタンバイ
    var wake4Page: some View {
        let nightAt: Date = Self.today(22, 40)
        let set: WakeEntry = wakeEntry(at: nightAt, snap: Self.wakeNight(alarm: true))
        let none: WakeEntry = wakeEntry(at: nightAt, snap: Self.wakeNight(alarm: false))
        let watch: WakeEntry = wakeEntry(at: Self.today(7, 12), snap: Self.wakeMorning(), watch: Self.watchSample())
        let black = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let standby = WakeWidgetView(entry: set, familyOverride: .systemSmall, standbyOverride: true)
            .padding(16)
            .frame(width: Self.small.width, height: Self.small.height)
            .background(Color.black, in: black)
        return VStack(alignment: .leading, spacing: 6) {
            caption("夜 22:40：アラームあり ／ なし")
            HStack(spacing: 8) {
                frame(WakeWidgetView(entry: set, familyOverride: .systemSmall, standbyOverride: false), Self.small, scale: 0.9)
                frame(WakeWidgetView(entry: none, familyOverride: .systemSmall, standbyOverride: false), Self.small, scale: 0.9)
            }
            frame(WakeWidgetView(entry: set, familyOverride: .systemMedium), Self.medium, scale: 0.9)
            caption("見張り中 7:12 ／ スタンバイ（夜）")
            HStack(spacing: 8) {
                frame(WakeWidgetView(entry: watch, familyOverride: .systemSmall), Self.small, scale: 0.9)
                standby
                    .scaleEffect(0.9)
                    .frame(width: Self.small.width * 0.9, height: Self.small.height * 0.9)
            }
            frame(WakeWidgetView(entry: watch, familyOverride: .systemMedium), Self.medium, scale: 0.9)
        }
    }

    /// ロック画面：ふだん（12:30）・見張り中（7:12）・夜（22:40）
    var lock4Page: some View {
        let day: DayWidgetEntry = dayEntry(at: Self.today(12, 30))
        let watching: DayWidgetEntry = dayEntry(at: Self.today(7, 12), watch: Self.watchSample(), wake: Self.wakeMorning())
        let night: DayWidgetEntry = dayEntry(at: Self.today(22, 40))
        let noAlarm: DayWidgetEntry = dayEntry(at: Self.today(22, 40), wake: Self.wakeNight(alarm: false))
        let wakeWatch: WakeEntry = wakeEntry(at: Self.today(7, 12), snap: Self.wakeMorning(), watch: Self.watchSample())
        let wakeNight: WakeEntry = wakeEntry(at: Self.today(22, 40), snap: Self.wakeNight(alarm: true))
        return VStack(alignment: .leading, spacing: 8) {
            caption("いまの日和：時間帯で中身が変わる")
            lockRow("ふだん 12:30", day)
            lockRow("見張り中 7:12", watching)
            lockRow("夜 22:40", night)
            lockRow("夜・アラームなし", noAlarm)
            caption("起床ウィジェット（見張り中・夜）")
            lockWakeRow(wakeWatch, wakeNight)
        }
    }

    private func lockRow(_ label: String, _ e: DayWidgetEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let circle = CGSize(width: 64, height: 64)
        let rect = CGSize(width: 160, height: 66)
        let panel: Color = Color(uiColor: .secondarySystemBackground)
        return VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                accessory(DayLockView(entry: e, familyOverride: .accessoryRectangular), rect, round: false)
                accessory(DayLockView(entry: e, familyOverride: .accessoryCircular), circle, round: true)
            }
            DayLockView(entry: e, familyOverride: .accessoryInline)
                .font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .background(panel, in: shape)
        .environment(\.colorScheme, .dark)
    }

    private func lockWakeRow(_ watch: WakeEntry, _ night: WakeEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let circle = CGSize(width: 64, height: 64)
        let rect = CGSize(width: 160, height: 66)
        let panel: Color = Color(uiColor: .secondarySystemBackground)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                accessory(WakeWidgetView(entry: watch, familyOverride: .accessoryRectangular), rect, round: false)
                accessory(WakeWidgetView(entry: watch, familyOverride: .accessoryCircular), circle, round: true)
            }
            HStack(spacing: 10) {
                accessory(WakeWidgetView(entry: night, familyOverride: .accessoryRectangular), rect, round: false)
                WakeWidgetView(entry: night, familyOverride: .accessoryInline)
                    .font(.caption.weight(.semibold)).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .background(panel, in: shape)
        .environment(\.colorScheme, .dark)
    }
}
