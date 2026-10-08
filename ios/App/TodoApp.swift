import SwiftUI
import WidgetKit

@main
struct HiyoriApp: App {
    @StateObject private var store = TodoStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: phase) { _, p in if p == .active { store.reload() } } // ウィジェットで変えた内容を反映
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: TodoStore
    // 起動引数 -tab 0/1/2（シミュレーターのスクリーンショット用）
    @State private var tab: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { return Int(args[i + 1]) ?? 0 }
        return 0
    }()

    var body: some View {
        let p = store.theme.palette
        TabView(selection: $tab) {
            HomeView().tabItem { Label("今日", systemImage: "sun.horizon") }.tag(0)
            WakeTab().tabItem { Label("起床", systemImage: "alarm") }.tag(1)
            SettingsView().tabItem { Label("設定", systemImage: "gearshape") }.tag(2)
        }
        // デザイン（色合い）をすべての画面に渡す
        .environment(\.palette, p)
        .fontDesign(p.fontDesign)
        .tint(p.accent)
        .preferredColorScheme(p.scheme)
    }
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
