import SwiftUI

// MARK: - 設定
// 画面全体を、選んでいる色合い（＋カスタマイズ）で描く。色を変えるとこの画面もその場で変わる。
// 起動引数（スクリーンショット用）：-settingsSection <design|custom|todo|notify|calendar|data|info> でその見出しまで送る。
// -accent / -corner / -font / -density <値> でカスタマイズを設定する。

struct SettingsView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var s = SettingsData.load()

    /// いまの色合いにカスタマイズを重ねたもの（この画面はこれで描く）
    private var p: Palette { store.theme.palette(with: s) }

    var body: some View {
        let p = self.p
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    SettingsContent(s: $s, save: saveDesign)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .onAppear { applyLaunchArgs(proxy) }
            }
            .paletteBackground(p)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .environment(\.palette, p)
        .environment(\.motion, MotionStyle.from(store.theme))
        .fontDesign(p.fontDesign)
        .tint(p.accent)
        .preferredColorScheme(p.scheme)
    }

    /// デザインの項目だけを書き戻す（TODO の設定など、ほかで変えた値を古い値で上書きしない）
    private func saveDesign() {
        var fresh = SettingsData.load()
        fresh.accentColor = s.accentColor
        fresh.cornerStyle = s.cornerStyle
        fresh.fontStyle = s.fontStyle
        fresh.density = s.density
        SettingsData.save(fresh)
        s = fresh
        store.objectWillChange.send() // 後ろの画面（RootView）も描き直す
    }

    private func applyLaunchArgs(_ proxy: ScrollViewProxy) {
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var changed = false
        if let v = arg("-accent") { s.accentColor = v; changed = true }
        if let v = arg("-corner") { s.cornerStyle = v; changed = true }
        if let v = arg("-font") { s.fontStyle = v; changed = true }
        if let v = arg("-density") { s.density = v; changed = true }
        if changed { saveDesign() }
        if let section = arg("-settingsSection") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(section, anchor: .top) }
        }
    }
}

/// 設定の中身（デザイン → TODO・通知・カレンダー・データ → 情報）
private struct SettingsContent: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ringSpace
    @Binding var s: AppSettings
    let save: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 30 * p.density.scale) {
            SettingsSection("デザイン", icon: "paintpalette.fill") {
                PalettePreview()
                SubHeading("構成（今日の画面）", note: "ボタンの位置と操作のしかたが変わります。")
                layoutGrid
                SubHeading("色合い", note: "すべての画面とウィジェットに反映されます。")
                themeGrid
                SubHeading("カスタマイズ", note: "色合いの上に重ねて、好みに合わせられます。").id("custom")
                CustomizeCard(s: $s, save: save)
            }
            .id("design")

            TodoSettingsSections()

            AppInfoSection().id("info")
        }
        .sensoryFeedback(.selection, trigger: store.theme)
        .sensoryFeedback(.selection, trigger: store.layout)
    }

    /// 選んだ枠が次のカードへ動く（「視差効果を減らす」がオンなら動かさずに切り替える）
    private func ring(_ id: String) -> SelectionRing? {
        reduceMotion ? nil : SelectionRing(id: id, space: ringSpace)
    }

    /// 選び直したときの動き。色合いは「新しい色合いの動き方」で全画面の色をなめらかに切り替える
    private func pick(_ motion: MotionStyle) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : motion.change
    }

    private var layoutGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(TodayLayout.allCases) { layout in
                Button { withAnimation(pick(MotionStyle.from(store.theme))) { store.setLayout(layout) } } label: {
                    ChoiceCard(title: layout.name, summary: layout.summary, selected: store.layout == layout, ring: ring("layout")) {
                        LayoutThumb(layout: layout)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var themeGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                Button { withAnimation(pick(MotionStyle.from(theme))) { store.setTheme(theme) } } label: {
                    ChoiceCard(title: theme.name, summary: theme.summary, selected: store.theme == theme, ring: ring("theme")) {
                        PaletteThumb(palette: theme.palette(with: s))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("色合い：\(theme.name)")
            }
        }
    }
}

// MARK: - プレビュー（いまの色合いとカスタマイズ）

private struct PalettePreview: View {
    @Environment(\.palette) private var p

    var body: some View {
        let rowGap: CGFloat = 8 * p.density.scale
        VStack(alignment: .leading, spacing: 12 * p.density.scale) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("今日").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text("あと").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Text("3").font(.system(size: 36, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                Text("件").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                Spacer()
                Text("追加")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(p.accent, in: Capsule())
            }
            VStack(spacing: rowGap) {
                PreviewRow(title: "歯医者", time: "14:00", overdue: false)
                PreviewRow(title: "市役所に書類を提出", time: "昨日", overdue: true)
            }
        }
        .paletteCard(p)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("いまの見た目のプレビュー")
    }
}

private struct PreviewRow: View {
    @Environment(\.palette) private var p
    let title: String
    let time: String
    let overdue: Bool

    var body: some View {
        let mark: Color = overdue ? p.overdue : p.accent
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(mark, lineWidth: 2)
                .frame(width: 20, height: 20)
            Text(title).font(.body.weight(.medium)).foregroundStyle(p.text).lineLimit(1)
            Spacer(minLength: 8)
            Text(time).font(.subheadline.weight(.bold)).foregroundStyle(mark)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10 * p.density.scale)
        .background(p.sub.opacity(0.10), in: RoundedRectangle(cornerRadius: max(6, p.radius * 0.5), style: .continuous))
    }
}

// MARK: - カスタマイズ（強調色・角の丸み・書体・表示の密度）

private struct CustomizeCard: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: TodoStore
    @Binding var s: AppSettings
    let save: () -> Void

    private var isCustomized: Bool {
        s.accentColor != "theme" || s.cornerStyle != "theme" || s.fontStyle != "theme" || s.density != Density.regular.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * p.density.scale) {
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "強調色", value: AccentChoice.from(s.accentColor).name)
                swatches
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "角の丸み", value: nil)
                ChipPicker(options: CornerChoice.allCases, selection: binding(\.cornerStyle, CornerChoice.from),
                           label: { $0.name })
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "書体", value: nil)
                ChipPicker(options: FontChoice.allCases, selection: binding(\.fontStyle, FontChoice.from),
                           label: { $0.name }, design: { $0.design })
            }
            VStack(alignment: .leading, spacing: 10) {
                FieldLabel(title: "表示の密度", value: nil)
                ChipPicker(options: Density.allCases, selection: binding(\.density, Density.from),
                           label: { $0.name })
            }
            if isCustomized {
                Button {
                    withAnimation(anim) {
                        s.accentColor = "theme"; s.cornerStyle = "theme"; s.fontStyle = "theme"; s.density = Density.regular.rawValue
                        save()
                    }
                } label: {
                    Label("カスタマイズを元に戻す", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .paletteCard(p)
        .sensoryFeedback(.selection, trigger: s.accentColor)
        .sensoryFeedback(.selection, trigger: s.cornerStyle)
        .sensoryFeedback(.selection, trigger: s.fontStyle)
        .sensoryFeedback(.selection, trigger: s.density)
    }

    private var anim: Animation { reduceMotion ? .easeInOut(duration: 0.2) : motion.change }

    /// 文字列で保存している設定を、選択肢の型で読み書きする
    private func binding<V: RawRepresentable>(_ key: WritableKeyPath<AppSettings, String>, _ from: @escaping (String) -> V) -> Binding<V>
    where V.RawValue == String {
        Binding(get: { from(s[keyPath: key]) },
                set: { v in withAnimation(anim) { s[keyPath: key] = v.rawValue; save() } })
    }

    private var swatches: some View {
        let base = store.theme.palette
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: AccentChoice.allCases.count)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(AccentChoice.allCases) { a in
                let pair = a.colors(for: base)
                let color: Color = pair?.accent ?? base.accent
                let mark: Color = pair?.onAccent ?? base.onAccent
                Button {
                    withAnimation(anim) { s.accentColor = a.rawValue; save() }
                } label: {
                    SwatchDot(color: color, mark: mark, isTheme: a == .theme, selected: AccentChoice.from(s.accentColor) == a)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("強調色：\(a.name)")
            }
        }
    }
}

private struct SwatchDot: View {
    @Environment(\.palette) private var p
    let color: Color
    let mark: Color
    let isTheme: Bool
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 26, height: 26)
            if isTheme {
                Circle().strokeBorder(p.card, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 26, height: 26)
            }
            Circle().strokeBorder(selected ? p.text : .clear, lineWidth: 2).frame(width: 34, height: 34)
            if selected {
                Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(mark)
            }
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity)
    }
}

private struct FieldLabel: View {
    @Environment(\.palette) private var p
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
            if let value { Text(value).font(.subheadline).foregroundStyle(p.sub) }
        }
    }
}

/// 横に並んだ選択肢（選んでいるものは強調色で塗る）
struct ChipPicker<V: Identifiable & Hashable>: View {
    @Environment(\.palette) private var p
    let options: [V]
    @Binding var selection: V
    let label: (V) -> String
    var design: (V) -> Font.Design? = { _ in nil }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { o in
                let on = o == selection
                Button { selection = o } label: {
                    Text(label(o))
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(design(o))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(on ? p.onAccent : p.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(on ? p.accent : p.sub.opacity(0.13), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - 情報

private struct AppInfoSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        let ok = SharedStore.isGroupAvailable
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        SettingsSection("情報", icon: "info.circle.fill",
                        footer: "うまく共有できないときは、上の内容を確認してください（長押しでコピーできます）。") {
            SettingsCard {
                SettingsRow(title: "バージョン", icon: "app.badge") {
                    Text("\(version)（\(build)）").font(.subheadline).foregroundStyle(p.sub)
                }
                RowDivider()
                SettingsRow(title: "ウィジェットとの共有", icon: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                            iconColor: ok ? p.accent : p.overdue) {
                    Text(ok ? "使える" : "使えない").font(.subheadline.weight(.semibold)).foregroundStyle(ok ? p.sub : p.overdue)
                }
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

// MARK: - 選択肢のカード

/// 選択肢のカード（見本＋名前＋説明）
struct ChoiceCard<Thumb: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let summary: String
    let selected: Bool
    var ring: SelectionRing? = nil
    @ViewBuilder let thumb: () -> Thumb

    var body: some View {
        let r: CGFloat = min(max(p.radius * 0.7, 10), 22)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let border: Color = p.outline ?? p.sub.opacity(0.15)
        VStack(alignment: .leading, spacing: 8) {
            thumb()
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: max(r - 6, 6), style: .continuous))
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(p.accent)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(p.sub)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(p.card, in: shape)
        .overlay(shape.strokeBorder(border, lineWidth: 1))
        .overlay {
            if selected {
                shape.strokeBorder(p.accent, lineWidth: 2.5).modifier(MatchedRing(ring: ring))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 選択の枠を、選び直したカードへ動かすための名前（matchedGeometryEffect）
struct SelectionRing {
    let id: String
    let space: Namespace.ID
}

private struct MatchedRing: ViewModifier {
    let ring: SelectionRing?

    func body(content: Content) -> some View {
        if let ring {
            content.matchedGeometryEffect(id: ring.id, in: ring.space)
        } else {
            content
        }
    }
}

/// 色合いの見本（その色合いの背景・カード・文字・強調色・警告色を小さく描く）
struct PaletteThumb: View {
    @Environment(\.colorScheme) private var deviceScheme
    let palette: Palette

    var body: some View {
        let p = palette
        let cardShape = RoundedRectangle(cornerRadius: min(p.radius, 12), style: .continuous)
        ZStack {
            LinearGradient(colors: p.background.count > 1 ? p.background : [p.background[0], p.background[0]],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("あと 3 件").font(.system(.subheadline, design: p.fontDesign).weight(.heavy)).foregroundStyle(p.text)
                    Spacer(minLength: 0)
                    Text("完了")
                        .font(.system(.caption2, design: p.fontDesign).weight(.bold))
                        .foregroundStyle(p.onAccent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(p.accent, in: Capsule())
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(p.accent, lineWidth: 2).frame(width: 14, height: 14)
                    Text("歯医者").font(.system(.caption, design: p.fontDesign)).foregroundStyle(p.text)
                    Spacer(minLength: 0)
                    Text("14:00").font(.caption2.bold()).foregroundStyle(p.accent)
                }
                .padding(8)
                .background(p.card, in: cardShape)
                .overlay(cardShape.strokeBorder(p.outline ?? .clear, lineWidth: 1))
                HStack(spacing: 4) {
                    Circle().fill(p.accent).frame(width: 10, height: 10)
                    Circle().fill(p.overdue).frame(width: 10, height: 10)
                    Circle().fill(p.sub).frame(width: 10, height: 10)
                }
            }
            .padding(10)
        }
        .environment(\.colorScheme, p.scheme ?? deviceScheme) // 端末の外観に合わせる色合いはそのまま
    }
}
