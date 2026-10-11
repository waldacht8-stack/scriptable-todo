import SwiftUI
import Charts

/// 起床の記録：平均・連続・2週間のグラフ・履歴
struct WakeRecordsView: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    private struct Bar: Identifiable {
        var id: String { day }
        let day: String
        let date: Date
        let score: Int
        let missed: Bool
    }

    private var bars: [Bar] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: model.now)
        return (0..<14).reversed().compactMap { i -> Bar? in
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            let k = WakeLogic.key(d)
            guard let s = model.sessions.first(where: { $0.day == k }) else { return nil }
            return Bar(day: k, date: d, score: s.score, missed: s.isMissed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WakeSummaryTiles(model: model)
                WakeOversleepSummary(sessions: model.sessions, now: model.now)
                VStack(alignment: .leading, spacing: 12) {
                    WakeCardTitle(text: "2週間のスコア", icon: "chart.bar.fill")
                    if bars.isEmpty {
                        Text("まだ記録がありません").foregroundStyle(p.sub)
                    } else {
                        Chart(bars) { b in
                            BarMark(x: .value("日", b.date, unit: .day), y: .value("点", b.score))
                                .foregroundStyle(b.missed ? p.overdue : p.accent)
                                .cornerRadius(4)
                        }
                        .chartYScale(domain: 0...100)
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
                                Text(s.isMissed ? "未チェックイン" : (s.stage == 0 ? "アラームの前に起床" : "\(s.stage)回目で起床"))
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
                            Text(s.checkInAt.map { JP.time($0) } ?? "--:--").font(.headline).monospacedDigit().foregroundStyle(p.sub)
                            Text("\(s.score)").font(.system(size: 24, weight: .heavy, design: p.fontDesign))
                                .foregroundStyle(s.isMissed ? p.overdue : p.accent).frame(width: 52, alignment: .trailing)
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
            tile("7日の平均", WakeLogic.average(model.sessions, days: 7, now: model.now).map { "\($0)" } ?? "―", "点")
            tile("30日の平均", WakeLogic.average(model.sessions, days: 30, now: model.now).map { "\($0)" } ?? "―", "点")
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

/// 二度寝の見張りのまとめ（30日）。点数は「止めたのが何回目か」から、二度寝の分だけ引く
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
            Text("点数は、止めたのが何回目のアラームか（1回目=100）から、二度寝した分を引きます（最大50点）")
                .font(Font.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
        }
        .paletteCard(p, padding: 16)
    }
}
