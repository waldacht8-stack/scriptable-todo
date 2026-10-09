import SwiftUI

/// 話題の追加・編集（キーワード・色・集める元・新着の通知）
struct InfoTopicSheet: View {
    @EnvironmentObject var model: InfoModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State var topic: InfoTopic
    let isNew: Bool
    @State private var confirmDelete = false

    private var keyword: String { topic.keyword.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicate: Bool {
        model.topics.contains { $0.id != topic.id && $0.keyword.lowercased() == keyword.lowercased() }
    }

    var body: some View {
        NavigationStack {
            Form {
                keywordSection
                colorSection
                sourceSection
                notifySection
                if !isNew { deleteSection }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle(isNew ? "話題を追加" : "話題を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") {
                        topic.keyword = keyword
                        model.upsert(topic)
                        dismiss()
                    }
                    .bold()
                    .disabled(keyword.isEmpty || duplicate)
                }
            }
            .confirmationDialog("「\(topic.keyword)」を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    model.delete(topic)
                    dismiss()
                }
            } message: {
                Text("集めた記事も消えます（あとで読むに保存した記事は残ります）。")
            }
        }
        .presentationDetents([.large])
    }

    private var keywordSection: some View {
        Section {
            TextField("例：猫、iPhone、キャンプ", text: $topic.keyword)
                .font(.title3.weight(.semibold))
                .submitLabel(.done)
            if isNew && keyword.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(InfoData.suggestions.filter { s in !model.topics.contains { $0.keyword == s } }, id: \.self) { s in
                            Button { topic.keyword = s } label: { InfoChip(title: s, selected: false) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("キーワード")
        } footer: {
            if duplicate { Text("同じ話題がすでにあります。").foregroundStyle(p.overdue) }
        }
        .listRowBackground(p.card)
    }

    private var colorSection: some View {
        Section("色") {
            HStack(spacing: 0) {
                ForEach(0..<InfoTopicColor.count, id: \.self) { i in
                    Button { topic.color = i } label: { colorDot(i) }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(p.card)
    }

    private func colorDot(_ i: Int) -> some View {
        let c: Color = InfoTopicColor.color(i, p)
        let on: Bool = topic.color == i
        return Circle().fill(c)
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(p.text, lineWidth: on ? 3 : 0).padding(-4))
            .accessibilityLabel(i == 0 ? "テーマの色" : "色 \(i)")
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var sourceSection: some View {
        Section {
            ForEach(InfoSource.allCases) { s in
                Toggle(isOn: binding(s)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(s.name, systemImage: s.symbol).foregroundStyle(p.text)
                        Text(s.isAlwaysOn ? "どの話題でも検索します" : s.summary).font(.caption).foregroundStyle(p.sub)
                    }
                }
                .disabled(s.isAlwaysOn)
            }
        } header: {
            Text("集める元")
        } footer: {
            Text("外国語の見出しや投稿は、端末の翻訳機能で日本語にして表示します（iOS 18 以降）。X は自動では集めず、話題のメニューから検索を開けます。")
        }
        .listRowBackground(p.card)
    }

    private func binding(_ s: InfoSource) -> Binding<Bool> {
        Binding {
            s.isAlwaysOn || topic.sourceIDs.contains(s.rawValue)
        } set: { on in
            topic.sourceIDs.removeAll { $0 == s.rawValue }
            if on { topic.sourceIDs.append(s.rawValue) }
        }
    }

    private var notifySection: some View {
        Section {
            Toggle("新着を通知", isOn: Binding { topic.notify ?? false } set: { topic.notify = $0 })
        } footer: {
            Text("新着の通知は準備中です。オンにしておくと、使えるようになったときから届きます。")
        }
        .listRowBackground(p.card)
    }

    private var deleteSection: some View {
        Section {
            Button("この話題を削除", role: .destructive) { confirmDelete = true }
        }
        .listRowBackground(p.card)
    }
}
