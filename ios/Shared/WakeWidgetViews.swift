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
    /// 見張りの状態（アラームを止めたあと、歩いて解除するまで。WidgetFeeds.swift）
    var watch: WakeWatchFeed = .none
    /// 明日の TODO の数（夜の中サイズに出す）
    var tomorrowTodos: Int = 0
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

    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    private let standbyOverride: Bool?
    /// スタンバイ（充電中に横向き。背景が消える）か
    private var standby: Bool { standbyOverride ?? !showsBackground }
    /// 見張り中（アラームを止めたあと、歩いて解除するまで）
    private var watching: Bool { entry.watch.isWatching(entry.date) }
    /// 夜（寝る前）：19時〜翌4時で、起床中・出発前でないとき
    private var night: Bool {
        !watching && s.phase != .window && departureAhead == nil && WidgetDayPart.isNight(entry.date)
    }

    /// familyOverride・standbyOverride はアプリ内の見本画面用（環境の値は書き換えられないため）
    init(entry: WakeEntry, familyOverride: WidgetFamily? = nil, standbyOverride: Bool? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
        self.standbyOverride = standbyOverride
    }

    /// 切り替わりの目印（見張り・夜・チェックインの前後）
    private var stateKey: String {
        if watching { return "watch" }
        if night { return s.next == nil ? "night-none" : "night" }
        return checked ? "after" : "before"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium:
                if watching { watchMedium } else if night { nightMedium } else { medium }
            default:
                if watching { watchSmall } else if night { if standby { standbyNight } else { nightSmall } } else { small }
            }
        }
        // 状態が変わったら切り替える（「なし」は下から押し上げる。世界観ごとの動きは World.widgetSwapTransition）
        .id(stateKey)
        .transition(p.world.widgetSwapTransition(p))
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: entry.date)
    }

    // MARK: 夜（寝る前）：アラームが入っているかを大きく

    /// 「明日 7:00・アラーム4回 入っています ✓」
    private func alarmSetLine(_ n: WakePlan) -> String {
        "\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first))・アラーム\(n.stages.count)回 入っています ✓"
    }

    /// 「いま寝ると 7:29:59」（起きる時刻までのタイマー。描き直しを待たずに秒まで進む）
    /// compact（小サイズ）は1行に収まるよう「明日はお休み」だけにする（次の起床の時刻は上に大きく出ている）
    private func sleepLine(_ n: WakePlan, compact: Bool = false) -> Text {
        // 次の朝がお休み（起床の曜日でない・祝日など）なら「いま寝ると」を出さない（アプリの就寝カードと同じ判定）
        if let off = WakeLogic.morningOffLine(next: n, now: entry.date) {
            return Text(compact ? "明日はお休み" : off)
        }
        return Text("いま寝ると \(n.first, style: .timer)")
    }

    @ViewBuilder private var nightSmall: some View {
        if let n = s.next {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(WakeLogic.dayLabel(n.first, now: entry.date))の起床").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                Spacer(minLength: 0)
                bigTime(Text(JP.time(n.first)), size: 40)
                Text("アラーム\(n.stages.count)回 入っています ✓").font(.caption.weight(.bold)).foregroundStyle(p.accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                sleepLine(n, compact: true).font(.caption2.weight(.semibold)).foregroundStyle(p.sub).lineLimit(1)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            noAlarm(compact: true)
        }
    }

    @ViewBuilder private var nightMedium: some View {
        if let n = s.next {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(WakeLogic.dayLabel(n.first, now: entry.date))の起床").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    Spacer(minLength: 0)
                    bigTime(Text(JP.time(n.first)), size: 46)
                    Spacer(minLength: 0)
                    Text(alarmSetLine(n)).font(.caption.weight(.bold)).foregroundStyle(p.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                Rectangle().fill(p.sub.opacity(0.25)).frame(width: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("就寝の目安").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    WidgetCount(p: p, text: s.bedtime.map { JP.time($0) } ?? "--:--", size: 20, color: p.text)
                    Spacer(minLength: 0)
                    sleepLine(n).font(.caption2.weight(.semibold)).foregroundStyle(p.sub).lineLimit(2)
                        .contentTransition(.numericText())
                    Text("明日の TODO \(entry.tomorrowTodos)件").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
                        .lineLimit(1)
                }
                .frame(width: 104, alignment: .leading)
            }
        } else {
            noAlarm(compact: false)
        }
    }

    /// アラームが入っていない夜：赤い枠で知らせ、押すと起床の画面へ
    private func noAlarm(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("明日の起床").font(.caption.weight(.bold)).foregroundStyle(p.overdue)
            Spacer(minLength: 0)
            Text(compact ? "アラームが\n入っていません" : "アラームが入っていません")
                .font(.system(size: compact ? 19 : 22, weight: .heavy, design: p.fontDesign))
                .foregroundStyle(p.text).lineLimit(2).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Link(destination: WidgetLinks.wake) {
                Text("いま設定する").font(.caption.weight(.heavy))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(Color.white)
                    .background(Capsule().fill(p.overdue))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ContainerRelativeShape().strokeBorder(p.overdue, lineWidth: 2.5).padding(-12)
        }
        .widgetURL(WidgetLinks.wake)
    }

    /// スタンバイの枕元の時計：黒地に暗い赤で、目にやさしく
    private var standbyNight: some View {
        let red: Color = Color(red: 0xC8 / 255, green: 0x47 / 255, blue: 0x3F / 255)
        return VStack(alignment: .leading, spacing: 4) {
            if let n = s.next {
                Text("\(WakeLogic.dayLabel(n.first, now: entry.date))の起床").font(.system(size: 13, weight: .bold))
                Text(JP.time(n.first)).font(.system(size: 52, weight: .heavy, design: p.fontDesign)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("✓ アラーム\(n.stages.count)回").font(.system(size: 13, weight: .bold))
                sleepLine(n).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            } else {
                Text("明日の起床").font(.system(size: 13, weight: .bold))
                Text("アラームが\n入っていません").font(.system(size: 22, weight: .heavy)).lineLimit(2)
            }
        }
        .foregroundStyle(red)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    // MARK: 見張り中：あと何歩で解除か（リング）

    private func stepRing(size: CGFloat, line: CGFloat) -> some View {
        let wf: WakeWatchFeed = entry.watch
        return ZStack {
            WidgetWorldRing(p: p, fraction: wf.fraction, lineWidth: line)
            VStack(spacing: 0) {
                WidgetCount(p: p, text: "\(wf.stepCount)", value: Double(wf.stepCount), size: size * 0.27, color: p.text)
                Text("/ \(wf.stepGoal)歩").font(.system(size: max(9, size * 0.1), weight: .semibold)).foregroundStyle(p.sub)
            }
        }
        .frame(width: size, height: size)
    }

    private var watchSmall: some View {
        let wf: WakeWatchFeed = entry.watch
        let foot: String = wf.nextWatchAt.map { "次の見張り \(JP.time($0))" } ?? "あと\(wf.stepsLeft)歩で解除"
        return VStack(spacing: 4) {
            HStack {
                Label("見張り中", systemImage: "figure.walk").font(.caption.weight(.bold)).foregroundStyle(p.overdue)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            stepRing(size: 84, line: 9)
            Spacer(minLength: 0)
            Text(foot).font(.caption2.weight(.bold)).foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.8)
        }
        .widgetURL(WidgetLinks.wake)
    }

    private var watchTimes: String {
        let wf: WakeWatchFeed = entry.watch
        var parts: [String] = []
        if let n = wf.nextWatchAt { parts.append("次の見張り \(JP.time(n))") }
        if let last = wf.lastWatchAt { parts.append("最後 \(JP.time(last))") }
        return parts.joined(separator: " ／ ")
    }

    private var watchMedium: some View {
        let wf: WakeWatchFeed = entry.watch
        let stopped: String = wf.stoppedAt.map { "見張り中・\(JP.time($0)) に止めました" } ?? "見張り中"
        let times: String = watchTimes
        return HStack(spacing: 16) {
            stepRing(size: 108, line: 11)
            VStack(alignment: .leading, spacing: 6) {
                Text(stopped).font(.caption.weight(.bold)).foregroundStyle(p.overdue).lineLimit(1).minimumScaleFactor(0.8)
                Text("あと\(wf.stepsLeft)歩で解除").font(.system(size: 20, weight: .heavy, design: p.fontDesign))
                    .foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: Double(wf.stepsLeft)))
                if !times.isEmpty {
                    Text(times).font(.caption).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text("歩かないと、また鳴ります").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .widgetURL(WidgetLinks.wake)
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
                Text(s.session.map { WakeLogic.stageText($0) } ?? "").font(.headline).foregroundStyle(p.accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
                    Text(s.session.map { WakeLogic.resultText($0) } ?? "").font(.headline).foregroundStyle(p.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
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
        if watching {
            Text("見張り中・あと\(entry.watch.stepsLeft)歩")
        } else if night, let n = s.next {
            Text("\(WakeLogic.dayLabel(n.first, now: entry.date)) \(JP.time(n.first)) ✓ アラーム\(n.stages.count)回")
        } else if night {
            Text("明日のアラームなし")
        } else if let dep = departureAhead {
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
            if watching {
                LockRing(world: w, fraction: entry.watch.fraction).padding(3)
                VStack(spacing: -1) {
                    Image(systemName: "figure.walk").font(.system(size: 9, weight: .bold))
                    Text("\(entry.watch.stepCount)").font(timeFont).monospacedDigit().minimumScaleFactor(0.6)
                        .contentTransition(.numericText(value: Double(entry.watch.stepCount)))
                    Text("歩").font(labelFont)
                }
            } else if let dep = departureAhead {
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
            if watching {
                let wf: WakeWatchFeed = entry.watch
                Text("見張り中・あと\(wf.stepsLeft)歩で解除").font(head).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(wf.stepCount)/\(wf.stepGoal)歩").font(big).monospacedDigit().lineLimit(1).fixedSize()
                        .contentTransition(.numericText(value: Double(wf.stepCount)))
                    LockBar(fraction: wf.fraction).frame(height: 5)
                }
                Text(wf.nextWatchAt.map { "次に鳴る \(JP.time($0))" } ?? "歩けば解除").font(small)
            } else if night, let n = s.next {
                Text("\(WakeLogic.dayLabel(n.first, now: entry.date))の起床・アラーム\(n.stages.count)回 ✓").font(head).lineLimit(1)
                Text(JP.time(n.first)).font(big).tracking(w.accessoryTracking)
                    .contentTransition(.numericText())
                sleepLine(n, compact: true).font(small).lineLimit(1)
            } else if night {
                Text("明日の起床").font(head)
                Text("アラームが入っていません").font(w == .none ? Font.headline : w.accessoryFont(.headline, .heavy))
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if let dep = departureAhead {
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
