import SwiftUI

// MARK: - Discord の見た目（#313338 の面・#5865F2 の強調。ロゴは使わず、ふつうの吹き出しのアイコン）

enum DiscordInk {
    static let surface = Color(red: 0.192, green: 0.200, blue: 0.220)   // #313338
    static let panel = Color(red: 0.169, green: 0.176, blue: 0.192)     // #2B2D31
    static let deep = Color(red: 0.118, green: 0.122, blue: 0.133)      // #1E1F22
    static let blurple = Color(red: 0.345, green: 0.396, blue: 0.949)   // #5865F2
    static let green = Color(red: 0.137, green: 0.647, blue: 0.353)     // #23A55A
    static let idle = Color(red: 0.941, green: 0.698, blue: 0.196)      // #F0B232
    static let dnd = Color(red: 0.949, green: 0.247, blue: 0.263)       // #F23F43
    static let text = Color(red: 0.949, green: 0.953, blue: 0.961)      // #F2F3F5
    static let sub = Color(red: 0.710, green: 0.729, blue: 0.757)       // #B5BAC1
    static let warn = Color(red: 1.0, green: 0.55, blue: 0.50)

    static func status(_ s: String?) -> Color {
        switch s {
        case "online": green
        case "idle": idle
        case "dnd": dnd
        default: sub
        }
    }
}

/// 吹き出しのアイコン（Discord のロゴではない）
struct DiscordBubbleIcon: View {
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(DiscordInk.blurple, in: shape)
            .accessibilityHidden(true)
    }
}

private struct DiscordAvatar: View {
    let member: DiscordWidget.Member
    var size: CGFloat = 26

    var body: some View {
        let initial = String(member.username.prefix(1))
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(DiscordInk.blurple.opacity(0.55))
                if let s = member.avatarURL, let u = URL(string: s), u.scheme == "https" {
                    AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Text(initial) }
                } else {
                    Text(initial)
                }
            }
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(DiscordInk.text)
            .frame(width: size, height: size)
            .clipShape(Circle())
            Circle().fill(DiscordInk.status(member.status))
                .frame(width: size * 0.34, height: size * 0.34)
                .overlay(Circle().stroke(DiscordInk.panel, lineWidth: 2))
        }
        .accessibilityHidden(true)
    }
}

enum DiscordFormat {
    static func time(_ d: Date, now: Date = .now) -> String {
        if Calendar.current.isDateInToday(d) { return "今日 \(JP.time(d))" }
        if Calendar.current.isDateInYesterday(d) { return "昨日 \(JP.time(d))" }
        return "\(JP.shortDate(d)) \(JP.time(d))"
    }
}

// MARK: - 情報タブの「ゲーム」に置く入口のカード

struct DiscordServerCard: View {
    @ObservedObject private var store = DiscordStore.shared
    @Environment(\.openURL) private var openURL
    let onOpen: () -> Void

    var body: some View {
        let w: DiscordWidget? = store.widget
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DiscordBubbleIcon(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DISCORD").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(DiscordInk.blurple)
                    Text(w?.name ?? "Discord").font(.headline.weight(.heavy)).foregroundStyle(DiscordInk.text).lineLimit(1)
                    onlineLine(w)
                }
                Spacer(minLength: 4)
                if let u = w?.inviteURL {
                    Button { openURL(u) } label: { joinLabel("参加") }
                        .buttonStyle(.plain)
                        .accessibilityHint("Discord のアプリでサーバーを開きます")
                }
            }
            if let g = w?.voiceGroups.first { voiceRow(g.channel, g.members) }
            if let m = store.messages.first { latest(m) }
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)

        content
            .background(DiscordInk.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture { onOpen() }
            .accessibilityAddTraits(.isButton)
            .environment(\.colorScheme, .dark)
            .task { await store.refreshIfNeeded() }
    }

    @ViewBuilder
    private func onlineLine(_ w: DiscordWidget?) -> some View {
        if let w {
            HStack(spacing: 5) {
                Circle().fill(DiscordInk.green).frame(width: 8, height: 8)
                Text("\(w.presenceCount) 人がオンライン")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(DiscordInk.sub)
        } else {
            Text(store.isConfigured ? (store.error == nil ? "読み込み中…" : "読み込めませんでした") : "サーバーの様子・お知らせ・募集（設定が必要）")
                .font(.caption.weight(.semibold)).foregroundStyle(DiscordInk.sub).lineLimit(1)
        }
    }

    private func voiceRow(_ ch: DiscordWidget.Channel, _ members: [DiscordWidget.Member]) -> some View {
        let first: String = members.first?.username ?? ""
        let rest: String = members.count > 1 ? " ほか \(members.count - 1)人" : ""
        return HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(DiscordInk.sub)
            Text(ch.name).font(.caption.weight(.bold)).foregroundStyle(DiscordInk.text).lineLimit(1)
            Text("・\(members.count)人").font(.caption).foregroundStyle(DiscordInk.sub)
            Spacer(minLength: 4)
            HStack(spacing: -6) {
                ForEach(members.prefix(3)) { m in DiscordAvatar(member: m, size: 22) }
            }
            Text(first + rest).font(.caption2).foregroundStyle(DiscordInk.sub).lineLimit(1)
        }
        .padding(10)
        .background(DiscordInk.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func latest(_ m: DiscordMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("#\(m.channelName)・\(m.author)・\(JP.time(m.date))").font(.caption2.weight(.bold)).foregroundStyle(DiscordInk.sub)
            Text(m.content).font(.footnote).foregroundStyle(DiscordInk.text).lineLimit(2)
        }
    }

    private var footer: some View {
        let all: Int = store.recruits(nil).count
        let first: String? = store.settings.keywords.first
        let firstCount: Int = first.map { store.recruits($0).count } ?? 0
        let text: String = store.botReady ? "募集 \(all)件" + (first.map { "・うち\($0) \(firstCount)件" } ?? "") : "お知らせ・募集はボットの設定で"
        return HStack {
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(DiscordInk.sub).lineLimit(1)
            Spacer()
            Text("くわしく ›").font(.caption.weight(.bold)).foregroundStyle(DiscordInk.blurple)
        }
    }
}

private func joinLabel(_ title: String) -> some View {
    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.white)
        .padding(.horizontal, 16).frame(height: 34)
        .background(DiscordInk.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
}

// MARK: - くわしく画面

struct DiscordHome: View {
    @ObservedObject private var store = DiscordStore.shared
    @State private var channelFilter: String?
    @State private var recruitFilter: String?
    @State private var expanded: Set<String> = []
    @State private var showSetup = ProcessInfo.processInfo.arguments.contains("-discordsetup")
    @Environment(\.openURL) private var openURL

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 16) {
            if store.isConfigured {
                serverSection
                announcements
                recruitSection
            } else {
                intro
            }
            if let e = store.error { Text(e).font(.footnote).foregroundStyle(DiscordInk.warn) }
            DiscordSettingsSection()
            Text("Discord とは関係のない個人のアプリです。読むのは公開のサーバーウィジェットと、自分のボットが読めるチャンネルだけです。DM やフレンド一覧は表示できません。")
                .font(.caption2).foregroundStyle(DiscordInk.sub)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)

        ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
            .background(DiscordInk.deep.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Discord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DiscordInk.deep, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSetup = true } label: { Image(systemName: "questionmark.circle") }
                        .foregroundStyle(DiscordInk.text)
                        .accessibilityLabel("設定の手順")
                }
            }
            .sheet(isPresented: $showSetup) { DiscordSetupGuide() }
            .task { await store.refreshIfNeeded() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscordBubbleIcon(size: 48)
            Text("サーバーとつなぐ").font(.title2.weight(.heavy)).foregroundStyle(DiscordInk.text)
            Text("サーバー設定でウィジェットをオンにして、下にサーバーIDを入れると、オンラインの人数やボイスチャンネルにいる人がわかります。ボットを追加すると、お知らせや募集も読めます。")
                .font(.subheadline).foregroundStyle(DiscordInk.sub)
            Button { showSetup = true } label: {
                Text("設定の手順を見る").font(.subheadline.weight(.bold)).foregroundStyle(Color.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(DiscordInk.blurple, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiscordInk.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // サーバーの様子
    private var serverSection: some View {
        let w: DiscordWidget? = store.widget
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DiscordBubbleIcon(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(w?.name ?? "サーバー").font(.title3.weight(.heavy)).foregroundStyle(DiscordInk.text).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(DiscordInk.green).frame(width: 8, height: 8)
                        Text(w.map { "\($0.presenceCount) 人がオンライン" } ?? "—")
                    }
                    .font(.footnote.weight(.semibold)).foregroundStyle(DiscordInk.sub)
                }
                Spacer(minLength: 4)
                if store.loading { ProgressView().tint(DiscordInk.text) }
                if let u = w?.inviteURL {
                    Button { openURL(u) } label: { joinLabel("参加") }
                        .buttonStyle(.plain)
                        .accessibilityHint("Discord のアプリでサーバーを開きます")
                }
            }
            if let w {
                let groups = w.voiceGroups
                if groups.isEmpty {
                    Text("いまボイスチャンネルにいる人はいません").font(.footnote).foregroundStyle(DiscordInk.sub)
                }
                ForEach(groups) { g in
                    voiceBlock(g.channel, g.members)
                }
                if w.inviteURL == nil {
                    Text("「参加」を出すには、サーバー設定 › ウィジェット で招待チャンネルを選んでください。")
                        .font(.caption2).foregroundStyle(DiscordInk.sub)
                }
            }
            Text(store.isDemo ? "見本のデータを表示しています" : "サーバーウィジェットから・数分ごとに更新・下に引っぱると更新")
                .font(.caption2).foregroundStyle(DiscordInk.sub)
        }
        .padding(16)
        .background(DiscordInk.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func voiceBlock(_ ch: DiscordWidget.Channel, _ members: [DiscordWidget.Member]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill").font(.caption)
                Text(ch.name).font(.subheadline.weight(.bold))
                Text("\(members.count)人").font(.caption).foregroundStyle(DiscordInk.sub)
            }
            .foregroundStyle(DiscordInk.text)
            ForEach(members) { m in
                HStack(spacing: 8) {
                    DiscordAvatar(member: m, size: 24)
                    Text(m.username).font(.footnote.weight(.semibold)).foregroundStyle(DiscordInk.text).lineLimit(1)
                    if m.selfMute == true { Image(systemName: "mic.slash.fill").font(.caption2).foregroundStyle(DiscordInk.sub) }
                    if let g = m.game?.name { Text(g).font(.caption2).foregroundStyle(DiscordInk.sub).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiscordInk.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // お知らせ（ボットで読んだチャンネル）
    private var announcements: some View {
        let channels: [String] = Array(Set(store.messages.map(\.channelName))).sorted()
        let shown: [DiscordMessage] = store.messages.filter { channelFilter == nil || $0.channelName == channelFilter }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("お知らせ").font(.headline).foregroundStyle(DiscordInk.text)
                Spacer(minLength: 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("すべて", on: channelFilter == nil) { channelFilter = nil }
                        ForEach(channels, id: \.self) { c in
                            chip("#\(c)", on: channelFilter == c) { channelFilter = c }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !store.botReady {
                Text("ボットを追加して、読むチャンネルのIDを入れると、最新のメッセージがここに出ます（下の設定）。")
                    .font(.footnote).foregroundStyle(DiscordInk.sub)
            } else if store.contentMissingHint {
                Text("メッセージがありません。投稿があるのに出ないときは、開発者ポータルの Bot で「MESSAGE CONTENT INTENT」をオンにしてください。")
                    .font(.footnote).foregroundStyle(DiscordInk.warn)
            }
            if let e = store.botError { Text(e).font(.footnote).foregroundStyle(DiscordInk.warn) }
            ForEach(shown.prefix(12)) { m in
                messageRow(m)
            }
        }
        .padding(16)
        .background(DiscordInk.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func messageRow(_ m: DiscordMessage) -> some View {
        let open: Bool = expanded.contains(m.id)
        return Button {
            withAnimation(.snappy) {
                if open { expanded.remove(m.id) } else { expanded.insert(m.id) }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(DiscordInk.blurple.opacity(0.6)).frame(width: 30, height: 30)
                    .overlay(Text(String(m.author.prefix(1))).font(.caption.weight(.bold)).foregroundStyle(DiscordInk.text))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(m.author).font(.caption.weight(.bold)).foregroundStyle(DiscordInk.text)
                        Text("・#\(m.channelName)・\(DiscordFormat.time(m.date))").font(.caption2).foregroundStyle(DiscordInk.sub)
                    }
                    .lineLimit(1)
                    Text(m.content).font(.footnote).foregroundStyle(DiscordInk.text)
                        .lineLimit(open ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(open ? "たたむ" : "全文を表示")
    }

    // 募集を見る（キーワードで絞る）
    private var recruitSection: some View {
        let list: [DiscordMessage] = store.recruits(recruitFilter)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("募集を見る").font(.headline).foregroundStyle(DiscordInk.text)
                Spacer(minLength: 4)
                ForEach(store.settings.keywords.prefix(3), id: \.self) { k in
                    chip(k, on: recruitFilter == k) { recruitFilter = k }
                }
                chip("すべて", on: recruitFilter == nil) { recruitFilter = nil }
            }
            if store.botReady && list.isEmpty {
                Text("キーワードに合うメッセージはありません").font(.footnote).foregroundStyle(DiscordInk.sub)
            }
            ForEach(list.prefix(8)) { m in
                recruitRow(m)
            }
        }
        .padding(16)
        .background(DiscordInk.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recruitRow(_ m: DiscordMessage) -> some View {
        let tag: String = store.settings.keywords.first { m.matches($0) } ?? "募集"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tag).font(.caption2.weight(.heavy)).foregroundStyle(Color.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(DiscordInk.blurple, in: Capsule())
                Text("\(m.author)・\(JP.time(m.date))").font(.caption.weight(.semibold)).foregroundStyle(DiscordInk.sub)
                Spacer()
            }
            Text(m.content).font(.subheadline).foregroundStyle(DiscordInk.text)
            HStack {
                Text("Discord でそのメッセージを開きます").font(.caption2).foregroundStyle(DiscordInk.sub)
                Spacer()
                if let u = m.link {
                    Button { openURL(u) } label: { joinLabel("参加する") }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(DiscordInk.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        let fill: Color = on ? DiscordInk.blurple : DiscordInk.panel
        return Button(action: action) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(on ? Color.white : DiscordInk.sub)
                .lineLimit(1)
                .padding(.horizontal, 10).frame(height: 28)
                .background(fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - 設定（サーバーID・ボット）

private struct DiscordSettingsSection: View {
    @ObservedObject private var store = DiscordStore.shared
    @State private var guildText = ""
    @State private var channelsText = ""
    @State private var keywordsText = ""
    @State private var appText = ""
    @State private var tokenText = ""
    @State private var loaded = false
    @State private var confirmDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("設定").font(.headline).foregroundStyle(DiscordInk.text)
            field("サーバーID（数字）", text: $guildText, prompt: "例：123456789012345678", keyboard: .numberPad)
            Text("ここから下はお知らせ・募集を読むとき（任意）").font(.caption.weight(.bold)).foregroundStyle(DiscordInk.sub)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("ボットのトークン").font(.caption.weight(.semibold)).foregroundStyle(DiscordInk.sub)
                SecureField("", text: $tokenText, prompt: Text(store.hasToken ? "保存済み（変えるときだけ入力）" : "開発者ポータルの Bot で作ったトークン")
                    .foregroundStyle(DiscordInk.sub.opacity(0.8)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .discordField()
                Text("トークンはこの iPhone の Keychain にだけ保存します。自分のアカウントのトークンは入れないでください（規約違反になります）。")
                    .font(.caption2).foregroundStyle(DiscordInk.sub)
            }
            field("読むチャンネルのID（改行か「,」で区切る・5つまで）", text: $channelsText, prompt: "例：234567890123456789", axis: true)
            field("募集のキーワード（「,」で区切る）", text: $keywordsText, prompt: "スプラ, 募集")
            HStack(spacing: 10) {
                Button { save() } label: {
                    Text("保存して読み込む").font(.subheadline.weight(.bold)).foregroundStyle(Color.white)
                        .padding(.horizontal, 18).frame(height: 40)
                        .background(DiscordInk.blurple, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.loading)
                if store.hasToken && !store.isDemo {
                    Button("トークンを消す") { store.removeToken() }
                        .font(.footnote.weight(.semibold)).foregroundStyle(DiscordInk.warn)
                }
            }
            if store.isConfigured && !store.isDemo {
                Button("連携をやめる") { confirmDisconnect = true }
                    .font(.footnote.weight(.semibold)).foregroundStyle(DiscordInk.warn)
            }
        }
        .padding(16)
        .background(DiscordInk.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear(perform: load)
        .confirmationDialog("Discord との連携をやめますか？", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("連携をやめる", role: .destructive) { store.disconnect(); loaded = false; load() }
        } message: {
            Text("サーバーID・チャンネル・ボットのトークンをこの iPhone から消します。")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let s = store.settings
        guildText = s.guildID
        channelsText = s.channelIDs.joined(separator: "\n")
        keywordsText = s.keywords.joined(separator: ", ")
        appText = s.appID
    }

    private func save() {
        var s = store.settings
        s.guildID = guildText
        s.channelIDs = channelsText.components(separatedBy: CharacterSet(charactersIn: ",、\n "))
        s.keywords = keywordsText.components(separatedBy: CharacterSet(charactersIn: ",、"))
        let token = tokenText
        tokenText = ""
        Task {
            if !token.isEmpty { await store.saveToken(token) }
            await store.save(s)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default,
                       axis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(DiscordInk.sub)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(DiscordInk.sub.opacity(0.8)), axis: axis ? .vertical : .horizontal)
                .lineLimit(axis ? 1...4 : 1...1)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .discordField()
        }
    }
}

private extension View {
    func discordField() -> some View {
        self
            .font(.body)
            .foregroundStyle(DiscordInk.text)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(DiscordInk.deep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 設定の手順（ボタンで Discord の画面を開く）

struct DiscordSetupGuide: View {
    @ObservedObject private var store = DiscordStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var appID = ""

    /// 「チャンネルを見る」(1024) ＋「メッセージ履歴を読む」(65536)
    static let botPermissions = 66560

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "サーバーウィジェットをオンにする",
                         "Discord のアプリでサーバー名を押し、サーバー設定 › ウィジェット で「サーバーウィジェットを有効化」をオンにします。「参加」ボタンを出すには、同じ画面で招待チャンネルを選びます。そこに出ている「サーバーID」をコピーします。") {
                        linkButton("Discord を開く", "https://discord.com/channels/@me")
                    }
                    step(2, "サーバーIDを入れる", "くわしく画面の下の設定に、コピーしたサーバーIDを入れて「保存して読み込む」を押します。ここまでで、オンラインの人数とボイスチャンネルにいる人が見られます。") { EmptyView() }
                    step(3, "ボットを作る（お知らせ・募集を読むとき）",
                         "開発者ポータルで New Application を作り、Bot の画面で Reset Token を押してトークンをコピーします。同じ画面の Privileged Gateway Intents で「MESSAGE CONTENT INTENT」をオンにします。") {
                        linkButton("開発者ポータルを開く", "https://discord.com/developers/applications")
                    }
                    step(4, "ボットをサーバーに追加する",
                         "アプリの「General Information」にある APPLICATION ID を入れると、追加用のリンクを開けます（チャンネルを見る・メッセージ履歴を読む の権限だけ）。サーバーの管理の権限が必要です。") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("", text: $appID, prompt: Text("APPLICATION ID（数字）").foregroundStyle(DiscordInk.sub.opacity(0.8)))
                                .keyboardType(.numberPad)
                                .discordField()
                            Button {
                                let id = appID.trimmingCharacters(in: .whitespaces)
                                if DiscordAPI.isSnowflake(id),
                                   let u = URL(string: "https://discord.com/oauth2/authorize?client_id=\(id)&scope=bot&permissions=\(Self.botPermissions)") {
                                    openURL(u)
                                }
                            } label: { buttonLabel("ボットを追加する") }
                            .buttonStyle(.plain)
                            .disabled(!DiscordAPI.isSnowflake(appID.trimmingCharacters(in: .whitespaces)))
                        }
                    }
                    step(5, "読むチャンネルのIDをコピーする",
                         "Discord の設定 › 詳細設定 で「開発者モード」をオンにし、読みたいチャンネル（#お知らせ・#募集 など）を長押しして「チャンネルIDをコピー」。設定の「読むチャンネルのID」に入れ、ボットのトークンも入れて保存します。") { EmptyView() }
                    Text("自分のアカウントのトークンを使う方法（セルフボット）は Discord の規約で禁止されているので使いません。DM やフレンド一覧は表示できません。")
                        .font(.caption2).foregroundStyle(DiscordInk.sub)
                }
                .padding(16)
            }
            .background(DiscordInk.deep.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Discord の設定の手順")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.foregroundStyle(DiscordInk.text) }
            }
        }
        .onAppear { appID = store.settings.appID }
    }

    private func step<Extra: View>(_ n: Int, _ title: String, _ body: String, @ViewBuilder extra: () -> Extra) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline.weight(.heavy)).foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(DiscordInk.blurple, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(DiscordInk.text)
                Text(body).font(.footnote).foregroundStyle(DiscordInk.sub).fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DiscordInk.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func linkButton(_ title: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: { buttonLabel(title) }
            .buttonStyle(.plain)
    }

    private func buttonLabel(_ title: String) -> some View {
        Label(title, systemImage: "arrow.up.right.square")
            .font(.footnote.weight(.bold)).foregroundStyle(Color.white)
            .padding(.horizontal, 14).frame(height: 34)
            .background(DiscordInk.blurple, in: Capsule())
    }
}
