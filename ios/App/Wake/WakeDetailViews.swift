import SwiftUI

// 起床タブのホームは大事なことだけにし、細かいもの（段階・明日だけオフ・天気・ルーティン・TODO）は
// 小さな行から開くシートに置く

/// 行から開くシートの種類
enum WakeSheet: String, Identifiable {
    case alarm      // アラームの段階・ボタンの違い・明日だけオフ
    case prep       // 出発まで・朝のルーティン・持ち物
    case weather    // 今日の天気
    case todo       // 今日のTODO
    var id: String { rawValue }

    /// 起動引数 -wakeShot alarm|prep|weather|todo で、そのシートを開いた状態にする（画面写真用）
    static var launch: WakeSheet? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-wakeShot"), i + 1 < args.count else { return nil }
        return WakeSheet(rawValue: args[i + 1])
    }
}

/// 行の中身：アイコン・見出し・ひとこと・右の矢印（高さは44pt以上）
struct WakeRowLabel: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    var detail: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(Font.body.weight(.semibold)).foregroundStyle(tint ?? p.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Font.body.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(Font.caption).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(Font.footnote.weight(.bold)).foregroundStyle(p.sub)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// 行をまとめる1枚のカード。行のあいだには WakeRowDivider を置く
struct WakeRowGroup<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 6)
            .paletteCard(p, padding: 8)
    }
}

/// 行のあいだの細い線（アイコンの右から）
struct WakeRowDivider: View {
    var body: some View { Divider().padding(.leading, 40) }
}

/// シートの入れ物：見出し・閉じるボタン・世界観の背景
struct WakeSheetFrame<Content: View>: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    let title: String
    /// 長い中身（段階・ルーティン）は最初から大きく開く
    var tall: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .paletteBackground(p)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.foregroundStyle(p.accent)
                }
            }
        }
        .presentationDetents(tall ? Set<PresentationDetent>([.large]) : Set<PresentationDetent>([.medium, .large]))
        .presentationDragIndicator(.visible)
    }
}

/// シートの中身（起床前・起床中・朝・夜で共通）
struct WakeSheetContent: View {
    @ObservedObject var model: WakeViewModel
    @ObservedObject var weather: WakeWeatherModel
    let sheet: WakeSheet

    var body: some View {
        switch sheet {
        case .alarm:
            WakeSheetFrame(title: "アラームの詳細") {
                let reached: Int = model.phase == .window ? (model.todayPlan.map { WakeLogic.reached($0, at: model.now) } ?? 0) : 0
                let plan: WakePlan? = model.phase == .window ? model.todayPlan : model.nextPlan
                if let plan { WakeStageTimeline(plan: plan, reached: reached) }
                if model.phase != .window && model.nextPlanAny != nil { WakeSkipCard(model: model) }
                if plan == nil && model.nextPlanAny == nil {
                    WakeMessage(text: "次の起床日がありません。「アラームの設定」で起きる曜日を決めてください")
                }
            }
        case .prep:
            WakeSheetFrame(title: "出発の準備") {
                if let dep = model.departure, dep > model.now { WakeCountdownCard(model: model, departure: dep) }
                if !model.settings.routine.isEmpty { WakeRoutineCard(model: model) }
                if !model.settings.belongings.isEmpty { WakeBelongingsCard(model: model) }
            }
        case .weather:
            WakeSheetFrame(title: "今日の天気", tall: false) {
                WakeWeatherCard(weather: weather)
            }
        case .todo:
            WakeSheetFrame(title: "今日のTODO", tall: false) {
                WakeTodoCard(now: model.now)
            }
        }
    }
}

// MARK: - 行のひとこと

extension WakeViewModel {
    /// 「アラームの詳細」の行：段階の数と時刻、明日だけオフの状態
    var alarmRowDetail: String {
        if phase == .window, let t = todayPlan {
            return "\(t.stages.count)回・\(JP.time(t.first))〜\(JP.time(t.last))"
        }
        if isNextSkipped, let any = nextPlanAny {
            return "\(JP.date(any.dayStart)) はオフにしています"
        }
        guard let plan = nextPlan else { return "明日だけオフ・ボタンの違い" }
        return "\(plan.stages.count)回・\(JP.time(plan.first))〜\(JP.time(plan.last))・明日だけオフ"
    }

    /// 「起床の記録」の行：7日の平均と連続
    var recordsRowDetail: String {
        let avg: String = WakeLogic.averageWakeMinutes(sessions, days: 7, now: now).map { "7日の平均 \(WakeLogic.clock($0))" } ?? "まだ記録がありません"
        let streak: Int = WakeLogic.streak(sessions)
        return streak > 1 ? "\(avg)・\(streak)日連続" : avg
    }

    /// 「出発の準備」の行：出発の時刻と、ルーティンの進み具合
    var prepRowDetail: String {
        var parts: [String] = []
        if let dep = departure, dep > now {
            parts.append("出発 \(JP.time(dep))・あと \(WakeLogic.duration(dep.timeIntervalSince(now)))")
        }
        let total: Int = settings.routine.count
        if total > 0 { parts.append("ルーティン \(total - remainingRoutine.count)/\(total)") }
        if !settings.belongings.isEmpty {
            parts.append("持ち物 \(state.belongingsDone.count)/\(settings.belongings.count)")
        }
        return parts.joined(separator: "・")
    }

    /// 出発の準備の行を出すか（出発前のとき）
    var showsPrepRow: Bool { departure.map { $0 > now } ?? false }
}

extension WakeWeatherModel {
    /// 「今日の天気」の行：天気・気温・降水確率
    var rowDetail: String {
        if let w = weather { return "\(w.text) \(Int(w.temp.rounded()))°・降水 \(w.rain)%" }
        if needsLocation { return "今いる場所の天気を表示する" }
        return loading ? "取得中…" : "天気を取得できませんでした"
    }
}
