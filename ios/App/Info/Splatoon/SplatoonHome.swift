import SwiftUI

/// スプラトゥーン3 の全画面：ステージの予定（いま・つぎ・そのあと）、サーモンラン、フェス、戦績、stat.ink の設定。
/// 自前の NavigationStack は持たない（情報タブから push される）。
struct SplatoonHome: View {
    @ObservedObject private var store = SplatStore.shared
    @State private var slotIndex = 0

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 22) {
            SplatHomeHeader()
            if let s = store.schedule {
                SplatTimelineSection(schedule: s, slotIndex: $slotIndex)
                SplatEventSection(schedule: s)
                SplatSalmonSection(schedule: s)
                if let f = s.fest { SplatFestSection(fest: f) }
            } else {
                SplatScheduleEmpty()
            }
            SplatRecordsSection()
            SplatSettingsSection()
            SplatCredits()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)

        let scroll = ScrollView { content }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refreshAll() }
        scroll
            .background(InkBlobBackground())
            .environment(\.colorScheme, .dark)
            .navigationTitle("スプラトゥーン3")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SplatInk.base, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await store.refreshIfNeeded() }
    }
}

// MARK: - 見出し

private struct SplatHomeHeader: View {
    @ObservedObject private var store = SplatStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ナワバリ情報")
                .font(SplatFont.display(size: 34))
                .foregroundStyle(SplatInk.lime)
                .splatSkew(0.1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let next = store.schedule?.nextSwitch() {
                    Text("次の切り替えまで").font(.subheadline.weight(.semibold)).foregroundStyle(SplatInk.sub)
                    SplatCountdown(to: next, font: SplatFont.display(.title2), color: SplatInk.text)
                } else if store.loadingSchedule {
                    ProgressView().tint(SplatInk.lime)
                    Text("読み込み中…").font(.subheadline).foregroundStyle(SplatInk.sub)
                }
                Spacer()
            }
            if let err = store.scheduleError {
                Text(err).font(.footnote).foregroundStyle(SplatInk.salmon)
            } else if let s = store.schedule, !store.isDemo {
                Text("\(SplatTime.ago(s.fetchedAt))に更新・下に引っぱると更新")
                    .font(.caption).foregroundStyle(SplatInk.sub)
            } else if store.isDemo {
                Text("見本のデータを表示しています").font(.caption).foregroundStyle(SplatInk.sub)
            }
        }
    }
}

private struct SplatScheduleEmpty: View {
    @ObservedObject private var store = SplatStore.shared

    var body: some View {
        VStack(spacing: 10) {
            if store.loadingSchedule { ProgressView().tint(SplatInk.lime) }
            Text(store.loadingSchedule ? "ステージ情報を読み込み中…" : "ステージ情報がまだありません")
                .font(.subheadline).foregroundStyle(SplatInk.sub)
            if !store.loadingSchedule {
                Button("読み込む") { Task { await store.refreshSchedule() } }
                    .buttonStyle(SplatButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(SplatInk.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 見出しの帯（傾いた文字＋インクの下線）
struct SplatSectionTitle: View {
    let title: String
    var color: Color = SplatInk.lime
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SplatFont.display(.title3))
                .foregroundStyle(SplatInk.text)
                .splatSkew(0.1)
                .background(alignment: .bottomLeading) {
                    Capsule().fill(color.opacity(0.85)).frame(height: 6).offset(y: 3)
                }
            Spacer()
            if let trailing {
                Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub)
            }
        }
    }
}

struct SplatButtonStyle: ButtonStyle {
    var color: Color = SplatInk.lime

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(SplatInk.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - ステージの予定（いま・つぎ・そのあと）

private struct SplatTimelineSection: View {
    let schedule: SplatSchedule
    @Binding var slotIndex: Int

    var body: some View {
        let slots = Array(schedule.slots().prefix(6))
        let index = min(slotIndex, max(0, slots.count - 1))
        VStack(alignment: .leading, spacing: 12) {
            SplatSectionTitle(title: "ステージ")
            if slots.isEmpty {
                Text("予定がありません。下に引っぱって更新してください。").font(.footnote).foregroundStyle(SplatInk.sub)
            } else {
                SplatSlotPicker(slots: slots, selection: $slotIndex)
                let list = schedule.rotations(at: slots[index])
                VStack(spacing: 14) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        SplatRotationCard(rotation: r, tilt: i.isMultiple(of: 2) ? -1.2 : 1.2)
                            .id("\(index)-\(r.id)")
                    }
                }
            }
        }
    }
}

private struct SplatSlotPicker: View {
    let slots: [Date]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(slots.enumerated()), id: \.offset) { i, d in
                    let label = i == 0 ? "いま" : (i == 1 ? "つぎ" : SplatTime.dayPrefix(d) + JP.time(d))
                    let on = i == selection
                    Button { selection = i } label: {
                        Text(label)
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(on ? SplatInk.ink : SplatInk.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? SplatInk.lime : SplatInk.panel, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// モード1つ分のカード（色の札・ルール・時間・少し傾いたステージの絵2枚）
struct SplatRotationCard: View {
    let rotation: SplatRotation
    var tilt: Double = -1

    var body: some View {
        let color = SplatInk.mode(rotation.mode)
        let title = rotation.mode == .event ? (rotation.eventName ?? rotation.mode.title) : rotation.mode.title
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SplatChip(text: rotation.mode.short, color: color)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub).lineLimit(1)
                Spacer(minLength: 4)
                Text(SplatTime.range(rotation.start, rotation.end))
                    .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(SplatInk.sub)
            }
            Text(rotation.rule)
                .font(SplatFont.display(.title2))
                .foregroundStyle(SplatInk.text)
                .splatSkew(0.1)
            HStack(spacing: 10) {
                ForEach(Array(rotation.stages.prefix(2).enumerated()), id: \.offset) { i, s in
                    SplatStageTile(stage: s, accent: color)
                        .splatWobble(i == 0 ? -2.5 : 2, delay: 0.05 + Double(i) * 0.06)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            InkSplash(color: color.opacity(0.9), size: 18).offset(x: -18, y: -6)
        }
        .rotationEffect(.degrees(tilt * 0.4))
        .accessibilityElement(children: .combine)
    }
}

/// ステージの絵（名前を下に重ねる）
struct SplatStageTile: View {
    let stage: SplatStage
    var accent: Color = SplatInk.lime
    var height: CGFloat = 86

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        SplatImage(url: stage.image, name: stage.name)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                Text(stage.name)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(SplatInk.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(SplatInk.base.opacity(0.85), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(5)
            }
            .overlay(shape.stroke(accent.opacity(0.9), lineWidth: 2))
    }
}

// MARK: - イベントマッチ

private struct SplatEventSection: View {
    let schedule: SplatSchedule

    var body: some View {
        let now = Date.now
        let events = schedule.upcomingEvents(now: now).filter { !$0.isActive(at: now) }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SplatSectionTitle(title: "イベントマッチの予定", color: SplatInk.pink)
                ForEach(events.prefix(3)) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SplatChip(text: "イベント", color: SplatInk.pink, small: true)
                            Text(e.eventName ?? "イベントマッチ").font(.subheadline.weight(.heavy)).foregroundStyle(SplatInk.text)
                                .lineLimit(1)
                        }
                        Text("\(SplatTime.range(e.start, e.end))・\(e.rule)")
                            .font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub)
                        if let d = e.eventDesc, !d.isEmpty {
                            Text(cleanDesc(d)).font(.caption).foregroundStyle(SplatInk.sub).lineLimit(2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func cleanDesc(_ s: String) -> String {
        s.replacingOccurrences(of: "<br />", with: " ").replacingOccurrences(of: "<br>", with: " ")
    }
}

// MARK: - サーモンラン

private struct SplatSalmonSection: View {
    let schedule: SplatSchedule

    var body: some View {
        let shifts = Array(schedule.currentSalmon().prefix(2))
        if !shifts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SplatSectionTitle(title: "サーモンラン", color: SplatInk.salmon)
                ForEach(Array(shifts.enumerated()), id: \.element.id) { i, s in
                    SplatSalmonCard(shift: s, isNow: s.start <= .now, tilt: i == 0 ? -0.6 : 0.6)
                }
            }
        }
    }
}

private struct SplatSalmonCard: View {
    let shift: SplatSalmonShift
    let isNow: Bool
    var tilt: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SplatChip(text: isNow ? "いま" : "つぎ", color: SplatInk.salmon)
                if shift.kind != "通常" { SplatChip(text: shift.kind, color: SplatInk.pink, small: true) }
                Spacer()
                if isNow {
                    Text("のこり").font(.caption).foregroundStyle(SplatInk.sub)
                    SplatCountdown(to: shift.end, font: .subheadline.weight(.heavy), color: SplatInk.text)
                } else {
                    Text(SplatTime.range(shift.start, shift.end)).font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                SplatStageTile(stage: shift.stage, accent: SplatInk.salmon, height: 96)
                    .frame(width: 140)
                    .splatWobble(-2.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(shift.stage.name)
                        .font(SplatFont.display(.headline)).foregroundStyle(SplatInk.text).lineLimit(2)
                    if let b = shift.boss {
                        Text("オカシラ：\(b)").font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub)
                    }
                }
            }
            SplatWeaponRow(weapons: shift.weapons)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .rotationEffect(.degrees(tilt))
    }
}

private struct SplatWeaponRow: View {
    let weapons: [SplatStage]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(weapons.prefix(4).enumerated()), id: \.offset) { _, w in
                VStack(spacing: 4) {
                    ZStack {
                        Circle().fill(SplatInk.panelHi)
                        if w.image != nil {
                            SplatImage(url: w.image, name: w.name, fill: false).padding(6)
                        } else {
                            Image(systemName: w.name == "ランダム" ? "questionmark" : "drop.fill")
                                .font(.title3.weight(.black)).foregroundStyle(SplatInk.salmon)
                        }
                    }
                    .frame(width: 52, height: 52)
                    Text(w.name)
                        .font(.caption2.weight(.semibold)).foregroundStyle(SplatInk.sub)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - フェス

private struct SplatFestSection: View {
    let fest: SplatFest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SplatSectionTitle(title: "フェス", color: SplatInk.sky, trailing: fest.stateText)
            VStack(alignment: .leading, spacing: 10) {
                if fest.image != nil {
                    SplatImage(url: fest.image, name: fest.title)
                        .frame(maxWidth: .infinity).frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(fest.title)
                    .font(SplatFont.display(.title3)).foregroundStyle(SplatInk.text).splatSkew(0.08)
                Text(SplatTime.range(fest.start, fest.end))
                    .font(.caption.weight(.semibold)).foregroundStyle(SplatInk.sub)
                HStack(spacing: 8) {
                    ForEach(Array(fest.teams.enumerated()), id: \.offset) { i, t in
                        SplatFestTeamChip(team: t).splatWobble(i == 1 ? 1.5 : -1.5, delay: Double(i) * 0.07)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SplatInk.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct SplatFestTeamChip: View {
    let team: SplatFestTeam

    static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    var body: some View {
        // チームの色の明るさで文字の色を決める（読みやすさのため）
        let lum = 0.2126 * Self.lin(team.r) + 0.7152 * Self.lin(team.g) + 0.0722 * Self.lin(team.b)
        let fg: Color = lum > 0.179 ? SplatInk.ink : .white
        let bg = Color(red: team.r, green: team.g, blue: team.b)
        HStack(spacing: 4) {
            if team.winner == true { Image(systemName: "crown.fill").font(.caption2) }
            Text(team.name).font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(fg)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 出典

private struct SplatCredits: View {
    var body: some View {
        Text("ステージ情報：splatoon3.ink　戦績：stat.ink\n任天堂の公式サービスではありません。")
            .font(.caption2).foregroundStyle(SplatInk.sub)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}
