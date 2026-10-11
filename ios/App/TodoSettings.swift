import SwiftUI
import UniformTypeIdentifiers

/// 設定画面の TODO まわり（通知・カレンダー・データ）。部品は Settings.swift のもの
/// 以前の「TODO」の見出し（期限前の通知）は「通知」にまとめた。-settingsSection todo は通知へ送る
struct TodoSettingsSections: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @State private var s = SettingsData.load()
    @State private var calendars: [String] = []
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28 * p.density.scale) {
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

    // MARK: 通知（TODO の期限・朝・夜）

    private var notifySection: some View {
        SettingsSection("通知", icon: "bell.badge.fill",
                        footer: "通知を長押しすると、アプリを開かずに「完了」「10分後に再通知」を選べます。") {
            SettingsCard {
                MenuRow(title: "TODO の期限前", icon: "checklist",
                        selection: Binding(get: { s.remindMinutes ?? -1 }, set: { s.remindMinutes = $0 < 0 ? nil : $0; save() }),
                        options: remindOptions)
                RowDivider()
                hourRow("朝に今日の一覧", icon: "sunrise.fill",
                        value: Binding(get: { s.morningHour }, set: { s.morningHour = $0; save() }), hours: Array(4...11))
                RowDivider()
                hourRow("夜に残りのTODO", icon: "moon.stars.fill",
                        value: Binding(get: { s.eveningHour }, set: { s.eveningHour = $0; save() }), hours: Array(17...23))
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

    private func hourRow(_ title: String, icon: String, value: Binding<Int?>, hours: [Int]) -> some View {
        var options: [(value: Int, label: String)] = [(value: -1, label: "通知しない")]
        for h in hours { options.append((value: h, label: "\(h):00")) }
        let selection = Binding<Int>(get: { value.wrappedValue ?? -1 }, set: { value.wrappedValue = $0 < 0 ? nil : $0 })
        return MenuRow(title: title, icon: icon, selection: selection, options: options)
    }

    // MARK: カレンダー

    private var calendarSection: some View {
        SettingsSection("カレンダー", icon: "calendar",
                        footer: "iPhoneのカレンダーの予定をTODOとして取り込みます。予定の変更・削除は、未完了のTODOにも反映されます。") {
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
                        footer: "毎日自動で14日分を保存します（「ファイル」→「このiPhone内」→「日和」→「バックアップ」）。Scriptable版のデータは「バックアップから戻す」で「todo-data.json」を選ぶと取り込めます。") {
            SettingsCard {
                Button(action: backupNow) {
                    SettingsRow(title: "今すぐバックアップ", icon: "arrow.clockwise.icloud.fill") {
                        HStack(spacing: 6) {
                            if let last = s.lastBackup {
                                Text("前回 \(JP.shortDate(last)) \(JP.time(last))")
                                    .font(.caption)
                                    .foregroundStyle(p.sub)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                        }
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                ActionRow(title: "バックアップから戻す", icon: "clock.arrow.circlepath") { importing = true }
            }
        }
    }

    private func backupNow() {
        guard Backup.write() != nil else { message = "バックアップできませんでした"; return }
        var x = SettingsData.load()
        x.lastBackup = .now
        SettingsData.save(x)
        s = x
        message = "バックアップしました"
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
