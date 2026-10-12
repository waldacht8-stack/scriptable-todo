import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

/// 段階0：AlarmKit（iOS 26）でアプリ自身がアラームを鳴らせるかの検証。
/// 本番の段階アラームはこの結果を見て設計する。
enum AlarmTest {
    static func scheduleInOneMinute() async -> String {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await schedule()
        }
        return "このiOSではAlarmKitを使えません（iOS 26以上が必要）"
        #else
        return "このビルドにはAlarmKitが入っていません（ビルド環境のXcodeが古い）"
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    struct WakeMetadata: AlarmMetadata {}

    @available(iOS 26.0, *)
    private static func schedule() async -> String {
        let manager = AlarmManager.shared
        do {
            let auth = try await manager.requestAuthorization()
            guard auth == .authorized else { return "アラームの許可がありません（設定アプリで許可してください）" }
            let alert = AlarmPresentation.Alert(
                title: "テストアラーム",
                stopButton: AlarmButton(text: "止める", textColor: .white, systemImageName: "stop.circle")
            )
            // 起床アラームと同じ種類にする（ウィジェットの鳴る画面 WakeAlarmActivity が使われる）
            let attributes = AlarmAttributes<WakeAlarmMetadata>(presentation: AlarmPresentation(alert: alert),
                                                                metadata: WakeAlarmMetadata(stage: 1), tintColor: .blue)
            let at = Date().addingTimeInterval(60)
            let config = AlarmManager.AlarmConfiguration<WakeAlarmMetadata>.alarm(schedule: .fixed(at), attributes: attributes)
            let id = UUID()
            // 起床アラームの予約し直しで消されないよう、テストの1件として覚えておく
            WakeTestAlarms.remember(id)
            _ = try await manager.schedule(id: id, configuration: config)
            // 確かめ：iOS に入ったアラームの数と、この1件の状態（鳴らないときの手がかり）
            let all: [Alarm] = (try? manager.alarms) ?? []
            let mine: String = all.first(where: { $0.id == id }).map { "\($0.state)" } ?? "見つからない"
            let time: String = at.formatted(date: .omitted, time: .standard)
            return "\(time) に鳴ります。画面をロックして待ってください（登録 \(all.count)件・この1件：\(mine)）"
        } catch {
            return "アラームを設定できませんでした：\(error.localizedDescription)"
        }
    }
    #endif
}
