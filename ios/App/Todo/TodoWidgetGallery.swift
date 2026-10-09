import SwiftUI
import WidgetKit

/// TODO ウィジェットの見本（起動引数 -todowidgets のとき「今日」タブに出す。スクリーンショット用）。
/// 小さい iPhone の大きさ（小 148・中 321×148・大 321×324）で描き、縮小して並べる。
struct TodoWidgetGallery: View {
    @Environment(\.palette) private var p

    private static let small = CGSize(width: 148, height: 148)
    private static let medium = CGSize(width: 321, height: 148)
    private static let large = CGSize(width: 321, height: 324)

    var body: some View {
        let items: [TodoItem] = Self.sampleItems()
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("ウィジェットの見本（TODO）").font(.headline.weight(.bold)).foregroundStyle(p.text)
                HStack(alignment: .top, spacing: 6) {
                    tile("週間", Self.data(items, .thumb, p), .systemSmall, Self.small, 0.72)
                    tile("かんばん", Self.data(items, .kanban, p), .systemSmall, Self.small, 0.72)
                    tile("チェックリスト", Self.data(items, .checklist, p), .systemSmall, Self.small, 0.72)
                }
                tile("かんばん（中）", Self.data(items, .kanban, p), .systemMedium, Self.medium, 0.9)
                tile("チェックリスト（中）", Self.data(items, .checklist, p), .systemMedium, Self.medium, 0.9)
                HStack(alignment: .top, spacing: 6) {
                    tile("かんばん（大）", Self.data(items, .kanban, p), .systemLarge, Self.large, 0.52)
                    tile("チェックリスト（大）", Self.data(items, .checklist, p), .systemLarge, Self.large, 0.52)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paletteBackground(p)
    }

    private func tile(_ name: String, _ data: TodoWidgetData, _ family: WidgetFamily, _ size: CGSize, _ scale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption2.weight(.bold)).foregroundStyle(p.sub)
            TodoWidgetView(data: data, familyOverride: family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(WidgetPaletteBackground(p: data.palette))
                .clipShape(shape)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
        }
    }

    private static func data(_ all: [TodoItem], _ layout: TodayLayout, _ palette: Palette) -> TodoWidgetData {
        let cal = Calendar.current
        let open: [TodoItem] = TodoData.sorted(all.filter { !$0.done })
        let done: [TodoItem] = all.filter { item in item.done && (item.doneAt.map { cal.isDateInToday($0) } ?? false) }
        return TodoWidgetData(items: open, overdue: open.filter { $0.isOverdue() }.count, doneToday: done.count,
                              next: nil, layout: layout, palette: palette, groupOK: true, doneItems: done, showDone: true)
    }

    /// 見本：長めの題名も入れて、切れ方や折り返しが見えるようにする（一般的な内容のみ）
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
            TodoItem(title: "ゴミ出し（燃えるゴミ）", done: true, due: later(-20), doneAt: later(-20)),
            TodoItem(title: "牛乳と卵とパンを買う", due: later(60), important: true),
            TodoItem(title: "部屋の掃除と洗濯をする", due: today, allDay: true),
            TodoItem(title: "請求書の内容を確認する", due: later(180)),
            TodoItem(title: "美容院に電話して予約する", due: day(1, 11)),
            TodoItem(title: "プレゼントを選ぶ", due: day(1, 0), allDay: true),
            TodoItem(title: "車検の見積もりをもらう", due: day(5, 0), allDay: true),
            TodoItem(title: "旅行の持ち物リストを作る"),
        ]
    }
}
