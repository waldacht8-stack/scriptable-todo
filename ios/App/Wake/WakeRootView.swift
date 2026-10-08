import SwiftUI

/// 起床タブの入口（エージェント1が作り込む。段階0の内容を仮に置いている）
struct WakeRootView: View {
    var body: some View { WakeTab() }
}

// MARK: - 起床（段階0：チェックインと AlarmKit のテスト。段階3で作り込む）

struct WakeTab: View {
    @State private var state = WakeData.state()
    @State private var alarmMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("チェックイン") {
                    if let at = state.checkedInAt {
                        Text("最後のチェックイン：\(at.formatted(date: .abbreviated, time: .shortened))")
                    } else {
                        Text("まだチェックインしていません")
                    }
                    Button("起きた！（チェックイン）") {
                        WakeData.checkIn()
                        state = WakeData.state()
                    }
                }
                Section {
                    Button("1分後にテストアラーム") {
                        Task { alarmMessage = await AlarmTest.scheduleInOneMinute() }
                    }
                    if !alarmMessage.isEmpty { Text(alarmMessage).font(.footnote) }
                } header: {
                    Text("アラーム（AlarmKit）")
                } footer: {
                    Text("マナーモード・画面ロック中でも鳴るかを確かめます。")
                }
            }
            .navigationTitle("起床")
            .onAppear { state = WakeData.state() }
        }
    }
}
