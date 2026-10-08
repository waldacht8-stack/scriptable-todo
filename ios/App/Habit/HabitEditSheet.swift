import SwiftUI

/// 習慣の追加・編集
struct HabitEditSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Habit
    @State private var countMode: Bool
    @State private var reminderOn: Bool
    @State private var reminderTime: Date
    let isNew: Bool
    let onSave: (Habit) -> Void

    static let icons = [
        "drop.fill", "figure.walk", "figure.run", "figure.flexibility", "dumbbell.fill", "bicycle",
        "book.fill", "character.book.closed.fill", "pencil", "brain.head.profile", "bed.double.fill", "sun.max.fill",
        "moon.stars.fill", "leaf.fill", "fork.knife", "cup.and.saucer.fill", "pills.fill", "heart.fill",
        "music.note", "paintbrush.fill", "laptopcomputer", "house.fill", "star.fill", "sparkles",
    ]

    init(habit: Habit, isNew: Bool, onSave: @escaping (Habit) -> Void) {
        _draft = State(initialValue: habit)
        _countMode = State(initialValue: habit.isCount)
        _reminderOn = State(initialValue: habit.remindHour != nil)
        let cal = Calendar.current
        let time = cal.date(bySettingHour: habit.remindHour ?? 20, minute: habit.remindMinute ?? 0, second: 0, of: .now) ?? .now
        _reminderTime = State(initialValue: time)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例：水を飲む", text: $draft.name)
                        .font(.title3.weight(.semibold))
                        .listRowBackground(p.card)
                }
                Section("アイコン") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                        ForEach(Self.icons, id: \.self) { icon in
                            let selected = draft.icon == icon
                            Button { draft.icon = icon } label: {
                                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                                    .frame(width: 42, height: 42)
                                    .foregroundStyle(selected ? draft.tint.onColor(p) : draft.tint.color(p))
                                    .background(selected ? draft.tint.color(p) : draft.tint.color(p).opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(p.card)
                }
                Section("色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                        ForEach(HabitColor.allCases) { c in
                            Button { draft.color = c.rawValue } label: {
                                ZStack {
                                    Circle().fill(c.color(p)).frame(width: 38, height: 38)
                                    if draft.tint == c {
                                        Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(c.onColor(p))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(c.name)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(p.card)
                }
                Section("目標") {
                    Picker("記録のしかた", selection: $countMode) {
                        Text("できた／まだ").tag(false)
                        Text("回数を数える").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(p.card)
                    if countMode {
                        Stepper(value: $draft.target, in: 2...99) {
                            Text("1日 \(draft.target)\(draft.unit.isEmpty ? "回" : draft.unit)").font(.body.weight(.semibold))
                        }
                        .listRowBackground(p.card)
                        TextField("単位（例：杯・回・ページ）", text: $draft.unit)
                            .listRowBackground(p.card)
                    }
                }
                Section("する曜日") {
                    HStack(spacing: 6) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                            let on = draft.weekdays.contains(wd)
                            Button {
                                if on { draft.weekdays.removeAll { $0 == wd } } else { draft.weekdays.append(wd) }
                            } label: {
                                Text(HabitData.weekdaySymbol(wd)).font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .foregroundStyle(on ? p.onAccent : p.sub)
                                    .background(on ? p.accent : p.sub.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(p.card)
                    HStack(spacing: 10) {
                        quick("毎日", Array(1...7))
                        quick("平日", [2, 3, 4, 5, 6])
                        quick("週末", [1, 7])
                    }
                    .listRowBackground(p.card)
                }
                Section {
                    Toggle("リマインダー", isOn: $reminderOn.animation())
                        .listRowBackground(p.card)
                    if reminderOn {
                        DatePicker("時刻", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .listRowBackground(p.card)
                    }
                } footer: {
                    Text("する曜日の決まった時刻に通知します。").foregroundStyle(p.sub)
                }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .foregroundStyle(p.text)
            .navigationTitle(isNew ? "習慣を追加" : "習慣を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.weekdays.isEmpty)
                }
            }
        }
    }

    private func quick(_ title: String, _ days: [Int]) -> some View {
        Button { draft.weekdays = days } label: {
            Text(title).font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(p.text).background(p.sub.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        var h = draft
        h.name = h.name.trimmingCharacters(in: .whitespaces)
        if !countMode { h.target = 1 } else { h.target = max(2, h.target) }
        if reminderOn {
            let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            h.remindHour = c.hour
            h.remindMinute = c.minute
        } else {
            h.remindHour = nil
            h.remindMinute = nil
        }
        onSave(h)
        dismiss()
    }
}
