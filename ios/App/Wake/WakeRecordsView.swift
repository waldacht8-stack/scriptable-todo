import SwiftUI
import Charts

/// 起床の記録：平均・連続・2週間のグラフ・履歴
struct WakeRecordsView: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p

    private struct Bar: Identifiable {
        var id: String { day }
        let day: String
        let label: String
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
            return Bar(day: k, label: "\(cal.component(.month, from: d))/\(cal.component(.day, from: d))", score: s.score, missed: s.isMissed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WakeSummaryTiles(model: model)
                VStack(alignment: .leading, spacing: 12) {
                    WakeCardTitle(text: "2週間のスコア", icon: "chart.bar.fill")
                    if bars.isEmpty {
                        Text("まだ記録がありません").foregroundStyle(p.sub)
                    } else {
                        Chart(bars) { b in
                            BarMark(x: .value("日", b.label), y: .value("点", b.score))
                                .foregroundStyle(b.missed ? p.overdue : p.accent)
                                .cornerRadius(4)
                        }
                        .chartYScale(domain: 0...100)
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
                                Text(s.isMissed ? "未チェックイン" : (s.stage == 0 ? "アラームの前に起床" : "段階\(s.stage)で起床"))
                                    .font(.caption).foregroundStyle(s.isMissed ? p.overdue : p.sub)
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
