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
            let attributes = AlarmAttributes<WakeMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .blue)
            let at = Date().addingTimeInterval(60)
            let config = AlarmManager.AlarmConfiguration<WakeMetadata>.alarm(schedule: .fixed(at), attributes: attributes)
            _ = try await manager.schedule(id: UUID(), configuration: config)
            return "\(at.formatted(date: .omitted, time: .standard)) に鳴ります。画面をロックして待ってください"
        } catch {
            return "アラームを設定できませんでした：\(error.localizedDescription)"
        }
    }
    #endif
}
