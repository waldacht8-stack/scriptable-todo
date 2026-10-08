import SwiftUI

// MARK: - 追加・編集（draft.item があれば編集）

struct AddSheet: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    let draft: AddDraft
    @State private var title = ""
    @State private var hasDue = false
    @State private var allDay = false
    @State private var due = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var note = ""
    @State private var repeatRule = ""
    @State private var important = false
    @State private var toCalendar = false
    @State private var calendarTitle = ""
    @FocusState private var focused: Bool
    @State private var confirmDelete = false

    private var editing: TodoItem? { draft.item }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("やること", text: $title).focused($focused).submitLabel(.done)
                    Toggle(isOn: $important) { Label("重要（先頭に固定）", systemImage: "star") }
                }
                Section {
                    Toggle("期限を決める", isOn: $hasDue.animation())
                    if hasDue {
                        Toggle("終日", isOn: $allDay)
                        DatePicker("期限", selection: $due, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        Picker("繰り返し", selection: $repeatRule) {
                            Text("なし").tag("")
                            ForEach(RepeatRule.allCases) { Text($0.name).tag($0.rawValue) }
                        }
                        if CalendarSync.authorized && editing == nil {
                            Toggle("カレンダーにも予定として登録", isOn: $toCalendar.animation())
                            if toCalendar {
                                Picker("登録先", selection: $calendarTitle) {
                                    Text("いつものカレンダー").tag("")
                                    ForEach(CalendarSync.writableCalendars(), id: \.calendarIdentifier) { Text($0.title).tag($0.title) }
                                }
                            }
                        }
                    }
                }
                Section("メモ") { TextField("メモ（任意）", text: $note, axis: .vertical).lineLimit(2...5) }
                if let item = editing {
                    Section {
                        Button {
                            if item.done { store.uncomplete(item) } else { store.complete(item) }
                            dismiss()
                        } label: {
                            Label(item.done ? "未完了に戻す" : "完了にする", systemImage: item.done ? "arrow.uturn.backward" : "checkmark")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("削除", systemImage: "trash") }
                    } footer: {
                        if item.isCalendar { Text("カレンダーから取り込んだTODOです。ここで変えた内容はカレンダーには反映されません。") }
                    }
                }
            }
            .navigationTitle(editing == nil ? "TODOを追加" : "TODOを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "追加" : "保存") {
                        let d = allDay ? Calendar.current.startOfDay(for: due) : due
                        if var item = editing {
                            item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            item.due = hasDue ? d : nil
                            item.allDay = hasDue && allDay ? true : nil
                            item.note = note.isEmpty ? nil : note
                            item.repeatRule = hasDue && !repeatRule.isEmpty ? repeatRule : nil
                            item.important = important ? true : nil
                            store.save(item)
                        } else {
                            store.add(title, due: hasDue ? d : nil, allDay: hasDue && allDay, note: note,
                                      repeatRule: hasDue && !repeatRule.isEmpty ? repeatRule : nil, important: important,
                                      toCalendar: hasDue && toCalendar ? calendarTitle : nil)
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let item = editing {
                    title = item.title
                    important = item.isImportant
                    hasDue = item.due != nil
                    allDay = item.isAllDay
                    if let d = item.due { due = d }
                    note = item.note ?? ""
                    repeatRule = item.repeatRule ?? ""
                } else {
                    if let d = draft.due { due = d; hasDue = true }
                    focused = true
                }
            }
            .confirmationDialog("このTODOを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let item = editing { store.delete(item) }
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 設定

struct SettingsView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(TodayLayout.allCases) { layout in
                            Button { withAnimation(.snappy) { store.setLayout(layout) } } label: {
                                ChoiceCard(title: layout.name, summary: layout.summary, selected: store.layout == layout) {
                                    LayoutThumb(layout: layout)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("画面の構成（今日）")
                } footer: {
                    Text("ボタンの位置と操作のしかたが変わります。")
                }
                Section {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AppTheme.allCases) { theme in
                            Button { withAnimation(.snappy) { store.setTheme(theme) } } label: {
                                ChoiceCard(title: theme.name, summary: theme.summary, selected: store.theme == theme) {
                                    PaletteThumb(palette: theme.palette)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("色合い")
                } footer: {
                    Text("すべての画面とウィジェットに反映されます。")
                }
                TodoSettingsSections()
                Section("状態") {
                    Label(SharedStore.isGroupAvailable ? "ウィジェットとのデータ共有：使える" : "ウィジェットとのデータ共有：使えない",
                          systemImage: SharedStore.isGroupAvailable ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(SharedStore.isGroupAvailable ? .green : .orange)
                    Text(SharedStore.diagnosis).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("設定")
        }
    }
}

/// 選択肢のカード（見本＋名前＋説明）
struct ChoiceCard<Thumb: View>: View {
    let title: String
    let summary: String
    let selected: Bool
    @ViewBuilder let thumb: () -> Thumb

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumb()
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack {
                Text(title).font(.headline.weight(.bold))
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
    }
}

/// 画面構成の見本（ボタンの位置がわかる簡単な図）
struct LayoutThumb: View {
    let layout: TodayLayout
    private let ink = Color.secondary.opacity(0.35)
    private let accent = Color.accentColor

    var body: some View {
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            switch layout {
            case .focus:
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)).shadow(radius: 1)
                                .frame(width: 70 - CGFloat(i) * 6, height: 56).offset(y: CGFloat(i) * 5).zIndex(Double(-i))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Circle().fill(accent).frame(width: 18, height: 18).padding(8)
                }
            case .board:
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([Color.red, accent, ink], id: \.self) { c in
                        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 3, height: 8); Capsule().fill(ink).frame(width: 24, height: 4) }
                        RoundedRectangle(cornerRadius: 3).fill(Color(.systemBackground)).frame(height: 12)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) { Capsule().fill(Color(.systemBackground)).frame(height: 12); Circle().fill(accent).frame(width: 12, height: 12) }
                }
                .padding(10)
            case .thumb:
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 6) {
                        HStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(i == 0 ? accent : Color(.systemBackground)).frame(height: 16) }
                        }
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 5) { Capsule().fill(accent.opacity(0.6)).frame(width: 14, height: 5); Capsule().fill(ink).frame(height: 5) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    Circle().fill(accent).frame(width: 16, height: 16).padding(8)
                }
            case .timeline:
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(ink).frame(width: 2).padding(.leading, 31).padding(.vertical, 10)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            if i == 2 { Rectangle().fill(Color.red).frame(height: 2).padding(.leading, 18) }
                            HStack(spacing: 5) {
                                Capsule().fill(ink).frame(width: 12, height: 3)
                                Circle().fill(i < 2 ? ink : accent).frame(width: 8, height: 8)
                                RoundedRectangle(cornerRadius: 3).fill(Color(.systemBackground)).frame(height: 12)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private var tileShape: some View { RoundedRectangle(cornerRadius: 5).fill(Color(.systemBackground)).frame(height: 24) }
}

/// 色合いの見本
struct PaletteThumb: View {
    let palette: Palette

    var body: some View {
        ZStack {
            LinearGradient(colors: palette.background.count > 1 ? palette.background : [palette.background[0], palette.background[0]],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text("あと 3 件").font(.system(.subheadline, design: palette.fontDesign).weight(.heavy)).foregroundStyle(palette.text)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(palette.accent, lineWidth: 2).frame(width: 14, height: 14)
                    Text("歯医者").font(.system(.caption, design: palette.fontDesign)).foregroundStyle(palette.text)
                    Spacer()
                    Text("14:00").font(.caption2.bold()).foregroundStyle(palette.accent)
                }
                .padding(8)
                .background(palette.card, in: RoundedRectangle(cornerRadius: min(palette.radius, 12)))
                HStack(spacing: 4) {
                    Circle().fill(palette.accent).frame(width: 10, height: 10)
                    Circle().fill(palette.overdue).frame(width: 10, height: 10)
                }
            }
            .padding(12)
        }
    }
}
