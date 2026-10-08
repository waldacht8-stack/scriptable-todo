import SwiftUI
import WidgetKit

/// ウィジェットの見本（起動引数 -widgetpreview のときだけ表示。スクリーンショット用）
struct WidgetPreviewScreen: View {
    @Environment(\.palette) private var p
    private let scale: CGFloat = 0.5

    var body: some View {
        let items = TodoData.demo()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ウィジェットの見本").font(.title3.weight(.bold)).foregroundStyle(p.text)
                ForEach(AppTheme.allCases) { theme in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(theme.name).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(TodayLayout.allCases) { layout in
                                let data = Self.data(items, layout: layout, palette: theme.palette)
                                HStack(alignment: .top, spacing: 4) {
                                    widget(data, .systemSmall, CGSize(width: 170, height: 170))
                                    widget(data, .systemMedium, CGSize(width: 364, height: 170))
                                }
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

    private func widget(_ data: TodoWidgetData, _ family: WidgetFamily, _ size: CGSize) -> some View {
        TodoWidgetView(data: data, familyOverride: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(WidgetPaletteBackground(p: data.palette))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    private static func data(_ all: [TodoItem], layout: TodayLayout, palette: Palette) -> TodoWidgetData {
        let now = Date.now
        let open = TodoData.sorted(all.filter { !$0.done })
        return TodoWidgetData(
            items: open,
            overdue: open.filter { $0.isOverdue(now) }.count,
            doneToday: all.filter { $0.done }.count,
            next: open.filter { !$0.isAllDay && ($0.due ?? .distantPast) > now }.min { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) },
            layout: layout,
            palette: palette,
            groupOK: true
        )
    }
}
