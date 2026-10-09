import SwiftUI

// STUB: replaced by Splatoon/Steam agent
// 統合のときにこのファイルは消す。本物は App/Info/Splatoon/・App/Info/Steam/ に同じ名前で置かれる。
// 使う名前は SplatoonEntryCard・SplatoonHome・SteamEntryCard・SteamHome の4つだけ。

// STUB: replaced by Splatoon/Steam agent
struct SplatoonEntryCard: View {
    @Environment(\.palette) private var p

    var body: some View {
        InfoStubCard(symbol: "drop.fill", title: "スプラトゥーン3", detail: "バトルの戦績・ステージ")
    }
}

// STUB: replaced by Splatoon/Steam agent
struct SplatoonHome: View {
    var body: some View { InfoStubScreen(title: "スプラトゥーン3") }
}

// STUB: replaced by Splatoon/Steam agent
struct SteamEntryCard: View {
    var body: some View {
        InfoStubCard(symbol: "gamecontroller.fill", title: "Steam", detail: "遊んだゲーム・セール・ニュース")
    }
}

// STUB: replaced by Splatoon/Steam agent
struct SteamHome: View {
    var body: some View { InfoStubScreen(title: "Steam") }
}

// STUB: replaced by Splatoon/Steam agent
private struct InfoStubCard: View {
    @Environment(\.palette) private var p
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2.weight(.bold)).foregroundStyle(p.onAccent)
                .frame(width: 52, height: 52)
                .background(p.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(p.text)
                Text(detail).font(.subheadline).foregroundStyle(p.sub).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("準備中").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(p.sub.opacity(0.15), in: Capsule())
        }
        .paletteCard(p)
    }
}

// STUB: replaced by Splatoon/Steam agent
private struct InfoStubScreen: View {
    @Environment(\.palette) private var p
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer").font(.system(size: 48)).foregroundStyle(p.sub)
            Text("準備中").font(.title2.bold()).foregroundStyle(p.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paletteBackground(p)
        .navigationTitle(title)
    }
}
