import SwiftUI

/// 「情報」→ ゲームの欄に置くスプラトゥーン3のカード。
/// 今の3つのステージ（小さなカード）・次の切り替えまでの時間・最近8戦の勝ち負け（インクの滴）・勝敗のまとめ。
/// 中には画面移動を持たない（全画面 SplatoonHome へは、置く側が NavigationLink で包む）。
struct SplatoonEntryCard: View {
    @ObservedObject private var store = SplatStore.shared

    var body: some View {
        let header = SplatEntryHeader(next: store.schedule?.nextSwitch())
        VStack(alignment: .leading, spacing: 12) {
            header
            rotations
            results
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .task { await store.refreshIfNeeded() }
        .accessibilityElement(children: .contain)
    }

    private var cardBackground: some View {
        ZStack(alignment: .topTrailing) {
            SplatInk.base
            InkSplash(color: SplatInk.purple.opacity(0.7), size: 90).offset(x: 30, y: -30)
        }
    }

    @ViewBuilder private var rotations: some View {
        let list = store.schedule?.headline() ?? []
        if list.isEmpty {
            let msg = store.loadingSchedule ? "ステージ情報を読み込み中…" : "ステージ情報はまだありません"
            Text(msg).font(.footnote).foregroundStyle(SplatInk.sub)
                .frame(maxWidth: .infinity, minHeight: 70)
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                    SplatMiniRotation(rotation: r)
                        .splatWobble(i == 1 ? 1.5 : -1.5, delay: Double(i) * 0.08)
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if let rec = store.records, !rec.decided.isEmpty {
            let last = Array(rec.decided.prefix(8))
            let wins = last.filter(\.isWin).count
            let loses = last.count - wins
            HStack(spacing: 10) {
                SplatDropletRow(results: last.reversed().map { Optional($0.isWin) }, size: 18, spacing: 4)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(wins)勝\(loses)敗")
                        .font(SplatFont.display(.headline))
                        .foregroundStyle(SplatInk.text)
                    Text("最近\(last.count)戦").font(.caption2).foregroundStyle(SplatInk.sub)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("最近\(last.count)戦 \(wins)勝\(loses)敗")
        } else if store.hasScreenName {
            Text(store.loadingRecords ? "戦績を読み込み中…" : "stat.ink の戦績はまだありません")
                .font(.footnote).foregroundStyle(SplatInk.sub)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").foregroundStyle(SplatInk.lime)
                Text("stat.ink のスクリーンネームを入れると、戦績も出せます")
                    .font(.footnote).foregroundStyle(SplatInk.sub)
            }
        }
    }
}

private struct SplatEntryHeader: View {
    let next: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("スプラトゥーン3")
                .font(SplatFont.display(.title2))
                .foregroundStyle(SplatInk.lime)
                .splatSkew(0.08)
            Spacer(minLength: 6)
            if let next {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("次の切り替えまで").font(.caption2).foregroundStyle(SplatInk.sub)
                    SplatCountdown(to: next, font: .headline.weight(.heavy), color: SplatInk.text)
                }
            }
        }
    }
}

/// 小さなステージのカード（モードの色・ルール・ステージ2つ）
struct SplatMiniRotation: View {
    let rotation: SplatRotation

    var body: some View {
        let color = SplatInk.mode(rotation.mode)
        VStack(alignment: .leading, spacing: 5) {
            SplatChip(text: rotation.mode.short, color: color, small: true)
            Text(rotation.rule)
                .font(SplatFont.display(.subheadline))
                .foregroundStyle(SplatInk.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ForEach(rotation.stages.prefix(2), id: \.self) { s in
                Text(s.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(SplatInk.sub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle().fill(color).frame(height: 3).clipShape(Capsule()).padding(.horizontal, 10)
        }
        .accessibilityElement(children: .combine)
    }
}
