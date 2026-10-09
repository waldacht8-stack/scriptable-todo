import SwiftUI

// MARK: - Steam の見た目（濃い紺と水色。承認済みの案）

enum SteamInk {
    static let top = Color(red: 0.106, green: 0.157, blue: 0.220)      // #1B2838
    static let base = Color(red: 0.090, green: 0.102, blue: 0.129)     // #171A21
    static let panel = Color(red: 0.106, green: 0.149, blue: 0.200)    // #1B2633
    static let thumb = Color(red: 0.165, green: 0.278, blue: 0.369)    // #2A475E
    static let track = Color(red: 0.173, green: 0.231, blue: 0.298)    // #2C3B4C
    static let blue = Color(red: 0.400, green: 0.753, blue: 0.957)     // #66C0F4
    static let green = Color(red: 0.561, green: 0.820, blue: 0.416)    // #8FD16A
    static let sale = Color(red: 0.643, green: 0.816, blue: 0.027)     // #A4D007
    static let text = Color.white
    static let sub = Color(red: 0.682, green: 0.714, blue: 0.753)      // #AEB6C0
    static let warn = Color(red: 1.0, green: 0.55, blue: 0.45)

    static var background: LinearGradient {
        LinearGradient(colors: [top, base], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
    }
}

enum SteamFormat {
    static func hours(_ h: Double) -> String {
        h >= 10 ? String(format: "%.0f", h) : String(format: "%.1f", h)
    }

    static func ago(_ d: Date, now: Date = .now) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "たった今" }
        if m < 60 { return "\(m)分前" }
        if m < 60 * 24 { return "\(m / 60)時間前" }
        return "\(m / (60 * 24))日前"
    }
}

// MARK: - 全画面（情報タブのゲームから push される）

struct SteamHome: View {
    @ObservedObject private var store = SteamStore.shared

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 20) {
            if let s = store.snapshot {
                SteamProfileHeader(snapshot: s)
                SteamStatsRow(snapshot: s)
                SteamRecentSection(games: s.recent)
                SteamDealsSection(deals: s.deals)
                SteamNewsSection(news: s.news)
            } else if store.isConfigured {
                SteamLoadingPanel()
            } else {
                SteamIntroPanel()
            }
            if let err = store.error {
                Text(err).font(.footnote).foregroundStyle(SteamInk.warn)
            }
            SteamSettingsSection()
            Text("データは Steam Web API と Steam ストアから読み込みます。Valve とは関係のない個人のアプリです。")
                .font(.caption2).foregroundStyle(SteamInk.sub)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)

        ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .background(SteamInk.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Steam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SteamInk.top, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await store.refreshIfNeeded() }
    }
}

// MARK: - プロフィール

private struct SteamProfileHeader: View {
    @ObservedObject private var store = SteamStore.shared
    let snapshot: SteamSnapshot

    var body: some View {
        let p: SteamProfile? = snapshot.profile
        let online: Bool = p?.isOnline ?? false
        HStack(spacing: 14) {
            SteamAvatar(url: p?.avatar, online: online)
            VStack(alignment: .leading, spacing: 3) {
                Text("STEAM").font(.caption2.weight(.bold)).tracking(2.5).foregroundStyle(SteamInk.blue)
                Text(p?.name ?? "Steam").font(.title2.weight(.heavy)).foregroundStyle(SteamInk.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Circle().fill(online ? SteamInk.green : SteamInk.sub).frame(width: 7, height: 7)
                    Text(p?.stateText ?? "").lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(online ? SteamInk.green : SteamInk.sub)
                Text(store.isDemo ? "見本のデータを表示しています" : "\(SteamFormat.ago(snapshot.fetchedAt))に更新・下に引っぱると更新")
                    .font(.caption2).foregroundStyle(SteamInk.sub)
            }
            Spacer(minLength: 0)
            if store.loading { ProgressView().tint(SteamInk.blue) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SteamAvatar: View {
    let url: String?
    let online: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let border: Color = online ? SteamInk.green : SteamInk.sub
        ZStack {
            shape.fill(SteamInk.thumb)
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
            } else {
                Image(systemName: "person.fill").font(.title).foregroundStyle(SteamInk.sub)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(shape)
        .overlay(shape.strokeBorder(border, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

// MARK: - 数字の3つの箱

private struct SteamStatsRow: View {
    let snapshot: SteamSnapshot

    var body: some View {
        HStack(spacing: 8) {
            SteamStatBox(label: "2週間", value: SteamFormat.hours(snapshot.hours2Weeks), unit: "時間")
            SteamStatBox(label: "持っているゲーム", value: snapshot.ownedCount.map { String($0) } ?? "—", unit: "本")
            SteamStatBox(label: "実績（最近）", value: snapshot.achievedSum.map { String($0) } ?? "—", unit: "")
        }
    }
}

private struct SteamStatBox: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(SteamInk.sub).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.weight(.heavy)).foregroundStyle(SteamInk.text)
                    .contentTransition(.numericText())
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(SteamInk.sub) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SteamInk.panel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 最近遊んだゲーム

private struct SteamSectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.headline).foregroundStyle(SteamInk.text).padding(.top, 4)
    }
}

private struct SteamRecentSection: View {
    let games: [SteamGame]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SteamSectionTitle(title: "最近遊んだゲーム")
            if games.isEmpty {
                Text("この2週間に遊んだゲームはありません（プロフィールの「ゲームの詳細」が非公開だと表示されません）")
                    .font(.footnote).foregroundStyle(SteamInk.sub)
            }
            let maxH: Double = max(games.map(\.hours2Weeks).max() ?? 1, 0.1)
            ForEach(games) { g in
                SteamGameRow(game: g, maxHours: maxH)
            }
        }
    }
}

private struct SteamGameRow: View {
    @Environment(\.openURL) private var openURL
    let game: SteamGame
    let maxHours: Double

    /// 実績があれば達成率、なければ2週間の時間（いちばん長いゲームを満タンとする）
    private var ratio: Double {
        if let a = game.achieved, let t = game.achievementsTotal, t > 0 { return Double(a) / Double(t) }
        return game.hours2Weeks / maxHours
    }

    private var caption: String {
        var parts: [String] = ["2週間 \(SteamFormat.hours(game.hours2Weeks))時間"]
        if let a = game.achieved, let t = game.achievementsTotal { parts.append("実績 \(a) / \(t)") }
        else { parts.append("合計 \(SteamFormat.hours(game.hoursTotal))時間") }
        return parts.joined(separator: "・")
    }

    var body: some View {
        Button {
            if let u = game.storeURL { openURL(u) }
        } label: {
            HStack(spacing: 0) {
                SteamHeaderImage(url: game.headerURL)
                    .frame(width: 120)
                    .frame(maxHeight: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name).font(.subheadline.weight(.bold)).foregroundStyle(SteamInk.text).lineLimit(1)
                    SteamBar(ratio: ratio)
                    Text(caption).font(.caption2).foregroundStyle(SteamInk.sub).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                Spacer(minLength: 0)
            }
            .frame(height: 70)
            .background(SteamInk.panel)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(game.name)、\(caption)")
        .accessibilityHint("ストアのページを開きます")
    }
}

private struct SteamHeaderImage: View {
    let url: URL?
    var body: some View {
        ZStack {
            SteamInk.thumb
            if let url {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "gamecontroller.fill").foregroundStyle(SteamInk.sub)
                }
            }
        }
    }
}

private struct SteamBar: View {
    let ratio: Double
    @Environment(\.motion) private var motion

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width * CGFloat(min(max(ratio, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(SteamInk.track)
                Capsule().fill(SteamInk.blue).frame(width: max(w, 4))
            }
        }
        .frame(height: 8)
        .animation(motion.change, value: ratio)
    }
}

// MARK: - ウィッシュリストのセール

private struct SteamDealsSection: View {
    let deals: [SteamDeal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SteamSectionTitle(title: "ウィッシュリスト")
            if deals.isEmpty {
                Text("ウィッシュリストのゲームが見つかりませんでした").font(.footnote).foregroundStyle(SteamInk.sub)
            }
            ForEach(deals) { d in
                SteamDealRow(deal: d)
            }
        }
    }
}

private struct SteamDealRow: View {
    @Environment(\.openURL) private var openURL
    let deal: SteamDeal

    var body: some View {
        Button {
            if let u = deal.storeURL { openURL(u) }
        } label: {
            HStack(spacing: 8) {
                Text(deal.name).font(.subheadline.weight(.bold)).foregroundStyle(SteamInk.text).lineLimit(1)
                Spacer(minLength: 6)
                if deal.discount > 0 {
                    Text("-\(deal.discount)%")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(SteamInk.top)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(SteamInk.sale, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Text(deal.finalPrice ?? "—")
                    .font(.subheadline.weight(deal.discount > 0 ? .bold : .regular))
                    .foregroundStyle(deal.discount > 0 ? SteamInk.text : SteamInk.sub)
            }
            .padding(12)
            .background(SteamInk.panel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("ストアのページを開きます")
    }
}

// MARK: - ゲームのニュース

private struct SteamNewsSection: View {
    @Environment(\.openURL) private var openURL
    let news: [SteamNews]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SteamSectionTitle(title: "ゲームのニュース")
            if news.isEmpty {
                Text("最近遊んだゲームのニュースはまだありません").font(.footnote).foregroundStyle(SteamInk.sub)
            }
            ForEach(news) { n in
                Button {
                    if let u = URL(string: n.url), u.scheme == "https" { openURL(u) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(n.appName)・\(SteamFormat.ago(n.date))").font(.caption2).foregroundStyle(SteamInk.sub)
                        Text(n.title).font(.subheadline.weight(.bold)).foregroundStyle(SteamInk.text)
                            .multilineTextAlignment(.leading).lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SteamInk.panel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - まだ設定していない・読み込み中

private struct SteamIntroPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "gamecontroller.fill").font(.system(size: 40)).foregroundStyle(SteamInk.blue)
            Text("Steam とつなぐ").font(.title2.weight(.heavy)).foregroundStyle(SteamInk.text)
            Text("下の設定に SteamID（またはプロフィールの URL）と Web API キーを入れると、最近遊んだゲームとプレイ時間、実績、ウィッシュリストのセール、ゲームのニュースを表示します。")
                .font(.subheadline).foregroundStyle(SteamInk.sub)
            Text("Steam のプロフィールと「ゲームの詳細」を公開にしておく必要があります。")
                .font(.footnote).foregroundStyle(SteamInk.sub)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SteamInk.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SteamLoadingPanel: View {
    @ObservedObject private var store = SteamStore.shared

    var body: some View {
        VStack(spacing: 10) {
            if store.loading { ProgressView().tint(SteamInk.blue) }
            Text(store.loading ? "Steam を読み込み中…" : "まだ読み込んでいません").font(.subheadline).foregroundStyle(SteamInk.sub)
            if !store.loading {
                Button("読み込む") { Task { await store.refresh() } }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SteamInk.top)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(SteamInk.blue, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(SteamInk.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - 設定（SteamID・Web API キー）

private struct SteamSettingsSection: View {
    @ObservedObject private var store = SteamStore.shared
    @Environment(\.openURL) private var openURL
    @State private var idText = ""
    @State private var keyText = ""
    @State private var confirmDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SteamSectionTitle(title: "設定")
            VStack(alignment: .leading, spacing: 6) {
                Text("SteamID かプロフィールの URL").font(.caption.weight(.semibold)).foregroundStyle(SteamInk.sub)
                TextField("", text: $idText, prompt: Text(store.steamID.isEmpty ? "例：steamcommunity.com/id/あなたの名前" : store.steamID)
                    .foregroundStyle(SteamInk.sub.opacity(0.8)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .steamField()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Web API キー").font(.caption.weight(.semibold)).foregroundStyle(SteamInk.sub)
                SecureField("", text: $keyText, prompt: Text(store.hasKey ? "保存済み（変えるときだけ入力）" : "32文字のキー")
                    .foregroundStyle(SteamInk.sub.opacity(0.8)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .steamField()
                Button {
                    if let u = URL(string: "https://steamcommunity.com/dev/apikey") { openURL(u) }
                } label: {
                    Label("キーを取得する（Steam のページ）", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold)).foregroundStyle(SteamInk.blue)
                }
                .buttonStyle(.plain)
                Text("キーはこの iPhone の Keychain にだけ保存します。ほかの人に見せないでください。")
                    .font(.caption2).foregroundStyle(SteamInk.sub)
            }
            HStack(spacing: 10) {
                Button {
                    let id = idText.isEmpty ? store.steamID : idText
                    let key = keyText
                    Task {
                        await store.save(idInput: id, key: key)
                        keyText = ""
                        idText = ""
                    }
                } label: {
                    Text("保存して読み込む").font(.subheadline.weight(.bold)).foregroundStyle(SteamInk.top)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(SteamInk.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.loading || (idText.isEmpty && store.steamID.isEmpty))
                if store.isConfigured && !store.isDemo {
                    Button("連携をやめる") { confirmDisconnect = true }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(SteamInk.warn)
                }
            }
        }
        .padding(16)
        .background(SteamInk.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .confirmationDialog("Steam との連携をやめますか？", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("連携をやめる", role: .destructive) { store.disconnect() }
        } message: {
            Text("SteamID・Web API キー・読み込んだデータをこの iPhone から消します。")
        }
    }
}

private extension View {
    func steamField() -> some View {
        self
            .font(.body)
            .foregroundStyle(SteamInk.text)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(SteamInk.base, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(SteamInk.track, lineWidth: 1))
    }
}

// MARK: - 情報タブの「ゲーム」に置く入口のカード

struct SteamEntryCard: View {
    @ObservedObject private var store = SteamStore.shared

    var body: some View {
        let s: SteamSnapshot? = store.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").font(.title3.weight(.bold)).foregroundStyle(SteamInk.top)
                    .frame(width: 40, height: 40)
                    .background(SteamInk.blue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Steam").font(.headline.weight(.heavy)).foregroundStyle(SteamInk.text)
                    Text(subtitle(s)).font(.caption.weight(.semibold))
                        .foregroundStyle((s?.profile?.isOnline ?? false) ? SteamInk.green : SteamInk.sub)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let s {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(SteamFormat.hours(s.hours2Weeks)).font(.title2.weight(.heavy)).foregroundStyle(SteamInk.text)
                        Text("時間・2週間").font(.caption2).foregroundStyle(SteamInk.sub)
                    }
                }
            }
            if let s, !s.recent.isEmpty {
                HStack(spacing: 6) {
                    ForEach(s.recent.prefix(3)) { g in
                        SteamHeaderImage(url: g.headerURL)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                .accessibilityHidden(true)
            }
            if let deal = s?.deals.first(where: { $0.discount > 0 }) {
                HStack(spacing: 6) {
                    Text("-\(deal.discount)%").font(.caption2.weight(.heavy)).foregroundStyle(SteamInk.top)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(SteamInk.sale, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text("\(deal.name) がセール中").font(.caption.weight(.semibold)).foregroundStyle(SteamInk.text).lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SteamInk.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .task { await store.refreshIfNeeded() }
    }

    private func subtitle(_ s: SteamSnapshot?) -> String {
        if let p = s?.profile { return p.stateText }
        return store.isConfigured ? "読み込み中…" : "遊んだゲーム・セール・ニュース（設定が必要）"
    }
}

// MARK: - 画面写真用：起動引数 -steamdemo で Steam を全画面で開く（RootView に .steamDemoLaunch() を1行）

struct SteamDemoLaunch: ViewModifier {
    @State private var show = ProcessInfo.processInfo.arguments.contains("-steamdemo")

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $show) {
                NavigationStack {
                    SteamHome()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("閉じる") { show = false }.foregroundStyle(SteamInk.blue)
                            }
                        }
                }
            }
    }
}

extension View {
    func steamDemoLaunch() -> some View { modifier(SteamDemoLaunch()) }
}
