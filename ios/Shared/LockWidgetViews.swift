import SwiftUI
import WidgetKit

// MARK: - ロック画面（時間帯で中身が切り替わる）
// ふだん：次の TODO と残りの数。見張り中：歩数と次の見張り。夜（19時〜翌4時）：明日のアラーム。
// ロック画面は単色で描かれるので、世界観は輪の形・文字の太さと形で出す（WorldWidget.swift）。

struct DayLockView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: DayWidgetEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var w: World { entry.palette.world }
    private var day: DayTodos { entry.day }
    private var watching: Bool { entry.watch.isWatching(entry.date) }
    private var night: Bool { WidgetDayPart.isNight(entry.date) }

    init(entry: DayWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .id(watching ? "watch" : (night ? "night" : "day"))
        .transition(w.widgetSwapTransition(entry.palette))
        .worldWidgetAnimation(entry.palette, value: entry.date)
        .widgetURL(watching || night ? WidgetLinks.wake : WidgetLinks.todo)
    }

    private func font(_ style: Font.TextStyle, _ weight: Font.Weight) -> Font {
        w == .none ? Font.system(style, weight: weight) : w.accessoryFont(style, weight)
    }

    /// 明日のアラームの一言（「明日 7:00 ✓ アラーム4回」）
    private var alarmText: String {
        guard let n = entry.wake.next else { return "明日のアラームなし" }
        return "\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first)) ✓ アラーム\(n.stages.count)回"
    }

    // MARK: 一行（時計の上）

    private var inline: some View {
        let text: String
        if watching {
            text = "見張り中・あと\(entry.watch.stepsLeft)歩"
        } else if night {
            if let n = entry.wake.next {
                text = "\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first)) ✓"
            } else {
                text = "明日のアラームなし"
            }
        } else if let n = day.next {
            text = "次：\(n.title) \(day.nextClock(n))"
        } else {
            text = day.today.isEmpty ? "今日のTODOはありません" : "のこり \(day.today.count)件"
        }
        return Text(text)
    }

    // MARK: 円

    private var circular: some View {
        let numberFont: Font = w == .none ? Font.system(size: 20, weight: .heavy) : w.accessoryNumberFont(19)
        let labelFont: Font = Font.system(size: 8, weight: w.accessoryWeight(.semibold), design: w.accessoryDesign ?? .default)
        let value: Int = watching ? entry.watch.stepCount : day.today.count
        let fraction: Double = watching ? entry.watch.fraction : day.fraction
        let label: String = watching ? "歩" : "のこり"
        return ZStack {
            AccessoryWorldBackground(world: w)
            LockRing(world: w, fraction: fraction)
                .padding(3)
            VStack(spacing: -1) {
                if watching {
                    Image(systemName: "figure.walk").font(.system(size: 9, weight: .bold))
                }
                Text("\(value)").font(numberFont).tracking(w.accessoryTracking)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .contentTransition(.numericText(value: Double(value)))
                Text(label).font(labelFont)
            }
            .padding(.horizontal, 8)
        }
        .widgetAccentable()
    }

    // MARK: 長方形

    private var rectangular: some View {
        let head: Font = font(.caption2, .semibold)
        let big: Font = font(.headline, .heavy)
        let line: Font = font(.caption, .semibold)
        return VStack(alignment: .leading, spacing: 1) {
            if watching {
                let wf: WakeWatchFeed = entry.watch
                Text("見張り中・あと\(wf.stepsLeft)歩で解除").font(head).lineLimit(1)
                    .contentTransition(.numericText(value: Double(wf.stepsLeft)))
                HStack(spacing: 6) {
                    Text("\(wf.stepCount)/\(wf.stepGoal)歩").font(big).monospacedDigit().lineLimit(1).fixedSize()
                        .contentTransition(.numericText(value: Double(wf.stepCount)))
                    LockBar(fraction: wf.fraction).frame(height: 5)
                }
                Text(wf.nextWatchAt.map { "次に鳴る \(JP.time($0))" } ?? "歩けば解除").font(line).lineLimit(1)
            } else if night {
                Text(alarmText).font(head).lineLimit(1).minimumScaleFactor(0.8)
                if let n = day.next, let due = n.due, Calendar.current.isDate(due, inSameDayAs: entry.date) {
                    Text("\(JP.time(due)) \(n.title)").font(big).lineLimit(1)
                } else if let t = day.tomorrow.first {
                    Text("明日 \(JP.clock(t, none: "")) \(t.title)").font(big).lineLimit(1)
                } else {
                    Text("おやすみなさい").font(big)
                }
                Text(reviewLine).font(line).lineLimit(1)
            } else {
                let n: TodoItem? = day.next ?? day.today.first
                Text(headLine).font(head).lineLimit(1)
                    .contentTransition(.numericText())
                Text(n?.title ?? "やることはありません").font(big).lineLimit(1)
                    .id(n?.id ?? "none")
                    .transition(w.widgetRowTransition(entry.palette))
                Text("のこり \(day.today.count)件" + (day.overdueCount > 0 ? "・期限切れ \(day.overdueCount)" : ""))
                    .font(line).lineLimit(1)
                    .contentTransition(.numericText(value: Double(day.today.count)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessoryWorldFrame(w)
    }

    /// ふだんの1行目（「次 14:00・あと 2時間」）
    private var headLine: String {
        guard let n = day.next, let due = n.due else {
            return day.today.first.map { "今日 \(day.shortClock($0))" } ?? "次のTODO"
        }
        return "次 \(day.nextClock(n))・\(WidgetFeedDay.untilText(due, from: entry.date))"
    }

    /// 夜の3行目（見返しの残り）
    private var reviewLine: String {
        let r: ReviewFeed = entry.review
        let left: Int = r.unreviewedCount ?? 0
        let nightDone: Bool = r.done(entry.date)[2]
        if nightDone { return "夜の見返し 済み・のこり \(day.today.count)件" }
        return left > 0 ? "夜の見返し 未確認 \(left)件" : "のこり \(day.today.count)件"
    }
}

/// ロック画面の円の輪
struct LockRing: View {
    let world: World
    let fraction: Double

    var body: some View {
        let width: CGFloat = 3.5
        let cap: CGLineCap = .round
        let shown: Double = max(0, min(1, fraction))
        ZStack {
            Circle().stroke(HierarchicalShapeStyle.tertiary, lineWidth: width)
            Circle().trim(from: 0, to: shown)
                .stroke(HierarchicalShapeStyle.primary, style: StrokeStyle(lineWidth: width, lineCap: cap))
                .rotationEffect(.degrees(-90))
                .opacity(shown > 0 ? 1 : 0)
        }
    }
}

/// ロック画面の横の棒（歩数）
struct LockBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(HierarchicalShapeStyle.tertiary)
                Capsule().fill(HierarchicalShapeStyle.primary).frame(width: g.size.width * max(0, min(1, fraction)))
            }
        }
    }
}
