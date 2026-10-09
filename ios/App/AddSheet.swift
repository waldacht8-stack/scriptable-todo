import SwiftUI

// MARK: - 追加・編集（draft.item があれば編集）

/// TODO の追加・編集画面。大きな題名の欄と、期限・時刻・繰り返しのチップ、下の大きな「追加」ボタン。
/// 新しく追加するときは、題名の「明日15時」「毎週」などを読み取ってチップに反映する（QuickParse）。
struct AddSheet: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduce
    let draft: AddDraft

    @State private var title = ""
    @State private var note = ""
    @State private var important = false
    // 手で選んだ期限（day は 0 時、time が nil なら終日）
    @State private var day: Date?
    @State private var time: DateComponents?
    @State private var repeatRule = ""
    @State private var picked: DueChoice?
    /// チップを触ったら手で選んだ期限を使う。題名から新しく期限を読み取ったら、また読み取りを使う
    @State private var dueTouched = false
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var toCalendar = false
    @State private var calendarTitle = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var editing: TodoItem? { draft.item }
    private var isNew: Bool { editing == nil }
    private var parsed: QuickParseResult { QuickParse.parse(title) }
    private var useParse: Bool { isNew && !dueTouched && parsed.hasSchedule }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: 実際に使う期限（読み取り or 手で選んだもの）

    private var effDay: Date? {
        if useParse { return parsed.due.map { Calendar.current.startOfDay(for: $0) } }
        return day
    }

    private var effTime: DateComponents? {
        if useParse {
            guard let d = parsed.due, !parsed.allDay else { return nil }
            return Calendar.current.dateComponents([.hour, .minute], from: d)
        }
        return time
    }

    private var effRepeat: String { useParse ? (parsed.repeatRule ?? "") : repeatRule }

    private var dueDate: Date? {
        guard let d = effDay else { return nil }
        guard let t = effTime else { return d }
        return Calendar.current.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: d) ?? d
    }

    private var dueSummary: String {
        guard let d = dueDate else { return "期限なし" }
        var s: String = Self.dayName(d)
        s += effTime == nil ? "・終日" : " " + JP.time(d)
        if let r = RepeatRule(rawValue: effRepeat) { s += "・" + Self.shortRepeat(r) }
        return s
    }

    // MARK: 画面

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleCard
                    dueCard
                    if effDay != nil { timeCard }
                    if effDay != nil { repeatCard }
                    memoCard
                    if isNew && dueDate != nil && CalendarSync.authorized { calendarCard }
                    if let item = editing, item.isCalendar {
                        Label("カレンダーから取り込んだTODOです。ここで変えた内容はカレンダーには反映されません。", systemImage: "calendar")
                            .font(.footnote).foregroundStyle(p.sub)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .onAppear(perform: load)
        .onChange(of: QuickParse.summary(parsed)) { _, new in
            if new != nil { dueTouched = false } // 新しく読み取れた期限を優先
        }
        .confirmationDialog("このTODOを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let item = editing { store.delete(item) }
                dismiss()
            }
        }
        .sensoryFeedback(.selection, trigger: dueSummary)
    }

    private var topBar: some View {
        ZStack {
            Text(isNew ? "TODOを追加" : "TODOを編集").font(.headline.weight(.bold)).foregroundStyle(p.text)
            HStack {
                Button("キャンセル") { dismiss() }
                    .font(.body.weight(.semibold)).foregroundStyle(p.accent)
                Spacer()
            }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
    }

    // MARK: 題名

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                TextField("何をする？", text: $title, axis: .vertical)
                    .font(.system(size: 24, weight: .bold, design: p.fontDesign))
                    .foregroundStyle(p.text)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.done)
                    .onChange(of: title) { _, new in
                        // 改行（確定）はキーボードを閉じる合図にする
                        if new.contains("\n") {
                            title = new.replacingOccurrences(of: "\n", with: "")
                            focused = false
                        }
                    }
                importantButton
            }
            parsePreview
        }
        .paletteCard(p, padding: 16)
        .animation(motion.change(reduce: reduce), value: QuickParse.summary(parsed))
    }

    private var importantButton: some View {
        Button { withAnimation(motion.tap(reduce: reduce)) { important.toggle() } } label: {
            VStack(spacing: 2) {
                Image(systemName: important ? "star.fill" : "star")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(important ? Color.yellow : p.sub)
                    .symbolEffect(.bounce, value: important)
                    .symbolEffectsRemoved(reduce)
                Text("重要").font(.caption2.weight(.bold)).foregroundStyle(important ? p.text : p.sub)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(important ? "重要を外す" : "重要にする")
        .sensoryFeedback(.selection, trigger: important)
    }

    /// 題名から読み取った期限・繰り返し（新しく追加するときだけ）
    @ViewBuilder private var parsePreview: some View {
        if isNew {
            if parsed.hasSchedule {
                let q: QuickParseResult = parsed
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    previewChip(icon: "wand.and.stars", text: "読み取り", strong: false)
                    if let d = q.due {
                        previewChip(icon: "calendar", text: Self.dayName(d) + (q.allDay ? "" : " " + JP.time(d)), strong: useParse)
                    }
                    if let r = q.repeatRule.flatMap(RepeatRule.init(rawValue:)) {
                        previewChip(icon: "repeat", text: Self.shortRepeat(r), strong: useParse)
                    }
                    if q.title != trimmedTitle && !q.title.isEmpty {
                        previewChip(icon: "character.cursor.ibeam", text: "「\(q.title)」で追加", strong: false)
                    }
                }
            } else if trimmedTitle.isEmpty {
                Text("「明日15時 美容院」「毎週月曜 ゴミ出し」のように書くと、期限と繰り返しも入ります。")
                    .font(.footnote).foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func previewChip(icon: String, text: String, strong: Bool) -> some View {
        let fg: Color = strong ? p.accent : p.sub
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(text).font(.footnote.weight(.bold)).lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(fg.opacity(0.12), in: Capsule())
    }

    // MARK: 期限

    private var dueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("期限", icon: "flag", value: dueSummary)
            FlowLayout {
                ChoiceChip(title: "なし", selected: effDay == nil) { clearDue() }
                ForEach(DueChoice.allCases) { c in
                    ChoiceChip(title: c.name, icon: c.icon, selected: selectedChoice == c) { choose(c) }
                }
                ChoiceChip(title: customDateLabel ?? "日付を選ぶ", icon: "calendar.badge.plus",
                           selected: showDatePicker || customDateLabel != nil) { toggleDatePicker() }
            }
            if showDatePicker {
                DatePicker("日付", selection: dayBinding, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(p.accent)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }
        }
        .paletteCard(p, padding: 16)
    }

    /// 選ばれている期限のチップ（金曜の「明日」と「週末」のように同じ日になるものは、押したほうを優先）
    private var selectedChoice: DueChoice? {
        guard let d = effDay else { return nil }
        let t: DateComponents? = effTime
        func matches(_ c: DueChoice) -> Bool {
            let r = c.resolve()
            guard r.day == d else { return false }
            let isTonight: Bool = t != nil && t?.hour == DueChoice.tonight.resolve().time?.hour
            if c == .tonight { return isTonight }
            if c == .today { return !isTonight }
            return true
        }
        if let picked, matches(picked) { return picked }
        return DueChoice.allCases.first(where: matches)
    }

    /// どのチップにも当てはまらない日なら、その日付を「日付を選ぶ」の所に出す
    private var customDateLabel: String? {
        guard let d = effDay, selectedChoice == nil else { return nil }
        return JP.date(d)
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { day ?? Calendar.current.startOfDay(for: .now) },
                set: { day = Calendar.current.startOfDay(for: $0); picked = nil })
    }

    private func toggleDatePicker() {
        touch()
        if day == nil { day = Calendar.current.startOfDay(for: .now) }
        withAnimation(motion.tap(reduce: reduce)) { showDatePicker.toggle() }
    }

    private func choose(_ c: DueChoice) {
        let wasSelected: Bool = selectedChoice == c
        touch()
        if wasSelected { clearDue(); return }
        let r = c.resolve()
        withAnimation(motion.tap(reduce: reduce)) {
            day = r.day
            picked = c
            if c == .tonight {
                time = r.time
            } else if c == .today && sameTime(time, DueChoice.tonight.resolve().time) {
                time = nil
            }
            showDatePicker = false
        }
    }

    private func clearDue() {
        touch()
        withAnimation(motion.tap(reduce: reduce)) {
            day = nil
            time = nil
            repeatRule = ""
            picked = nil
            showDatePicker = false
            showTimePicker = false
            toCalendar = false
        }
    }

    /// 手で選び始めたとき、いまの値（読み取った期限）を引き継ぐ
    private func touch() {
        guard !dueTouched else { return }
        if useParse {
            day = effDay
            time = effTime
            repeatRule = effRepeat
        }
        dueTouched = true
    }

    // MARK: 時刻

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("時刻", icon: "clock", value: nil)
            FlowLayout {
                ForEach(TimeChoice.allCases) { c in
                    ChoiceChip(title: c.name, selected: !showTimePicker && sameTime(effTime, c.time)) {
                        touch()
                        withAnimation(motion.tap(reduce: reduce)) { time = c.time; showTimePicker = false }
                    }
                }
                ChoiceChip(title: customTimeLabel ?? "時刻を選ぶ", icon: "clock.badge",
                           selected: showTimePicker || customTimeLabel != nil) {
                    touch()
                    if time == nil { time = DateComponents(hour: 9, minute: 0) }
                    withAnimation(motion.tap(reduce: reduce)) { showTimePicker.toggle() }
                }
            }
            if showTimePicker {
                DatePicker("時刻", selection: timeBinding, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            }
        }
        .paletteCard(p, padding: 16)
    }

    private var customTimeLabel: String? {
        guard let t = effTime, !TimeChoice.allCases.contains(where: { sameTime(t, $0.time) }) else { return nil }
        return String(format: "%d:%02d", t.hour ?? 0, t.minute ?? 0)
    }

    private func sameTime(_ a: DateComponents?, _ b: DateComponents?) -> Bool {
        a?.hour == b?.hour && a?.minute == b?.minute
    }

    private var timeBinding: Binding<Date> {
        Binding(get: {
            let t: DateComponents = time ?? DateComponents(hour: 9, minute: 0)
            return Calendar.current.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: .now) ?? .now
        }, set: {
            time = Calendar.current.dateComponents([.hour, .minute], from: $0)
        })
    }

    // MARK: 繰り返し

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("繰り返し", icon: "repeat", value: nil)
            FlowLayout {
                ChoiceChip(title: "しない", selected: effRepeat.isEmpty) { touch(); repeatRule = "" }
                ForEach(RepeatRule.allCases) { r in
                    ChoiceChip(title: Self.shortRepeat(r), selected: effRepeat == r.rawValue) { touch(); repeatRule = r.rawValue }
                }
            }
        }
        .paletteCard(p, padding: 16)
    }

    private static func shortRepeat(_ r: RepeatRule) -> String {
        r == .weekdays ? "平日" : r.name
    }

    // MARK: メモ・カレンダー

    private var memoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("メモ", icon: "note.text", value: nil)
            TextField("気をつけること、持ち物など", text: $note, axis: .vertical)
                .font(.body).foregroundStyle(p.text)
                .lineLimit(2...6)
        }
        .paletteCard(p, padding: 16)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $toCalendar.animation(motion.change(reduce: reduce))) {
                Label("カレンダーにも予定として登録", systemImage: "calendar.badge.plus")
                    .font(.body.weight(.semibold)).foregroundStyle(p.text)
            }
            .tint(p.accent)
            if toCalendar {
                Picker("登録先", selection: $calendarTitle) {
                    Text("いつものカレンダー").tag("")
                    ForEach(CalendarSync.writableCalendars(), id: \.calendarIdentifier) { Text($0.title).tag($0.title) }
                }
                .pickerStyle(.menu)
                .tint(p.accent)
            }
        }
        .paletteCard(p, padding: 16)
    }

    private func sectionTitle(_ text: String, icon: String, value: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(p.accent)
            Text(text).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(effDay == nil ? p.sub : p.accent)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: 下のボタン

    private var bottomBar: some View {
        let empty: Bool = trimmedTitle.isEmpty
        let shape = RoundedRectangle(cornerRadius: min(p.radius, 20), style: .continuous)
        return VStack(spacing: 10) {
            if let item = editing {
                HStack(spacing: 10) {
                    secondaryButton(item.done ? "未完了に戻す" : "完了にする",
                                    icon: item.done ? "arrow.uturn.backward" : "checkmark", color: p.text) {
                        if item.done { store.uncomplete(item) } else { store.complete(item) }
                        dismiss()
                    }
                    secondaryButton("削除", icon: "trash", color: p.overdue) { confirmDelete = true }
                }
            }
            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: isNew ? "plus" : "checkmark").font(.headline.weight(.bold))
                    Text(isNew ? "追加" : "保存").font(.title3.weight(.bold))
                }
                .foregroundStyle(p.onAccent)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(p.accent.opacity(empty ? 0.4 : 1), in: shape)
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .disabled(empty)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    private func secondaryButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.bold)).foregroundStyle(color)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(p.card, in: RoundedRectangle(cornerRadius: min(p.radius, 16), style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 読み込み・保存

    private func load() {
        guard !loaded else { return }
        loaded = true
        let cal = Calendar.current
        if let item = editing {
            title = item.title
            important = item.isImportant
            note = item.note ?? ""
            repeatRule = item.repeatRule ?? ""
            if let d = item.due {
                day = cal.startOfDay(for: d)
                time = item.isAllDay ? nil : cal.dateComponents([.hour, .minute], from: d)
            }
            dueTouched = true
        } else {
            if let d = draft.due {
                day = cal.startOfDay(for: d)
                time = draft.allDay ? nil : cal.dateComponents([.hour, .minute], from: d)
            }
            if let t = draft.title { title = t } else { focused = true }
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let q: QuickParseResult = parsed
        let name: String = isNew && q.hasSchedule ? q.title : trimmedTitle   // 読み取った語は題名から外す
        let due: Date? = dueDate
        let allDay: Bool = due != nil && effTime == nil
        let rule: String? = due != nil && !effRepeat.isEmpty ? effRepeat : nil
        if var item = editing {
            item.title = name
            item.due = due
            item.allDay = allDay ? true : nil
            item.note = note.isEmpty ? nil : note
            item.repeatRule = rule
            item.important = important ? true : nil
            store.save(item)
        } else {
            store.add(name, due: due, allDay: allDay, note: note, repeatRule: rule, important: important,
                      toCalendar: due != nil && toCalendar ? calendarTitle : nil)
        }
        dismiss()
    }

    /// 「今日」「明日」「10月12日（月）」
    private static func dayName(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今日" }
        if cal.isDateInTomorrow(d) { return "明日" }
        if cal.isDateInYesterday(d) { return "昨日" }
        return JP.date(d)
    }
}
