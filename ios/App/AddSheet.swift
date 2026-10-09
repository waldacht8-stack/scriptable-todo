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
                    if editing == nil, !hasDue, let preview = QuickParse.summary(QuickParse.parse(title)) {
                        Label(preview, systemImage: "wand.and.stars").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                    }
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
                        let q = QuickParse.parse(title)
                        if editing == nil && !hasDue && q.hasSchedule { // 期限を手で決めていなければ、文から読み取った期限を使う
                            store.add(q.title, due: q.due, allDay: q.allDay, note: note, repeatRule: q.repeatRule, important: important)
                            dismiss()
                            return
                        }
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
