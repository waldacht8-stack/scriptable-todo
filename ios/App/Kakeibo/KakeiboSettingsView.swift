import SwiftUI

/// 家計簿の設定：予算・分類（足す・消す・並べ替え）・分類の決まり（覚えたものも）・列の対応・取り込みの既定
struct KakeiboSettingsView: View {
    @ObservedObject var store: KakeiboStore
    @Environment(\.palette) private var p
    @State private var budgetText = ""
    @State private var newCategory = ""
    @State private var newKeyword = ""
    @State private var newRuleCategory = "食費"
    @FocusState private var budgetFocused: Bool

    var body: some View {
        List {
            budgetSection
            categorySection
            ruleSection
            importSection
        }
        .scrollContentBackground(.hidden)
        .paletteBackground(p)
        .navigationTitle("家計簿の設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .onAppear { budgetText = String(store.settings.budget) }
    }

    // MARK: 予算

    private var budgetSection: some View {
        Section {
            HStack {
                Text("1か月の予算").foregroundStyle(p.text)
                Spacer()
                TextField("50000", text: $budgetText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($budgetFocused)
                    .frame(maxWidth: 140)
                    .onSubmit(saveBudget)
                Text("円").foregroundStyle(p.sub)
            }
            .listRowBackground(p.card)
            .onChange(of: budgetFocused) { _, f in if !f { saveBudget() } }
        } header: {
            header("予算")
        } footer: {
            Text("ホームの「残り」とウィジェットに使います。0 にすると予算なし").font(.caption).foregroundStyle(p.sub)
        }
    }

    private func saveBudget() {
        let v = max(0, Int(budgetText.filter(\.isNumber)) ?? store.settings.budget)
        store.updateSettings { $0.budget = v }
        budgetText = String(v)
    }

    // MARK: 分類

    private var categorySection: some View {
        Section {
            ForEach(store.settings.categories, id: \.self) { c in
                HStack(spacing: 10) {
                    Circle().fill(KakeiboStyle.color(c)).frame(width: 10, height: 10)
                    Text(c).foregroundStyle(p.text)
                }
                .listRowBackground(p.card)
            }
            .onDelete { idx in
                store.updateSettings { s in
                    let keep = s.categories.count - idx.count >= 1
                    if keep { s.categories.remove(atOffsets: idx) }
                }
            }
            .onMove { from, to in store.updateSettings { $0.categories.move(fromOffsets: from, toOffset: to) } }
            HStack {
                TextField("分類を足す（例：ペット）", text: $newCategory).foregroundStyle(p.text)
                Button("足す") { addCategory() }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(p.card)
        } header: {
            header("分類")
        } footer: {
            Text("右上の「編集」で並べ替え・削除。消した分類の記録はそのまま残ります").font(.caption).foregroundStyle(p.sub)
        }
    }

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !store.settings.categories.contains(name) else { return }
        store.updateSettings { s in
            let at = s.categories.firstIndex(of: "その他") ?? s.categories.count
            s.categories.insert(name, at: at)
        }
        newCategory = ""
    }

    // MARK: 決まり

    private var ruleSection: some View {
        Section {
            ForEach(store.settings.rules) { r in
                HStack(spacing: 8) {
                    if r.learned {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(p.accent)
                            .accessibilityLabel("覚えた決まり")
                    }
                    Text(r.keyword).foregroundStyle(p.text).lineLimit(1)
                    Spacer()
                    Menu {
                        ForEach(store.settings.categories, id: \.self) { c in
                            Button(c) { setRule(r.id, category: c) }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(r.category)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                    }
                }
                .listRowBackground(p.card)
            }
            .onDelete { idx in store.updateSettings { $0.rules.remove(atOffsets: idx) } }
            .onMove { from, to in store.updateSettings { $0.rules.move(fromOffsets: from, toOffset: to) } }
            HStack {
                TextField("言葉（例：ベーカリー）", text: $newKeyword).foregroundStyle(p.text)
                Picker("分類", selection: $newRuleCategory) {
                    ForEach(store.settings.categories, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("足す") { addRule() }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(p.card)
            Button("決まりを最初の状態に戻す") {
                store.updateSettings { $0.rules = KakeiboRule.defaults }
            }
            .foregroundStyle(p.overdue)
            .listRowBackground(p.card)
        } header: {
            header("分類の決まり")
        } footer: {
            Text("摘要やお店の名前にこの言葉が入っていたら、その分類にします。上にあるものが先。取り込みの確認で分類を直すと、ここに覚えます（✦の印）")
                .font(.caption).foregroundStyle(p.sub)
        }
    }

    private func setRule(_ id: String, category: String) {
        store.updateSettings { s in
            if let i = s.rules.firstIndex(where: { $0.id == id }) { s.rules[i].category = category }
        }
    }

    private func addRule() {
        let k = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return }
        let c = newRuleCategory
        store.updateSettings { $0.rules.insert(KakeiboRule(keyword: k, category: c, learned: true), at: 0) }
        newKeyword = ""
    }

    // MARK: 取り込み

    private var importSection: some View {
        Section {
            Toggle(isOn: Binding(get: { store.settings.excludeTransfers },
                                 set: { v in store.updateSettings { $0.excludeTransfers = v } })) {
                Text("カード引落・振替を入れない").foregroundStyle(p.text)
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
            Button("テストの記録（Apple Pay）を消す") { store.deleteTests() }
                .foregroundStyle(p.overdue)
                .listRowBackground(p.card)
        } header: {
            header("取り込み")
        } footer: {
            Text("JCB の明細を取り込むと、銀行の明細にある JCB の引落は合計から外します（2回数えないため）").font(.caption).foregroundStyle(p.sub)
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.bold)).foregroundStyle(p.sub)
    }
}
