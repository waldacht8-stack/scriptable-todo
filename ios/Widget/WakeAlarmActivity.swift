import SwiftUI
import WidgetKit
import ActivityKit
#if canImport(AlarmKit)
import AlarmKit
#endif

// 起床アラーム（AlarmKit）が鳴るときのロック画面・ダイナミックアイランドの表示。
// AlarmKit のアラームは、アプリのウィジェットにこの Live Activity が無いと、鳴る画面を出せないことがある

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct WakeAlarmActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeAlarmMetadata>.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "alarm.fill").font(.title2.weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("起床アラーム").font(.headline)
                    Text("\(context.attributes.metadata?.stage ?? 1)回目").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").font(.title3)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("起床アラーム").font(.headline)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
            } compactTrailing: {
                Text("\(context.attributes.metadata?.stage ?? 1)").font(.caption.weight(.bold))
            } minimal: {
                Image(systemName: "alarm.fill")
            }
        }
    }
}
#endif

/// 起床まわりの Live Activity（出発のカウントダウンと、アラームが鳴るときの表示）
struct WakeActivityBundle: WidgetBundle {
    var body: some Widget {
        WakeLiveActivity()
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            WakeAlarmActivity()
        }
        #endif
    }
}
