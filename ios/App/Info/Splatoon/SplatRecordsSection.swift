import SwiftUI
import Charts

// 戦績（stat.ink の公開データ）と、stat.ink のスクリーンネームの設定

struct SplatRecordsSection: View {
    @ObservedObject private var store = SplatStore.shared
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SplatSectionTitle(title: "戦績", color: SplatInk.purple, trailing: store.hasScreenName ? "stat.ink" : nil)
            if !store.hasScreenName {
                SplatStatInkIntro()
            } else if let rec = store.records, !rec.battles.isEmpty || !rec.salmon.isEmpty {
                if !rec.decided.isEmpty {
                    SplatSummaryCard(records: rec)
                    SplatWeaponChart(battles: rec.battles)
                    SplatBattleList(battles: rec.battles, showAll: $showAll)
                }
                if !rec.salmon.isEmpty { SplatSalmonRecordList(records: Array(rec.salmon.prefix(5))) }
            } else if store.loadingRecords {
                HStack(spacing: 8) {
                    ProgressView().tint(SplatInk.lime)
                    Text("戦績を読み込み中…").font(.subheadline).foregroundStyle(SplatInk.sub)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if store.recordsError == nil {
                Text("まだ記録がありません。stat.ink に送った試合がここに出ます。")
                    .font(.subheadline).foregroundStyle(SplatInk.sub)
            }
            if let err = store.recordsError {
                Text(err).font(.footnote).foregroundStyle(SplatInk.salmon)
            }
        }
    }
}

/// stat.ink を使っていないときの説明
private struct SplatStatInkIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in InkDroplet(win: i % 3 != 2, size: 16).opacity(0.9) }
            }
            Text("stat.ink は、バトルやサーモンランの記録を集めて公開できるサイトです。s3s などのツールで記録を送っていれば、下の設定にスクリーンネームを入れるだけで、ここに戦績が出ます。")
                .font(.subheadline).foregroundStyle(SplatInk.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("ログインやパスワードは要りません（公開されている記録だけを読みます）。")
                .font(.caption).foregroundStyle(SplatInk.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - 勝率のまとめ

private struct SplatSummaryCard: View {
    let records: SplatRecords

    var body: some View {
        let recent = Array(records.decided.prefix(20))
        let wins = recent.filter(\.isWin).count
        let loses = recent.count - wins
        let rate = recent.isEmpty ? 0 : Double(wins) / Double(recent.count)
        let kills = recent.compactMap(\.kill).reduce(0, +)
        let deaths = recent.compactMap(\.death).reduce(0, +)
        let kd = deaths == 0 ? Double(kills) : Double(kills) / Double(deaths)
        let last8 = Array(records.decided.prefix(8)).reversed().map { Optional($0.isWin) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                SplatWinDonut(wins: wins, loses: loses)
                    .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近\(recent.count)戦").font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int((rate * 100).rounded()))")
                            .font(SplatFont.display(size: 44)).foregroundStyle(SplatInk.lime)
                            .contentTransition(.numericText())
                        Text("%").font(SplatFont.display(.title3)).foregroundStyle(SplatInk.lime)
                    }
                    .splatSkew(0.1)
                    Text("\(wins)勝 \(loses)敗・キル/デス \(String(format: "%.2f", kd))")
                        .font(.caption.weight(.semibold)).foregroundStyle(SplatInk.text)
                }
                Spacer(minLength: 0)
            }
            SplatDropletRow(results: last8, size: 24, spacing: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct SplatWinDonut: View {
    let wins: Int
    let loses: Int

    private struct Part: Identifiable {
        let id: String
        let value: Int
        let color: Color
    }

    var body: some View {
        let parts = [Part(id: "勝ち", value: wins, color: SplatInk.lime), Part(id: "負け", value: loses, color: SplatInk.lavender)]
        Chart(parts) { p in
            let mark = SectorMark(angle: .value("試合", p.value), innerRadius: .ratio(0.62), angularInset: 2)
            mark.foregroundStyle(p.color).cornerRadius(4)
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 0) {
                Text("勝率").font(.caption2.weight(.bold)).foregroundStyle(SplatInk.sub)
                Image(systemName: "drop.fill").font(.caption).foregroundStyle(SplatInk.lime)
            }
        }
        .accessibilityLabel("勝ち\(wins) 負け\(loses)")
    }
}

// MARK: - ブキの使用回数

private struct SplatWeaponChart: View {
    let battles: [SplatBattle]

    private struct Row: Identifiable {
        let id: String
        let count: Int
        let wins: Int
        var rate: Int { count == 0 ? 0 : Int((Double(wins) / Double(count) * 100).rounded()) }
    }

    var body: some View {
        let rows = Self.rows(battles)
        let height = CGFloat(rows.count) * 34 + 10
        VStack(alignment: .leading, spacing: 8) {
            Text("よく使うブキ").font(.subheadline.weight(.heavy)).foregroundStyle(SplatInk.text)
            Text("最近\(battles.count)戦・右の数字は勝率").font(.caption).foregroundStyle(SplatInk.sub)
            Chart(rows) { r in
                let bar = BarMark(x: .value("回数", Double(r.count)), y: .value("ブキ", r.id))
                bar.foregroundStyle(SplatInk.lime.gradient)
                    .cornerRadius(6)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(r.count)回・\(r.rate)%")
                            .font(.caption2.weight(.bold)).foregroundStyle(SplatInk.text)
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.caption.weight(.semibold)).foregroundStyle(SplatInk.text)
                }
            }
            .chartXScale(domain: 0...(Double(rows.map(\.count).max() ?? 1) * 1.45))
            .frame(height: height)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private static func rows(_ battles: [SplatBattle]) -> [Row] {
        var count: [String: Int] = [:]
        var wins: [String: Int] = [:]
        for b in battles {
            count[b.weapon, default: 0] += 1
            if b.isWin { wins[b.weapon, default: 0] += 1 }
        }
        let list = count.map { Row(id: $0.key, count: $0.value, wins: wins[$0.key] ?? 0) }
        let sorted = list.sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
        return Array(sorted.prefix(6))
    }
}

// MARK: - 試合の一覧

private struct SplatBattleList: View {
    let battles: [SplatBattle]
    @Binding var showAll: Bool

    var body: some View {
        let shown = Array(battles.prefix(showAll ? 30 : 8))
        VStack(alignment: .leading, spacing: 8) {
            Text("最近の試合").font(.subheadline.weight(.heavy)).foregroundStyle(SplatInk.text)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, b in
                    SplatBattleRow(battle: b)
                    if i < shown.count - 1 { Divider().overlay(SplatInk.panelHi) }
                }
            }
            if battles.count > 8 {
                Button(showAll ? "少なく表示" : "もっと見る") { withAnimation(.snappy) { showAll.toggle() } }
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(SplatInk.lime)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SplatBattleRow: View {
    let battle: SplatBattle

    var body: some View {
        let win: Bool? = battle.isWin ? true : (battle.isLose ? false : nil)
        let k = battle.kill.map(String.init) ?? "-"
        let a = battle.assist.map(String.init) ?? "-"
        let d = battle.death.map(String.init) ?? "-"
        let paint = battle.inked.map { "\($0)p" } ?? ""
        HStack(alignment: .center, spacing: 10) {
            InkDroplet(win: win, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    SplatChip(text: SplatInk.lobbyShort(battle.lobbyKey, fallback: battle.lobby),
                              color: SplatInk.lobby(battle.lobbyKey), small: true)
                    Text(battle.rule).font(.caption.weight(.heavy)).foregroundStyle(SplatInk.text).lineLimit(1)
                    if battle.knockout == true {
                        Text("ノックアウト").font(.caption2.weight(.bold)).foregroundStyle(SplatInk.lime)
                    }
                }
                Text("\(battle.stage)・\(battle.weapon)")
                    .font(.caption).foregroundStyle(SplatInk.sub).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(k)/\(a)/\(d)")
                    .font(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(SplatInk.text)
                Text(paint.isEmpty ? SplatTime.ago(battle.at) : "\(paint)・\(SplatTime.ago(battle.at))")
                    .font(.caption2).monospacedDigit().foregroundStyle(SplatInk.sub)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(win == true ? "勝ち" : (win == false ? "負け" : "引き分け"))、\(battle.rule)、\(battle.stage)、\(battle.weapon)、キル\(k) アシスト\(a) デス\(d)")
    }
}

// MARK: - サーモンランの記録

private struct SplatSalmonRecordList: View {
    let records: [SplatSalmonRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("サーモンランの記録").font(.subheadline.weight(.heavy)).foregroundStyle(SplatInk.text)
                Spacer()
                let cleared = records.filter(\.cleared).count
                Text("クリア \(cleared)/\(records.count)").font(.caption.weight(.bold)).foregroundStyle(SplatInk.salmon)
            }
            ForEach(records) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.cleared ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3).foregroundStyle(r.cleared ? SplatInk.lime : SplatInk.lavender)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.kind.map { "\($0)・\(r.stage)" } ?? r.stage)
                            .font(.caption.weight(.heavy)).foregroundStyle(SplatInk.text).lineLimit(1)
                        Text(waveText(r)).font(.caption2).foregroundStyle(SplatInk.sub).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("金 \(r.goldenEggs.map(String.init) ?? "-")")
                            .font(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(SplatInk.text)
                        Text(SplatTime.ago(r.at)).font(.caption2).foregroundStyle(SplatInk.sub)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func waveText(_ r: SplatSalmonRecord) -> String {
        var parts: [String] = []
        if let c = r.clearWaves { parts.append(r.cleared ? "クリア" : "WAVE \(min(c + 1, r.waves)) で失敗") }
        if let d = r.dangerRate { parts.append("キケン度 \(Int((d * 100).rounded()))%") }
        if let w = r.weapons.first { parts.append(w) }
        return parts.joined(separator: "・")
    }
}

// MARK: - stat.ink の設定

struct SplatSettingsSection: View {
    @ObservedObject private var store = SplatStore.shared
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SplatSectionTitle(title: "stat.ink の設定", color: SplatInk.mint)
            VStack(alignment: .leading, spacing: 10) {
                Text("スクリーンネーム").font(.caption.weight(.bold)).foregroundStyle(SplatInk.sub)
                HStack(spacing: 8) {
                    Text("@").font(.headline.weight(.heavy)).foregroundStyle(SplatInk.lime)
                    TextField("", text: $name, prompt: Text("例：your_name").foregroundStyle(SplatInk.sub.opacity(0.8)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .focused($focused)
                        .foregroundStyle(SplatInk.text)
                        .onSubmit { save() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(SplatInk.base, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 10) {
                    Button("保存して読み込む") { save() }
                        .buttonStyle(SplatButtonStyle(color: SplatInk.mint))
                        .disabled(store.isDemo)
                    if store.hasScreenName && !store.isDemo {
                        Button("外す") {
                            name = ""
                            Task { await store.setScreenName("") }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SplatInk.sub)
                    }
                    Spacer()
                }
                Text("stat.ink のプロフィールの URL（stat.ink/@ のあと）の名前です。公開されている記録だけを読み、ほかには送りません。")
                    .font(.caption).foregroundStyle(SplatInk.sub)
                    .fixedSize(horizontal: false, vertical: true)
                if store.hasScreenName, let url = URL(string: "https://stat.ink/@\(store.settings.screenName)/spl3/") {
                    Link(destination: url) {
                        Label("stat.ink で開く", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.bold)).foregroundStyle(SplatInk.mint)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .onAppear { name = store.settings.screenName }
    }

    private func save() {
        focused = false
        let cleaned = SplatAPI.cleanScreenName(name)
        name = cleaned
        Task {
            await store.setScreenName(cleaned)
            if cleaned == store.settings.screenName, !cleaned.isEmpty, store.records == nil {
                await store.refreshRecords()
            }
        }
    }
}
