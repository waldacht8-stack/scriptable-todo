import SwiftUI

// MARK: - 第五人格の見た目（暗いヴィクトリア調：セピアと深い赤。公式のロゴや画像は使わない）

enum IdvInk {
    static let top = Color(red: 0.165, green: 0.114, blue: 0.090)      // #2A1D17
    static let base = Color(red: 0.082, green: 0.063, blue: 0.051)     // #15100D
    static let panel = Color(red: 0.169, green: 0.129, blue: 0.106)    // #2B211B
    static let line = Color(red: 0.290, green: 0.212, blue: 0.157)     // #4A3628
    static let sepia = Color(red: 0.914, green: 0.863, blue: 0.765)    // #E9DCC3
    static let sub = Color(red: 0.718, green: 0.635, blue: 0.533)      // #B7A288
    static let red = Color(red: 0.620, green: 0.122, blue: 0.141)      // #9E1F24
    static let redBright = Color(red: 0.761, green: 0.216, blue: 0.235) // #C2373C
    static let gold = Color(red: 0.784, green: 0.643, blue: 0.392)     // #C8A464

    static var background: LinearGradient {
        LinearGradient(colors: [top, base], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
    }
}

/// 飾りの線（左右に細い線と小さなひし形）
private struct IdvOrnament: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(IdvInk.gold.opacity(0.5)).frame(height: 1)
            Image(systemName: "suit.diamond.fill").font(.system(size: 7)).foregroundStyle(IdvInk.gold.opacity(0.8))
            Rectangle().fill(IdvInk.gold.opacity(0.5)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct IdvDaysBadge: View {
    let end: Date

    var body: some View {
        let n: Int = IdvDates.daysLeft(end)
        let urgent: Bool = n >= 0 && n <= 3
        let fill: Color = n < 0 ? IdvInk.line : (urgent ? IdvInk.red : IdvInk.panel)
        Text(IdvDates.label(end))
            .font(.system(.subheadline, design: .serif).weight(.bold))
            .foregroundStyle(n < 0 ? IdvInk.sub : IdvInk.sepia)
            .padding(.horizontal, 10).frame(height: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(urgent ? IdvInk.redBright : IdvInk.line, lineWidth: 1))
    }
}

struct IdvLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - 入口のカード

struct IdvEntryCard: View {
    @ObservedObject private var store = IdvStore.shared

    var body: some View {
        let next: IdvEvent? = store.nextEvent
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "theatermasks.fill").font(.title3).foregroundStyle(IdvInk.sepia)
                    .frame(width: 44, height: 44)
                    .background(IdvInk.red, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(IdvInk.gold.opacity(0.6), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("IDENTITY V").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(IdvInk.gold)
                    Text("第五人格").font(.system(.title3, design: .serif).weight(.bold)).foregroundStyle(IdvInk.sepia)
                }
                Spacer(minLength: 4)
                if let next { IdvDaysBadge(end: next.end) }
            }
            IdvOrnament()
            if let next {
                Text(next.title).font(.footnote.weight(.semibold)).foregroundStyle(IdvInk.sepia).lineLimit(1)
            }
            if let n = store.news.first {
                Text("お知らせ：\(n.title)").font(.caption).foregroundStyle(IdvInk.sub).lineLimit(2)
            } else {
                Text("公式のお知らせ・イベントの期限").font(.caption).foregroundStyle(IdvInk.sub)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)

        content
            .background(IdvInk.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .task { await store.refreshIfNeeded() }
    }
}

// MARK: - くわしく画面

struct IdvHome: View {
    @ObservedObject private var store = IdvStore.shared
    @State private var opening: IdvLink?
    @State private var adding = false

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 18) {
            header
            deadlines
            newsSection
            Text("お知らせは公式 YouTube チャンネルと、運営のプレスリリース（PR TIMES）から読み込みます。NetEase Games とは関係のない個人のアプリです。")
                .font(.caption2).foregroundStyle(IdvInk.sub)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)

        ScrollView { content }
            .refreshable { await store.refresh() }
            .background(IdvInk.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("第五人格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(IdvInk.top, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await store.refreshIfNeeded() }
            .fullScreenCover(item: $opening) { link in
                InfoSafariView(url: link.url, tint: IdvInk.redBright) { opening = nil }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $adding) { IdvAddSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IDENTITY V").font(.caption.weight(.bold)).tracking(3).foregroundStyle(IdvInk.gold)
            Text("第五人格").font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(IdvInk.sepia)
            IdvOrnament()
            HStack(spacing: 8) {
                if let x = IdvFeed.xURL {
                    Button { opening = IdvLink(url: x) } label: {
                        Label("X で見る", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.bold)).foregroundStyle(IdvInk.sepia)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(IdvInk.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("公式アカウントの投稿をアプリ内のブラウザで開きます")
                }
                Spacer()
                if store.loading { ProgressView().tint(IdvInk.sepia) }
            }
            Text(store.isDemo ? "見本のデータを表示しています" : (store.updatedAt.map { "最終更新 \(JP.time($0))・下に引っぱると更新" } ?? "下に引っぱると更新"))
                .font(.caption2).foregroundStyle(IdvInk.sub)
            if let e = store.error { Text(e).font(.footnote).foregroundStyle(IdvInk.redBright) }
        }
    }

    // イベント・シーズンの期限
    private var deadlines: some View {
        let list: [IdvEvent] = store.sortedEvents
        let found: [IdvEvent] = store.suggestions
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("イベント・シーズンの期限").font(.system(.headline, design: .serif)).foregroundStyle(IdvInk.sepia)
                Spacer()
                Button { adding = true } label: {
                    Label("追加", systemImage: "plus").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sepia)
                        .padding(.horizontal, 12).frame(height: 30)
                        .overlay(Capsule().strokeBorder(IdvInk.gold.opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            if list.isEmpty && found.isEmpty {
                Text("終わる日を登録すると「あと◯日」を表示し、前日の夜に知らせます。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
            }
            ForEach(list) { e in
                eventRow(e, suggested: false)
            }
            if !found.isEmpty {
                Text("お知らせから見つけた期間").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub).padding(.top, 4)
                ForEach(found.prefix(4)) { e in
                    eventRow(e, suggested: true)
                }
            }
            if !list.isEmpty {
                Text("終わる日の前日 19:00 に通知します").font(.caption2).foregroundStyle(IdvInk.sub)
            }
        }
        .padding(16)
        .background(IdvInk.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
    }

    private func eventRow(_ e: IdvEvent, suggested: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.title).font(.subheadline.weight(.semibold)).foregroundStyle(IdvInk.sepia).lineLimit(2)
                Text("\(JP.date(e.end))まで").font(.caption).foregroundStyle(IdvInk.sub)
            }
            Spacer(minLength: 6)
            if suggested {
                Button { withAnimation(.snappy) { store.add(IdvEvent(title: e.title, end: e.end, link: e.link)) } } label: {
                    Label("登録", systemImage: "bell").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sepia)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(IdvInk.red, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("期限に登録して、前日に通知します")
            } else {
                IdvDaysBadge(end: e.end)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !suggested {
                Button(role: .destructive) { withAnimation(.snappy) { store.remove(e) } } label: { Label("削除", systemImage: "trash") }
            }
        }
    }

    // 公式のお知らせ
    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("公式のお知らせ").font(.system(.headline, design: .serif)).foregroundStyle(IdvInk.sepia)
            if store.news.isEmpty {
                Text(store.loading ? "読み込み中…" : "まだお知らせがありません。下に引っぱると更新します。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
            }
            ForEach(store.news.prefix(20)) { n in
                Button { if let u = n.url { opening = IdvLink(url: u) } } label: { IdvNewsCard(news: n) }
                    .buttonStyle(.plain)
                    .accessibilityHint("アプリ内のブラウザで開きます")
            }
        }
    }
}

private struct IdvNewsCard: View {
    let news: IdvNews

    var body: some View {
        let video: Bool = news.kind == .video
        HStack(spacing: 0) {
            thumb
                .frame(width: 112)
                .frame(maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(video ? "動画" : "お知らせ").font(.caption2.weight(.heavy)).foregroundStyle(IdvInk.sepia)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(video ? IdvInk.red : IdvInk.line, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(InfoText.ago(news.date)).font(.caption2).foregroundStyle(IdvInk.sub)
                }
                Text(news.title).font(.footnote.weight(.semibold)).foregroundStyle(IdvInk.sepia)
                    .multilineTextAlignment(.leading).lineLimit(3)
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .frame(height: 86)
        .background(IdvInk.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
    }

    private var thumb: some View {
        ZStack {
            LinearGradient(colors: [IdvInk.red.opacity(0.6), IdvInk.base], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let s = news.image, let u = URL(string: s), u.scheme == "https" {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { placeholderIcon }
            } else {
                placeholderIcon
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholderIcon: some View {
        Image(systemName: news.kind == .video ? "play.rectangle.fill" : "envelope.open.fill")
            .font(.title2).foregroundStyle(IdvInk.sepia.opacity(0.8))
    }
}

// MARK: - 期限を足す

private struct IdvAddSheet: View {
    @ObservedObject private var store = IdvStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("イベントやシーズンの名前と、終わる日を入れてください。前日の 19:00 に通知します。")
                    .font(.subheadline).foregroundStyle(IdvInk.sub)
                TextField("", text: $title, prompt: Text("例：ランク戦 今シーズン").foregroundStyle(IdvInk.sub.opacity(0.8)))
                    .foregroundStyle(IdvInk.sepia)
                    .padding(.horizontal, 12).frame(height: 46)
                    .background(IdvInk.base, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
                DatePicker("終わる日", selection: $end, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    .foregroundStyle(IdvInk.sepia)
                    .tint(IdvInk.redBright)
                Spacer()
            }
            .padding(20)
            .background(IdvInk.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("期限を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() }.foregroundStyle(IdvInk.sepia) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        store.add(IdvEvent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), end: end, link: nil))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(IdvInk.sepia)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
