import SwiftUI

/// 「情報」タブ：好きな話題の記事・投稿をカードの山で読む。ゲーム（スプラトゥーン3・Steam・第五人格）への入口。相談は独立したタブ
struct InfoRootView: View {
    @StateObject private var model = InfoModel()
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @State private var section: InfoSection = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-infogames") ? .games : .topics
    }()
    @State private var opening: InfoOpenTarget?
    @State private var lastOpened: InfoArticle?
    @State private var openedAt = Date()
    /// ゲームの見出しの隠しコマンドで出した Discord の行。情報の画面を離れる（ほかのタブ・話題へ切り替える）と消す
    @State private var discordRevealed = InfoDiscordReveal.launchRevealed

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    InfoSegmented(selection: $section)
                    Spacer()
                    SettingsButton()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                switch section {
                case .topics:
                    InfoTopicsScreen(onOpen: open, onOpenURL: openURL)
                        .transition(motion.appear)
                case .games:
                    InfoGameSection(discordRevealed: $discordRevealed)
                        .transition(motion.appear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .paletteBackground(p)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear { discordRevealed = false }
        .onChange(of: section) { _, s in if s != .games { discordRevealed = false } }
        .environmentObject(model)
        .infoTranslation(model)
        .fullScreenCover(item: $opening, onDismiss: finishReading) { target in
            InfoSafariView(url: target.url, tint: p.accent) { opening = nil }
                .ignoresSafeArea()
        }
        .task { await model.refreshIfStale() }
    }

    private func open(_ a: InfoArticle) {
        guard let url = URL(string: a.link), url.scheme == "https" || url.scheme == "http" else { return }
        model.opened(a)
        lastOpened = a
        openedAt = .now
        opening = InfoOpenTarget(url: url, article: a)
    }

    private func openURL(_ url: URL) {
        lastOpened = nil
        opening = InfoOpenTarget(url: url, article: nil)
    }

    private func finishReading() {
        if let a = lastOpened { model.dwell(a, seconds: Date().timeIntervalSince(openedAt)) }
        lastOpened = nil
    }
}

/// 話題の編集シートに渡すもの
struct InfoTopicEdit: Identifiable {
    let id = UUID()
    var topic: InfoTopic
    let isNew: Bool
}

// MARK: - 話題：未読の数・絞り込みのチップ・カードの山（または一覧）

struct InfoTopicsScreen: View {
    @EnvironmentObject var model: InfoModel
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpen: (InfoArticle) -> Void
    let onOpenURL: (URL) -> Void
    @State private var filter: InfoFilter = .all
    @State private var listMode = !ProcessInfo.processInfo.arguments.contains("-infodeck")   // 最初は一覧（-infodeck でカード：スクリーンショット用）
    @State private var editing: InfoTopicEdit?
    @Namespace private var chipSpace

    private var currentTopic: InfoTopic? {
        if case .topic(let id) = filter { return model.topics.first { $0.id == id } }
        return nil
    }

    private var showList: Bool { listMode || filter == .saved }

    var body: some View {
        VStack(spacing: 10) {
            header
            chips
            statusLine
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.bottom, 10)
        .sheet(item: $editing) { e in
            InfoTopicSheet(topic: e.topic, isNew: e.isNew)
                .environmentObject(model)
                .environment(\.palette, p)
                .environment(\.motion, motion)
        }
        .onChange(of: model.topics) { _, topics in
            if case .topic(let id) = filter, !topics.contains(where: { $0.id == id }) { filter = .all }
        }
    }

    // 「未読 12 件」・一覧の切り替え・メニュー
    private var header: some View {
        let isSaved: Bool = filter == .saved
        let count: Int = model.deck(filter).count
        return HStack(alignment: .center, spacing: 8) {
            BigCount(prefix: isSaved ? "保存" : "未読", value: count, suffix: "件")
            if !isSaved {
                Button {
                    withAnimation(reduceMotion ? nil : motion.change) { listMode.toggle() }
                } label: {
                    InfoRoundIcon(symbol: listMode ? "rectangle.stack" : "list.bullet")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(listMode ? "カードで見る" : "一覧で見る")
            }
            menu
        }
        .padding(.horizontal, 20)
    }

    private var menu: some View {
        Menu {
            Button { editing = InfoTopicEdit(topic: InfoTopic(keyword: ""), isNew: true) } label: {
                Label("話題を追加", systemImage: "plus")
            }
            if let t = currentTopic {
                Button { editing = InfoTopicEdit(topic: t, isNew: false) } label: {
                    Label("「\(t.keyword)」を編集", systemImage: "pencil")
                }
                if let url = t.xSearchURL {
                    Button { onOpenURL(url) } label: { Label("X で見る", systemImage: "magnifyingglass") }
                }
            }
            Button { Task { await model.refresh() } } label: {
                Label("今すぐ更新", systemImage: "arrow.clockwise")
            }
            .disabled(model.loading || model.isDemo)
            Divider()
            Button(role: .destructive) { model.resetPrefs() } label: {
                Label("おすすめの学習をリセット", systemImage: "arrow.counterclockwise")
            }
        } label: {
            InfoRoundIcon(symbol: "ellipsis")
        }
        .accessibilityLabel("メニュー")
    }

    // 絞り込み：すべて・おすすめ・各話題・あとで読む・追加
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(.all, InfoChip(title: "すべて", count: model.deck(.all).count, selected: filter == .all, ns: chipSpace))
                chipButton(.recommend, InfoChip(title: "おすすめ", symbol: "sparkles", selected: filter == .recommend, ns: chipSpace))
                ForEach(model.topics) { t in
                    topicChip(t)
                }
                chipButton(.saved, InfoChip(title: "あとで読む", symbol: "bookmark", count: model.saved.count,
                                            selected: filter == .saved, ns: chipSpace))
                Button { editing = InfoTopicEdit(topic: InfoTopic(keyword: ""), isNew: true) } label: {
                    InfoChip(title: "追加", symbol: "plus", selected: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("話題を追加")
            }
            .padding(.horizontal, 20)
        }
    }

    private func chipButton(_ f: InfoFilter, _ chip: InfoChip) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : motion.tap) { filter = f }
        } label: { chip }
        .buttonStyle(.plain)
    }

    private func topicChip(_ t: InfoTopic) -> some View {
        let chip = InfoChip(title: t.keyword, dot: InfoTopicColor.color(t.color, p), count: model.unreadCount(t),
                            selected: filter == .topic(t.id), ns: chipSpace)
        return chipButton(.topic(t.id), chip)
            .contextMenu {
                Button { editing = InfoTopicEdit(topic: t, isNew: false) } label: { Label("編集", systemImage: "pencil") }
                if let url = t.xSearchURL {
                    Button { onOpenURL(url) } label: { Label("X で見る", systemImage: "magnifyingglass") }
                }
                Button(role: .destructive) { model.delete(t) } label: { Label("削除", systemImage: "trash") }
            }
    }

    // 更新の状態（オフラインのときは前回の記事を出していることを伝える）
    private var statusLine: some View {
        HStack(spacing: 6) {
            statusText
            Spacer()
            if model.loading {
                ProgressView().controlSize(.small)
            } else if !model.isDemo {
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(p.accent)
                .accessibilityLabel("更新")
            }
        }
        .font(.caption)
        .foregroundStyle(p.sub)
        .padding(.horizontal, 24)
        .frame(height: 20)
    }

    @ViewBuilder
    private var statusText: some View {
        if model.loading {
            Text("新しい記事を集めています…")
        } else if model.offline {
            Label("オフライン。前回集めた記事を表示しています", systemImage: "wifi.slash")
                .foregroundStyle(p.overdue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if let d = model.lastUpdated {
            Text("最終更新 \(JP.time(d))")
        } else {
            Text("まだ更新していません")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.topics.isEmpty && (filter == .all || currentTopic != nil) {
            InfoEmptyTopics { keyword in
                editing = InfoTopicEdit(topic: InfoTopic(keyword: keyword), isNew: true)
            }
        } else if showList {
            InfoListView(filter: filter, onOpen: onOpen, onOpenURL: onOpenURL)
        } else {
            InfoDeckView(filter: filter, onOpen: onOpen, onOpenURL: onOpenURL) {
                withAnimation(reduceMotion ? nil : motion.change) { listMode = true }
            }
        }
    }
}

// MARK: - 話題がまだ無いとき

struct InfoEmptyTopics: View {
    @Environment(\.palette) private var p
    let onAdd: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "newspaper.fill").font(.system(size: 52)).foregroundStyle(p.accent)
                Text("好きな話題を追加しましょう").font(.title3.bold()).foregroundStyle(p.text)
                Text("キーワードを登録すると、ニュース・はてなブックマーク・Bluesky から関連する記事や投稿を集めて、カードで1枚ずつ見られます。")
                    .font(.subheadline).foregroundStyle(p.sub).multilineTextAlignment(.center)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(InfoData.suggestions, id: \.self) { s in
                        Button { onAdd(s) } label: { InfoChip(title: s, symbol: "plus", selected: false) }
                            .buttonStyle(.plain)
                    }
                }
                Button { onAdd("") } label: {
                    Text("話題を追加").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(p.accent, in: Capsule())
                        .foregroundStyle(p.onAccent)
                }
                .buttonStyle(.plain)
            }
            .paletteCard(p, padding: 24)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

// MARK: - ゲーム：スプラトゥーン3・Steam・第五人格への入口（並びと表示は GameOrderSheet で変える）

/// ゲームのくわしく画面（第五人格はカードの中にボタンがあるので、NavigationLink ではなく行き先で開く）
enum InfoGameRoute: Hashable {
    case discord, identityV
}

struct InfoGameSection: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 隠しの Discord の行を出しているか（InfoRootView が持つ。情報の画面を離れると消える）
    @Binding var discordRevealed: Bool
    /// Web版 Discord（試作）。起動引数 -discordweb で最初から開く（画面写真用。-demo なら通信しない）
    @State private var showDiscord = ProcessInfo.processInfo.arguments.contains("-discordweb")
    /// 起動引数 -discorddemo で Discord、-idvdemo で第五人格のくわしく画面を開く（画面写真用）
    @State private var route: InfoGameRoute? = {
        let a = ProcessInfo.processInfo.arguments
        if a.contains("-discorddemo") { return .discord }
        if a.contains("-idvdemo") { return .identityV }
        return nil
    }()
    /// 並びと表示のシート。起動引数 -gamesettings で開いた状態にする（画面写真用）
    @State private var showOrder = ProcessInfo.processInfo.arguments.contains("-gamesettings")
    @State private var games: [GameItem] = SettingsData.load().visibleGames
    /// 見出しを続けて押した回数と、最後に押した時刻
    @State private var headerTaps = 0
    @State private var lastHeaderTap = Date.distantPast

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Text("ゲーム").font(.largeTitle.weight(.heavy)).foregroundStyle(p.text)
                        .contentShape(Rectangle())
                        .onTapGesture { headerTapped() }
                    Spacer()
                    Button { showOrder = true } label: {
                        Image(systemName: "arrow.up.arrow.down").font(.body.weight(.bold)).foregroundStyle(p.text)
                            .frame(width: 40, height: 40)
                            .background(p.card, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ゲームの並びと表示")
                }
                Text("戦績やゲームの情報を、日和のデザインで見られます。")
                    .font(.subheadline).foregroundStyle(p.sub)
                ForEach(games) { g in
                    card(g).id(g.rawValue)
                }
                if games.isEmpty { emptyNote }
                if discordRevealed {
                    InfoDiscordRow { route = .discord }
                        .id("discord")
                        .transition(floatUp)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onAppear {
            // 画面写真用：-gamesscroll でいちばん下のカードまで下げる
            guard ProcessInfo.processInfo.arguments.contains("-gamesscroll") else { return }
            let last: String = discordRevealed ? "discord" : (games.last?.rawValue ?? "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(last, anchor: .top) }
        }
        }
        .navigationDestination(item: $route) { r in
            switch r {
            case .discord: DiscordHome()
            case .identityV: IdvHome()
            }
        }
        .fullScreenCover(isPresented: $showDiscord) {
            DiscordWebScreen { showDiscord = false }
                .environment(\.palette, p)
                .environment(\.motion, motion)
        }
        .sheet(isPresented: $showOrder, onDismiss: reloadGames) {
            GameOrderSheet()
                .environment(\.palette, p)
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: reloadGames)
    }

    @ViewBuilder
    private func card(_ g: GameItem) -> some View {
        switch g {
        case .splatoon:
            NavigationLink { SplatoonHome() } label: { SplatoonEntryCard() }
                .buttonStyle(.plain)
        case .steam:
            NavigationLink { SteamHome() } label: { SteamEntryCard() }
                .buttonStyle(.plain)
        case .identityV:
            Button { route = .identityV } label: { IdvEntryCard() }
                .buttonStyle(.plain)
        }
    }

    private var emptyNote: some View {
        Text("表示するゲームがありません。右上の ↑↓ から選べます。")
            .font(.subheadline).foregroundStyle(p.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paletteCard(p, padding: 18)
    }

    /// 下からふわっと浮かび上がる（「視差効果を減らす」ではフェードだけ）
    private var floatUp: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        let rise: AnyTransition = AnyTransition.offset(y: 36).combined(with: .opacity)
        let scale: AnyTransition = AnyTransition.scale(scale: 0.96, anchor: .bottom)
        return rise.combined(with: scale)
    }

    private func reloadGames() {
        let next: [GameItem] = SettingsData.load().visibleGames
        if next != games { withAnimation(motion.change) { games = next } }
    }

    /// 見出しを 8 回すばやく押すと Discord の行が出る（押すあいだが 0.7 秒より空いたら数え直す）
    private func headerTapped() {
        let now = Date()
        let gap: TimeInterval = now.timeIntervalSince(lastHeaderTap)
        headerTaps = gap <= InfoDiscordReveal.maxGap ? headerTaps + 1 : 1
        lastHeaderTap = now
        guard headerTaps >= InfoDiscordReveal.taps, !discordRevealed else { return }
        headerTaps = 0
        let anim: Animation = reduceMotion ? Animation.easeOut(duration: 0.3) : Animation.easeOut(duration: 1.1)
        withAnimation(anim) { discordRevealed = true }
    }
}

/// 隠しコマンドの決まり（画面には何も出さない）
enum InfoDiscordReveal {
    /// 見出しを押す回数
    static let taps = 8
    /// 続けて押したとみなす間隔（秒）
    static let maxGap: TimeInterval = 0.7
    /// 画面写真用：起動引数 -discordreveal で最初から出しておく
    static var launchRevealed: Bool { ProcessInfo.processInfo.arguments.contains("-discordreveal") }
}

/// 隠しの Discord の行（押すと Discord のくわしく画面へ）
private struct InfoDiscordRow: View {
    let onOpen: () -> Void

    var body: some View {
        let shape: RoundedRectangle = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: onOpen) {
            HStack(spacing: 12) {
                DiscordBubbleIcon(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discord").font(.headline.weight(.heavy)).foregroundStyle(DiscordInk.text)
                    Text("サーバーの様子・お知らせ・募集").font(.caption).foregroundStyle(DiscordInk.sub).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(DiscordInk.sub)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DiscordInk.surface, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - ゲームの並びと表示（情報 › ゲームの右上 ↑↓ から開く。設定 settings.json に保存）

struct GameOrderSheet: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var order: [GameItem] = SettingsData.load().gameOrderItems
    @State private var hidden: Set<String> = Set(SettingsData.load().hiddenGames)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { g in
                        row(g)
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("右の ≡ をドラッグすると並びが変わります。オフにしたゲームは、一覧と情報のウィジェットに出ません。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle("ゲームの並びと表示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(p.accent)
    }

    private func row(_ g: GameItem) -> some View {
        let on: Binding<Bool> = Binding(
            get: { !hidden.contains(g.rawValue) },
            set: { v in
                if v { hidden.remove(g.rawValue) } else { hidden.insert(g.rawValue) }
                save()
            })
        return Toggle(isOn: on) {
            Label(g.title, systemImage: g.symbol).foregroundStyle(p.text)
        }
        .listRowBackground(p.card)
    }

    private func move(_ from: IndexSet, _ to: Int) {
        order.move(fromOffsets: from, toOffset: to)
        save()
    }

    /// 並びと表示だけを書き戻す（ほかの設定を古い値で上書きしない）。情報のウィジェットにもすぐ反映する
    private func save() {
        var fresh = SettingsData.load()
        let raw: [String] = order.map(\.rawValue)
        fresh.gameOrder = raw
        fresh.hiddenGames = raw.filter { hidden.contains($0) }
        SettingsData.save(fresh)
        InfoWidgetSync.update()
    }
}
