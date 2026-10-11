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

    var start: Date? = nil
    var text: String? = nil

    var body: some View {
        let n: Int = IdvDates.daysLeft(end)
        let notYet: Bool = start.map { IdvDates.daysLeft($0) > 0 } ?? false
        let urgent: Bool = !notYet && n >= 0 && n <= 3
        let fill: Color = n < 0 ? IdvInk.line : (urgent ? IdvInk.red : IdvInk.panel)
        Text(text ?? IdvDates.label(end))
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
            if let s = store.season, let line = IdvSeasonCard.shortLine(s) {
                Text(line).font(.caption.weight(.bold)).foregroundStyle(IdvInk.gold).lineLimit(1)
            }
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
    @State private var editingSeason = false

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 18) {
            header
            IdvSeasonCard(season: store.season, overridden: store.seasonOverride.season != nil) { editingSeason = true }
                .id("season")
            scheduleSection
                .id("schedule")
            deadlines
                .id("deadlines")
            newsSection
            Text("お知らせは公式 YouTube チャンネル、公式サイトのアップデート情報、運営のプレスリリース（PR TIMES）から読み込みます。NetEase Games とは関係のない個人のアプリです。")
                .font(.caption2).foregroundStyle(IdvInk.sub)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)

        ScrollViewReader { proxy in
            ScrollView { content }
                .onAppear { Self.scrollForShot(proxy) }
        }
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
            .sheet(isPresented: $editingSeason) { IdvSeasonSheet() }
            .task { await store.prepareNotifications() }
    }

    /// 画面写真用：起動引数 -idvscroll schedule|deadlines でその欄まで下げておく
    private static func scrollForShot(_ proxy: ScrollViewProxy) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-idvscroll"), i + 1 < args.count else { return }
        let target = args[i + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(target, anchor: .top) }
    }

    private func open(_ link: String?) {
        guard let link, let u = URL(string: link), u.scheme == "https" else { return }
        opening = IdvLink(url: u)
    }

    // メンテナンス・アップデートの予定
    private var scheduleSection: some View {
        let items: [IdvScheduleItem] = store.schedule
        let upcoming: [IdvScheduleItem] = items.filter { !$0.isPast() }
        let past: [IdvScheduleItem] = Array(items.filter { $0.isPast() }.prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            Text("予定").font(.system(.headline, design: .serif)).foregroundStyle(IdvInk.sepia)
            if items.isEmpty {
                Text("メンテナンスやアップデートのお知らせが見つかると、ここに日時を出します。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
            }
            ForEach(upcoming.prefix(6)) { s in
                IdvScheduleRow(item: s, past: false) { open(s.link) }
            }
            ForEach(past) { s in
                IdvScheduleRow(item: s, past: true) { open(s.link) }
            }
            if upcoming.contains(where: { $0.kind == .maintenance && $0.hasTime }) {
                Text("メンテナンスの始まる1時間前に通知します").font(.caption2).foregroundStyle(IdvInk.sub)
            }
        }
        .padding(16)
        .background(IdvInk.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
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
                ForEach(found.prefix(6)) { e in
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
        let period: String = e.start.map { "\(JP.shortDate($0))〜\(JP.shortDate(e.end))" } ?? "\(JP.date(e.end))まで"
        let sub: String = suggested ? "\(period)・\(e.label)" : period
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let tag = e.tag { IdvTagChip(text: tag) }
                    Text(e.title).font(.subheadline.weight(.semibold)).foregroundStyle(IdvInk.sepia).lineLimit(2)
                }
                Text(sub).font(.caption).foregroundStyle(IdvInk.sub)
            }
            Spacer(minLength: 6)
            if suggested {
                Button {
                    withAnimation(.snappy) { store.add(IdvEvent(title: e.title, end: e.end, link: e.link, start: e.start, tag: e.tag)) }
                } label: {
                    Label("登録", systemImage: "bell").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sepia)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(IdvInk.red, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("期限に登録して、前日に通知します")
            } else {
                IdvDaysBadge(end: e.end, start: e.start, text: e.label)
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
                TextField("", text: $title, prompt: Text("例：推理の径 第3章").foregroundStyle(IdvInk.sub.opacity(0.8)))
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

// MARK: - 予定・コラボの小さな部品

private struct IdvTagChip: View {
    let text: String

    var body: some View {
        let fill: Color = text == "コラボ" ? IdvInk.red : (text == "メンテナンス" ? IdvInk.line : IdvInk.gold.opacity(0.28))
        Text(text).font(.caption2.weight(.heavy)).foregroundStyle(IdvInk.sepia)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct IdvScheduleRow: View {
    let item: IdvScheduleItem
    let past: Bool
    let open: () -> Void

    var body: some View {
        let when: String = IdvSchedule.label(item)
        let row = HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    IdvTagChip(text: item.kind.label)
                    Text(when).font(.system(.subheadline, design: .serif).weight(.bold)).foregroundStyle(IdvInk.sepia)
                        .monospacedDigit()
                }
                Text(item.title).font(.footnote).foregroundStyle(IdvInk.sub).lineLimit(2)
            }
            Spacer(minLength: 4)
            if item.link != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub).padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .opacity(past ? 0.45 : 1)
        .contentShape(Rectangle())

        Button(action: open) { row }
            .buttonStyle(.plain)
            .disabled(item.link == nil)
            .accessibilityLabel("\(item.kind.label)、\(when)、\(item.title)\(past ? "、終了" : "")")
    }
}

// MARK: - ランクマッチのシーズン（いちばん上のカード）

struct IdvSeasonCard: View {
    let season: IdvSeason?
    let overridden: Bool
    let edit: () -> Void

    /// 入口のカードに出す1行（終わる日が分かるときだけ）
    static func shortLine(_ s: IdvSeason) -> String? {
        guard let e = s.end else { return nil }
        let n = IdvDates.daysLeft(e)
        guard n >= 0 else { return nil }
        return "ランクマ \(s.title) 終了まで" + (n == 0 ? "今日" : "あと\(n)日")
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            Text("RANK MATCH").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(IdvInk.gold)
            if let s = season {
                found(s)
            } else {
                Text("シーズン情報が見つかりませんでした").font(.system(.headline, design: .serif)).foregroundStyle(IdvInk.sepia)
                Text("公式のお知らせにシーズンの日付が出ると、ここに「終了まであと◯日」を出します。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
            }
            Button(action: edit) {
                Text("日付がずれているとき").font(.caption.weight(.semibold)).foregroundStyle(IdvInk.sub).underline()
            }
            .buttonStyle(.plain)
            .accessibilityHint("シーズンの名前と日付を手で入れて上書きします")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)

        let fill = LinearGradient(colors: [IdvInk.red.opacity(0.35), IdvInk.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IdvInk.gold.opacity(0.45), lineWidth: 1))
    }

    @ViewBuilder
    private func found(_ s: IdvSeason) -> some View {
        let days: Int? = s.end.map { IdvDates.daysLeft($0) }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("ランクマ \(s.title)").font(.system(.title3, design: .serif).weight(.bold)).foregroundStyle(IdvInk.sepia)
            Spacer(minLength: 4)
            if let d = days {
                let urgent: Bool = d >= 0 && d <= 3
                Text(d < 0 ? "終了" : (d == 0 ? "今日で終了" : "終了まであと\(d)日"))
                    .font(.system(.headline, design: .serif).weight(.heavy))
                    .foregroundStyle(urgent ? IdvInk.redBright : IdvInk.sepia)
            }
        }
        if let p = s.progress() {
            IdvProgressBar(value: p)
                .accessibilityLabel("シーズンの進み具合")
                .accessibilityValue("\(Int((p * 100).rounded()))パーセント")
        }
        Text(periodText(s)).font(.caption).foregroundStyle(IdvInk.sub).monospacedDigit()
        Text(sourceText(s)).font(.caption2).foregroundStyle(IdvInk.sub)
    }

    private func sourceText(_ s: IdvSeason) -> String {
        if overridden { return "手動で入れた日付を使っています" }
        let notice: String = s.end != nil ? "・終了の3日前と前日に通知" : ""
        return "出どころ：\(s.source)\(notice)"
    }

    private func periodText(_ s: IdvSeason) -> String {
        switch (s.start, s.end) {
        case let (a?, b?): return "\(JP.date(a))〜\(JP.date(b))"
        case let (a?, nil): return "\(JP.date(a))から・終了日はまだ発表されていません"
        case let (nil, b?): return "\(JP.date(b))まで"
        default: return "期間はまだ見つかっていません"
        }
    }
}

private struct IdvProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = max(6, geo.size.width * CGFloat(value))
            let bar = LinearGradient(colors: [IdvInk.red, IdvInk.redBright], startPoint: .leading, endPoint: .trailing)
            ZStack(alignment: .leading) {
                Capsule().fill(IdvInk.base.opacity(0.8))
                Capsule().fill(bar).frame(width: w)
            }
        }
        .frame(height: 8)
        .overlay(Capsule().strokeBorder(IdvInk.line, lineWidth: 1))
    }
}

// MARK: - シーズンの手動の上書き（「日付がずれているとき」）

private struct IdvSeasonSheet: View {
    @ObservedObject private var store = IdvStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = IdvSeasonOverride()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("ふだんは公式のお知らせから自動で読み取ります。日付がずれているときだけ、ここで上書きしてください。")
                    .font(.subheadline).foregroundStyle(IdvInk.sub)
                Toggle("手動の日付を使う", isOn: $draft.enabled)
                    .foregroundStyle(IdvInk.sepia)
                    .tint(IdvInk.redBright)
                if draft.enabled { fields }
                Spacer()
            }
            .padding(20)
            .background(IdvInk.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("日付がずれているとき")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() }.foregroundStyle(IdvInk.sepia) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.setOverride(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(IdvInk.sepia)
                }
            }
            .onAppear { draft = initialDraft() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var fields: some View {
        TextField("", text: $draft.name, prompt: Text("例：シーズン44").foregroundStyle(IdvInk.sub.opacity(0.8)))
            .foregroundStyle(IdvInk.sepia)
            .padding(.horizontal, 12).frame(height: 46)
            .background(IdvInk.base, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
        DatePicker("始まる日", selection: $draft.start, displayedComponents: .date)
            .foregroundStyle(IdvInk.sepia).tint(IdvInk.redBright)
        DatePicker("終わる日", selection: $draft.end, in: draft.start..., displayedComponents: .date)
            .foregroundStyle(IdvInk.sepia).tint(IdvInk.redBright)
    }

    private func initialDraft() -> IdvSeasonOverride {
        var d = store.seasonOverride
        guard !d.enabled, let s = store.detectedSeason else { return d }
        d.name = s.title
        if let a = s.start { d.start = a }
        if let b = s.end { d.end = b }
        return d
    }
}
