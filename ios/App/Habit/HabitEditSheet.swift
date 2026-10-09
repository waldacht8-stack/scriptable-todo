import SwiftUI

/// 習慣の追加・編集（色合いに合わせたカードで組む）
struct HabitEditSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Habit
    @State private var countMode: Bool
    @State private var reminderOn: Bool
    @State private var reminderTime: Date
    @FocusState private var nameFocused: Bool
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
            ScrollView {
                VStack(spacing: 16) {
                    nameCard
                    card("アイコン") { iconGrid }
                    card("色") { colorGrid }
                    card("記録のしかた") { goal }
                    card("曜日") { weekdays }
                    card("通知") { reminder }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .paletteBackground(p)
            .navigationTitle(isNew ? "習慣を追加" : "習慣を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
        }
        .tint(p.accent)
        .onAppear { if isNew { nameFocused = true } }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draft.weekdays.isEmpty
    }

    // MARK: 部品

    /// 見出し付きのカード
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
            content()
        }
        .paletteCard(p)
    }

    /// アイコンの見本と名前
    private var nameCard: some View {
        let c: Color = draft.tint.color(p)
        let on: Color = draft.tint.onColor(p)
        let fieldShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: draft.icon).font(.system(size: 24, weight: .bold)).foregroundStyle(on)
                .frame(width: 56, height: 56)
                .background(c, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("名前").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                TextField("例：水を飲む", text: $draft.name, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(p.text)
                    .lineLimit(1...3)
                    .focused($nameFocused)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(p.sub.opacity(0.1), in: fieldShape)
            }
        }
        .paletteCard(p)
    }

    private var iconGrid: some View {
        let c: Color = draft.tint.color(p)
        let on: Color = draft.tint.onColor(p)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
            ForEach(Self.icons, id: \.self) { icon in
                iconButton(icon, c, on)
            }
        }
    }

    private func iconButton(_ icon: String, _ c: Color, _ on: Color) -> some View {
        let selected: Bool = draft.icon == icon
        let fg: Color = selected ? on : c
        let bg: Color = selected ? c : c.opacity(0.12)
        return Button { draft.icon = icon } label: {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(fg)
                .frame(width: 42, height: 42)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
            ForEach(HabitColor.allCases) { c in
                colorButton(c)
            }
        }
    }

    private func colorButton(_ c: HabitColor) -> some View {
        let selected: Bool = draft.tint == c
        return Button { draft.color = c.rawValue } label: {
            ZStack {
                Circle().fill(c.color(p)).frame(width: 38, height: 38)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(c.onColor(p))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var goal: some View {
        HabitSegment(selection: $countMode.animation(), options: [(false, "チェックだけ"), (true, "回数を数える")])
        if countMode {
            HStack(spacing: 10) {
                Text("1日の目標").font(.body.weight(.semibold)).foregroundStyle(p.text)
                Spacer(minLength: 4)
                HabitStepButton(icon: "minus", enabled: draft.target > 2) { draft.target = max(2, draft.target - 1) }
                Text(targetText).font(.system(size: 20, weight: .heavy, design: p.fontDesign))
                    .foregroundStyle(p.text).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minWidth: 64)
                HabitStepButton(icon: "plus", enabled: draft.target < 99) { draft.target = min(99, max(2, draft.target) + 1) }
            }
            TextField("単位（例：杯・回・ページ）", text: $draft.unit)
                .foregroundStyle(p.text)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(p.sub.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text("1日1回、タップしてチェックします。").font(.footnote).foregroundStyle(p.sub)
        }
    }

    private var targetText: String {
        let unit: String = draft.unit.isEmpty ? "回" : draft.unit
        return "\(max(2, draft.target))\(unit)"
    }

    @ViewBuilder
    private var weekdays: some View {
        HStack(spacing: 6) {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                dayButton(wd)
            }
        }
        HStack(spacing: 8) {
            quick("毎日", Array(1...7))
            quick("平日", [2, 3, 4, 5, 6])
            quick("週末", [1, 7])
        }
        if draft.weekdays.isEmpty {
            Text("曜日を1つ以上選んでください").font(.footnote.weight(.semibold)).foregroundStyle(p.overdue)
        }
    }

    private func dayButton(_ wd: Int) -> some View {
        let on: Bool = draft.weekdays.contains(wd)
        let fg: Color = on ? p.onAccent : p.sub
        let bg: Color = on ? p.accent : p.sub.opacity(0.12)
        return Button {
            if on { draft.weekdays.removeAll { $0 == wd } } else { draft.weekdays.append(wd) }
        } label: {
            Text(HabitData.weekdaySymbol(wd)).font(.subheadline.weight(.bold)).foregroundStyle(fg)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private var reminder: some View {
        Toggle(isOn: $reminderOn.animation()) {
            Text("決まった時刻に知らせる").font(.body.weight(.semibold)).foregroundStyle(p.text)
        }
        .tint(p.accent)
        if reminderOn {
            DatePicker(selection: $reminderTime, displayedComponents: .hourAndMinute) {
                Text("時刻").foregroundStyle(p.text)
            }
            Text("選んだ曜日のこの時刻に通知します。").font(.footnote).foregroundStyle(p.sub)
        }
    }

    private func quick(_ title: String, _ days: [Int]) -> some View {
        let on: Bool = Set(draft.weekdays) == Set(days)
        let fg: Color = on ? p.accent : p.text
        let bg: Color = on ? p.accent.opacity(0.15) : p.sub.opacity(0.1)
        return Button { draft.weekdays = days } label: {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(fg)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        var h = draft
        h.name = h.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        h.unit = h.unit.trimmingCharacters(in: .whitespaces)
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

/// −・＋の丸いボタン（数を変える）
struct HabitStepButton: View {
    @Environment(\.palette) private var p
    let icon: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        let fg: Color = enabled ? p.accent : p.sub.opacity(0.4)
        let bg: Color = enabled ? p.accent.opacity(0.14) : p.sub.opacity(0.08)
        return Button(action: action) {
            Image(systemName: icon).font(.headline.weight(.bold)).foregroundStyle(fg)
                .frame(width: 36, height: 36)
                .background(bg, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(icon == "plus" ? "増やす" : "減らす")
    }
}
