import SwiftUI

// MARK: - デザインを変える
// 設定の一番上の「デザインを変える」から開く。上に いまの見た目の TODO 画面を小さく描き、
// その下の 世界観・色合い・構成・こまかい調整 をそれぞれ別のページで選ぶ。
// 値の保存は SettingsView の saveDesign（世界観・調整）と TodoStore の setTheme / setLayout（色合い・構成）。
// 起動引数（スクリーンショット用）：-settings -designpage <hub|world|theme|layout|tune>

/// 設定の NavigationStack で使う行き先
enum SettingsRoute: Hashable {
    case design
    case page(DesignPage)

    /// 起動引数から、最初に開いておく画面を決める（-settings のときだけ）
    static func fromLaunchArgs(_ args: [String] = ProcessInfo.processInfo.arguments) -> [SettingsRoute] {
        guard args.contains("-settings") else { return [] }
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var name: String? = arg("-designpage")
        if name == nil, let section = arg("-settingsSection") {
            // 以前は設定の中にあった見出し。いまはデザインの画面へ送る
            switch section {
            case "design": name = "hub"
            case "world", "theme", "layout": name = section
            case "custom": name = "tune"
            default: break
            }
        }
        guard let name else { return [] }
        let key: String = name == "custom" ? "tune" : name
        if let page = DesignPage(rawValue: key) { return [.design, .page(page)] }
        return [.design]
    }
}

/// デザインの各ページ
enum DesignPage: String, CaseIterable, Identifiable, Hashable {
    case world, theme, layout, tune

    var id: String { rawValue }

    /// 一覧に出す名前
    var title: String {
        switch self {
        case .world: "世界観"
        case .theme: "色合い"
        case .layout: "構成（TODO の画面）"
        case .tune: "こまかい調整"
        }
    }

    /// ページの上の名前（短く）
    var navTitle: String {
        switch self {
        case .world: "世界観"
        case .theme: "色合い"
        case .layout: "構成"
        case .tune: "こまかい調整"
        }
    }

    var note: String {
        switch self {
        case .world: "背景・カード・数字・動きまで、アプリ全体の雰囲気が変わります。選ぶと色合いより優先されます。"
        case .theme: "すべての画面とウィジェットの色が変わります。"
        case .layout: "TODO の画面の、ボタンの位置と操作のしかたが変わります。"
        case .tune: "色合いの上に重ねて、好みに合わせます。"
        }
    }

    var hint: String {
        switch self {
        case .world: "背景・カード・動きまで"
        case .theme: "画面とウィジェットの色"
        case .layout: "ボタンの位置と操作"
        case .tune: "強調色・角・書体・密度"
        }
    }
}

// MARK: - 入口（デザインの一覧）

struct DesignView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Binding var s: AppSettings
    let save: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22 * p.density.scale) {
                DesignHero(height: 236)

                VStack(spacing: 12 * p.density.scale) {
                    ForEach(DesignPage.allCases) { page in
                        NavigationLink(value: SettingsRoute.page(page)) {
                            DesignEntryRow(page: page, s: s)
                        }
                        .buttonStyle(.plain)
                    }
                }

                UpcomingDesignSection()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .paletteBackground(p)
        .navigationTitle("デザインを変える")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 一覧の1行（いまの選択の見本・名前・いまの値）
private struct DesignEntryRow: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    let page: DesignPage
    let s: AppSettings

    var body: some View {
        let thumbShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 14) {
            thumb
                .miniThumb(width: 78, height: 62, scale: 0.55)
                .clipShape(thumbShape)
                .overlay(thumbShape.strokeBorder(p.sub.opacity(0.15), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(page.hint)
                    .font(.caption)
                    .foregroundStyle(p.sub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title)：\(value)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var thumb: some View {
        switch page {
        case .world: WorldThumb(palette: p)
        case .theme: PaletteThumb(palette: store.theme.palette(with: s.withoutWorld))
        case .layout: LayoutThumb(layout: store.layout)
        case .tune: TuneThumb()
        }
    }

    private var value: String {
        switch page {
        case .world:
            let w = World.from(s.world)
            return w.isOn ? w.name : "なし（色合いのまま）"
        case .theme:
            return World.from(s.world).isOn ? "\(store.theme.name)（世界観が優先）" : store.theme.name
        case .layout:
            return store.layout.name
        case .tune:
            guard TuneSections.isCustomized(s) else { return "色合いのまま" }
            var parts: [String] = []
            let a = AccentChoice.from(s.accentColor)
            if a != .theme { parts.append(a.name) }
            let c = CornerChoice.from(s.cornerStyle)
            if c != .theme { parts.append("角 \(c.name)") }
            let f = FontChoice.from(s.fontStyle)
            if f != .theme { parts.append(f.name) }
            let d = Density.from(s.density)
            if d != .regular { parts.append(d.name) }
            return parts.joined(separator: "・")
        }
    }
}

extension AppSettings {
    /// 世界観を外した設定（色合いそのものの見本に使う）
    var withoutWorld: AppSettings {
        var c = self
        c.world = World.none.rawValue
        return c
    }
}

/// こまかい調整の見本（強調色・角の丸み・書体を小さく描く）
private struct TuneThumb: View {
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var deviceScheme

    var body: some View {
        let r: CGFloat = min(p.radius * 0.45, 14)
        ZStack {
            WorldBackground(p: p)
            HStack(spacing: 6) {
                Circle().fill(p.accent).frame(width: 16, height: 16)
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(p.card)
                    .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(p.accent, lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                Text("Aa")
                    .font(.system(size: 15, weight: .bold, design: p.fontDesign))
                    .foregroundStyle(p.text)
            }
        }
        .environment(\.colorScheme, p.scheme ?? deviceScheme)
    }
}

// MARK: - 新しい変え方（準備中）
// 今後ここに、新しい変え方の入口を足す（まだ作らない）：
//   ・AI で色合いを作る（言葉や写真から Palette を作る）
//   ・時間帯で切り替える（朝・昼・夜で色合いや世界観を自動で変える）
//   ・構成を組み立てる（TODO の画面の部品を自分で並べる）
// 足すときは DesignPage に case を足し、DesignPageView にそのページを書く。この見出しは入口に置き換える。

private struct UpcomingDesignSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(max(p.radius * 0.7, 10), 22), style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            SubHeading("新しい変え方（準備中）")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                Text("AI で色合いを作る、時間帯で自動で切り替える、TODO の画面を自分で組み立てる、を準備しています。")
                    .font(.footnote)
                    .foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(shape.strokeBorder(p.sub.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 各ページ

struct DesignPageView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ringSpace
    let page: DesignPage
    @Binding var s: AppSettings
    let save: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16 * p.density.scale) {
                if page == .layout || page == .tune {
                    DesignHero(height: 196)
                }
                Text(page.note)
                    .font(.footnote)
                    .foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .paletteBackground(p)
        .navigationTitle(page.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: store.theme)
        .sensoryFeedback(.selection, trigger: store.layout)
        .sensoryFeedback(.selection, trigger: s.world)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .world: worldGrid
        case .theme: themePage
        case .layout: layoutGrid
        case .tune: TuneSections(s: $s, save: save)
        }
    }

    /// 選んだ枠が次のカードへ動く（「視差効果を減らす」がオンなら動かさずに切り替える）
    private func ring(_ id: String) -> SelectionRing? {
        reduceMotion ? nil : SelectionRing(id: id, space: ringSpace)
    }

    /// 選び直したときの動き。新しい見た目の動き方で、全画面の色をなめらかに切り替える
    private func pick(_ motion: MotionStyle) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : motion.change
    }

    private var worldGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(World.allCases) { world in
                let wp: Palette = (world.palette ?? store.theme.palette)
                Button {
                    withAnimation(pick(world.motion ?? MotionStyle.from(store.theme))) {
                        s.world = world.rawValue
                        save()
                    }
                } label: {
                    ChoiceCard(title: world.name, summary: world.summary, selected: World.from(s.world) == world,
                               ring: ring("world"), thumbHeight: 132) {
                        WorldThumb(palette: wp)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("世界観：\(world.name)")
            }
        }
    }

    @ViewBuilder
    private var themePage: some View {
        let world = World.from(s.world)
        if world.isOn {
            WorldOverrideNote(world: world) {
                withAnimation(pick(MotionStyle.from(store.theme))) {
                    s.world = World.none.rawValue
                    save()
                }
            }
        }
        themeGrid
            .opacity(world.isOn ? 0.45 : 1)
    }

    private var themeGrid: some View {
        let plain: AppSettings = s.withoutWorld
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                Button { withAnimation(pick(MotionStyle.from(theme))) { store.setTheme(theme) } } label: {
                    ChoiceCard(title: theme.name, summary: theme.summary, selected: store.theme == theme,
                               ring: ring("theme"), thumbHeight: 132) {
                        PaletteThumb(palette: theme.palette(with: plain))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("色合い：\(theme.name)")
            }
        }
    }

    private var layoutGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(TodayLayout.allCases) { layout in
                Button { withAnimation(pick(MotionStyle.from(store.theme))) { store.setLayout(layout) } } label: {
                    ChoiceCard(title: layout.name, summary: layout.summary, selected: store.layout == layout,
                               ring: ring("layout"), thumbHeight: 120) {
                        LayoutThumb(layout: layout)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("構成：\(layout.name)")
            }
        }
    }
}

/// 世界観を選んでいるあいだは色合いが使われないことの説明と、世界観を外すボタン
private struct WorldOverrideNote: View {
    @Environment(\.palette) private var p
    let world: World
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("いまは世界観「\(world.name)」の色で表示しています。色合いを使うには、世界観を「なし」にします。")
                .font(.subheadline)
                .foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: clear) {
                Text("世界観をなしにする")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .paletteCard(p, padding: 16)
    }
}

// MARK: - いまの見た目のプレビュー（TODO の画面を小さく描く）

/// いまの色合い・世界観・調整・構成で、TODO の画面を小さく描く。選び直すとその場で変わる
struct DesignHero: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    var height: CGFloat = 260

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let border: Color = p.outline ?? p.sub.opacity(0.18)
        let gap: CGFloat = 8 * p.density.scale
        ZStack {
            WorldBackground(p: p)
            VStack(alignment: .leading, spacing: gap) {
                header
                content(for: store.layout)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(outer)
        .overlay(outer.strokeBorder(border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("いまの見た目のプレビュー")
    }

    private var header: some View {
        let numberSize: CGFloat = min(p.world.bigNumberSize * 0.62, 46)
        let numberColor: Color = p.world.bigNumberAccent ? p.accent : p.text
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(JP.date(.now))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(p.sub)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("あと").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                    Text("3")
                        .font(.system(size: numberSize, weight: .heavy, design: p.fontDesign))
                        .tracking(p.world.bigNumberTracking * 0.6)
                        .foregroundStyle(numberColor)
                    Text("件").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(p.onAccent)
                .frame(width: 38, height: 38)
                .background(p.accent, in: Circle())
        }
    }

    @ViewBuilder
    private func content(for layout: TodayLayout) -> some View {
        switch layout {
        case .focus:
            HeroFocusCard()
            HeroRows(count: 1, start: 1)
                .opacity(0.55)
                .padding(.horizontal, 14)
        case .thumb:
            HeroWeekStrip()
            HeroRows(count: 2)
        case .kanban:
            HeroKanbanTabs()
            HeroRows(count: 2)
        case .board, .timeline, .checklist:
            HeroRows(count: 3)
        }
    }
}

/// 見本の TODO（例の文言だけ）
private enum HeroSample {
    static let rows: [(title: String, time: String, overdue: Bool)] = [
        (title: "歯医者", time: "14:00", overdue: false),
        (title: "市役所に書類を提出", time: "昨日", overdue: true),
        (title: "牛乳を買う", time: "終日", overdue: false),
    ]
}

private struct HeroRows: View {
    @Environment(\.palette) private var p
    let count: Int
    var start: Int = 0

    var body: some View {
        var small = p
        small.radius = min(p.radius, 14)
        let gap: CGFloat = 7 * p.density.scale
        return VStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                let row = HeroSample.rows[(start + i) % HeroSample.rows.count]
                let mark: Color = row.overdue ? p.overdue : p.accent
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(mark, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    Text(row.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(row.time)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mark)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8 * p.density.scale)
                .background(WorldCardSurface(p: small))
                .padding(.trailing, p.world == .brutal ? 5 : 0)
            }
        }
    }
}

private struct HeroFocusCard: View {
    @Environment(\.palette) private var p

    var body: some View {
        var small = p
        small.radius = min(p.radius, 20)
        return VStack(alignment: .leading, spacing: 8 * p.density.scale) {
            Text("今日 14:00")
                .font(.caption.weight(.bold))
                .foregroundStyle(p.accent)
            Text("歯医者")
                .font(.system(.title3, design: p.fontDesign).weight(.bold))
                .foregroundStyle(p.text)
            HStack(spacing: 8) {
                Text("完了")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(p.accent, in: Capsule())
                Text(p.world.postponeWord)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(p.text)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(p.sub.opacity(0.14), in: Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorldCardSurface(p: small))
        .padding(.trailing, p.world == .brutal ? 5 : 0)
    }
}

private struct HeroWeekStrip: View {
    @Environment(\.palette) private var p
    private static let days = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let on: Bool = i == 0
                Text(Self.days[i])
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(on ? p.onAccent : p.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(on ? p.accent : p.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

private struct HeroKanbanTabs: View {
    @Environment(\.palette) private var p
    private static let names = ["今日", "明日", "あとで"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                let on: Bool = i == 0
                Text(Self.names[i])
                    .font(.caption.weight(.bold))
                    .foregroundStyle(on ? p.onAccent : p.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(on ? p.accent : p.card, in: Capsule())
            }
        }
    }
}

// MARK: - 設定の一番上に置く入口

/// 設定の一番上の「デザインを変える」（いまの見た目の小さな見本つき）
struct DesignEntryCard: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p

    var body: some View {
        let thumbShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let world = p.world
        let current: String = world.isOn ? "\(world.name)・\(store.layout.name)" : "\(store.theme.name)・\(store.layout.name)"
        HStack(spacing: 14) {
            WorldThumb(palette: p)
                .miniThumb(width: 96, height: 76, scale: 0.62)
                .clipShape(thumbShape)
                .overlay(thumbShape.strokeBorder(p.sub.opacity(0.15), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text("デザインを変える")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(p.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(current)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(p.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("世界観・色合い・構成など")
                    .font(.caption)
                    .foregroundStyle(p.sub)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("デザインを変える。いまは\(current)")
        .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// 大きめに描いた見本を縮めて小さな枠に入れる（文字が詰まって切れないように）
    func miniThumb(width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        self.frame(width: width / scale, height: height / scale)
            .scaleEffect(scale)
            .frame(width: width, height: height)
    }
}
