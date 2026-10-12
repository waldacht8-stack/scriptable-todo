import SwiftUI

// MARK: - 第五人格：遊ぶときに要る情報の欄（ランクマッチの開放時間・対戦情報・アプリの版・第五録の新着・設定）
// どの欄にも、出どころと取得した時刻（「公式・3時間前」）を出す。分からないものは「公式で確認」とリンクにする

/// 欄の見出しと、出どころ・取得時刻
struct IdvBlockTitle: View {
    let title: String
    let fresh: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.headline, design: .serif)).foregroundStyle(IdvInk.sepia)
            IdvFreshLabel(text: fresh)
        }
    }
}

struct IdvFreshLabel: View {
    let text: String

    var body: some View {
        let failed: Bool = text.contains("更新できませんでした")
        Label(text, systemImage: failed ? "exclamationmark.triangle" : "clock")
            .font(.caption2)
            .foregroundStyle(failed ? IdvInk.redBright : IdvInk.sub)
            .labelStyle(.titleAndIcon)
    }
}

/// 「公式で確認」のリンク（推測で埋めない代わり）
struct IdvCheckOfficial: View {
    let label: String
    let link: String?
    let open: (String?) -> Void

    var body: some View {
        Button { open(link) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square").font(.caption.weight(.bold))
                Text(label).font(.caption.weight(.bold))
            }
            .foregroundStyle(IdvInk.gold)
            .padding(.horizontal, 10).frame(minHeight: 30)
            .overlay(Capsule().strokeBorder(IdvInk.gold.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(link == nil)
        .accessibilityHint("アプリ内のブラウザで開きます")
    }
}

private extension View {
    func idvPanel() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IdvInk.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IdvInk.line, lineWidth: 1))
    }
}

// MARK: ランクマッチ（開放時間・メンテナンス中の封鎖・段位継承）

struct IdvRankPanel: View {
    let rank: IdvRankInfo
    let nextMaintenance: IdvScheduleItem?
    let latestOfficial: IdvNews?
    let fresh: String
    let open: (String?) -> Void

    var body: some View {
        let now: Date = .now
        let openNow: IdvRankWindow? = rank.openWindow(now: now)
        let next: Date? = rank.nextOpen(now: now)
        VStack(alignment: .leading, spacing: 8) {
            IdvBlockTitle(title: "ランクマッチの開放時間", fresh: fresh)
            if rank.windows.isEmpty {
                Text("開放時間は公式のお知らせから見つかりませんでした。ゲーム内のランク画面か公式のお知らせで確認してください。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
                IdvCheckOfficial(label: "公式で確認", link: latestOfficial?.link ?? IdvOfficial.updateListURL?.absoluteString, open: open)
            } else {
                let labels: [String] = rank.windows.reduce(into: [String]()) { acc, w in if !acc.contains(w.label) { acc.append(w.label) } }
                ForEach(labels, id: \.self) { label in
                    let text: String = rank.windows.filter { $0.label == label }.map(\.text).joined(separator: "・")
                    HStack(spacing: 6) {
                        IdvTagChip(text: label)
                        Text(text).font(.system(.subheadline, design: .serif).weight(.bold)).foregroundStyle(IdvInk.sepia).monospacedDigit()
                    }
                }
                if let w = openNow {
                    Label("いま開いています（\(IdvRankWindow.hm(w.end))まで）", systemImage: "circle.fill")
                        .font(.footnote.weight(.bold)).foregroundStyle(IdvInk.gold)
                } else if let next {
                    Label("いまは閉じています・次は\(IdvMatchText.day(next))\(JP.time(next))から", systemImage: "circle")
                        .font(.footnote.weight(.bold)).foregroundStyle(IdvInk.sub)
                }
            }
            if rank.closedDuringMaintenance {
                let when: String = nextMaintenance.map { "（次は\(IdvSchedule.label($0))）" } ?? ""
                Text("メンテナンスの間はランク戦が閉じます\(when)")
                    .font(.caption).foregroundStyle(IdvInk.sub)
            }
            if !rank.notes.isEmpty {
                Text("シーズンの切り替え").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub).padding(.top, 2)
                ForEach(rank.notes, id: \.self) { n in
                    Text("・" + n).font(.caption).foregroundStyle(IdvInk.sepia.opacity(0.9))
                }
                if let link = rank.link {
                    IdvCheckOfficial(label: "公式のお知らせを開く", link: link, open: open)
                }
            }
        }
        .idvPanel()
    }
}

enum IdvMatchText {
    /// 「今日 」「明日 」「10月15日（木） 」
    static func day(_ d: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return "今日 " }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "明日 " }
        return JP.date(d) + " "
    }

    static func period(_ p: IdvPeriod) -> String {
        guard let s = p.start else { return "\(JP.date(p.end))まで" }
        if Calendar.current.isDate(s, inSameDayAs: p.end) { return JP.date(s) }
        return "\(JP.shortDate(s))〜\(JP.shortDate(p.end))"
    }
}

// MARK: 対戦情報（期間限定モード・大会）

struct IdvMatchesSection: View {
    let modes: [IdvPeriod]
    let tournaments: [IdvPeriod]
    let broadcasts: [IdvNews]
    let fresh: String
    let open: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IdvBlockTitle(title: "対戦情報", fresh: fresh)
            Text("期間限定モード").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub)
            if modes.isEmpty {
                Text("開催中の期間限定モードは、公式のお知らせから見つかりませんでした。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
                IdvCheckOfficial(label: "公式で確認", link: IdvOfficial.updateListURL?.absoluteString, open: open)
            }
            ForEach(modes.prefix(5)) { p in row(p) }

            Text("大会").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub).padding(.top, 4)
            if tournaments.isEmpty && broadcasts.isEmpty {
                Text("大会の日程は、公式のお知らせから見つかりませんでした。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
            }
            ForEach(tournaments.prefix(3)) { p in row(p) }
            ForEach(broadcasts) { v in
                Button { open(v.link) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill").foregroundStyle(IdvInk.redBright)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.title).font(.footnote.weight(.semibold)).foregroundStyle(IdvInk.sepia)
                                .multilineTextAlignment(.leading).lineLimit(2)
                            Text("公式YouTube・\(v.date.map { IdvFresh.ago($0) } ?? "")").font(.caption2).foregroundStyle(IdvInk.sub)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("配信・動画をアプリ内のブラウザで開きます")
            }
            IdvCheckOfficial(label: "配信は公式 YouTube で確認", link: IdvMatches.channelURL, open: open)
        }
        .idvPanel()
    }

    private func row(_ p: IdvPeriod) -> some View {
        let ended: Bool = IdvDates.daysLeft(p.end) < 0
        return Button { open(p.link) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        IdvTagChip(text: p.kind.label)
                        Text(p.title).font(.subheadline.weight(.semibold)).foregroundStyle(IdvInk.sepia)
                            .multilineTextAlignment(.leading).lineLimit(2)
                    }
                    Text(IdvMatchText.period(p)).font(.caption).foregroundStyle(IdvInk.sub).monospacedDigit()
                }
                Spacer(minLength: 6)
                IdvDaysBadge(end: p.end, start: p.start)
            }
            .opacity(ended ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(p.kind.label)、\(p.title)、\(IdvMatchText.period(p))")
    }
}

// MARK: アプリの版（App Store）

struct IdvAppVersionRow: View {
    let app: IdvAppVersion?
    let fresh: String
    let open: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(IdvInk.line).padding(.vertical, 2)
            if let app {
                Button { open(app.url) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                IdvTagChip(text: "最新の版")
                                Text("ver. \(app.version)").font(.system(.subheadline, design: .serif).weight(.bold))
                                    .foregroundStyle(IdvInk.sepia).monospacedDigit()
                            }
                            if let d = app.released {
                                Text("\(JP.date(d))に公開").font(.caption).foregroundStyle(IdvInk.sub)
                            }
                            if !app.notes.isEmpty {
                                Text(app.notes).font(.caption).foregroundStyle(IdvInk.sepia.opacity(0.85))
                                    .multilineTextAlignment(.leading).lineLimit(3)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(IdvInk.sub).padding(.top, 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("App Store のページを開きます")
            } else {
                Text("アプリの版を読み込めていません。").font(.footnote).foregroundStyle(IdvInk.sub)
                IdvCheckOfficial(label: "App Store で確認", link: IdvAppStore.pageURL, open: open)
            }
            IdvFreshLabel(text: fresh)
        }
    }
}

// MARK: 第五録の新着（見出しと日付だけ）

struct IdvDaigorokuSection: View {
    let headlines: [IdvHeadline]
    let fresh: String
    let open: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("第五録の新着").font(.system(.headline, design: .serif)).foregroundStyle(IdvInk.sepia)
                Spacer()
                Text("ファンの攻略サイト").font(.caption2.weight(.heavy)).foregroundStyle(IdvInk.sepia)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(IdvInk.line, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            IdvFreshLabel(text: fresh)
            if headlines.isEmpty {
                Text("まだ見出しを読み込んでいません。下に引っぱると更新します（数時間に1回まで）。")
                    .font(.footnote).foregroundStyle(IdvInk.sub)
                IdvCheckOfficial(label: "第五録を開く", link: IdvDaigoroku.topURL, open: open)
            }
            ForEach(headlines.prefix(8)) { h in
                Button { open(h.link) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(h.date.map { JP.shortDate($0) } ?? "")
                            .font(.caption.weight(.bold)).foregroundStyle(IdvInk.gold).monospacedDigit()
                            .frame(width: 64, alignment: .leading)
                        Text(h.title).font(.footnote.weight(.semibold)).foregroundStyle(IdvInk.sepia)
                            .multilineTextAlignment(.leading).lineLimit(2)
                        Spacer(minLength: 4)
                        Image(systemName: "safari").font(.caption).foregroundStyle(IdvInk.sub)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第五録、\(h.title)")
                .accessibilityHint("記事を第五録のサイトで開きます")
            }
            Text("出どころ：第五録（daigoroku.com）。見出しと日付だけを表示し、記事は第五録のサイトで開きます。")
                .font(.caption2).foregroundStyle(IdvInk.sub)
        }
        .idvPanel()
    }
}

// MARK: 設定（通知のスイッチ。既定はオフ）

struct IdvSettingsSheet: View {
    @ObservedObject private var store = IdvStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let on = Binding<Bool>(get: { store.notifyEnabled }, set: { store.setNotify($0) })
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("第五人格の通知", isOn: on)
                    .font(.headline)
                    .foregroundStyle(IdvInk.sepia)
                    .tint(IdvInk.redBright)
                VStack(alignment: .leading, spacing: 6) {
                    Text("オンにすると、次のときに知らせます。").font(.subheadline).foregroundStyle(IdvInk.sub)
                    Label("メンテナンスの前の日の 19:00", systemImage: "wrench.and.screwdriver")
                    Label("ガチャ・コラボ・登録した期限の残り1日（前日の 19:00）", systemImage: "hourglass")
                    Label("ランクマッチのシーズン終了の3日前", systemImage: "flag.checkered")
                }
                .font(.subheadline).foregroundStyle(IdvInk.sepia)
                Text("日時は公式のお知らせから読み取ったものです。予定が変わることがあるので、公式でも確認してください。")
                    .font(.caption).foregroundStyle(IdvInk.sub)
                Spacer()
            }
            .padding(20)
            .background(IdvInk.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("第五人格の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.fontWeight(.semibold).foregroundStyle(IdvInk.sepia)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
