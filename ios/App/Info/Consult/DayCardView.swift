import SwiftUI
import PhotosUI

// MARK: - 相談タブ（tag 3）：見出し・夜の誘い・「話す」と「1日1枚」の切り替え
// 起動引数：-daycard で「1日1枚」、-daycardviewer で過去の1枚をめくる画面、-daycardreview で AI のふり返り（画面写真用）

enum ConsultMode: String {
    case talk, daycard
}

struct ConsultRootView: View {
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dayModel = DayCardModel()
    @State private var mode: ConsultMode = {
        let a = ProcessInfo.processInfo.arguments
        return (a.contains("-daycard") || a.contains("-daycardviewer") || a.contains("-daycardreview")) ? .daycard : .talk
    }()
    @State private var showViewer = ProcessInfo.processInfo.arguments.contains("-daycardviewer")
    /// 夜の誘いのカード（18時以降で、今日の1枚がまだのとき。×で今日は隠す）
    @State private var hidePromptDay = ""
    /// 画面写真用：-consultevening で夕方として扱う
    private let forceEvening = ProcessInfo.processInfo.arguments.contains("-consultevening")

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                header
                if showPrompt { eveningPrompt.transition(motion.appear) }
                modeBar
                switch mode {
                case .talk:
                    ConsultView()
                        .transition(motion.appear)
                case .daycard:
                    DayCardWriteView(model: dayModel, onTalk: { switchTo(.talk) })
                        .transition(motion.appear)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .paletteBackground(p)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showViewer) {
            DayCardViewer(model: dayModel, onTalk: {
                showViewer = false
                switchTo(.talk)
            })
            .environmentObject(store)
            .environment(\.palette, p)
            .environment(\.motion, motion)
        }
        .task {
            await DayCardReminder.reschedule()
            ConsultWidgetSync.write()
        }
    }

    private var isEvening: Bool { forceEvening || Calendar.current.component(.hour, from: .now) >= 18 }

    private var showPrompt: Bool {
        mode == .talk && isEvening && !dayModel.savedToday && hidePromptDay != dayModel.todayKey
    }

    private func switchTo(_ m: ConsultMode) {
        withAnimation(reduceMotion ? nil : motion.tap) { mode = m }
    }

    // 見出し：「相談」・日付・1日1枚・歯車
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(JP.date(.now)).font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
                Text("相談").font(.largeTitle.weight(.heavy)).foregroundStyle(p.text)
            }
            Spacer()
            Button { switchTo(.daycard) } label: {
                Label("1日1枚", systemImage: dayModel.savedToday ? "checkmark.seal.fill" : "square.and.pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(mode == .daycard ? p.onAccent : p.accent)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(mode == .daycard ? p.accent : p.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("今日の1枚を書く画面を開きます")
            SettingsButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // 夜の誘い（書く画面へ）
    private var eveningPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(p.accent)
                .frame(width: 44, height: 44)
                .background(p.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("今日の1枚を書きましょう").font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                Text("TODO や気分はもう入っています。ひとことだけどうぞ").font(.caption).foregroundStyle(p.sub).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button { switchTo(.daycard) } label: {
                Text("書く").font(.subheadline.weight(.bold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(reduceMotion ? nil : motion.change) { hidePromptDay = dayModel.todayKey }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(p.sub).frame(width: 28, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("今日は隠す")
        }
        .paletteCard(p, padding: 12)
        .padding(.horizontal, 16)
    }

    private var modeBar: some View {
        HStack(spacing: 6) {
            modeButton(.talk, "話す")
            modeButton(.daycard, "1日1枚")
            Spacer(minLength: 4)
            Button { showViewer = true } label: {
                Text("これまでの1枚 ›").font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .disabled(dayModel.cards.isEmpty)
            .opacity(dayModel.cards.isEmpty ? 0.4 : 1)
            .accessibilityHint("過去のカードを1枚ずつめくります")
        }
        .padding(.horizontal, 16)
    }

    private func modeButton(_ m: ConsultMode, _ title: String) -> some View {
        let on: Bool = mode == m
        let fill: Color = on ? p.accent : Color.clear
        let stroke: Color = on ? Color.clear : p.sub.opacity(0.35)
        return Button { switchTo(m) } label: {
            Text(title).font(.subheadline.weight(.bold))
                .foregroundStyle(on ? p.onAccent : p.text)
                .padding(.horizontal, 14).frame(height: 32)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - ① 今日の1枚を書く

struct DayCardWriteView: View {
    @ObservedObject var model: DayCardModel
    let onTalk: () -> Void
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @State private var auto = DayCardAuto()
    @State private var pickerItem: PhotosPickerItem?
    @State private var remindOn = DayCardReminder.enabled
    @State private var remindTime = DayCardWriteView.timeFrom(DayCardReminder.minutes)
    @State private var justSaved = false
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                card
                reminderCard
                Text("写真はこの iPhone のアプリの中にだけ保存します。AI のふり返りに写真は送りません。")
                    .font(.caption2).foregroundStyle(p.sub)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { refreshAuto() }
        .onChange(of: store.doneToday.count) { _, _ in refreshAuto() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    withAnimation(motion.change) { model.attachPhoto(data) }
                }
                pickerItem = nil
            }
        }
    }

    private func refreshAuto() {
        if model.isDemo {
            auto = DayCardAuto(doneCount: 5, doneTitles: ["企画書の下書き", "洗濯", "ジムに行く"], wakeScore: 82,
                               wakeTime: Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: .now), mood: .good)
        } else {
            auto = DayCardAuto.make(store: store)
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: max(p.radius, 20), style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            photoArea
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("今日の1枚").font(.headline.weight(.heavy)).foregroundStyle(p.text)
                    Spacer()
                    Text(JP.date(.now)).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                }
                autoRows
                noteField
                saveButton
            }
            .padding(16)
        }
        .background(p.card, in: shape)
        .clipShape(shape)
        .shadow(color: Color.black.opacity(0.10), radius: 14, y: 8)
    }

    @ViewBuilder
    private var photoArea: some View {
        let warm = LinearGradient(colors: [p.accent.opacity(0.22), p.accent.opacity(0.38)], startPoint: .topLeading, endPoint: .bottomTrailing)
        if let img = DayCardData.image(model.photoName) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(height: 180).frame(maxWidth: .infinity).clipped()
                Button { withAnimation(motion.change) { model.removePhoto() } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Color.black.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("写真を外す")
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus").font(.title2)
                    Text("写真を添える（なくても大丈夫）").font(.caption.weight(.bold))
                }
                .foregroundStyle(p.accent)
                .frame(maxWidth: .infinity).frame(height: 92)
                .background(warm)
            }
            .buttonStyle(.plain)
            .disabled(model.isDemo)
            .accessibilityLabel("写真を添える")
        }
    }

    private var autoRows: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("自動で入ります").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                Spacer()
            }
            DayCardAutoRow(label: "TODO", value: "\(auto.doneCount)件 完了",
                           detail: auto.doneTitles.isEmpty ? "今日はまだ完了なし" : auto.doneTitles.joined(separator: "・"))
            DayCardAutoRow(label: "起床", value: auto.wakeScore.map { "\($0)点" } ?? "記録なし",
                           detail: auto.wakeTime.map { "\(JP.time($0)) に起きた" } ?? "")
            DayCardAutoRow(label: "気分", value: auto.mood?.title ?? "まだ選んでいません",
                           detail: auto.mood == nil ? "「話す」の今日の気分から" : "相談の「今日の気分」から",
                           symbol: auto.mood?.symbol, tint: auto.mood?.color(p))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ひとこと").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            TextField("今日をひとことで", text: $model.note, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .font(.body)
                .foregroundStyle(p.text)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(p.sub.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var saveButton: some View {
        let title: String = justSaved ? "残しました" : (model.savedToday ? "書き直して残す" : "この1枚を残す")
        return Button {
            typing = false
            withAnimation(motion.change) {
                model.save(auto: auto)
                justSaved = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { justSaved = false }
        } label: {
            Label(title, systemImage: justSaved ? "checkmark" : "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(p.onAccent)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(p.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $remindOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("夜の通知").font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                    Text("「今日の1枚を書きましょう」。書いた日は出しません")
                        .font(.caption).foregroundStyle(p.sub)
                }
            }
            .tint(p.accent)
            if remindOn {
                DatePicker("時刻", selection: $remindTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                    .foregroundStyle(p.text)
                    .tint(p.accent)
            }
        }
        .paletteCard(p, padding: 14)
        .onChange(of: remindOn) { _, on in
            DayCardReminder.enabled = on
            Task {
                if on { await DayCardReminder.requestAuthorization() }
                await DayCardReminder.reschedule()
            }
        }
        .onChange(of: remindTime) { _, t in
            let c = Calendar.current.dateComponents([.hour, .minute], from: t)
            DayCardReminder.minutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
            Task { await DayCardReminder.reschedule() }
        }
    }

    static func timeFrom(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}

private struct DayCardAutoRow: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let detail: String
    var symbol: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(p.sub).frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(tint ?? p.accent) }
                    Text(value).font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                }
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(p.sub).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ② 過去の1枚をめくる（ストーリー形式・全画面）

enum DayInk {
    static let base = Color(red: 0.118, green: 0.106, blue: 0.086)     // #1E1B16
    static let panel = Color(red: 0.180, green: 0.165, blue: 0.137)
    static let text = Color(red: 0.984, green: 0.973, blue: 0.949)
    static let sub = Color(red: 0.851, green: 0.804, blue: 0.733)      // #D9CDBB
}

struct DayCardViewer: View {
    @ObservedObject var model: DayCardModel
    let onTalk: () -> Void
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var showReview = ProcessInfo.processInfo.arguments.contains("-daycardreview")

    /// めくるのは新しい30枚まで（古い順）
    private var cards: [DayCard] { Array(model.cards.suffix(30)) }

    var body: some View {
        let list = cards
        ZStack {
            DayInk.base.ignoresSafeArea()
            if list.isEmpty {
                Text("まだカードがありません").font(.headline).foregroundStyle(DayInk.sub)
            } else {
                let i: Int = min(max(index, 0), list.count - 1)
                VStack(spacing: 12) {
                    segments(count: list.count, current: i)
                    header(list[i], position: i, list: list)
                    DayCardFace(card: list[i])
                        .id(list[i].day)
                        .transition(.opacity)
                        .offset(x: drag)
                        .overlay(tapZones(count: list.count))
                        .gesture(swipe(count: list.count))
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { index = max(cards.count - 1, 0) }
        .sheet(isPresented: $showReview) {
            DayCardReviewSheet(model: model, onTalk: {
                showReview = false
                onTalk()
            })
            .environmentObject(store)
            .environment(\.palette, p)
            .environment(\.motion, motion)
        }
    }

    private func segments(count: Int, current: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { k in
                Capsule()
                    .fill(k <= current ? DayInk.text : DayInk.text.opacity(0.28))
                    .frame(height: 3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count)枚中 \(current + 1)枚目")
    }

    private func header(_ c: DayCard, position: Int, list: [DayCard]) -> some View {
        let week: [DayCard] = DayCardData.week(containing: c.date, cards: list).sorted { $0.day < $1.day }
        let nth: Int = (week.firstIndex { $0.day == c.day } ?? 0) + 1
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(JP.date(c.date)).font(.headline.weight(.heavy)).foregroundStyle(DayInk.text)
                Text("その週の \(nth) 枚目").font(.caption).foregroundStyle(DayInk.sub)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(DayInk.text)
                    .frame(width: 44, height: 44)
                    .background(DayInk.panel, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
    }

    private func tapZones(count: Int) -> some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { step(-1, count: count) }
                .accessibilityLabel("前の日")
                .accessibilityAddTraits(.isButton)
            Color.clear.contentShape(Rectangle())
                .onTapGesture { step(1, count: count) }
                .accessibilityLabel("次の日")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func swipe(count: Int) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in drag = v.translation.width * 0.4 }
            .onEnded { v in
                let w: CGFloat = v.translation.width
                withAnimation(reduceMotion ? nil : motion.change) { drag = 0 }
                if w < -60 { step(1, count: count) } else if w > 60 { step(-1, count: count) }
            }
    }

    private func step(_ d: Int, count: Int) {
        let next = index + d
        guard next >= 0, next < count else { return }
        withAnimation(reduceMotion ? nil : motion.change) { index = next }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text("左右をタップ、またはスワイプでめくる").font(.caption).foregroundStyle(DayInk.sub)
            Button { showReview = true } label: {
                Label("AI にふり返ってもらう", systemImage: "sparkles")
                    .font(.headline).foregroundStyle(p.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 1枚の表（写真・ひとこと・数字）
private struct DayCardFace: View {
    @Environment(\.palette) private var p
    let card: DayCard

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            photo
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text(card.note.isEmpty ? "（ひとことなし）" : card.note)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DayInk.text)
                    .fixedSize(horizontal: false, vertical: true)
                chips
                if !card.doneTitles.isEmpty {
                    let more: String = card.doneCount > card.doneTitles.count ? " ほか" : ""
                    Text(card.doneTitles.joined(separator: "・") + more)
                        .font(.caption).foregroundStyle(DayInk.sub).lineLimit(2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DayInk.panel)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(DayInk.text.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var photo: some View {
        if let img = DayCardData.image(card.photo) {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            let tint: Color = card.mood?.color(p) ?? p.accent
            ZStack {
                LinearGradient(colors: [tint.opacity(0.55), DayInk.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: card.mood?.symbol ?? "sun.haze.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(DayInk.text.opacity(0.85))
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            DayChip(text: "TODO \(card.doneCount)件")
            if let w = card.wakeScore { DayChip(text: "起床 \(w)点") }
            if let m = card.mood { DayChip(text: m.title, symbol: m.symbol) }
        }
    }
}

private struct DayChip: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(DayInk.text)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(DayInk.text.opacity(0.12), in: Capsule())
    }
}

// MARK: - ③ AI にふり返ってもらう（今週の1枚から）

struct DayCardReviewSheet: View {
    @ObservedObject var model: DayCardModel
    let onTalk: () -> Void
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.dismiss) private var dismiss
    @State private var kept = false

    private var week: [DayCard] { DayCardData.week(containing: .now, cards: model.cards) }

    var body: some View {
        let w = week
        let range = DayCardData.weekRange(.now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今週のふり返り").font(.title2.weight(.heavy)).foregroundStyle(p.text)
                        Text("\(JP.shortDate(range.start)) 〜 \(JP.shortDate(range.end.addingTimeInterval(-3600)))")
                            .font(.subheadline).foregroundStyle(p.sub)
                    }
                    dayDots(w, start: range.start)
                    stats(w)
                    aiCard(w)
                    Text("相談と同じ Gemini（無料枠）を使います。送るのは1週間分のカードの数字とひとことだけです（写真・TODO の題名は送りません）。")
                        .font(.caption2).foregroundStyle(p.sub)
                }
                .padding(16)
            }
            .paletteBackground(p)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.large])
    }

    private func dayDots(_ w: [DayCard], start: Date) -> some View {
        let names = ["月", "火", "水", "木", "金", "土", "日"]
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { k in
                let date: Date = Calendar.current.date(byAdding: .day, value: k, to: start) ?? start
                let card: DayCard? = w.first { $0.day == WakeLogic.key(date) }
                VStack(spacing: 4) {
                    Text(names[k]).font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                    ZStack {
                        Circle().fill(card == nil ? p.sub.opacity(0.12) : (card?.mood?.color(p) ?? p.accent))
                        if let m = card?.mood {
                            Image(systemName: m.symbol).font(.caption).foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 32, height: 32)
                    Text(card == nil ? "なし" : " ").font(.system(size: 9)).foregroundStyle(p.sub)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .paletteCard(p, padding: 12)
    }

    private func stats(_ w: [DayCard]) -> some View {
        let done: Int = w.map(\.doneCount).reduce(0, +)
        let wakes: [Int] = w.compactMap(\.wakeScore)
        let avg: String = wakes.isEmpty ? "—" : String(wakes.reduce(0, +) / wakes.count)
        return HStack(spacing: 8) {
            DayStat(label: "TODO 完了", value: String(done), unit: "件")
            DayStat(label: "起床の平均", value: avg, unit: wakes.isEmpty ? "" : "点")
            DayStat(label: "書いた日", value: String(w.count), unit: "/ 7 日")
        }
    }

    private func aiCard(_ w: [DayCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI のまとめ", systemImage: "sparkles").font(.headline).foregroundStyle(p.text)
            if let r = model.review {
                Text(r.text).font(.subheadline).lineSpacing(4).foregroundStyle(p.text).textSelection(.enabled)
                if let step = ConsultStep.extract(r.text) { stepButton(step) }
            } else {
                Text("今週の1枚から、よかったことや流れの変化を、短くまとめます。")
                    .font(.subheadline).foregroundStyle(p.sub)
            }
            if let e = model.reviewError {
                Text(e).font(.footnote.weight(.semibold)).foregroundStyle(p.overdue)
            }
            VStack(alignment: .leading, spacing: 8) {
                Button { Task { await model.runReview(week: w) } } label: {
                    HStack(spacing: 6) {
                        if model.reviewing { ProgressView().tint(p.onAccent) }
                        Text(model.review == nil ? "ふり返ってもらう" : "もう一度").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(p.onAccent)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(p.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.reviewing)
                HStack(spacing: 8) {
                if model.review != nil {
                    Button {
                        model.keepReview()
                        withAnimation(motion.change) { kept = true }
                    } label: {
                        outlined(kept ? "残しました" : "まとめを残す", symbol: kept ? "checkmark" : "tray.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                }
                Button { onTalk() } label: { outlined("相談で話す", symbol: "bubble.left") }
                    .buttonStyle(.plain)
                }
            }
        }
        .paletteCard(p)
    }

    private func outlined(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(p.accent)
            .padding(.horizontal, 12).frame(height: 40)
            .overlay(Capsule().strokeBorder(p.accent, lineWidth: 1))
    }

    private func stepButton(_ step: String) -> some View {
        let added: Bool = store.items.contains { t in t.title == step && !t.done }
        let fill: Color = added ? Color.clear : p.accent
        return Button {
            let today = Calendar.current.startOfDay(for: .now)
            withAnimation(motion.change) { store.add(step, due: today, allDay: true) }
        } label: {
            Label(added ? "TODO に追加しました" : "「\(step)」を TODO に", systemImage: added ? "checkmark" : "plus")
                .font(.caption.weight(.bold)).lineLimit(1)
                .foregroundStyle(added ? p.accent : p.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(p.accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(added)
    }
}

private struct DayStat: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(p.sub).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.weight(.heavy)).foregroundStyle(p.text)
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(p.sub).lineLimit(1) }
            }
        }
        .paletteCard(p, padding: 12)
        .accessibilityElement(children: .combine)
    }
}
