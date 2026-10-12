import SwiftUI

// MARK: - 進み具合の輪（アプリとウィジェットで共有。起床・今日のまとめの WidgetWorldRing が使う）

/// 進み具合の輪
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var track: Color? = nil
    var lineWidth: CGFloat = 8

    var body: some View {
        // 0 のときは丸い線端だけの点が出ないよう、線そのものを隠す
        let shown: Double = max(0, min(1, fraction))
        let style: StrokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        return ZStack {
            Circle().stroke((track ?? color.opacity(0.18)), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: style)
                .rotationEffect(.degrees(-90))
                .opacity(shown > 0 ? 1 : 0)
        }
    }
}

/// 旧名（WorldWidget.swift の WidgetWorldRing がまだこの名前で呼ぶ。世界観の作業が終わったら ProgressRing にそろえる）
typealias HabitRing = ProgressRing
