import SwiftUI
import WidgetKit

@main
struct TodoApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    // 起動引数 -preview でウィジェットの見本タブから始める（シミュレーターのスクリーンショット用）
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-preview") ? 2 : 0

    var body: some View {
        TabView(selection: $tab) {
            TodoTab().tabItem { Label("TODO", systemImage: "checklist") }.tag(0)
            WakeTab().tabItem { Label("起床", systemImage: "alarm") }.tag(1)
            PreviewTab().tabItem { Label("見本", systemImage: "rectangle.3.group") }.tag(2)
        }
    }
}

// MARK: - TODO（段階0：追加と完了だけ）

struct TodoTab: View {
    @State private var items = TodoData.all()
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusRow()
                }
                Section("TODO") {
                    ForEach(items) { item in
                        Button {
                            TodoData.toggle(id: item.id)
                            items = TodoData.all()
                        } label: {
                            HStack {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                Text(item.title).strikethrough(item.done)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    HStack {
                        TextField("新しいTODO", text: $newTitle)
                        Button("追加") {
                            let t = newTitle.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            items.append(TodoItem(title: t))
                            TodoData.save(items)
                            newTitle = ""
                        }
                    }
                }
            }
            .navigationTitle("TODO")
            .refreshable { items = TodoData.all() }
            .onAppear { items = TodoData.all() }
        }
    }
}

/// 段階0の検証結果をそのまま画面に出す
struct StatusRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(SharedStore.isGroupAvailable ? "App Group：使える" : "App Group：使えない（ウィジェットと共有できない）",
                  systemImage: SharedStore.isGroupAvailable ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(SharedStore.isGroupAvailable ? .green : .orange)
            Text("検証用 v0.1").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 起床（段階0：チェックインと AlarmKit のテスト）

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

// MARK: - ウィジェットの見本（スクリーンショットで見た目を確かめる用）

struct PreviewTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                card { TodoWidgetView(items: TodoData.all(), groupOK: SharedStore.isGroupAvailable) }
                card { WakeWidgetView(state: WakeData.state()) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(width: 338, height: 158)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
