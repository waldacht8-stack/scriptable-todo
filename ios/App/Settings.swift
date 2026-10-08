import SwiftUI

// MARK: - 追加

struct AddSheet: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("やること", text: $title).focused($focused).submitLabel(.done)
                Toggle("期限を決める", isOn: $hasDue.animation())
                if hasDue { DatePicker("期限", selection: $due) }
            }
            .navigationTitle("TODOを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        store.add(title, due: hasDue ? due : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - 設定（デザインの切り替え）

struct SettingsView: View {
    @EnvironmentObject var store: TodoStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(AppTheme.allCases) { theme in
                            Button { withAnimation(.snappy) { store.setTheme(theme) } } label: {
                                ThemeCard(theme: theme, selected: store.theme == theme)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("デザイン")
                } footer: {
                    Text("ホーム画面の見た目と操作が変わります。ウィジェットにも反映されます。")
                }
                Section("状態") {
                    Label(SharedStore.isGroupAvailable ? "ウィジェットとのデータ共有：使える" : "ウィジェットとのデータ共有：使えない",
                          systemImage: SharedStore.isGroupAvailable ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(SharedStore.isGroupAvailable ? .green : .orange)
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
                Section("ウィジェットの見本") {
                    TodoWidgetView(items: TodoData.sorted(store.items.filter { !$0.done }), groupOK: SharedStore.isGroupAvailable)
                        .padding(16)
                        .frame(height: 158)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("設定")
        }
    }
}

/// デザインを選ぶカード（小さな見本つき）
struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeThumb(theme: theme)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack {
                Text(theme.name).font(.headline.weight(.bold)).fontDesign(theme.fontDesign)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            Text(theme.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
    }
}

struct ThemeThumb: View {
    let theme: AppTheme

    var body: some View {
        switch theme {
        case .sky:
            ZStack {
                LinearGradient(colors: Sky.colors(), startPoint: .top, endPoint: .bottom)
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(.white.opacity(0.35)).frame(height: 12)
                    }
                }
                .padding(14)
            }
        case .dial:
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.06)
                Circle().stroke(.white.opacity(0.15), lineWidth: 6).padding(18)
                Circle().trim(from: 0, to: 0.6).stroke(theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(18)
                Text("1:23").font(.system(.headline, design: .monospaced).bold()).foregroundStyle(theme.accent)
            }
        case .focus:
            ZStack {
                Color(.systemGroupedBackground)
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .frame(width: 90 - CGFloat(i) * 8, height: 70)
                        .offset(y: CGFloat(i) * 7)
                        .zIndex(Double(-i))
                }
            }
        case .paper:
            ZStack(alignment: .topLeading) {
                Color(red: 0.98, green: 0.96, blue: 0.90)
                VStack(spacing: 16) { ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color.blue.opacity(0.18)).frame(height: 1) } }
                    .padding(.top, 14)
                Hanko(color: theme.accent).scaleEffect(0.8).padding(10).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
