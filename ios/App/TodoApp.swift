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
            WakeRootView().tabItem { Label("起床", systemImage: "alarm") }.tag(1)
            HabitRootView().tabItem { Label("習慣", systemImage: "leaf") }.tag(2)
            FocusTimerRootView().tabItem { Label("集中", systemImage: "timer") }.tag(3)
            SettingsView().tabItem { Label("設定", systemImage: "gearshape") }.tag(4)
        }
        // デザイン（色合い）をすべての画面に渡す
        .environment(\.palette, p)
        .fontDesign(p.fontDesign)
        .tint(p.accent)
        .preferredColorScheme(p.scheme)
    }
}

