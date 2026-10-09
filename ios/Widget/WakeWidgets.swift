import SwiftUI
import WidgetKit
import AppIntents

// 起床のウィジェット（エージェント1の担当）。
// チェックイン前：次のアラームと「起きた！」ボタン。チェックイン後：出発までのカウントダウンと次のルーティン。

struct WakeEntry: TimelineEntry {
    let date: Date
    let snap: WakeSnapshot
    let palette: Palette
}

struct WakeProvider: TimelineProvider {
    private func entry(at d: Date) -> WakeEntry {
        WakeEntry(date: d, snap: WakeSnapshot.make(now: d), palette: AppTheme.from(SettingsData.load().theme).palette)
    }

    func placeholder(in context: Context) -> WakeEntry { entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        // 時間帯が切り替わる時刻（起床の2時間前・各段階・正午・出発・18時）にも描き直す
        let now = Date()
        let snap = WakeSnapshot.make(now: now)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var times: [Date] = [now]
        if let n = snap.next {
            times.append(n.first.addingTimeInterval(-2 * 3600))
            times.append(contentsOf: n.stages.map(\.at))
        }
        if let dep = snap.departure { times.append(dep) }
        if let t = snap.today { times.append(t.last.addingTimeInterval(3600)) }   // 受付の終わり
        for h in [12, 18, 24] {
            if let d = cal.date(byAdding: .hour, value: h, to: today) { times.append(d) }
        }
        let limit = now.addingTimeInterval(24 * 3600)
        let sorted = Array(Set(times.filter { $0 >= now && $0 <= limit })).sorted()
        let entries: [WakeEntry] = sorted.prefix(20).map { entry(at: $0) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct WakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WakeWidget", provider: WakeProvider()) { entry in
            WakeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetPaletteBackground(p: entry.palette) }
        }
        .configurationDisplayName("起床")
        .description("次のアラームと「起きた！」ボタン。起きた後は出発までの時間と次のルーティン。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct WakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WakeEntry
    private var p: Palette { entry.palette }
    private var s: WakeSnapshot { entry.snap }
    private var checked: Bool { s.checkInAt != nil }
    private var departureAhead: Date? {
        guard checked, let d = s.departure, d > entry.date else { return nil }
        return d
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        // チェックインの前後で、下から押し上げるように切り替える
        .id(checked ? "after" : "before")
        .transition(.push(from: .bottom))
        .fontDesign(p.fontDesign)
    }

    // MARK: ホーム画面

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let dep = departureAhead {
                Text("出発まで").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                Text(dep, style: .timer).font(.system(size: 30, weight: .heavy, design: p.fontDesign))
                    .contentTransition(.numericText())
                    .monospacedDigit().foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                stepButton
            } else if checked {
                Text("今朝の起床").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                Text(s.checkInAt.map { JP.time($0) } ?? "").font(.system(size: 30, weight: .heavy, design: p.fontDesign))
                    .foregroundStyle(p.text)
                Text("\(s.score ?? 0)点").font(.headline).foregroundStyle(p.accent).contentTransition(.numericText())
                Spacer(minLength: 0)
                nextLine
            } else {
                nextAlarmBlock(size: 34)
                Spacer(minLength: 0)
                checkInButton
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if let dep = departureAhead {
                    Text("出発まで").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    Text(dep, style: .timer).font(.system(size: 36, weight: .heavy, design: p.fontDesign))
                        .contentTransition(.numericText())
                    .monospacedDigit().foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                    Text("出発 \(JP.time(dep))").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                } else if checked {
                    Text("今朝の起床").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    Text(s.checkInAt.map { JP.time($0) } ?? "").font(.system(size: 36, weight: .heavy, design: p.fontDesign))
                        .foregroundStyle(p.text)
                    Text("\(s.score ?? 0)点").font(.headline).foregroundStyle(p.accent).contentTransition(.numericText())
                } else {
                    nextAlarmBlock(size: 40)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if departureAhead != nil {
                    Text("次のルーティン").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    Text(s.nextStep?.name ?? "出発準備OK").font(.headline).foregroundStyle(p.text).lineLimit(2)
                    Spacer(minLength: 0)
                    stepButton
                } else if checked {
                    nextLine
                    Spacer(minLength: 0)
                } else {
                    stagesList
                    Spacer(minLength: 0)
                    checkInButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 起床中の一言（まだ鳴っていなければ「まもなく」）
    private var windowNote: String {
        if s.reached == 0 { return "1回目のアラームの前です" }
        if s.nextStage == nil { return "最後のアラームが鳴りました" }
        return "\(s.reached)回目まで鳴りました"
    }

    private func nextAlarmBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(s.phase == .window ? "起床中" : "次のアラーム",
                  systemImage: s.phase == .window ? "alarm.waves.left.and.right.fill" : "alarm.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(Font.caption.weight(.bold)).foregroundStyle(p.sub)
            if s.phase == .window, let t = s.nextStage?.at ?? s.today?.last {
                // 起床中は今日の次のアラーム（全部鳴った後は最後の時刻）
                Text(JP.time(t))
                    .font(Font.system(size: size, weight: .heavy, design: p.fontDesign))
                    .contentTransition(.numericText())
                    .monospacedDigit().foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                Text(windowNote).font(Font.caption.weight(.semibold)).foregroundStyle(p.accent).lineLimit(1)
            } else if let n = s.next {
                Text(JP.time(n.first))
                    .font(Font.system(size: size, weight: .heavy, design: p.fontDesign))
                    .contentTransition(.numericText())
                    .monospacedDigit().foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.6)
                let note: String = "\(WakeLogic.dayLabel(n.first, now: entry.date))・アラーム\(n.stages.count)回"
                Text(note).font(Font.caption.weight(.semibold)).foregroundStyle(p.accent).lineLimit(1)
            } else {
                Text("アラームなし").font(.title2.weight(.heavy)).foregroundStyle(p.text)
            }
        }
    }

    private var stagesList: some View {
        let stages: [WakePlan.Stage] = (s.phase == .window ? s.today : s.next)?.stages ?? []
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(stages, id: \.number) { st in
                HStack(spacing: 6) {
                    Image(systemName: st.at <= entry.date ? "bell.fill" : "bell")
                        .font(.caption2).foregroundStyle(p.accent)
                    Text("\(st.number)回目").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                    Spacer(minLength: 0)
                    Text(JP.time(st.at)).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(p.text)
                }
            }
        }
    }

    private var nextLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("次の起床").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
            Text(s.next.map { "\(WakeLogic.dayLabel($0.first, now: entry.date)) \(JP.time($0.first))" } ?? "アラームなし")
                .font(.caption.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
        }
    }

    /// 受付時間（最初のアラームの2時間前から）だけ「起きた！」を出す。それ以外は押せる時刻を出す（誤タップ防止）
    @ViewBuilder private var checkInButton: some View {
        if s.canCheckIn {
            Button(intent: WakeCheckInIntent()) {
                Label("起きた！", systemImage: "sun.max.fill").font(.subheadline.weight(.heavy))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(p.accent, in: RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous))
                    .foregroundStyle(p.onAccent)
                    .invalidatableContent()   // 押した直後、反映されるまで薄く表示
            }
            .buttonStyle(.plain)
        } else if let from = s.checkInFrom {
            let label: String = "\(WakeLogic.dayLabel(from, now: entry.date)) \(JP.time(from))から押せます"
            Text(label).font(Font.caption2.weight(.semibold)).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private var stepButton: some View {
        if let step = s.nextStep {
            Button(intent: WakeRoutineStepIntent(id: step.id)) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(step.name).lineLimit(1)
                }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(p.accent, in: RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous))
                .foregroundStyle(p.onAccent)
            }
            .buttonStyle(.plain)
        } else {
            Label("出発準備OK", systemImage: "checkmark.seal.fill").font(.caption.weight(.bold)).foregroundStyle(p.accent)
        }
    }

    // MARK: ロック画面（単色）

    @ViewBuilder private var inline: some View {
        if let dep = departureAhead {
            Text("出発まで \(dep, style: .timer)")
        } else if s.phase == .window {
            Text("起きたらチェックイン")
        } else if let n = s.next {
            Text("\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first)) 起床")
        } else {
            Text("起床アラームなし")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let dep = departureAhead {
                VStack(spacing: 0) {
                    Text("出発").font(.system(size: 9, weight: .semibold))
                    Text(dep, style: .timer).font(.system(size: 12, weight: .heavy)).monospacedDigit()
                        .multilineTextAlignment(.center).minimumScaleFactor(0.5)
                }
                .padding(4)
            } else if !checked && s.phase == .window {
                Button(intent: WakeCheckInIntent()) {
                    VStack(spacing: 0) {
                        Image(systemName: "sun.max.fill").font(.title3)
                        Text("起きた").font(.system(size: 10, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
            } else if let n = s.next {
                VStack(spacing: 0) {
                    Image(systemName: "alarm.fill").font(.caption)
                    Text(JP.time(n.first)).font(.system(size: 14, weight: .heavy)).monospacedDigit().minimumScaleFactor(0.6)
                }
            } else {
                Image(systemName: "alarm")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let dep = departureAhead {
                Text("出発 \(JP.time(dep)) まで").font(.caption2.weight(.semibold))
                Text(dep, style: .timer).font(.title3.weight(.heavy)).monospacedDigit()
                Text(s.nextStep.map { "次：\($0.name)" } ?? "出発準備OK").font(.caption.weight(.semibold)).lineLimit(1)
            } else if !checked && s.phase == .window {
                Button(intent: WakeCheckInIntent()) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(windowNote).font(Font.caption2.weight(.semibold))
                        Label("起きた！", systemImage: "sun.max.fill").font(.headline.weight(.heavy))
                        Text(s.nextStage.map { "次は \(JP.time($0.at))" } ?? "最後のアラーム").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            } else if let n = s.next {
                Text("次の起床・アラーム\(n.stages.count)回").font(.caption2.weight(.semibold))
                Text("\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first))").font(.title3.weight(.heavy))
                if let bed = s.bedtime, bed > entry.date {
                    Text("就寝 \(JP.time(bed))").font(.caption2)
                }
            } else {
                Text("起床").font(.caption2.weight(.semibold))
                Text("アラームなし").font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
