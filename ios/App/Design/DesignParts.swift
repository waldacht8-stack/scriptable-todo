import SwiftUI

// MARK: - 選択肢のカード

/// 選択肢のカード（見本＋名前＋説明）
struct ChoiceCard<Thumb: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let summary: String
    let selected: Bool
    var ring: SelectionRing? = nil
    var thumbHeight: CGFloat = 104
    @ViewBuilder let thumb: () -> Thumb

    var body: some View {
        let r: CGFloat = min(max(p.radius * 0.7, 10), 22)
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let border: Color = p.outline ?? p.sub.opacity(0.15)
        VStack(alignment: .leading, spacing: 8) {
            thumb()
                .frame(height: thumbHeight)
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

/// 世界観の見本（その世界観の背景・カード・大きな数字を小さく描く）
struct WorldThumb: View {
    @Environment(\.colorScheme) private var deviceScheme
    let palette: Palette

    var body: some View {
        let p = palette
        var small = p
        small.radius = min(p.radius, 12)
        let num: Color = p.world.bigNumberAccent ? p.accent : p.text
        return ZStack {
            WorldBackground(p: p)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("あと").font(.system(.caption2, design: p.fontDesign).weight(.bold)).foregroundStyle(p.sub)
                    Text("3").font(.system(size: p.world == .swiss ? 30 : 22, weight: .heavy, design: p.fontDesign))
                        .foregroundStyle(num)
                    Spacer(minLength: 0)
                    Circle().fill(p.accent).frame(width: 14, height: 14)
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(p.accent, lineWidth: 2).frame(width: 12, height: 12)
                    Text("歯医者").font(.system(.caption, design: p.fontDesign).weight(.semibold)).foregroundStyle(p.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(WorldCardSurface(p: small))
            }
            .padding(10)
        }
        .environment(\.colorScheme, p.scheme ?? deviceScheme)
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

// MARK: - こまかい調整（強調色・角の丸み・書体・表示の密度）

/// 色合い（または世界観）の上に重ねる4つの調整。どれも選ぶとすぐ全画面に反映する
struct TuneSections: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: TodoStore
    @Binding var s: AppSettings
    let save: () -> Void

    static func isCustomized(_ s: AppSettings) -> Bool {
        s.accentColor != "theme" || s.cornerStyle != "theme" || s.fontStyle != "theme" || s.density != Density.regular.rawValue
    }

    /// 「色合い」を選んでいるときは「色合いのまま」と出す
    static func valueName(_ name: String, isTheme: Bool) -> String { isTheme ? "色合いのまま" : name }

    /// 調整を重ねる前の色の組（「色合いのまま」の見本に使う）
    private var base: Palette { World.from(s.world).palette ?? store.theme.palette }

    var body: some View {
        let base = self.base
        VStack(alignment: .leading, spacing: 14 * p.density.scale) {
            TuneGroup(title: "強調色", value: AccentChoice.from(s.accentColor).name) { swatches(base) }
            TuneGroup(title: "角の丸み", value: Self.valueName(CornerChoice.from(s.cornerStyle).name, isTheme: CornerChoice.from(s.cornerStyle) == .theme)) {
                OptionTiles(options: CornerChoice.allCases, selection: binding(\.cornerStyle, CornerChoice.from),
                            label: { $0.name }) { c in
                    CornerSample(radius: c.radius ?? base.radius)
                }
            }
            TuneGroup(title: "書体", value: Self.valueName(FontChoice.from(s.fontStyle).name, isTheme: FontChoice.from(s.fontStyle) == .theme)) {
                OptionTiles(options: FontChoice.allCases, selection: binding(\.fontStyle, FontChoice.from),
                            label: { $0.name }) { f in
                    FontSample(design: f.design ?? base.fontDesign)
                }
            }
            TuneGroup(title: "表示の密度", value: Density.from(s.density).name) {
                OptionTiles(options: Density.allCases, selection: binding(\.density, Density.from),
                            label: { $0.name }) { d in
                    DensitySample(density: d)
                }
            }
            if Self.isCustomized(s) {
                Button {
                    withAnimation(anim) {
                        s.accentColor = "theme"; s.cornerStyle = "theme"; s.fontStyle = "theme"; s.density = Density.regular.rawValue
                        save()
                    }
                } label: {
                    Label("調整を元に戻す", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(p.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
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

    private func swatches(_ base: Palette) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)
        return LazyVGrid(columns: cols, spacing: 10) {
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

/// 調整の1項目（名前と今の値、その下に選択肢）をカードにまとめる
private struct TuneGroup<Content: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FieldLabel(title: title, value: value)
            content()
        }
        .paletteCard(p, padding: 16)
    }
}

/// 見本つきの選択肢（上に小さな見本、下に名前）。選んでいるものは強調色の枠
struct OptionTiles<V: Identifiable & Hashable, Sample: View>: View {
    @Environment(\.palette) private var p
    let options: [V]
    @Binding var selection: V
    let label: (V) -> String
    @ViewBuilder let sample: (V) -> Sample

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { o in
                tile(o)
            }
        }
    }

    private func tile(_ o: V) -> some View {
        let on: Bool = o == selection
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let fill: Color = on ? p.accent.opacity(0.14) : p.sub.opacity(0.10)
        let edge: Color = on ? p.accent : Color.clear
        return Button { selection = o } label: {
            VStack(spacing: 6) {
                sample(o)
                    .frame(height: 34)
                Text(label(o))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(on ? p.accent : p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(o))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 角の丸みの見本（小さなカード）
private struct CornerSample: View {
    @Environment(\.palette) private var p
    let radius: CGFloat

    var body: some View {
        let r: CGFloat = min(radius * 0.45, 15)
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(p.card)
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(p.accent, lineWidth: 2))
            .frame(width: 40, height: 30)
    }
}

/// 書体の見本
private struct FontSample: View {
    @Environment(\.palette) private var p
    let design: Font.Design

    var body: some View {
        Text("あA")
            .font(.system(size: 21, weight: .bold, design: design))
            .foregroundStyle(p.text)
    }
}

/// 表示の密度の見本（行の間隔）
private struct DensitySample: View {
    @Environment(\.palette) private var p
    let density: Density

    var body: some View {
        let gap: CGFloat = max((density.scale - 0.6) * 11, 1.5)
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(p.sub.opacity(0.55)).frame(width: 34, height: 4)
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

