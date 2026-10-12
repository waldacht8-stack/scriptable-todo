import SwiftUI

/// 家計簿の設定：給料日・振り込み元・目標貯金・覚えた分類・取り込みの既定と列の対応
struct KakeiboSettingsView: View {
    @ObservedObject var store: KakeiboStore
    @Environment(\.palette) private var p
    @State private var employerText = ""
    @FocusState private var employerFocused: Bool
    @State private var goalText = ""
    @FocusState private var goalFocused: Bool

    var body: some View {
        List {
            paySection
            goalSection
            reminderSection
            learnedSection
            importSection
        }
        .scrollContentBackground(.hidden)
        .paletteBackground(p)
        .navigationTitle("家計簿の設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            employerText = store.settings.employer
            goalText = store.settings.savingsGoal.map { String($0.amount) } ?? ""
        }
    }

    // MARK: 給料日・振り込み元

    private var paySection: some View {
        let cycle: KakeiboCycle.Period = store.cycle(offset: 0)
        return Section {
            Picker(selection: Binding(get: { store.settings.payday ?? 0 },
                                      set: { v in store.updateSettings { $0.payday = KakeiboCycle.validDay(v) } })) {
                Text("決めない（暦の月）").tag(0)
                ForEach(1...30, id: \.self) { d in Text("\(d)日").tag(d) }
                Text("月末").tag(31)
            } label: {
                Text("給料日").foregroundStyle(p.text)
            }
            .tint(p.accent)
            .listRowBackground(p.card)
            HStack {
                Text("振り込み元").foregroundStyle(p.text)
                Spacer()
                TextField("会社名（例：ミホンショウジ）", text: $employerText)
                    .multilineTextAlignment(.trailing)
                    .focused($employerFocused)
                    .submitLabel(.done)
                    .onSubmit(saveEmployer)
            }
            .listRowBackground(p.card)
            .onChange(of: employerFocused) { _, f in if !f { saveEmployer() } }
            HStack {
                Text("いまの周期").foregroundStyle(p.text)
                Spacer()
                Text("\(cycle.title) ・ \(cycle.rangeText)").foregroundStyle(p.sub).monospacedDigit()
            }
            .listRowBackground(p.card)
        } header: {
            header("給料")
        } footer: {
            Text("家計簿の「1か月」は、給料日から次の給料日の前の日までです（給料日 25 日なら 9/25〜10/24 が「10月分」）。給料日が土日・祝日なら、前の営業日を給料日にします。振り込み元は、明細の収入の行にこの名前があれば「給料」にします。通帳の書き方（カタカナなど）で入れると確実です。「、」で区切ると、いくつも入れられます")
                .font(.caption).foregroundStyle(p.sub)
        }
    }

    private func saveEmployer() {
        let v = employerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard v != store.settings.employer else { return }
        store.updateSettings { $0.employer = v }
        store.applyEmployer()
    }

    // MARK: 目標貯金

    private var goalSection: some View {
        let goal: KakeiboSavingsGoal? = store.settings.savingsGoal
        return Section {
            HStack {
                Text("目標の総額").foregroundStyle(p.text)
                Spacer()
                TextField("500000", text: $goalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($goalFocused)
                    .frame(maxWidth: 140)
                    .onSubmit(saveGoal)
                Text("円").foregroundStyle(p.sub)
            }
            .listRowBackground(p.card)
            .onChange(of: goalFocused) { _, f in if !f { saveGoal() } }
            if let goal {
                DatePicker("期限（この月分まで）", selection: goalBinding(\.deadline, goal), in: Date.now..., displayedComponents: .date)
                    .foregroundStyle(p.text)
                    .listRowBackground(p.card)
                DatePicker("数えはじめ", selection: goalBinding(\.start, goal), in: ...Date.now, displayedComponents: .date)
                    .foregroundStyle(p.text)
                    .listRowBackground(p.card)
                Button("目標をやめる", role: .destructive) {
                    store.updateSettings { $0.savingsGoal = nil }
                    goalText = ""
                }
                .listRowBackground(p.card)
            }
        } header: {
            header("目標貯金")
        } footer: {
            Text("数えはじめの日を含む周期から、周期ごとの「収入 − 支出」を積み上げます。ホームに、月にいくら残せばよいかと、今の周期が目標どおりかを出します")
                .font(.caption).foregroundStyle(p.sub)
        }
    }

    private func goalBinding(_ key: WritableKeyPath<KakeiboSavingsGoal, Date>, _ goal: KakeiboSavingsGoal) -> Binding<Date> {
        Binding(
            get: { store.settings.savingsGoal?[keyPath: key] ?? goal[keyPath: key] },
            set: { d in store.updateSettings { s in s.savingsGoal?[keyPath: key] = d } }
        )
    }

    private func saveGoal() {
        let v: Int = Int(goalText.filter(\.isNumber)) ?? 0
        if v <= 0 {
            goalText = store.settings.savingsGoal.map { String($0.amount) } ?? ""
            return
        }
        let cycle: KakeiboCycle.Period = store.cycle(offset: 0)
        store.updateSettings { s in
            if s.savingsGoal != nil {
                s.savingsGoal?.amount = v
            } else {
                // はじめて決めたとき：期限は半年後の月分、数えはじめは今の周期
                let deadline: Date = KakeiboMonth.start(cycle.label, offset: 6)
                s.savingsGoal = KakeiboSavingsGoal(amount: v, deadline: deadline, start: cycle.start)
            }
        }
        goalText = String(v)
    }

    // MARK: 取り込みのお知らせ

    private var reminderSection: some View {
        let r: KakeiboReminderSettings = store.settings.reminder
        let cards: [KakeiboInstitution] = KakeiboInstitution.allCases.filter(KakeiboReminders.isCard)
        return Section {
            Toggle(isOn: Binding(get: { store.settings.reminder.enabled },
                                 set: { v in store.updateSettings { $0.reminder.enabled = v } })) {
                Text("取り込みのお知らせ").foregroundStyle(p.text)
            }
            .tint(p.accent)
            .listRowBackground(p.card)
            if r.enabled {
                DatePicker("お知らせの時刻", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .foregroundStyle(p.text)
                    .listRowBackground(p.card)
                ForEach(cards) { i in
                    Stepper(value: cardDayBinding(i), in: 1...28) {
                        HStack {
                            Text("\(i.name) の明細の確定日").foregroundStyle(p.text)
                            Spacer()
                            Text("\(r.cardDay(i))日ごろ").foregroundStyle(p.sub).monospacedDigit()
                        }
                    }
                    .listRowBackground(p.card)
                }
            }
        } header: {
            header("取り込みのお知らせ")
        } footer: {
            Text("銀行は給料日の次の日、カードは明細の確定日にお知らせします。どちらも \(KakeiboReminders.fallbackDays) 日取り込んでいなければお知らせします。お知らせを押すと、その明細の取り込みを開きます")
                .font(.caption).foregroundStyle(p.sub)
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                let r = store.settings.reminder
                return Calendar.current.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: .now) ?? .now
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                store.updateSettings { s in
                    s.reminder.hour = c.hour ?? 20
                    s.reminder.minute = c.minute ?? 0
                }
            }
        )
    }

    private func cardDayBinding(_ i: KakeiboInstitution) -> Binding<Int> {
        Binding(
            get: { store.settings.reminder.cardDay(i) },
            set: { v in store.updateSettings { $0.reminder.cardDays[i.rawValue] = v } }
        )
    }

    // MARK: 覚えた分類（記録の分類を直したもの）

    @ViewBuilder private var learnedSection: some View {
        let rules: [KakeiboRule] = store.settings.rules
        Section {
            if rules.isEmpty {
                Text("まだありません").foregroundStyle(p.sub).listRowBackground(p.card)
            }
            ForEach(rules) { r in
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(p.accent)
                    Text(r.keyword).foregroundStyle(p.text).lineLimit(1)
                    Spacer()
                    Circle().fill(KakeiboStyle.color(r.category)).frame(width: 8, height: 8)
                    Text(r.category).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                }
                .listRowBackground(p.card)
            }
            .onDelete { idx in store.updateSettings { $0.rules.remove(atOffsets: idx) } }
        } header: {
            header("覚えた分類")
        } footer: {
            Text("分類は取引先の名前から自動で決めます（ETC は交通、ENEOS は車・ガソリン、Amazon は買い物 など）。合わなければ記録をタップして直すと、ここに覚えて次から使います。左へ払うと忘れます")
                .font(.caption).foregroundStyle(p.sub)
        }
    }

    // MARK: 取り込み

    private var importSection: some View {
        Section {
            Toggle(isOn: Binding(get: { store.settings.excludeTransfers },
                                 set: { v in store.updateSettings { $0.excludeTransfers = v } })) {
                Text("カードの引き落とし・振替を合計に入れない").foregroundStyle(p.text)
            }
            .tint(p.accent)
            .listRowBackground(p.card)
            ForEach(KakeiboInstitution.allCases) { i in
                HStack {
                    Text("列の対応：\(i.name)").foregroundStyle(p.text)
                    Spacer()
                    if store.settings.mappings[i.rawValue] != nil {
                        Button("忘れる") { store.updateSettings { $0.mappings[i.rawValue] = nil } }
                            .foregroundStyle(p.accent)
                    } else {
                        Text("まだ").foregroundStyle(p.sub)
                    }
                }
                .listRowBackground(p.card)
            }
        } header: {
            header("取り込み")
        } footer: {
            Text("銀行の明細にあるカードの引き落とし（十六カード・JCB・ニコス など）は、カードの明細で1件ずつ数えるので合計に入れません。同じ取引がほかの明細や前の取り込みにあれば、1件だけ残します")
                .font(.caption).foregroundStyle(p.sub)
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.bold)).foregroundStyle(p.sub)
    }
}
