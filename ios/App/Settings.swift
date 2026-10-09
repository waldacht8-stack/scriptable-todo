import SwiftUI

// MARK: - 設定

struct SettingsView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
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
                TodoSettingsSections()
                Section("状態") {
                    Label(SharedStore.isGroupAvailable ? "ウィジェットとのデータ共有：使える" : "ウィジェットとのデータ共有：使えない",
                          systemImage: SharedStore.isGroupAvailable ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(SharedStore.isGroupAvailable ? .green : .orange)
                    Text(SharedStore.diagnosis).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
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
