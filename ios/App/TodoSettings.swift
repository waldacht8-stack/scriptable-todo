import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の TODO まわり（TODO・通知・カレンダー・データ）。部品は Settings.swift のもの
struct TodoSettingsSections: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @State private var s = SettingsData.load()
    @State private var calendars: [String] = []
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 30 * p.density.scale) {
            todoSection.id("todo")
            notifySection.id("notify")
            calendarSection.id("calendar")
            dataSection.id("data")
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
                message = "\(n)件のTODOを読み込みました"
            } catch {
                message = "読み込めませんでした（\(error.localizedDescription)）"
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: TODO

    private var todoSection: some View {
        SettingsSection("TODO", icon: "checklist", footer: "期限のあるTODOを、期限の少し前に通知でお知らせします。") {
            SettingsCard {
                MenuRow(title: "期限前の通知", icon: "bell.fill",
                        selection: Binding(get: { s.remindMinutes ?? -1 }, set: { s.remindMinutes = $0 < 0 ? nil : $0; save() }),
                        options: remindOptions)
                // ここに TODO の表示の設定（完了したTODOの表示など）を足す
            }
        }
    }

    private var remindOptions: [(value: Int, label: String)] {
        var list: [(value: Int, label: String)] = [(value: -1, label: "通知しない"), (value: 0, label: "期限ちょうど")]
        for m in [10, 15, 30, 60, 120] {
            list.append((value: m, label: m >= 60 ? "\(m / 60)時間前" : "\(m)分前"))
        }
        return list
    }

    // MARK: 通知

    private var notifySection: some View {
        SettingsSection("通知", icon: "bell.badge.fill",
                        footer: "通知を長押しすると「完了」「10分後に再通知」を選べます。アプリを開かずに操作できます。") {
            SettingsCard {
                hourRow("朝に今日の一覧", icon: "sunrise.fill",
                        value: Binding(get: { s.morningHour }, set: { s.morningHour = $0; save() }), hours: Array(4...11))
                RowDivider()
                hourRow("夜に残りのTODO", icon: "moon.stars.fill",
                        value: Binding(get: { s.eveningHour }, set: { s.eveningHour = $0; save() }), hours: Array(17...23))
            }
        }
    }

    private func hourRow(_ title: String, icon: String, value: Binding<Int?>, hours: [Int]) -> some View {
        var options: [(value: Int, label: String)] = [(value: -1, label: "通知しない")]
        for h in hours { options.append((value: h, label: "\(h):00")) }
        let selection = Binding<Int>(get: { value.wrappedValue ?? -1 }, set: { value.wrappedValue = $0 < 0 ? nil : $0 })
        return MenuRow(title: title, icon: icon, selection: selection, options: options)
    }

    // MARK: カレンダー

    private var calendarSection: some View {
        SettingsSection("カレンダー", icon: "calendar",
                        footer: "iPhoneのカレンダーの予定を、TODOとして取り込みます。予定を変更・削除すると、まだ完了していないTODOにも反映されます。") {
            SettingsCard {
                ToggleRow(title: "カレンダーから取り込む", icon: "square.and.arrow.down.fill",
                          isOn: Binding(get: { s.calendarImport }, set: { s.calendarImport = $0; save() }))
                if s.calendarImport {
                    if !CalendarSync.authorized {
                        RowDivider()
                        ActionRow(title: "カレンダーへのアクセスを許可", icon: "lock.open.fill") {
                            Task {
                                _ = await CalendarSync.requestAccess()
                                calendars = CalendarSync.allCalendarTitles()
                                await store.refreshServices()
                            }
                        }
                    }
                    RowDivider()
                    MenuRow(title: "取り込む期間", icon: "calendar.badge.clock",
                            selection: Binding(get: { s.lookaheadDays }, set: { s.lookaheadDays = $0; save() }),
                            options: [14, 30, 45, 60, 90].map { (value: $0, label: "\($0)日先まで") })
                }
            }
            if s.calendarImport && !calendars.isEmpty {
                SubHeading("取り込むカレンダー", note: "オフにしたカレンダーの予定は取り込みません。")
                SettingsCard {
                    ForEach(Array(calendars.enumerated()), id: \.element) { i, title in
                        if i > 0 { RowDivider() }
                        ToggleRow(title: title, icon: "circle.fill", isOn: Binding(
                            get: { !s.excludeCalendars.contains(title) },
                            set: { on in
                                if on { s.excludeCalendars.removeAll { $0 == title } } else { s.excludeCalendars.append(title) }
                                save()
                            }))
                    }
                }
            }
        }
    }

    // MARK: データ

    private var dataSection: some View {
        SettingsSection("データ", icon: "externaldrive.fill",
                        footer: "毎日自動でバックアップします（14日分）。保存先は「ファイル」アプリ →「このiPhone内」→「日和」→「バックアップ」です。Scriptable版のデータは、iCloud Drive の「Scriptable」→「todo-data」→「todo-data.json」を選ぶと取り込めます。") {
            SettingsCard {
                ActionRow(title: "今すぐバックアップ", icon: "arrow.clockwise.icloud.fill") {
                    guard Backup.write() != nil else { message = "バックアップできませんでした"; return }
                    var x = SettingsData.load()
                    x.lastBackup = .now
                    SettingsData.save(x)
                    s = x
                    message = "バックアップしました"
                }
                if let last = s.lastBackup {
                    RowDivider()
                    SettingsRow(title: "前回のバックアップ", icon: "clock.fill") {
                        Text("\(JP.date(last)) \(JP.time(last))").font(.subheadline).foregroundStyle(p.sub)
                    }
                }
                RowDivider()
                ActionRow(title: "バックアップから戻す", icon: "clock.arrow.circlepath") { importing = true }
                RowDivider()
                ActionRow(title: "Scriptable版から取り込む", icon: "square.and.arrow.down.on.square.fill") { importing = true }
            }
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
