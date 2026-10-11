import SwiftUI
import WidgetKit

// MARK: - 今日のまとめ（ウィジェット・大。案A「縦3段」）
// 上：次のアラーム（夜は「明日 7:00・アラーム4回 入っています ✓」、入っていなければ赤）か、見張り中の歩数。
// 真ん中：今日の TODO の上位3件（丸を押すと完了）。下：見返しの3つの丸と、今月の家計簿の支出。

struct SummaryWidgetView: View {
    let entry: DayWidgetEntry
    private var p: Palette { entry.palette }
    private var day: DayTodos { entry.day }

    init(entry: DayWidgetEntry) {
        self.entry = entry
    }

    /// 上位3件（今日の分が先。3件に満たなければ、ほかの期限の近いものを足す）
    private var top: [TodoItem] {
        let todayIDs: Set<String> = Set(day.today.map(\.id))
        let rest: [TodoItem] = day.open.filter { !todayIDs.contains($0.id) }
        return Array((day.today + rest).prefix(3))
    }

    var body: some View {
        let key: [String] = top.map(\.id) + ["\(day.today.count)", entry.watch.isWatching(entry.date) ? "w\(entry.watch.stepCount)" : "-"]
        VStack(alignment: .leading, spacing: 10) {
            wakeCard
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("今日の TODO").font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                Spacer(minLength: 0)
                Text("のこり").font(.footnote).foregroundStyle(p.sub)
                WidgetCount(p: p, text: "\(day.today.count)", value: Double(day.today.count), size: 20)
                Text("件").font(.footnote).foregroundStyle(p.sub)
            }
            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { pair in
                    todoRow(pair.element, last: pair.offset == top.count - 1)
                }
                if top.isEmpty {
                    Text("やることはありません").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                reviewTile
                kakeiboTile
            }
            .frame(height: 70)
        }
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: key)
    }

    // MARK: 上：起床

    private var wakeCard: some View {
        let watch: WakeWatchFeed = entry.watch
        let s: WakeSnapshot = entry.wake
        return Group {
            if watch.isWatching(entry.date) {
                HStack(spacing: 10) {
                    ZStack {
                        WidgetWorldRing(p: p, fraction: watch.fraction, lineWidth: 5)
                        Text("\(watch.stepCount)").font(.system(size: 11, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(p.text).contentTransition(.numericText(value: Double(watch.stepCount)))
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("見張り中").font(.caption.weight(.bold)).foregroundStyle(p.overdue)
                        Text("あと\(watch.stepsLeft)歩で解除").font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                            .contentTransition(.numericText(value: Double(watch.stepsLeft)))
                    }
                    Spacer(minLength: 0)
                    if let n = watch.nextWatchAt, n > entry.date {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("次の見張り").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                            Text(JP.time(n)).font(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(p.text)
                        }
                    }
                }
            } else if let n = s.next {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(WakeLogic.dayLabel(n.first, now: entry.date))の起床").font(.caption.weight(.bold)).foregroundStyle(p.accent)
                    WidgetCount(p: p, text: JP.time(n.first), size: 22)
                    Spacer(minLength: 0)
                    Text("アラーム\(n.stages.count)回 ✓").font(.caption.weight(.bold)).foregroundStyle(p.accent).lineLimit(1)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "alarm.waves.left.and.right").font(.subheadline.weight(.bold))
                    Text("明日のアラームが入っていません").font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(p.overdue)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .widgetCard(p, radius: 14)
        .transition(p.world.widgetSwapTransition(p))
    }

    // MARK: 真ん中：TODO

    private func todoRow(_ item: TodoItem, last: Bool) -> some View {
        let overdue: Bool = item.isOverdue(entry.date)
        let color: Color = overdue ? p.overdue : p.accent
        let clock: String = day.shortClock(item)
        return Button(intent: ToggleTodoIntent(id: item.id)) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: p.world.widgetCheckSymbol(done: false))
                        .font(.system(size: 18, weight: p.world.widgetCheckWeight)).foregroundStyle(color)
                        .contentTransition(p.world.widgetSymbolTransition)
                        .invalidatableContent()
                        .widgetAccentable()
                    Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                    Spacer(minLength: 0)
                    if !clock.isEmpty {
                        Text(clock).font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(overdue ? p.overdue : p.sub).lineLimit(1).fixedSize()
                    }
                }
                .padding(.vertical, 8)
                if !last { Rectangle().fill(p.sub.opacity(0.18)).frame(height: 0.5) }
            }
        }
        .buttonStyle(.plain)
        .transition(p.world.widgetRowTransition(p))
    }

    // MARK: 下：見返し・家計簿

    private var reviewTile: some View {
        let r: ReviewFeed = entry.review
        let next: String = r.next(after: entry.date).map { "次 \(JP.time($0))" } ?? ""
        return Link(destination: WidgetLinks.review) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("見返し").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    Spacer(minLength: 0)
                    Text(next).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(p.sub).lineLimit(1)
                }
                ReviewSlotsView(p: p, done: r.done(entry.date), size: 18, showLabels: false, spacing: 6)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCard(p, radius: 14)
        }
    }

    private var kakeiboTile: some View {
        let k: KakeiboFeed = entry.kakeibo
        let spent: Int = k.spentThisMonth(entry.date)
        let remaining: Int? = k.remainingThisMonth(entry.date)
        let used: Double? = k.usedFraction(entry.date)
        let over: Bool = (remaining ?? 0) < 0
        return Link(destination: WidgetLinks.kakeibo) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("今月の支出").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    if k.isSample { WidgetSampleBadge(color: p.sub) }
                    Spacer(minLength: 0)
                }
                WidgetCount(p: p, text: WidgetFeedDay.yenText(spent), value: Double(spent), size: 17)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let used, let remaining {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.sub.opacity(0.18))
                            Capsule().fill(over ? p.overdue : p.accent).frame(width: g.size.width * used)
                        }
                    }
                    .frame(height: 4)
                    Text(over ? "予算を \(WidgetFeedDay.yenText(-remaining)) 超え" : "残り \(WidgetFeedDay.yenText(remaining))")
                        .font(.caption2.weight(.semibold)).foregroundStyle(over ? p.overdue : p.sub).lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCard(p, radius: 14)
        }
    }
}
