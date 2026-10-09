import SwiftUI

// MARK: - 一覧（すべての記事を小さな行で。あとで読むの一覧もここ）

struct InfoListView: View {
    @EnvironmentObject var model: InfoModel
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filter: InfoFilter
    let onOpen: (InfoArticle) -> Void
    let onOpenURL: (URL) -> Void

    private var topic: InfoTopic? {
        if case .topic(let id) = filter { return model.topics.first { $0.id == id } }
        return nil
    }

    var body: some View {
        let items: [InfoArticle] = model.list(filter)
        List {
            if items.isEmpty {
                emptyRow.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(items) { a in
                InfoRow(article: a, read: filter != .saved && model.readIDs.contains(a.id))
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen(a) }
                    .listRowBackground(p.card)
                    .swipeActions(edge: .leading) { leading(a) }
                    .swipeActions(edge: .trailing) { trailing(a) }
            }
            if let t = topic, let url = t.xSearchURL {
                Button { onOpenURL(url) } label: {
                    Label("X で「\(t.keyword)」の反応を見る", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(p.accent)
                }
                .listRowBackground(p.card)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : motion.change, value: items.map(\.id))
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private func leading(_ a: InfoArticle) -> some View {
        if filter == .saved {
            Button { model.markRead(a) } label: { Label("既読", systemImage: "checkmark") }.tint(p.sub)
        } else if model.isSaved(a) {
            Button { model.unsave(a) } label: { Label("保存をやめる", systemImage: "bookmark.slash") }.tint(p.sub)
        } else {
            Button { model.save(a) } label: { Label("あとで読む", systemImage: "bookmark") }.tint(p.accent)
        }
    }

    @ViewBuilder
    private func trailing(_ a: InfoArticle) -> some View {
        if filter == .saved {
            Button(role: .destructive) { model.unsave(a) } label: { Label("削除", systemImage: "trash") }
        } else if model.readIDs.contains(a.id) {
            Button { model.markUnread(a) } label: { Label("未読に戻す", systemImage: "circle") }.tint(p.accent)
        } else {
            Button { model.markRead(a) } label: { Label("既読", systemImage: "checkmark") }.tint(p.sub)
        }
    }

    private var emptyRow: some View {
        VStack(spacing: 10) {
            Image(systemName: filter == .saved ? "bookmark" : "tray").font(.system(size: 44)).foregroundStyle(p.sub)
            Text(filter == .saved ? "あとで読む記事はありません" : "まだ記事がありません")
                .font(.headline).foregroundStyle(p.text)
            Text(filter == .saved ? "カードを右にスワイプすると、ここに保存されます。"
                 : (model.offline ? "インターネットにつながりません。下に引っぱると取り直します。" : "下に引っぱると新しい記事を集めます。"))
                .font(.subheadline).foregroundStyle(p.sub).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// 一覧の1行：小さな画像・見出し・元と時間
struct InfoRow: View {
    @EnvironmentObject var model: InfoModel
    @Environment(\.palette) private var p
    let article: InfoArticle
    let read: Bool

    private var tint: Color {
        guard let t = model.topic(for: article) else { return p.accent }
        return InfoTopicColor.color(t.color, p)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InfoThumb(article: article, tint: tint, symbolSize: 20)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.title(article))
                    .font(.subheadline.weight(read ? .regular : .semibold))
                    .foregroundStyle(read ? p.sub : p.text)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if article.isPost, let h = article.handle {
                        Text("@" + h).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                    }
                    InfoMeta(article: article)
                    if model.isTranslated(article) {
                        Image(systemName: "character.bubble").font(.caption2).foregroundStyle(p.accent)
                            .accessibilityLabel("翻訳済み")
                    }
                    if model.isSaved(article) {
                        Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(p.accent)
                            .accessibilityLabel("あとで読む")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
