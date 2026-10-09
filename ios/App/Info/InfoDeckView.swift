import SwiftUI

// MARK: - カードの山（フォーカスの考え方）：右スワイプであとで読む、左で既読、タップで開く

struct InfoDeckView: View {
    @EnvironmentObject var model: InfoModel
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filter: InfoFilter
    let onOpen: (InfoArticle) -> Void
    let onOpenURL: (URL) -> Void
    let onShowList: () -> Void
    @State private var drag: CGSize = .zero
    @State private var feedback = 0

    private var topic: InfoTopic? {
        if case .topic(let id) = filter { return model.topics.first { $0.id == id } }
        return nil
    }

    var body: some View {
        let deck: [InfoArticle] = model.deck(filter)
        let reasons: [String: String] = filter == .recommend ? reasonMap() : [:]
        let shown: [InfoArticle] = Array(deck.prefix(3))
        VStack(spacing: 10) {
            ZStack {
                if shown.isEmpty && topic == nil { emptyCard }
                if shown.count < 3, let t = topic {
                    InfoDeckEndCard(topic: t, index: shown.count, onOpenURL: onOpenURL, onShowList: onShowList)
                }
                ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, a in
                    InfoDeckCard(article: a, index: index, drag: index == 0 ? drag : .zero, reason: reasons[a.id])
                        .onTapGesture { onOpen(a) }
                        .gesture(swipe(a), including: index == 0 ? .all : .none)
                        .contextMenu { menu(a) }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(reduceMotion ? nil : motion.change, value: shown.map(\.id))
            hints(visible: !shown.isEmpty)
        }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func reasonMap() -> [String: String] {
        var m: [String: String] = [:]
        for pick in model.recommended.prefix(40) { m[pick.id] = pick.reason }
        return m
    }

    private func hints(visible: Bool) -> some View {
        HStack {
            Label("既読", systemImage: "arrow.left").foregroundStyle(p.sub)
            Spacer()
            Label("あとで読む", systemImage: "arrow.right").labelStyle(TrailingIcon()).foregroundStyle(p.accent)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 32)
        .opacity(visible ? 1 : 0)
    }

    @ViewBuilder
    private func menu(_ a: InfoArticle) -> some View {
        Button { onOpen(a) } label: { Label("開く", systemImage: "safari") }
        Button { model.save(a); feedback += 1 } label: { Label("あとで読む", systemImage: "bookmark") }
        Button { model.markRead(a) } label: { Label("既読にする", systemImage: "checkmark.circle") }
        if model.translations[a.id] != nil {
            Button { model.toggleOriginal(a) } label: {
                Label(model.isTranslated(a) ? "原文を表示" : "日本語で表示", systemImage: "character.bubble")
            }
        }
        if let url = URL(string: a.link) {
            ShareLink(item: url) { Label("共有", systemImage: "square.and.arrow.up") }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .recommend ? "sparkles" : "checkmark.seal.fill")
                .font(.system(size: 60)).foregroundStyle(p.accent)
            Text(model.list(filter).isEmpty ? "まだ記事がありません" : "すべて読みました")
                .font(.title2.bold()).foregroundStyle(p.text)
            Text(emptyMessage).font(.subheadline).foregroundStyle(p.sub).multilineTextAlignment(.center)
            if !model.list(filter).isEmpty {
                Button(action: onShowList) {
                    Label("一覧で見る", systemImage: "list.bullet").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(p.card, in: Capsule())
                }
                .foregroundStyle(p.text)
            }
        }
        .padding(.horizontal, 32)
    }

    private var emptyMessage: String {
        if model.offline { return "インターネットにつながりません。つながったら上の更新ボタンで取り直せます。" }
        if model.loading { return "記事を集めています…" }
        return filter == .recommend ? "読んだり保存したりするほど、好みに合う記事が並びます。" : "新しい記事が届くとここに並びます。"
    }

    // テーマの動き方。「視差効果を減らす」のときは動かさない
    private var fly: Animation? { reduceMotion ? nil : motion.tap }
    private var rise: Animation? { reduceMotion ? .easeInOut(duration: 0.2) : motion.change }

    private func swipe(_ a: InfoArticle) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if v.translation.width > 120 {
                    withAnimation(fly) { drag = CGSize(width: reduceMotion ? 0 : 600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation(rise) { model.save(a); drag = .zero }; feedback += 1 }
                } else if v.translation.width < -120 {
                    withAnimation(fly) { drag = CGSize(width: reduceMotion ? 0 : -600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(rise) {
                            if filter == .saved { model.unsave(a) } else { model.markRead(a) }
                            drag = .zero
                        }
                    }
                } else {
                    withAnimation(fly) { drag = .zero }
                }
            }
    }
}

// MARK: - 1枚のカード

struct InfoDeckCard: View {
    @EnvironmentObject var model: InfoModel
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let article: InfoArticle
    let index: Int
    let drag: CGSize
    let reason: String?

    private var tint: Color {
        guard let t = model.topic(for: article) else { return p.accent }
        return InfoTopicColor.color(t.color, p)
    }

    private var framed: some View {
        let shape = RoundedRectangle(cornerRadius: p.radius + 4, style: .continuous)
        let shadow: Color = .black.opacity(p.scheme == .dark ? 0.3 : 0.12)
        return cardContent
            .frame(maxWidth: .infinity, maxHeight: 460, alignment: .top)
            .background(p.card)
            .clipShape(shape)
            .shadow(color: shadow, radius: 18, y: 8)
    }

    var body: some View {
        framed
            .overlay(alignment: .topTrailing) { stampView }
            .padding(.horizontal, 20)
            .scaleEffect(1 - CGFloat(index) * 0.05)
            .offset(x: drag.width, y: CGFloat(index) * 16 + drag.height * 0.1)
            .rotationEffect(.degrees(Double(drag.width) / 20))
    }

    @ViewBuilder
    private var cardContent: some View {
        if article.isPost {
            postContent
        } else {
            articleContent
        }
    }

    // 記事：上に画像、話題・元・時間、大きな見出し
    private var articleContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoThumb(article: article, tint: tint)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 10) {
                metaRow
                Text(model.title(article))
                    .font(.system(size: 24, weight: .bold, design: p.fontDesign))
                    .foregroundStyle(p.text)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
                if let s = article.summary, !s.isEmpty {
                    Text(s).font(.callout).foregroundStyle(p.sub).lineLimit(2)
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(20)
        }
    }

    // Bluesky の投稿：名前・ハンドル・本文・いいね/リポスト
    private var postContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            metaRow
            HStack(spacing: 10) {
                Text(String((article.author ?? "?").prefix(1)))
                    .font(.headline.weight(.bold)).foregroundStyle(p.onAccent)
                    .frame(width: 40, height: 40)
                    .background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.author ?? "").font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                    Text("@" + (article.handle ?? "")).font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            Text(model.title(article))
                .font(.system(size: 20, weight: .semibold, design: p.fontDesign))
                .foregroundStyle(p.text)
                .lineLimit(7)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)
            if article.image != nil {
                InfoThumb(article: article, tint: tint, symbolSize: 24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                Label("\(article.likes ?? 0)", systemImage: "heart")
                Label("\(article.reposts ?? 0)", systemImage: "arrow.2.squarepath")
                Spacer()
                translateToggle
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(p.sub)
            if let reason { reasonLine(reason) }
        }
        .padding(22)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            topicChip
            InfoMeta(article: article)
            Spacer(minLength: 4)
            if model.isTranslated(article) { InfoTranslatedBadge() }
        }
    }

    @ViewBuilder
    private var topicChip: some View {
        let name: String = model.topic(for: article)?.keyword ?? article.sourceName
        Text(name)
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var footer: some View {
        if let reason { reasonLine(reason) }
        HStack {
            if let s = InfoSource(rawValue: article.source), !article.isPost {
                Label(s.short, systemImage: s.symbol).font(.caption.weight(.semibold)).foregroundStyle(p.sub)
            }
            Spacer()
            translateToggle
        }
    }

    private func reasonLine(_ text: String) -> some View {
        Label(text, systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(p.accent)
            .lineLimit(1)
    }

    @ViewBuilder
    private var translateToggle: some View {
        if model.translations[article.id] != nil {
            Button { withAnimation(reduceMotion ? nil : motion.change) { model.toggleOriginal(article) } } label: {
                Text(model.isTranslated(article) ? "原文" : "日本語")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Capsule().stroke(p.sub.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.sub)
        } else if article.isForeign {
            Text(model.translationUnavailable ? "翻訳できないため原文のまま" : "原文のまま表示")
                .font(.caption2).foregroundStyle(p.sub)
        }
    }

    @ViewBuilder
    private var stampView: some View {
        if index == 0 && drag.width > 30 {
            stamp("保存", p.accent)
        } else if index == 0 && drag.width < -30 {
            stamp("既読", p.sub)
        }
    }

    private func stamp(_ text: String, _ color: Color) -> some View {
        // 型を明示（Xcode 26.3 では1つの式のままだと font があいまいになる）
        let label: Text = Text(verbatim: text).font(Font.title2.weight(.bold))
        let angle: Double = drag.width > 0 ? -12 : 12
        let fade: Double = Double(min(1, abs(drag.width) / 120))
        return label.foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(p.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(angle))
            .padding(.horizontal, 40).padding(.vertical, 24)
            .opacity(fade)
    }
}

// MARK: - 話題の最後のカード：X での反応を見る

struct InfoDeckEndCard: View {
    @Environment(\.palette) private var p
    @EnvironmentObject var model: InfoModel
    let topic: InfoTopic
    let index: Int
    let onOpenURL: (URL) -> Void
    let onShowList: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: p.radius + 4, style: .continuous)
        let tint: Color = InfoTopicColor.color(topic.color, p)
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundStyle(tint)
            Text("「\(topic.keyword)」の新着は以上です").font(.title3.bold()).foregroundStyle(p.text)
                .multilineTextAlignment(.center)
            Text(model.offline ? "インターネットにつながりません。" : "ほかの人の反応も見てみましょう。")
                .font(.subheadline).foregroundStyle(p.sub)
            if let url = topic.xSearchURL {
                Button { onOpenURL(url) } label: {
                    Label("X での反応を見る", systemImage: "magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(p.accent, in: Capsule())
                        .foregroundStyle(p.onAccent)
                }
                .buttonStyle(.plain)
            }
            Button(action: onShowList) {
                Text("一覧で見る").font(.subheadline.weight(.semibold)).foregroundStyle(p.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: 460)
        .background(p.card, in: shape)
        .shadow(color: .black.opacity(p.scheme == .dark ? 0.3 : 0.12), radius: 18, y: 8)
        .padding(.horizontal, 20)
        .scaleEffect(1 - CGFloat(index) * 0.05)
        .offset(y: CGFloat(index) * 16)
    }
}
