import SwiftUI

/// 起床の設定（曜日・時刻・段階・就寝・ルーティン・持ち物・祝日）
struct WakeSettingsView: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p
    @State private var newRoutine = ""
    @State private var newRoutineMinutes = 5
    @State private var newBelonging = ""
    @State private var testMessage = ""

    static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]
    /// 月曜から並べる
    static let order = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        Form {
            Section {
                ForEach(Self.order, id: \.self) { i in
                    NavigationLink {
                        WakeDayEditor(model: model, index: i)
                    } label: {
                        dayRow(i)
                    }
                }
            } header: {
                Text("曜日ごとの起床")
            } footer: {
                Text("オンの曜日だけアラームが鳴ります。出発時刻を決めると、チェックイン後にカウントダウンします。")
            }
            .listRowBackground(p.card)

            Section {
                Stepper("段階の数：\(model.settings.stages.count)", value: stageCount, in: 1...4)
                ForEach(model.settings.stages.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.headline).foregroundStyle(p.onAccent)
                            .frame(width: 28, height: 28).background(p.accent, in: Circle())
                        TextField("名前", text: stageName(i)).frame(maxWidth: .infinity)
                        Stepper("+\(model.settings.stages[i].offset)分", value: stageOffset(i), in: 0...120, step: 5)
                            .fixedSize()
                    }
                }
            } header: {
                Text("段階アラーム")
            } footer: {
                Text("起床時刻からのずれ（分）。チェックインするまで、次の段階が順に鳴ります。点数：段階1=100、2=85、3=70、4=40")
            }
            .listRowBackground(p.card)

            Section {
                DatePicker("就寝時刻", selection: minutesBinding(\.bedtime), displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
            } footer: {
                Text("就寝の30分前に、次の起床時刻と段階の数を通知します。")
            }
            .listRowBackground(p.card)

            Section {
                ForEach(model.settings.routine.indices, id: \.self) { i in
                    HStack {
                        TextField("項目", text: routineName(i))
                        Stepper("\(model.settings.routine[i].minutes)分", value: routineMinutes(i), in: 1...60).fixedSize()
                    }
                }
                .onMove { from, to in model.update { $0.routine.move(fromOffsets: from, toOffset: to) } }
                .onDelete { idx in model.update { $0.routine.remove(atOffsets: idx) } }
                HStack {
                    TextField("項目を追加", text: $newRoutine)
                    Stepper("\(newRoutineMinutes)分", value: $newRoutineMinutes, in: 1...60).fixedSize()
                    Button {
                        let t = newRoutine.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        model.update { $0.routine.append(WakeRoutineItem(name: t, minutes: newRoutineMinutes)) }
                        newRoutine = ""
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(p.accent)
                }
            } header: {
                Text("朝のルーティン")
            } footer: {
                Text("右上の「編集」で並べ替え・削除ができます。")
            }
            .listRowBackground(p.card)

            Section {
                ForEach(model.settings.belongings.indices, id: \.self) { i in
                    TextField("持ち物", text: belongingName(i))
                }
                .onMove { from, to in model.update { $0.belongings.move(fromOffsets: from, toOffset: to) } }
                .onDelete { idx in model.update { $0.belongings.remove(atOffsets: idx) } }
                HStack {
                    TextField("持ち物を追加", text: $newBelonging)
                    Button {
                        let t = newBelonging.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        model.update { $0.belongings.append(WakeBelonging(name: t)) }
                        newBelonging = ""
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(p.accent)
                }
            } header: {
                Text("持ち物")
            } footer: {
                Text("出発の5分前に通知します。")
            }
            .listRowBackground(p.card)

            Section {
                Toggle("祝日は鳴らさない", isOn: Binding(
                    get: { model.settings.skipHolidays },
                    set: { v in
                        model.update { $0.skipHolidays = v }
                        if v { Task { _ = await WakeHolidays.requestAccess(); model.scheduleAll() } }
                    }))
                Toggle("すべてのアラームを止める", isOn: Binding(
                    get: { model.settings.paused },
                    set: { v in model.update { $0.paused = v } }))
            } footer: {
                Text("祝日は、名前に「祝日」か「Holiday」を含むカレンダーから読み取ります。")
            }
            .listRowBackground(p.card)

            Section {
                Button("アラームを今すぐ予約し直す") { model.scheduleAll() }
                if !model.message.isEmpty { Text(model.message).font(.footnote).foregroundStyle(p.sub) }
                Button("1分後にテストアラーム") {
                    Task { testMessage = await AlarmTest.scheduleInOneMinute() }
                }
                if !testMessage.isEmpty { Text(testMessage).font(.footnote).foregroundStyle(p.sub) }
            } header: {
                Text("アラーム")
            } footer: {
                Text("マナーモード・画面ロック中でも鳴ります。アラームの画面の「起きた！」でチェックインできます。")
            }
            .listRowBackground(p.card)
        }
        .scrollContentBackground(.hidden)
        .paletteBackground(p)
        .navigationTitle("起床の設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { EditButton() }
    }

    private func dayRow(_ i: Int) -> some View {
        let d = model.settings.days[i]
        return HStack(spacing: 12) {
            Text(Self.weekdayNames[i]).font(.headline).foregroundStyle(d.on ? p.onAccent : p.sub)
                .frame(width: 32, height: 32)
                .background(d.on ? p.accent : p.sub.opacity(0.15), in: Circle())
            if d.on {
                Text(WakeLogic.clock(d.wake)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(p.text)
                Spacer(minLength: 0)
                Text(d.departure.map { "出発 \(WakeLogic.clock($0))" } ?? "出発なし").font(.subheadline).foregroundStyle(p.sub)
            } else {
                Text("オフ").font(.title3.weight(.semibold)).foregroundStyle(p.sub)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 値の受け渡し

    private var stageCount: Binding<Int> {
        Binding(get: { model.settings.stages.count }, set: { n in
            model.update { s in
                while s.stages.count < n {
                    let i = s.stages.count
                    s.stages.append(WakeStage(name: WakeSettings.stageNames[min(i, 3)],
                                              offset: (s.stages.last?.offset ?? -10) + 10))
                }
                if s.stages.count > n { s.stages.removeLast(s.stages.count - n) }
            }
        })
    }

    private func stageName(_ i: Int) -> Binding<String> {
        Binding(get: { i < model.settings.stages.count ? model.settings.stages[i].name : "" },
                set: { v in model.update { if i < $0.stages.count { $0.stages[i].name = v } } })
    }

    private func stageOffset(_ i: Int) -> Binding<Int> {
        Binding(get: { i < model.settings.stages.count ? model.settings.stages[i].offset : 0 },
                set: { v in model.update { if i < $0.stages.count { $0.stages[i].offset = v } } })
    }

    private func routineName(_ i: Int) -> Binding<String> {
        Binding(get: { i < model.settings.routine.count ? model.settings.routine[i].name : "" },
                set: { v in model.update { if i < $0.routine.count { $0.routine[i].name = v } } })
    }

    private func routineMinutes(_ i: Int) -> Binding<Int> {
        Binding(get: { i < model.settings.routine.count ? model.settings.routine[i].minutes : 5 },
                set: { v in model.update { if i < $0.routine.count { $0.routine[i].minutes = v } } })
    }

    private func belongingName(_ i: Int) -> Binding<String> {
        Binding(get: { i < model.settings.belongings.count ? model.settings.belongings[i].name : "" },
                set: { v in model.update { if i < $0.belongings.count { $0.belongings[i].name = v } } })
    }

    private func minutesBinding(_ key: WritableKeyPath<WakeSettings, Int>) -> Binding<Date> {
        Binding(get: { WakeTime.date(model.settings[keyPath: key]) },
                set: { d in model.update { $0[keyPath: key] = WakeTime.minutes(d) } })
    }
}

/// 分（0時から）と DatePicker の日時の変換
enum WakeTime {
    static func date(_ m: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .minute, value: ((m % 1440) + 1440) % 1440, to: start) ?? start
    }

    static func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// 1つの曜日の編集
struct WakeDayEditor: View {
    @ObservedObject var model: WakeViewModel
    @Environment(\.palette) private var p
    let index: Int

    private var day: WakeDay { model.settings.days[index] }

    var body: some View {
        Form {
            Section {
                Toggle("この曜日に起きる", isOn: Binding(get: { day.on }, set: { v in model.update { $0.days[index].on = v } }))
                if day.on {
                    DatePicker("起床時刻（段階1）", selection: Binding(
                        get: { WakeTime.date(day.wake) },
                        set: { d in model.update { $0.days[index].wake = WakeTime.minutes(d) } }),
                               displayedComponents: .hourAndMinute)
                }
            }
            .listRowBackground(p.card)

            Section {
                Toggle("出発時刻を決める", isOn: Binding(
                    get: { day.departure != nil },
                    set: { v in model.update { $0.days[index].departure = v ? ($0.days[index].wake + 60) % 1440 : nil } }))
                if let dep = day.departure {
                    DatePicker("出発時刻", selection: Binding(
                        get: { WakeTime.date(dep) },
                        set: { d in model.update { $0.days[index].departure = WakeTime.minutes(d) } }),
                               displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("出発の5分前に持ち物を通知し、チェックイン後に出発までの時間を表示します。")
            }
            .listRowBackground(p.card)

            if day.on {
                Section("この日の段階") {
                    ForEach(Array(model.settings.stages.enumerated()), id: \.offset) { i, st in
                        HStack {
                            Text("段階\(i + 1)　\(st.name)").foregroundStyle(p.text)
                            Spacer()
                            Text(WakeLogic.clock(day.wake + st.offset)).monospacedDigit().foregroundStyle(p.sub)
                        }
                    }
                }
                .listRowBackground(p.card)
            }

            Section {
                Button("ほかの平日にも同じ時刻を使う") {
                    let day = self.day
                    model.update { s in
                        for i in 1...5 where i != index {
                            s.days[i].on = day.on
                            s.days[i].wake = day.wake
                            s.days[i].departure = day.departure
                        }
                    }
                }
            }
            .listRowBackground(p.card)
        }
        .environment(\.locale, Locale(identifier: "ja_JP"))
        .scrollContentBackground(.hidden)
        .paletteBackground(p)
        .navigationTitle("\(WakeSettingsView.weekdayNames[index])曜日")
        .navigationBarTitleDisplayMode(.inline)
    }
}
