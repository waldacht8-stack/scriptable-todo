import SwiftUI
import WidgetKit
import AppIntents

// MARK: - タブごとのウィジェット：家計簿・相談・情報（ホームの小・中、情報は大も。ロック画面の長方形・円・一行）
// データは Shared/WidgetFeeds.swift（kakeibo-summary.json / consult-widget.json / info-widget.json）。
// 世界観は WorldWidget.swift の部品（背景・カード・数字・輪・動き・ロック画面の字と枠）で描き分ける。

/// ロック画面の字（世界観なしなら標準）
private func lockFont(_ w: World, _ style: Font.TextStyle, _ weight: Font.Weight) -> Font {
    w == .none ? Font.system(style, weight: weight) : w.accessoryFont(style, weight)
}

/// 「1.8万」（ロック画面の円の中など狭いところ用）
private func compactYen(_ v: Int) -> String {
    let a: Int = abs(v)
    let sign: String = v < 0 ? "-" : ""
    if a >= 10000 {
        let man: Double = Double(a) / 10000
        let text: String = man >= 10 ? String(format: "%.0f", man) : String(format: "%.1f", man)
        return "\(sign)\(text)万"
    }
    return "\(sign)\(a)"
}

// MARK: - 家計簿

struct KakeiboWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: DayWidgetEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { entry.palette }
    private var k: KakeiboFeed { entry.kakeibo }
    private var spent: Int { k.spentThisMonth(entry.date) }
    private var remaining: Int? { k.remainingThisMonth(entry.date) }
    private var used: Double? { k.usedFraction(entry.date) }

    init(entry: DayWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: spent)
        .widgetURL(WidgetLinks.kakeibo)
    }

    private var monthTitle: String { "\(Calendar.current.component(.month, from: entry.date))月の支出" }

    private var spendBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(monthTitle).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                if k.isSample { WidgetSampleBadge(color: p.sub) }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            WidgetCount(p: p, text: WidgetFeedDay.yenText(spent), value: Double(spent), size: 28)
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            budgetBar
        }
    }

    @ViewBuilder private var budgetBar: some View {
        if let used, let remaining, let budget = k.budget {
            let over: Bool = remaining < 0
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.sub.opacity(0.18))
                        Capsule().fill(over ? p.overdue : p.accent).frame(width: g.size.width * used)
                    }
                }
                .frame(height: 6)
                Text(over ? "予算を \(WidgetFeedDay.yenText(-remaining)) 超え" : "残り \(WidgetFeedDay.yenText(remaining))")
                    .font(.caption.weight(.bold)).foregroundStyle(over ? p.overdue : p.text).lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text("予算 \(WidgetFeedDay.yenText(budget))").font(.caption2).foregroundStyle(p.sub).lineLimit(1)
            }
        } else {
            Text("予算は未設定").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
        }
    }

    private var small: some View { spendBlock }

    private var medium: some View {
        let cats: [KakeiboFeed.Category] = Array(k.categories(entry.date).prefix(3))
        let top: Int = max(1, cats.first?.amount ?? 1)
        return HStack(spacing: 14) {
            spendBlock.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("多い分類").font(.caption2.weight(.bold)).foregroundStyle(p.sub)
                ForEach(cats, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.name).font(.caption.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(WidgetFeedDay.yenText(c.amount)).font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(p.sub).lineLimit(1)
                        }
                        GeometryReader { g in
                            Capsule().fill(p.accent.opacity(0.7))
                                .frame(width: g.size.width * Double(c.amount) / Double(top))
                        }
                        .frame(height: 3)
                    }
                    .transition(p.world.widgetRowTransition(p))
                }
                if cats.isEmpty {
                    Text("まだ記録がありません").font(.caption).foregroundStyle(p.sub)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 150)
            .frame(maxHeight: .infinity, alignment: .top)
            .widgetCard(p, radius: 14)
        }
    }

    // ロック画面

    private var inline: some View {
        let rest: String = remaining.map { "・残り \(WidgetFeedDay.yenText($0))" } ?? ""
        return Text("今月 \(WidgetFeedDay.yenText(spent))\(rest)")
    }

    private var circular: some View {
        let w: World = p.world
        let left: Double = used.map { max(0, 1 - $0) } ?? 0
        let numberFont: Font = w == .none ? Font.system(size: 15, weight: .heavy) : w.accessoryNumberFont(14)
        let labelFont: Font = Font.system(size: 8, weight: w.accessoryWeight(.semibold), design: w.accessoryDesign ?? .default)
        return ZStack {
            AccessoryWorldBackground(world: w)
            LockRing(world: w, fraction: left).padding(3)
            VStack(spacing: -1) {
                Text("残り").font(labelFont)
                Text(remaining.map { compactYen($0) } ?? compactYen(spent)).font(numberFont)
                    .tracking(w.accessoryTracking).minimumScaleFactor(0.5).lineLimit(1)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 8)
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        let w: World = p.world
        return VStack(alignment: .leading, spacing: 1) {
            Text(monthTitle).font(lockFont(w, .caption2, .semibold))
            Text(WidgetFeedDay.yenText(spent)).font(lockFont(w, .headline, .heavy)).monospacedDigit()
                .tracking(w.accessoryTracking).lineLimit(1)
                .contentTransition(.numericText(value: Double(spent)))
            if let remaining, let used {
                HStack(spacing: 6) {
                    Text("残り \(WidgetFeedDay.yenText(remaining))").font(lockFont(w, .caption, .semibold)).lineLimit(1)
                        .minimumScaleFactor(0.7)
                    LockBar(fraction: max(0, 1 - used)).frame(height: 4)
                }
            } else {
                Text("予算は未設定").font(lockFont(w, .caption, .regular))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessoryWorldFrame(w)
    }
}

// MARK: - 相談

struct ConsultWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: DayWidgetEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { entry.palette }
    private var c: ConsultFeed { entry.consult }
    private var mood: Int? { c.mood(entry.date) }

    init(entry: DayWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: mood ?? -1)
        .widgetURL(WidgetLinks.consult)
    }

    /// 気分の色（最高は暖色 → つらいは寒色）
    private func moodColor(_ level: Int) -> Color {
        switch level {
        case 0: Color.orange
        case 1: p.accent
        case 2: p.sub
        case 3: Color.blue
        default: Color.indigo
        }
    }

    private var bigMood: some View {
        let symbol: String = mood.map { WidgetMood.symbol($0) } ?? "questionmark.circle"
        let color: Color = mood.map { moodColor($0) } ?? p.sub
        return Image(systemName: symbol)
            .font(.system(size: family == .systemMedium ? 44 : 34, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .contentTransition(p.world.widgetSymbolTransition)
            .widgetAccentable()
    }

    /// 5つの気分のボタン（押すとその場で記録）
    private func moodButtons(size: CGFloat, labels: Bool) -> some View {
        HStack(spacing: labels ? 4 : 2) {
            ForEach(0..<5, id: \.self) { level in
                let selected: Bool = mood == level
                Button(intent: LogMoodIntent(level: level)) {
                    VStack(spacing: 2) {
                        Image(systemName: WidgetMood.symbol(level))
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(selected ? p.onAccent : moodColor(level))
                            .frame(width: size, height: size)
                            .background {
                                if selected {
                                    WidgetButtonSurface(p: p, radius: size / 2)
                                } else {
                                    WidgetCardSurface(p: p, radius: size / 2)
                                }
                            }
                        if labels {
                            Text(WidgetMood.title(level)).font(.system(size: 9, weight: .bold))
                                .foregroundStyle(selected ? p.accent : p.sub).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .invalidatableContent()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardBadge: some View {
        Text("今日の1枚 まだ").font(.system(size: 10, weight: .heavy))
            .foregroundStyle(p.onAccent)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .widgetButton(p, radius: 8)
            .transition(p.world.widgetSwapTransition(p))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("今日の気分").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                if c.isSample { WidgetSampleBadge(color: p.sub) }
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 6) {
                bigMood
                VStack(alignment: .leading, spacing: 1) {
                    Text(mood.map { WidgetMood.title($0) } ?? "まだ").font(.headline.weight(.heavy)).foregroundStyle(p.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("連続 \(c.streakDays ?? 0)日").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
                        .contentTransition(.numericText())
                }
            }
            if c.cardDue(entry.date) { cardBadge }
            Spacer(minLength: 0)
            moodButtons(size: 24, labels: false)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("今日の気分").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    if c.isSample { WidgetSampleBadge(color: p.sub) }
                }
                Spacer(minLength: 0)
                bigMood
                Text(mood.map { WidgetMood.title($0) } ?? "まだ記録していません").font(.subheadline.weight(.heavy))
                    .foregroundStyle(p.text).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("連続 \(c.streakDays ?? 0)日").font(.caption2.weight(.semibold)).foregroundStyle(p.sub)
            }
            .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(mood == nil ? "いまの気分は？" : "変えるときは押す").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    Spacer(minLength: 0)
                    if c.cardDue(entry.date) { cardBadge }
                }
                Spacer(minLength: 0)
                moodButtons(size: 32, labels: true)
                Spacer(minLength: 0)
                Text(c.cardWritten(entry.date) ? "今日の1枚 書きました ✓" : "夜に「1日1枚」を書くと、AI がふり返ります")
                    .font(.caption2).foregroundStyle(p.sub).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ロック画面

    private var inline: some View {
        let text: String
        if c.cardDue(entry.date) {
            text = "1日1枚 まだ"
        } else if let m = mood {
            text = "今日の気分：\(WidgetMood.title(m))"
        } else {
            text = "今日の気分 まだ"
        }
        return Text(text)
    }

    private var circular: some View {
        let w: World = p.world
        let labelFont: Font = Font.system(size: 9, weight: w.accessoryWeight(.bold), design: w.accessoryDesign ?? .default)
        return ZStack {
            AccessoryWorldBackground(world: w)
            VStack(spacing: 1) {
                Image(systemName: mood.map { WidgetMood.symbol($0) } ?? "questionmark")
                    .font(.system(size: 22, weight: .semibold))
                    .contentTransition(w.widgetSymbolTransition)
                Text(mood.map { WidgetMood.title($0) } ?? "気分は？").font(labelFont).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(6)
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        let w: World = p.world
        return HStack(spacing: 8) {
            Image(systemName: mood.map { WidgetMood.symbol($0) } ?? "questionmark.circle")
                .font(.system(size: 26, weight: .semibold))
                .contentTransition(w.widgetSymbolTransition)
            VStack(alignment: .leading, spacing: 1) {
                Text("今日の気分").font(lockFont(w, .caption2, .semibold))
                Text(mood.map { WidgetMood.title($0) } ?? "まだ").font(lockFont(w, .headline, .heavy)).lineLimit(1)
                Text(c.cardWritten(entry.date) ? "1日1枚 済み・連続\(c.streakDays ?? 0)日" : "1日1枚 まだ")
                    .font(lockFont(w, .caption, .semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessoryWorldFrame(w)
    }
}

// MARK: - 情報

struct InfoWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: DayWidgetEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { entry.palette }
    private var info: InfoFeed { entry.info }

    init(entry: DayWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemLarge: large
            case .systemMedium: medium
            default: small
            }
        }
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: info.shownHeadlines.map(\.title))
        .widgetURL(WidgetLinks.info)
    }

    /// 話題の色（情報タブの InfoTopicColor と同じ番号。0 はデザインの強調色）
    private func topicColor(_ index: Int?) -> Color {
        switch index ?? 0 {
        case 1: Color.blue
        case 2: Color.orange
        case 3: Color.green
        case 4: Color.pink
        case 5: Color.purple
        case 6: Color.teal
        default: p.accent
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("未読の話題").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            if info.isSample { WidgetSampleBadge(color: p.sub) }
            Spacer(minLength: 0)
            Text("\(info.shownHeadlines.count)").font(.caption.weight(.heavy)).foregroundStyle(p.accent)
                .contentTransition(.numericText(value: Double(info.shownHeadlines.count)))
        }
    }

    private func headlineRow(_ h: InfoFeed.Headline, lines: Int, titleFont: Font) -> some View {
        let color: Color = topicColor(h.colorIndex)
        let meta: String = [h.topic, h.source].compactMap { $0 }.joined(separator: "・")
        return HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                if !meta.isEmpty {
                    Text(meta).font(.system(size: 10, weight: .bold)).foregroundStyle(color).lineLimit(1)
                }
                Text(h.title).font(titleFont).foregroundStyle(p.text).lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .transition(p.world.widgetRowTransition(p))
    }

    private var emptyText: some View {
        Text("未読の話題はありません").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(info.shownHeadlines.prefix(2), id: \.self) { h in
                headlineRow(h, lines: 2, titleFont: Font.system(size: 12, weight: .semibold))
            }
            if info.shownHeadlines.isEmpty { emptyText }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(info.shownHeadlines.prefix(2), id: \.self) { h in
                headlineRow(h, lines: 1, titleFont: Font.caption.weight(.semibold))
            }
            if info.shownHeadlines.isEmpty { emptyText }
            Spacer(minLength: 0)
            if let s = info.currentSplat(entry.date) {
                splatStrip(s, compact: true)
            } else if let sale = info.steamSale {
                steamLine(sale)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(info.shownHeadlines.prefix(3), id: \.self) { h in
                headlineRow(h, lines: 2, titleFont: Font.subheadline.weight(.semibold))
            }
            if info.shownHeadlines.isEmpty { emptyText }
            Spacer(minLength: 0)
            if let s = info.currentSplat(entry.date) { splatStrip(s, compact: false) }
            if let sale = info.steamSale { steamLine(sale) }
        }
    }

    /// スプラトゥーンの帯（レギュラー・バンカラ・X）
    private func splatStrip(_ s: InfoFeed.Splat, compact: Bool) -> some View {
        let modes: [(String, String?, Color)] = [
            ("レギュラー", s.regular, Color.green), ("バンカラ", s.bankara, Color.orange), ("X", s.x, Color.teal),
        ]
        let until: String = s.endsAt.map { "〜\(JP.time($0))" } ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("スプラトゥーン3").font(.system(size: 10, weight: .heavy)).foregroundStyle(p.text)
                Spacer(minLength: 0)
                Text(until).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(p.sub)
            }
            if compact {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        let m = modes[i]
                        VStack(alignment: .leading, spacing: 0) {
                            Text(m.0).font(.system(size: 9, weight: .heavy)).foregroundStyle(m.2)
                            Text(m.1 ?? "―").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.text)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ForEach(0..<3, id: \.self) { i in
                    let m = modes[i]
                    HStack(spacing: 8) {
                        Text(m.0).font(.system(size: 10, weight: .heavy)).foregroundStyle(m.2).frame(width: 58, alignment: .leading)
                        Text(m.1 ?? "―").font(.caption.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .widgetCard(p, radius: 12)
    }

    private func steamLine(_ sale: InfoFeed.SteamSale) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gamecontroller.fill").font(.caption2).foregroundStyle(p.accent)
            Text("Steam").font(.system(size: 10, weight: .heavy)).foregroundStyle(p.sub)
            Text(sale.title).font(.caption.weight(.semibold)).foregroundStyle(p.text).lineLimit(1)
            Spacer(minLength: 0)
            if let d = sale.discount {
                Text("-\(d)%").font(.caption.weight(.heavy)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .widgetButton(p, radius: 6)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .widgetCard(p, radius: 12)
    }

    // ロック画面

    private var inline: some View {
        Text(info.shownHeadlines.first.map { $0.title } ?? "未読の話題はありません")
    }

    private var circular: some View {
        let w: World = p.world
        let n: Int = info.shownHeadlines.count
        let numberFont: Font = w == .none ? Font.title2.weight(.heavy) : w.accessoryNumberFont(22)
        let labelFont: Font = Font.system(size: 9, weight: w.accessoryWeight(.semibold), design: w.accessoryDesign ?? .default)
        return ZStack {
            AccessoryWorldBackground(world: w)
            VStack(spacing: 0) {
                Text("\(n)").font(numberFont).tracking(w.accessoryTracking)
                    .contentTransition(.numericText(value: Double(n)))
                Text("未読").font(labelFont)
            }
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        let w: World = p.world
        return VStack(alignment: .leading, spacing: 1) {
            if let s = info.currentSplat(entry.date) {
                Text("スプラ 次の切り替わり").font(lockFont(w, .caption2, .semibold))
                Text(s.endsAt.map { JP.time($0) } ?? "―").font(lockFont(w, .headline, .heavy)).monospacedDigit()
                    .tracking(w.accessoryTracking)
                    .contentTransition(.numericText())
                Text("X \(s.x ?? "―")").font(lockFont(w, .caption, .semibold)).lineLimit(1)
            } else {
                Text("未読の話題 \(info.shownHeadlines.count)件").font(lockFont(w, .caption2, .semibold))
                Text(info.shownHeadlines.first?.title ?? "ありません").font(lockFont(w, .caption, .bold)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessoryWorldFrame(w)
    }
}
