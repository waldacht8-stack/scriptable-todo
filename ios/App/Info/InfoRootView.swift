import SwiftUI

/// 「情報」タブ：好きな話題の記事・投稿をカードの山で読む。ゲーム（スプラトゥーン3・Steam）への入口
struct InfoRootView: View {
    @StateObject private var model = InfoModel()
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @State private var section: InfoSection = .topics
    @State private var opening: InfoOpenTarget?
    @State private var lastOpened: InfoArticle?
    @State private var openedAt = Date()

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
                    InfoGameSection()
                        .transition(motion.appear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .paletteBackground(p)
            .toolbar(.hidden, for: .navigationBar)
        }
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
    @State private var listMode = false
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

// MARK: - ゲーム：スプラトゥーン3・Steam への入口

struct InfoGameSection: View {
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ゲーム").font(.largeTitle.weight(.heavy)).foregroundStyle(p.text)
                Text("戦績やゲームの情報を、日和のデザインで見られます。")
                    .font(.subheadline).foregroundStyle(p.sub)
                NavigationLink { SplatoonHome() } label: { SplatoonEntryCard() }
                    .buttonStyle(.plain)
                NavigationLink { SteamHome() } label: { SteamEntryCard() }
                    .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
