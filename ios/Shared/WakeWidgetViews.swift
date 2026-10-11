import SwiftUI
import WidgetKit
import AppIntents

// 起床のウィジェットの見た目（アプリのウィジェット見本からも使うので Shared に置く。タイムラインは Widget/WakeWidgets.swift）。
// チェックイン前：次のアラームと「起きた！」ボタン。チェックイン後：出発までのカウントダウンと次のルーティン。
// 世界観を選んでいれば、背景・時刻の数字・ボタン・切り替わりの動きを世界観に合わせる（部品は WorldWidget.swift）。

struct WakeEntry: TimelineEntry {
    let date: Date
    let snap: WakeSnapshot
    let palette: Palette
}

struct WakeWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: WakeEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { entry.palette }
    private var s: WakeSnapshot { entry.snap }
    private var checked: Bool { s.checkInAt != nil }
    private var departureAhead: Date? {
        guard checked, let d = s.departure, d > entry.date else { return nil }
        return d
    }

    /// familyOverride はアプリ内の見本画面用（環境の widgetFamily は書き換えられないため）
    init(entry: WakeEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
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
        // チェックインの前後で切り替える（「なし」は下から押し上げる。世界観ごとの動きは World.widgetSwapTransition）
        .id(checked ? "after" : "before")
        .transition(p.world.widgetSwapTransition(p))
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: entry.date)
    }

    // MARK: ホーム画面

    /// 大きな時刻の字（世界観の大きな数字に合わせる）
    private func bigTime(_ text: Text, size: CGFloat) -> some View {
        text
            .font(p.widgetNumberFont(size))
            .tracking(p.widgetNumberTracking(size))
            .contentTransition(.numericText())
            .monospacedDigit().foregroundStyle(p.widgetNumberColor).lineLimit(1).minimumScaleFactor(0.6)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let dep = departureAhead {
                Text("出発まで").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                bigTime(Text(dep, style: .timer), size: 30)
                Spacer(minLength: 0)
                stepButton
            } else if checked {
                Text("今朝の起床").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                bigTime(Text(s.checkInAt.map { JP.time($0) } ?? ""), size: 30)
                Text("\(s.score ?? 0)点").font(.headline).foregroundStyle(p.accent)
                    .contentTransition(.numericText(value: Double(s.score ?? 0)))
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
                    bigTime(Text(dep, style: .timer), size: 36)
                    Text("出発 \(JP.time(dep))").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                } else if checked {
                    Text("今朝の起床").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    bigTime(Text(s.checkInAt.map { JP.time($0) } ?? ""), size: 36)
                    Text("\(s.score ?? 0)点").font(.headline).foregroundStyle(p.accent)
                        .contentTransition(.numericText(value: Double(s.score ?? 0)))
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
                        .id(s.nextStep?.id ?? "done")
                        .transition(p.world.widgetRowTransition(p))
                    Spacer(minLength: 0)
                    stepButton
                } else if checked {
                    nextLine
                    Spacer(minLength: 0)
                } else {
                    stagesCard
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
                .contentTransition(p.world.widgetSymbolTransition)
                .font(Font.caption.weight(.bold)).foregroundStyle(p.sub)
            if s.phase == .window, let t = s.nextStage?.at ?? s.today?.last {
                // 起床中は今日の次のアラーム（全部鳴った後は最後の時刻）
                bigTime(Text(JP.time(t)), size: size)
                Text(windowNote).font(Font.caption.weight(.semibold)).foregroundStyle(p.accent).lineLimit(1)
            } else if let n = s.next {
                bigTime(Text(JP.time(n.first)), size: size)
                let note: String = "\(WakeLogic.dayLabel(n.first, now: entry.date))・アラーム\(n.stages.count)回"
                Text(note).font(Font.caption.weight(.semibold)).foregroundStyle(p.accent).lineLimit(1)
            } else {
                Text("アラームなし").font(.title2.weight(.heavy)).foregroundStyle(p.text)
            }
        }
    }

    /// アラームの段階の一覧（世界観を選んでいればカードに載せる）
    @ViewBuilder private var stagesCard: some View {
        if p.world.isOn {
            stagesList.padding(.horizontal, 8).padding(.vertical, 6).widgetCard(p, radius: 12)
        } else {
            stagesList
        }
    }

    private var stagesList: some View {
        let stages: [WakePlan.Stage] = (s.phase == .window ? s.today : s.next)?.stages ?? []
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(stages, id: \.number) { st in
                HStack(spacing: 6) {
                    Image(systemName: st.at <= entry.date ? "bell.fill" : "bell")
                        .font(.caption2).foregroundStyle(p.accent)
                        .contentTransition(p.world.widgetSymbolTransition)
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
                .contentTransition(.numericText())
        }
    }

    /// 受付時間（最初のアラームの2時間前から）だけ「起きた！」を出す。それ以外は押せる時刻を出す（誤タップ防止）
    @ViewBuilder private var checkInButton: some View {
        if s.canCheckIn {
            Button(intent: WakeCheckInIntent()) {
                Label("起きた！", systemImage: "sun.max.fill").font(.subheadline.weight(.heavy))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .widgetButton(p, radius: 12)
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
                        .contentTransition(p.world.widgetSymbolTransition)
                    Text(step.name).lineLimit(1)
                }
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .widgetButton(p, radius: 12)
                .foregroundStyle(p.onAccent)
                .invalidatableContent()
            }
            .buttonStyle(.plain)
            .id(step.id)
            .transition(p.world.widgetRowTransition(p))
        } else {
            Label("出発準備OK", systemImage: "checkmark.seal.fill").font(.caption.weight(.bold)).foregroundStyle(p.accent)
        }
    }

    // MARK: ロック画面（単色。世界観は文字の太さ・形と輪の形で出す）

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
        let w: World = p.world
        let timeFont: Font = w == .none ? Font.system(size: 14, weight: .heavy) : w.accessoryNumberFont(14)
        let timerFont: Font = w == .none ? Font.system(size: 12, weight: .heavy) : w.accessoryNumberFont(12)
        let labelFont: Font = Font.system(size: 9, weight: w.accessoryWeight(.semibold), design: w.accessoryDesign ?? .default)
        return ZStack {
            AccessoryWorldBackground(world: w)
            if let dep = departureAhead {
                VStack(spacing: 0) {
                    Text("出発").font(labelFont)
                    Text(dep, style: .timer).font(timerFont).monospacedDigit()
                        .multilineTextAlignment(.center).minimumScaleFactor(0.5)
                }
                .padding(4)
            } else if !checked && s.phase == .window {
                Button(intent: WakeCheckInIntent()) {
                    VStack(spacing: 0) {
                        Image(systemName: "sun.max.fill").font(.title3)
                        Text("起きた").font(Font.system(size: 10, weight: w.accessoryWeight(.bold), design: w.accessoryDesign ?? .default))
                    }
                    .invalidatableContent()
                }
                .buttonStyle(.plain)
            } else if let n = s.next {
                VStack(spacing: 0) {
                    Image(systemName: "alarm.fill").font(.caption)
                    Text(JP.time(n.first)).font(timeFont).tracking(w.accessoryTracking).monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
            } else {
                Image(systemName: "alarm")
            }
        }
    }

    private var rectangular: some View {
        let w: World = p.world
        let head: Font = w == .none ? Font.caption2.weight(.semibold) : w.accessoryFont(.caption2, .semibold)
        let big: Font = w == .none ? Font.title3.weight(.heavy) : w.accessoryFont(.title3, .heavy)
        let line: Font = w == .none ? Font.caption.weight(.semibold) : w.accessoryFont(.caption, .semibold)
        let small: Font = w == .none ? Font.caption2 : w.accessoryFont(.caption2, .regular)
        return VStack(alignment: .leading, spacing: 1) {
            if let dep = departureAhead {
                Text("出発 \(JP.time(dep)) まで").font(head)
                Text(dep, style: .timer).font(big).monospacedDigit().tracking(w.accessoryTracking)
                Text(s.nextStep.map { "次：\($0.name)" } ?? "出発準備OK").font(line).lineLimit(1)
            } else if !checked && s.phase == .window {
                Button(intent: WakeCheckInIntent()) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(windowNote).font(head)
                        Label("起きた！", systemImage: "sun.max.fill").font(w == .none ? Font.headline.weight(.heavy) : w.accessoryFont(.headline, .heavy))
                        Text(s.nextStage.map { "次は \(JP.time($0.at))" } ?? "最後のアラーム").font(small)
                    }
                    .invalidatableContent()
                }
                .buttonStyle(.plain)
            } else if let n = s.next {
                Text("次の起床・アラーム\(n.stages.count)回").font(head)
                Text("\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first))").font(big)
                    .tracking(w.accessoryTracking)
                    .contentTransition(.numericText())
                if let bed = s.bedtime, bed > entry.date {
                    Text("就寝 \(JP.time(bed))").font(small)
                }
            } else {
                Text("起床").font(head)
                Text("アラームなし").font(w == .none ? Font.headline : w.accessoryFont(.headline, .regular))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessoryWorldFrame(w)
    }
}
