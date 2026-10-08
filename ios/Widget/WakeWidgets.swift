import SwiftUI
import WidgetKit
import AppIntents

// 起床のウィジェット（エージェント1の担当）

struct WakeEntry: TimelineEntry {
    let date: Date
    let state: WakeState
}

struct WakeProvider: TimelineProvider {
    func placeholder(in context: Context) -> WakeEntry { WakeEntry(date: .now, state: WakeState()) }

    func getSnapshot(in context: Context, completion: @escaping (WakeEntry) -> Void) {
        completion(WakeEntry(date: .now, state: WakeData.state()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WakeEntry>) -> Void) {
        let e = WakeEntry(date: .now, state: WakeData.state())
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct WakeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WakeWidget", provider: WakeProvider()) { entry in
            WakeWidgetView(state: entry.state)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("起床")
        .description("起床チェックインと出発までの時間。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WakeWidgetView: View {
    let state: WakeState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("起床").font(.headline)
            if let at = state.checkedInAt, Calendar.current.isDateInToday(at) {
                Label("チェックイン済み \(at.formatted(date: .omitted, time: .shortened))", systemImage: "sun.max.fill")
                    .font(.subheadline)
            } else {
                Button(intent: CheckInIntent()) {
                    Label("起きた！", systemImage: "alarm")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
