import SwiftUI

// MARK: - 設定
// 画面全体を、選んでいる色合い（＋カスタマイズ）で描く。見た目の項目は「デザインを変える」（App/Design/DesignView.swift）へ分けた。
// 起動引数（スクリーンショット用）：
//   -settingsSection <icon|todo|notify|calendar|data|info> でその見出しまで送る。
//   -settingsSection <design|world|theme|layout|custom> と -designpage <hub|world|theme|layout|tune> はデザインの画面を開く。
//   -accent / -corner / -font / -density <値> でカスタマイズを設定する。

struct SettingsView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var s = SettingsData.load()
    @State private var path: [SettingsRoute] = SettingsRoute.fromLaunchArgs()
    @State private var didLaunchScroll = false

    /// いまの色合いにカスタマイズを重ねたもの（この画面はこれで描く）
    private var p: Palette { store.theme.palette(with: s) }

    var body: some View {
        let p = self.p
        let motion: MotionStyle = p.world.motion ?? MotionStyle.from(store.theme)
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    SettingsContent()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .onAppear { scrollToLaunchSection(proxy) }
            }
            .paletteBackground(p)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.fontWeight(.semibold)
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(route)
            }
        }
        .onAppear { applyLaunchCustomize() }
        .environment(\.palette, p)
        .environment(\.motion, motion)
        .fontDesign(p.fontDesign)
        .tint(p.accent)
        .preferredColorScheme(p.scheme)
    }

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .design: DesignView(s: $s, save: saveDesign)
        case .page(let page): DesignPageView(page: page, s: $s, save: saveDesign)
        }
    }

    /// デザインの項目だけを書き戻す（TODO の設定など、ほかで変えた値を古い値で上書きしない）
    private func saveDesign() {
        var fresh = SettingsData.load()
        fresh.accentColor = s.accentColor
        fresh.cornerStyle = s.cornerStyle
        fresh.fontStyle = s.fontStyle
        fresh.density = s.density
        fresh.world = s.world
        SettingsData.save(fresh)
        s = fresh
        store.objectWillChange.send() // 後ろの画面（RootView）も描き直す
    }

    private static func launchArg(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 起動引数のカスタマイズを保存する（デザインのページを開いて起動しても効くよう、NavigationStack の外で読む）
    private func applyLaunchCustomize() {
        let arg = Self.launchArg
        var changed = false
        if let v = arg("-accent") { s.accentColor = v; changed = true }
        if let v = arg("-corner") { s.cornerStyle = v; changed = true }
        if let v = arg("-font") { s.fontStyle = v; changed = true }
        if let v = arg("-density") { s.density = v; changed = true }
        if changed { saveDesign() }
    }

    private func scrollToLaunchSection(_ proxy: ScrollViewProxy) {
        guard !didLaunchScroll else { return }
        didLaunchScroll = true
        if let section = Self.launchArg("-settingsSection"), path.isEmpty {
            // TODO の見出しは通知とひとつにまとめた
            let target: String = section == "todo" ? "notify" : section
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(target, anchor: .top) }
        }
    }
}

/// 設定の中身（デザインの入口 → アプリのアイコン → 通知・カレンダー・データ → 情報）
private struct SettingsContent: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 28 * p.density.scale) {
            NavigationLink(value: SettingsRoute.design) {
                DesignEntryCard()
            }
            .buttonStyle(.plain)
            .id("design")

            TodoSettingsSections()

            AppInfoSection().id("info")
        }
    }
}

// MARK: - 情報

private struct AppInfoSection: View {
    @Environment(\.palette) private var p
    @State private var showDiagnosis = false

    var body: some View {
        let ok = SharedStore.isGroupAvailable
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let chevron: String = showDiagnosis ? "chevron.up" : "chevron.down"
        SettingsSection("情報", icon: "info.circle.fill") {
            SettingsCard {
                SettingsRow(title: "バージョン", icon: "app.badge") {
                    Text("\(version)（\(build)）").font(.subheadline).foregroundStyle(p.sub)
                }
                RowDivider()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDiagnosis.toggle() }
                } label: {
                    SettingsRow(title: "ウィジェット連携", icon: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                                iconColor: ok ? p.accent : p.overdue) {
                        HStack(spacing: 6) {
                            Text(ok ? "使える" : "使えない").font(.subheadline.weight(.semibold)).foregroundStyle(ok ? p.sub : p.overdue)
                            Image(systemName: chevron).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("押すと、くわしい状態を表示します")
                if showDiagnosis {
                    RowDivider()
                    Text(SharedStore.diagnosis)
                        .font(.caption2.monospaced())
                        .foregroundStyle(p.sub)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            if showDiagnosis {
                Text("うまく共有できないときは、この内容を確認してください（長押しでコピーできます）。")
                    .font(.footnote)
                    .foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - 設定画面の部品（TodoSettings.swift でも使う）

/// 見出し（アイコン＋大きめの文字）と、その下の中身・補足
struct SettingsSection<Content: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let icon: String
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, icon: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * p.density.scale) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(p.onAccent)
                    .frame(width: 30, height: 30)
                    .background(p.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(p.text)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// セクションの中の小見出し
struct SubHeading: View {
    @Environment(\.palette) private var p
    let title: String
    var note: String? = nil

    init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline.weight(.bold)).foregroundStyle(p.text)
            if let note {
                Text(note).font(.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }
}

/// 行を並べるカード（行の間は RowDivider で区切る）
struct SettingsCard<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .paletteCard(p, padding: 0)
    }
}

/// 設定の1行（左にアイコンと名前、右に値や操作）
struct SettingsRow<Trailing: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let icon: String?
    var iconColor: Color? = nil
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, icon: String? = nil, iconColor: Color? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(iconColor ?? p.accent)
                    .frame(width: 24)
            }
            Text(title)
                .font(.body)
                .foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, p.density.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 行の区切り線
struct RowDivider: View {
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle()
            .fill(p.sub.opacity(0.2))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

/// スイッチの行
struct ToggleRow: View {
    @Environment(\.palette) private var p
    let title: String
    var icon: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, icon: icon) {
            Toggle(title, isOn: $isOn).labelsHidden().tint(p.accent)
        }
    }
}

/// メニューから選ぶ行（右に今の値を強調色で出す）
struct MenuRow<V: Hashable>: View {
    @Environment(\.palette) private var p
    let title: String
    var icon: String? = nil
    @Binding var selection: V
    let options: [(value: V, label: String)]

    var body: some View {
        let current = options.first { $0.value == selection }?.label ?? ""
        SettingsRow(title: title, icon: icon) {
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options.indices, id: \.self) { i in
                        Text(options[i].label).tag(options[i].value)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(current).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundStyle(p.accent)
            }
        }
    }
}

/// 押すと何かをする行
struct ActionRow: View {
    @Environment(\.palette) private var p
    let title: String
    let icon: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            SettingsRow(title: title, icon: icon) {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            }
        }
        .buttonStyle(.plain)
    }
}
