import SwiftUI
import WidgetKit

// MARK: - リリース4のウィジェットが共通で使うデータ（TODO・起床・見返し・見張り・家計簿）
// 時刻 now を外から渡せるようにしておく（タイムラインの先の時刻・アプリの見本の -widgettime）。

struct DayWidgetEntry: TimelineEntry {
    let date: Date
    let todos: [TodoItem]
    let palette: Palette
    let review: ReviewFeed
    let watch: WakeWatchFeed
    let kakeibo: KakeiboFeed
    let wake: WakeSnapshot
    var groupOK: Bool = true

    /// アプリと共有したファイルから読む（ウィジェットのタイムライン用）
    static func load(at date: Date, todos: [TodoItem]? = nil) -> DayWidgetEntry {
        DayWidgetEntry(date: date, todos: todos ?? TodoData.all(), palette: AppTheme.current(),
                       review: .load(now: date), watch: .load(), kakeibo: .load(now: date),
                       wake: WakeSnapshot.make(now: date), groupOK: SharedStore.isGroupAvailable)
    }

    var day: DayTodos { DayTodos(todos, now: date) }
}

/// ある時刻から見た今日の TODO
struct DayTodos {
    let now: Date
    /// 未完了のすべて（並びはアプリと同じ）
    let open: [TodoItem]
    /// 期限切れと今日の期限のもの（未完了）
    let today: [TodoItem]
    /// 今日完了したもの
    let doneToday: [TodoItem]
    /// 期限なしの未完了
    let noDue: [TodoItem]
    /// 明日の期限の未完了
    let tomorrow: [TodoItem]
    /// 時刻つきで、まだ来ていない一番近いもの
    let next: TodoItem?

    init(_ all: [TodoItem], now: Date) {
        let cal = Calendar.current
        self.now = now
        let open: [TodoItem] = TodoData.sorted(all.filter { !$0.done })
        self.open = open
        self.today = open.filter { item in
            guard let due = item.due else { return false }
            return item.isOverdue(now) || cal.isDate(due, inSameDayAs: now)
        }
        self.doneToday = all.filter { item in
            item.done && (item.doneAt.map { cal.isDate($0, inSameDayAs: now) } ?? false)
        }
        self.noDue = open.filter { $0.due == nil }
        let tomorrowDay: Date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        self.tomorrow = open.filter { item in item.due.map { cal.isDate($0, inSameDayAs: tomorrowDay) } ?? false }
        let timed: [TodoItem] = open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > now }
        self.next = timed.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    var overdueCount: Int { today.filter { $0.isOverdue(now) }.count }

    /// 今日の分の進み具合（済み ÷ 済み＋のこり）
    var fraction: Double {
        let total: Int = doneToday.count + today.count
        return total == 0 ? 1 : Double(doneToday.count) / Double(total)
    }

    /// 「次 14:00 歯医者」用の時刻（今日でなければ「明日 8:00」など）
    func nextClock(_ t: TodoItem) -> String {
        guard let due = t.due else { return "" }
        let cal = Calendar.current
        if cal.isDate(due, inSameDayAs: now) { return JP.time(due) }
        if cal.isDateInTomorrow(due) || cal.isDate(due, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now) ?? now) {
            return "明日 \(JP.time(due))"
        }
        return "\(cal.component(.month, from: due))/\(cal.component(.day, from: due)) \(JP.time(due))"
    }

    /// 一覧の左の短い時刻（期限切れは「昨日」「10/9」、今日は時刻、終日は「終日」）
    func shortClock(_ t: TodoItem) -> String {
        guard let due = t.due else { return "" }
        let cal = Calendar.current
        if cal.isDate(due, inSameDayAs: now) { return t.isAllDay ? "終日" : JP.time(due) }
        let days: Int = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        if days == -1 { return "昨日" }
        if days == 1 { return "明日" }
        return "\(cal.component(.month, from: due))/\(cal.component(.day, from: due))"
    }
}

/// 夜（寝る前）か：19時から翌4時まで。起床ウィジェット・ロック画面の切り替えに使う
enum WidgetDayPart {
    static func isNight(_ d: Date) -> Bool {
        let h: Int = Calendar.current.component(.hour, from: d)
        return h >= 19 || h < 4
    }
}

/// ウィジェットの「見本」の小さな札（共有ファイルが無く、見本のデータを出しているとき）
struct WidgetSampleBadge: View {
    let color: Color

    var body: some View {
        Text("見本").font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 0.8))
    }
}

/// アプリの画面を開くリンク（アプリがまだ受けていなくても、アプリが開く）
enum WidgetLinks {
    static let review = URL(string: "hiyori://review")!
    static let wake = URL(string: "hiyori://wake")!
    static let todo = URL(string: "hiyori://todo")!
    static let kakeibo = URL(string: "hiyori://kakeibo")!
}
