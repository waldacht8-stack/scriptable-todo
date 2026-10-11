import SwiftUI
import Charts

/// 起床の記録：平均・連続・2週間のグラフ・履歴
struct WakeRecordsView: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    /// グラフの点（起きた時刻）。未チェックインの日は時刻がないので出さない
    private struct Dot: Identifiable {
        var id: String { day }
        let day: String
        let date: Date
        let minutes: Int     // 0時からの分
        let overslept: Bool
    }

    private var dots: [Dot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: model.now)
        return (0..<14).reversed().compactMap { i -> Dot? in
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            let k = WakeLogic.key(d)
            guard let s = model.sessions.first(where: { $0.day == k }), let m = WakeLogic.wakeMinutes(s) else { return nil }
            return Dot(day: k, date: d, minutes: m, overslept: (s.oversleep ?? 0) > 0)
        }
    }

    /// 縦軸の範囲（30分きざみ）。早い時刻を上にするため、値は「-分」で描く
    private var yRange: (lo: Int, hi: Int) {
        let ms: [Int] = dots.map(\.minutes)
        let lo: Int = ((ms.min() ?? 420) - 15) / 30 * 30
        let hi: Int = ((ms.max() ?? 420) + 15 + 29) / 30 * 30
        return (lo, max(hi, lo + 60))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WakeSummaryTiles(model: model)
                WakeOversleepSummary(sessions: model.sessions, now: model.now)
                VStack(alignment: .leading, spacing: 12) {
                    WakeCardTitle(text: "2週間の起床時刻", icon: "chart.dots.scatter")
                    if dots.isEmpty {
                        Text("まだ記録がありません").foregroundStyle(p.sub)
                    } else {
                        let r = yRange
                        let ticks: [Int] = Array(stride(from: -r.hi, through: -r.lo, by: 30))
                        Chart(dots) { b in
                            PointMark(x: .value("日", b.date, unit: .day), y: .value("起床", -b.minutes))
                                .foregroundStyle(b.overslept ? p.overdue : p.accent)
                                .symbolSize(90)
                        }
                        .chartYScale(domain: -r.hi ... -r.lo)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: ticks) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let v = value.as(Int.self) { Text(WakeLogic.clock(-v)) }
                                }
                            }
                        }
                        // 日付は1日おきに「9日」のように短く（狭い画面で切れないように）
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 2)) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let d = value.as(Date.self) {
                                        let day: Int = Calendar.current.component(.day, from: d)
                                        Text("\(day)日")
                                    }
                                }
                            }
                        }
                        .frame(height: 180)
                    }
                }
                .paletteCard(p)

                VStack(alignment: .leading, spacing: 0) {
                    WakeCardTitle(text: "履歴", icon: "clock.arrow.circlepath").padding(.bottom, 8)
                    if model.sessions.isEmpty {
                        Text("チェックインすると記録されます").foregroundStyle(p.sub)
                    }
                    ForEach(model.sessions.prefix(60)) { s in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(WakeLogic.date(fromKey: s.day).map { JP.date($0) } ?? s.day)
                                    .font(.body.weight(.semibold)).foregroundStyle(p.text)
                                Text(WakeLogic.stageText(s))
                                    .font(.caption).foregroundStyle(s.isMissed ? p.overdue : p.sub)
                                // 二度寝の見張り：二度寝の分か、「二度寝なし」
                                if let over = s.oversleep {
                                    let text: String = over > 0 ? "二度寝 \(over)分" : "二度寝なし"
                                    let icon: String = over > 0 ? "zzz" : "checkmark.circle.fill"
                                    Label(text, systemImage: icon).font(Font.caption.weight(.bold))
                                        .foregroundStyle(over > 0 ? p.overdue : p.accent)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(s.checkInAt.map { JP.time($0) } ?? "--:--").font(.system(size: 24, weight: .heavy, design: p.fontDesign))
                                .monospacedDigit().foregroundStyle(s.isMissed ? p.overdue : p.accent)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .paletteCard(p)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .paletteBackground(p)
        .navigationTitle("起床の記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

struct WakeSummaryTiles: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 10) {
            tile("7日の平均起床", WakeLogic.averageWakeMinutes(model.sessions, days: 7, now: model.now).map { WakeLogic.clock($0) } ?? "―", "")
            tile("30日の平均起床", WakeLogic.averageWakeMinutes(model.sessions, days: 30, now: model.now).map { WakeLogic.clock($0) } ?? "―", "")
            tile("連続", "\(WakeLogic.streak(model.sessions))", "日")
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p, padding: 14)
    }
}

/// 二度寝の見張りのまとめ（30日）
struct WakeOversleepSummary: View {
    @Environment(\.palette) private var p
    let sessions: [WakeSession]
    let now: Date

    var body: some View {
        let from: String = WakeLogic.key(Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now)
        let watched: [WakeSession] = sessions.filter { $0.day >= from && $0.oversleep != nil }
        let late: [Int] = watched.compactMap(\.oversleep).filter { $0 > 0 }
        VStack(alignment: .leading, spacing: 6) {
            WakeCardTitle(text: "二度寝の見張り（30日）", icon: "eye.fill")
            if watched.isEmpty {
                Text("アラームの「止める」で見張りが始まります").font(Font.subheadline).foregroundStyle(p.sub)
            } else {
                let avg: Int = late.isEmpty ? 0 : late.reduce(0, +) / late.count
                let line: String = late.isEmpty ? "見張った\(watched.count)日とも二度寝なし" : "見張った\(watched.count)日のうち二度寝 \(late.count)回・平均\(avg)分"
                Text(line).font(Font.headline).foregroundStyle(late.isEmpty ? p.accent : p.text)
            }
            Text("アラームを止めてから5分たっても動き出さないと、二度寝として数えます")
                .font(Font.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
        }
        .paletteCard(p, padding: 16)
    }
}
