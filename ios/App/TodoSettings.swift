import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の TODO まわり（通知・カレンダー・データ）
struct TodoSettingsSections: View {
    @EnvironmentObject var store: TodoStore
    @State private var s = SettingsData.load()
    @State private var calendars: [String] = []
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        Group {
            Section {
                Picker("期限前の通知", selection: Binding(get: { s.remindMinutes ?? -1 }, set: { s.remindMinutes = $0 < 0 ? nil : $0; save() })) {
                    Text("通知しない").tag(-1)
                    Text("期限ちょうど").tag(0)
                    ForEach([10, 15, 30, 60, 120], id: \.self) { Text($0 >= 60 ? "\($0 / 60)時間前" : "\($0)分前").tag($0) }
                }
                hourPicker("朝の一覧", value: Binding(get: { s.morningHour }, set: { s.morningHour = $0; save() }), hours: Array(4...11))
                hourPicker("夜の残り", value: Binding(get: { s.eveningHour }, set: { s.eveningHour = $0; save() }), hours: Array(17...23))
            } header: {
                Text("TODOの通知")
            } footer: {
                Text("通知を長押しすると［完了］［10分後に再通知］を選べます（アプリは開きません）。")
            }

            Section {
                Toggle("iPhoneのカレンダーから取り込む", isOn: Binding(get: { s.calendarImport }, set: { s.calendarImport = $0; save() }))
                if s.calendarImport {
                    if !CalendarSync.authorized {
                        Button("カレンダーへのアクセスを許可する") {
                            Task { _ = await CalendarSync.requestAccess(); calendars = CalendarSync.allCalendarTitles(); await store.refreshServices() }
                        }
                    }
                    Picker("取り込む範囲", selection: Binding(get: { s.lookaheadDays }, set: { s.lookaheadDays = $0; save() })) {
                        ForEach([14, 30, 45, 60, 90], id: \.self) { Text("\($0)日先まで").tag($0) }
                    }
                    ForEach(calendars, id: \.self) { title in
                        Toggle(title, isOn: Binding(
                            get: { !s.excludeCalendars.contains(title) },
                            set: { on in
                                if on { s.excludeCalendars.removeAll { $0 == title } } else { s.excludeCalendars.append(title) }
                                save()
                            }))
                    }
                }
            } header: {
                Text("カレンダー")
            } footer: {
                Text("予定はそのままTODOになります。予定の変更・削除は、未完了のTODOに自動で反映されます。")
            }

            Section {
                Button("今すぐバックアップ") {
                    if Backup.write() != nil { message = "バックアップしました" }
                    var x = SettingsData.load(); x.lastBackup = .now; SettingsData.save(x); s = x
                }
                if let last = s.lastBackup {
                    LabeledContent("前回のバックアップ", value: "\(JP.date(last)) \(JP.time(last))")
                }
                Button("バックアップから戻す・Scriptable版から取り込む") { importing = true }
            } header: {
                Text("データ")
            } footer: {
                Text("毎日自動でバックアップします（14日分）。保存先：「ファイル」アプリ → このiPhone内 → ひより → バックアップ。Scriptable版のデータは、iCloud Drive → Scriptable → todo-data → todo-data.json を選ぶと取り込めます。")
            }
        }
        .onAppear {
            s = SettingsData.load()
            if CalendarSync.authorized { calendars = CalendarSync.allCalendarTitles() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            do {
                var items = TodoData.all()
                let n = try Backup.restore(from: url, into: &items)
                TodoData.save(items)
                store.reload()
                s = SettingsData.load()
                message = "\(n)件を読み込みました"
            } catch {
                message = "読み込めませんでした：\(error.localizedDescription)"
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func hourPicker(_ title: String, value: Binding<Int?>, hours: [Int]) -> some View {
        Picker(title, selection: Binding(get: { value.wrappedValue ?? -1 }, set: { value.wrappedValue = $0 < 0 ? nil : $0 })) {
            Text("送らない").tag(-1)
            ForEach(hours, id: \.self) { Text("\($0):00").tag($0) }
        }
    }

    /// TODO の項目だけを書き戻す（デザインなど他の画面で変えた設定を古い値で上書きしない）
    private func save() {
        var fresh = SettingsData.load()
        fresh.remindMinutes = s.remindMinutes
        fresh.morningHour = s.morningHour
        fresh.eveningHour = s.eveningHour
        fresh.calendarImport = s.calendarImport
        fresh.lookaheadDays = s.lookaheadDays
        fresh.excludeCalendars = s.excludeCalendars
        SettingsData.save(fresh)
        s = fresh
        Task { await store.refreshServices() }
    }
}
