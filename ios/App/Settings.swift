import SwiftUI

// MARK: - 追加

struct AddSheet: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    let draft: AddDraft
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
            .onAppear {
                if let d = draft.due { due = d; hasDue = true }
                focused = true
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
                VStack(spacing: 5) {
                    Capsule().fill(accent.opacity(0.5)).frame(height: 10)
                    HStack(spacing: 5) { tileShape; tileShape }
                    HStack(spacing: 5) { tileShape; tileShape }
                    Capsule().fill(ink).frame(height: 6)
                }
                .padding(10)
            case .thumb:
                VStack(spacing: 4) {
                    Spacer()
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(ink).frame(height: 8) }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(ink).frame(height: 18)
                        RoundedRectangle(cornerRadius: 4).fill(ink).frame(height: 18)
                        RoundedRectangle(cornerRadius: 4).fill(accent).frame(height: 18)
                    }
                }
                .padding(10)
            case .timeline:
                ZStack(alignment: .topTrailing) {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(0..<5, id: \.self) { i in
                            HStack(spacing: 5) {
                                Capsule().fill(ink).frame(width: 12, height: 3)
                                if i == 1 || i == 3 { RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.6)).frame(height: 10) }
                                else { Rectangle().fill(ink.opacity(0.5)).frame(height: 1) }
                            }
                        }
                    }
                    .padding(12)
                    Circle().fill(accent).frame(width: 14, height: 14).padding(6)
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
