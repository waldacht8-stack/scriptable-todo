import SwiftUI
import WidgetKit

/// ウィジェットの見本（起動引数 -widgetpreview のときだけ表示。スクリーンショット用）
/// 色合いは -theme に従う。-widgetsize large で大サイズを並べる
struct WidgetPreviewScreen: View {
    @Environment(\.palette) private var p
    private let large: Bool = ProcessInfo.processInfo.arguments.contains("large")

    var body: some View {
        let items: [TodoItem] = Self.sampleItems()
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(large ? "ウィジェットの見本（大）" : "ウィジェットの見本（小・中）")
                    .font(.title3.weight(.bold)).foregroundStyle(p.text)
                if large {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                        ForEach(TodayLayout.allCases) { layout in
                            VStack(alignment: .leading, spacing: 4) {
                                caption(layout)
                                widget(Self.data(items, layout: layout, palette: p), .systemLarge, CGSize(width: 364, height: 382), scale: 0.47)
                            }
                        }
                    }
                } else {
                    ForEach(TodayLayout.allCases) { layout in
                        let data: TodoWidgetData = Self.data(items, layout: layout, palette: p)
                        VStack(alignment: .leading, spacing: 4) {
                            caption(layout)
                            HStack(alignment: .top, spacing: 6) {
                                widget(data, .systemSmall, CGSize(width: 170, height: 170), scale: 0.55)
                                widget(data, .systemMedium, CGSize(width: 364, height: 170), scale: 0.55)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paletteBackground(p)
    }

    private func caption(_ layout: TodayLayout) -> some View {
        Text(layout.name).font(.caption.weight(.bold)).foregroundStyle(p.sub)
    }

    private func widget(_ data: TodoWidgetData, _ family: WidgetFamily, _ size: CGSize, scale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return TodoWidgetView(data: data, familyOverride: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetPaletteBackground(p: data.palette))
            .clipShape(shape)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    /// 見本：長めの題名で、切れ方や折り返しが見えるようにする（一般的な内容のみ）
    private static func sampleItems() -> [TodoItem] {
        let cal = Calendar.current
        let now = Date.now
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, _ h: Int, _ m: Int = 0) -> Date {
            let d: Date = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return cal.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
        }
        func later(_ minutes: Int) -> Date {
            let d: Date = cal.date(byAdding: .minute, value: minutes, to: now) ?? now
            return min(max(d, today), day(0, 23, 50))
        }
        return [
            TodoItem(title: "図書館に本を返却する", due: day(-1, 17)),
            TodoItem(title: "朝のストレッチを10分", done: true, due: later(-50), doneAt: later(-50)),
            TodoItem(title: "ゴミ出し（燃えるゴミ）", done: true, due: later(-20), doneAt: later(-20)),
            TodoItem(title: "牛乳と卵とパンを買う", due: later(60), important: true),
            TodoItem(title: "部屋の掃除と洗濯をする", due: today, allDay: true),
            TodoItem(title: "請求書の内容を確認する", due: later(180)),
            TodoItem(title: "美容院に電話して予約する", due: day(1, 11)),
            TodoItem(title: "車検の見積もりをもらう", due: day(5, 0), allDay: true),
            TodoItem(title: "旅行の持ち物リストを作る"),
        ]
    }

    private static func data(_ all: [TodoItem], layout: TodayLayout, palette: Palette) -> TodoWidgetData {
        let now = Date.now
        let cal = Calendar.current
        let open: [TodoItem] = TodoData.sorted(all.filter { !$0.done })
        let done: [TodoItem] = all.filter { item in item.done && (item.doneAt.map { cal.isDateInToday($0) } ?? false) }
        let timed: [TodoItem] = open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > now }
        return TodoWidgetData(
            items: open,
            overdue: open.filter { $0.isOverdue(now) }.count,
            doneToday: done.count,
            next: timed.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) },
            layout: layout,
            palette: palette,
            groupOK: true,
            doneItems: done
        )
    }
}
