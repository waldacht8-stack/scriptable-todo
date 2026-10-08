import SwiftUI
import WidgetKit
import BackgroundTasks

@main
struct HiyoriApp: App {
    @StateObject private var store = TodoStore()
    @Environment(\.scenePhase) private var phase

    init() {
        TodoNotifier.shared.setUp() // 通知のボタン（完了・10分後）をアプリを開かずに処理する
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onChange(of: phase) { _, p in
                    if p == .background { BackgroundRefresh.schedule() }
                    guard p == .active else { return }
                    store.reload() // ウィジェット・通知で変えた内容を反映
                    if !ProcessInfo.processInfo.arguments.contains("-demo") { Task { await store.refreshServices() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .todoDataChanged)) { _ in store.reload() }
        }
        // アプリを開いていなくても、ときどきカレンダーの取り込みと通知の予約し直しをする
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            BackgroundRefresh.schedule()
            await BackgroundRefresh.run()
        }
    }
}

/// バックグラウンドでの更新（実行の時刻は iOS が決める。おおむね1時間以上の間隔）
enum BackgroundRefresh {
    static let id = "com.todoapp.TodoApp.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        let s = SettingsData.load()
        var list = TodoData.all()
        if s.calendarImport && CalendarSync.authorized {
            CalendarSync.importEvents(into: &list, settings: s)
            TodoData.save(list)
        }
        await TodoNotifier.shared.reschedule(list, settings: s)
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

