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
                    if !ProcessInfo.processInfo.arguments.contains("-demo") { Task { await DayCardReminder.reschedule() } } // 1日1枚の通知を切らさない
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
    // 起動引数 -tab 0〜4（0 今日・1 起床・2 習慣・3 集中・4 情報。シミュレーターのスクリーンショット用）
    @State private var tab: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { return Int(args[i + 1]) ?? 0 }
        return 0
    }()
    // 設定は各画面の右上の歯車から開く（起動引数 -settings で開いた状態にする：スクリーンショット用）
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-settings")

    var body: some View {
        let p = store.theme.palette(with: SettingsData.load())
        Group {
            if ProcessInfo.processInfo.arguments.contains("-widgetpreview") {
                WidgetPreviewScreen() // ウィジェットの見本（スクリーンショット用）
            } else {
                TabView(selection: $tab) {
                    HomeView().tabItem { Label("TODO", systemImage: "checklist") }.tag(0)
                    WakeRootView().tabItem { Label("起床", systemImage: "alarm") }.tag(1)
                    // 習慣・集中はタブから外した（コードと記録は残す。リリース4）
                    KakeiboRootView().tabItem { Label("家計簿", systemImage: "yensign.circle") }.tag(2)
                    ConsultRootView().tabItem { Label("相談", systemImage: "bubble.left.and.text.bubble.right") }.tag(3)
                    InfoRootView().tabItem { Label("情報", systemImage: "newspaper") }.tag(4)
                }
                // 家計簿のファイル（CSV・PDF）とウィジェットの hiyori:// は openWidgetLink がまとめて受け取る
                .onOpenURL { url in openWidgetLink(url) }
                .onReceive(NotificationCenter.default.publisher(for: .openConsultTab)) { _ in tab = 3 }
                .onAppear { if ConsultDeepLink.consumePending() { tab = 3 } }
                .environment(\.openAppSettings, OpenAppSettingsAction { showSettings = true })
                .sheet(isPresented: $showSettings) {
                    SettingsView().environmentObject(store).environment(\.palette, p)
                }
            }
        }
        // デザイン（色合い）をすべての画面に渡す
        .environment(\.palette, p)
        .environment(\.motion, p.world.motion ?? MotionStyle.from(store.theme))
        .fontDesign(p.fontDesign)
        .tint(p.accent)
        .preferredColorScheme(p.scheme)
        .splatoonDemoLaunch()   // -splatdemo / -splatcard でスプラトゥーンを開く（スクリーンショット用）
        .steamDemoLaunch()      // -steamdemo で Steam を開く（スクリーンショット用）
    }

    /// ウィジェットのリンク（hiyori://todo|wake|kakeibo|consult|info|review）でタブを開く。
    /// ファイルの URL（家計簿の CSV・PDF）は .kakeiboOpenURL が受け取るので、ここでは hiyori:// だけを見る
    private func openWidgetLink(_ url: URL) {
        guard url.scheme?.lowercased() == "hiyori" else {
            // 念のため：同じ URL を受け取っても家計簿の側で1回にまとめる
            if KakeiboInbox.shared.receive(url) { tab = 2 }
            return
        }
        switch url.host?.lowercased() ?? "" {
        case "todo": tab = 0
        case "wake": tab = 1
        case "kakeibo": tab = 2
        case "consult": tab = 3
        case "info": tab = 4
        case "review":
            tab = 0
            let now = Date()
            let due: ReviewSlot? = ReviewState.load(now: now).dueSlot
            let slot: ReviewSlot = due ?? ReviewLogic.slot(at: now, settings: ReviewStore.settings())
            ReviewPresenter.shared.request = slot
        default: break
        }
    }
}


// MARK: - 設定を開く（各画面の右上に SettingsButton を置く）

struct OpenAppSettingsAction {
    var run: () -> Void = {}
    func callAsFunction() { run() }
}

private struct OpenAppSettingsKey: EnvironmentKey { static let defaultValue = OpenAppSettingsAction() }

extension EnvironmentValues {
    var openAppSettings: OpenAppSettingsAction {
        get { self[OpenAppSettingsKey.self] }
        set { self[OpenAppSettingsKey.self] = newValue }
    }
}

/// 各画面の右上に置く歯車ボタン（アプリ全体の設定を開く）
struct SettingsButton: View {
    @Environment(\.openAppSettings) private var openAppSettings
    @Environment(\.palette) private var p

    var body: some View {
        Button { openAppSettings() } label: {
            Image(systemName: "gearshape.fill").font(.title3.weight(.semibold)).foregroundStyle(p.text)
                .frame(width: 44, height: 44)
                .background(p.card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("設定")
    }
}
