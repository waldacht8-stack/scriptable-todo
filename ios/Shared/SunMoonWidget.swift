import SwiftUI
import WidgetKit

// MARK: - 太陽と月の一日（ウィジェット・小 / 中 / 大）
// 昼（6時〜18時）は太陽が弧を左から右へ、夜（18時〜翌6時）は月が同じ弧を進む。位置は時刻から計算する。
// 空の色は時間帯（明け方・昼・夕方・夜）で変わる。弧の上に今日の TODO を時刻の位置に置く（○ これから・● 済み）。
// タイムラインは 15 分ごとの絵を先に用意しておき、時間が進むと太陽（月）が少しずつ動く。
// 世界観は、空の上の飾り（ブルータルの黒枠・スイスの帯・オーロラの光・日なたの日だまり・ベントのタイル）と、
// 数字の字・切り替わりの動きで出す（部品は WorldWidget.swift）。

/// 空の時間帯
enum SkyPeriod: String {
    case dawn, day, dusk, night

    static func of(_ d: Date) -> SkyPeriod {
        let cal = Calendar.current
        let m: Int = cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d)
        switch m {
        case 300..<540: return .dawn       // 5:00〜9:00
        case 540..<960: return .day        // 9:00〜16:00
        case 960..<1110: return .dusk      // 16:00〜18:30
        default: return .night
        }
    }

    var name: String {
        switch self {
        case .dawn: "朝"
        case .day: "昼"
        case .dusk: "夕方"
        case .night: "夜"
        }
    }

    /// 空のグラデーション（上から下）
    var sky: [Color] {
        switch self {
        case .dawn: [skyx(0xF59E6B), skyx(0xFFD2A1), skyx(0xFFEBD0)]
        case .day: [skyx(0x3F8FD8), skyx(0x8CC6F0), skyx(0xCDE8FA)]
        case .dusk: [skyx(0x6D5A9C), skyx(0xE58FA8), skyx(0xFFC9B5)]
        case .night: [skyx(0x0E1433), skyx(0x1D2752), skyx(0x2E3A6E)]
        }
    }

    /// 空の上の文字
    var ink: Color {
        switch self {
        case .dawn: skyx(0x4A230A)
        case .day: skyx(0x0B2440)
        case .dusk: skyx(0x3A1B3F)
        case .night: skyx(0xE6E9FF)
        }
    }

    /// 空の上の文字の強調（「あと30分」）
    var highlight: Color {
        switch self {
        case .dawn: skyx(0xB4461E)
        case .day: skyx(0x0B4F94)
        case .dusk: skyx(0x8A2A55)
        case .night: skyx(0xFFC9A0)
        }
    }

    /// 弧の線
    var line: Color {
        switch self {
        case .dawn: skyx(0x7A3A12)
        case .day: Color.white
        case .dusk: skyx(0x5A2D58)
        case .night: Color.white
        }
    }

    /// これからの点線の濃さ
    var dashOpacity: Double {
        switch self {
        case .dawn: 0.4
        case .day: 0.7
        case .dusk: 0.45
        case .night: 0.35
        }
    }

    /// 通った道の濃さ
    var passedOpacity: Double {
        switch self {
        case .dawn, .dusk: 0.8
        case .day: 1
        case .night: 0.75
        }
    }

    /// これからの TODO の丸の中
    var hollowFill: Color { self == .night ? skyx(0x1D2752) : Color.white }

    /// 大きいサイズの下の帯
    var panel: Color { self == .night ? skyx(0x0E122C, 0.6) : skyx(0xFFFBF4, 0.92) }
    var panelText: Color { self == .night ? skyx(0xEEF0FF) : skyx(0x1E1B16) }
    var panelSub: Color { self == .night ? skyx(0xAEB3D6) : skyx(0x4D473D) }
    var panelHighlight: Color { self == .night ? skyx(0xFFC9A0) : skyx(0xB4461E) }

    /// 月の欠けた部分に塗る色（月のあたりの空の色）
    var moonShade: Color { skyx(0x1B2550) }
}

/// 0xRRGGBB から色を作る（空の色。このファイルの中だけで使う）
fileprivate func skyx(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}

// MARK: 時刻 → 弧の上の位置

/// 弧の上の TODO の点
struct SunMoonDot: Identifiable, Equatable {
    let id: String
    let fraction: Double
    let time: String
    let title: String
    let done: Bool
}

/// ある時刻の太陽（月）の位置と、弧に載る TODO
struct SunMoonModel {
    let now: Date
    let isDay: Bool          // 太陽の弧（6〜18時）か、月の弧か
    let fraction: Double     // 弧の上の位置（0 左端〜1 右端）
    let period: SkyPeriod
    let dots: [SunMoonDot]
    let windowStart: Date
    let windowEnd: Date

    static let dayStartHour = 6
    static let dayEndHour = 18

    init(now: Date, todos: [TodoItem]) {
        let cal = Calendar.current
        self.now = now
        self.period = SkyPeriod.of(now)
        let today: Date = cal.startOfDay(for: now)
        let h: Int = cal.component(.hour, from: now)
        let sunrise: Date = cal.date(bySettingHour: Self.dayStartHour, minute: 0, second: 0, of: today) ?? today
        let sunset: Date = cal.date(bySettingHour: Self.dayEndHour, minute: 0, second: 0, of: today) ?? today
        let start: Date
        let end: Date
        if h >= Self.dayStartHour && h < Self.dayEndHour {
            isDay = true
            start = sunrise
            end = sunset
        } else if h >= Self.dayEndHour {
            isDay = false
            start = sunset
            end = cal.date(byAdding: .hour, value: 12, to: sunset) ?? sunset
        } else {
            isDay = false
            end = sunrise
            start = cal.date(byAdding: .hour, value: -12, to: sunrise) ?? sunrise
        }
        windowStart = start
        windowEnd = end
        let span: TimeInterval = end.timeIntervalSince(start)
        fraction = max(0, min(1, now.timeIntervalSince(start) / span))
        // 弧の時間の中にある、時刻つきの TODO（未完了と、完了したもの）
        let inWindow: [TodoItem] = todos.filter { item in
            guard let due = item.due, !item.isAllDay else { return false }
            return due >= start && due <= end
        }
        let sorted: [TodoItem] = inWindow.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        dots = sorted.map { item in
            let due: Date = item.due ?? start
            return SunMoonDot(id: item.id, fraction: due.timeIntervalSince(start) / span,
                              time: JP.time(due), title: item.title, done: item.done)
        }
    }
}

/// 弧の形（左端 → 右端の半楕円。幅・高さの比で決める）
struct SunMoonArcGeometry {
    let x0: CGFloat
    let x1: CGFloat
    let baseY: CGFloat
    let ry: CGFloat

    var cx: CGFloat { (x0 + x1) / 2 }
    var rx: CGFloat { (x1 - x0) / 2 }

    func point(_ f: Double) -> CGPoint {
        let theta: Double = Double.pi * (1 - max(0, min(1, f)))
        let x: CGFloat = cx + rx * CGFloat(cos(theta))
        let y: CGFloat = baseY - ry * CGFloat(sin(theta))
        return CGPoint(x: x, y: y)
    }

    static func make(_ family: WidgetFamily, size: CGSize) -> SunMoonArcGeometry {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        switch family {
        case .systemSmall:
            let x0: CGFloat = w * 0.09
            let x1: CGFloat = w * 0.91
            return SunMoonArcGeometry(x0: x0, x1: x1, baseY: h * 0.68, ry: min((x1 - x0) / 2, h * 0.4))
        case .systemLarge:
            return SunMoonArcGeometry(x0: w * 0.06, x1: w * 0.94, baseY: h * 0.5, ry: h * 0.37)
        default:
            return SunMoonArcGeometry(x0: w * 0.055, x1: w * 0.945, baseY: h * 0.74, ry: h * 0.5)
        }
    }
}

/// 弧の線（trim で通った道だけを描ける）
struct SunMoonArcShape: Shape {
    let geo: SunMoonArcGeometry

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let steps: Int = 64
        for i in 0...steps {
            let pt: CGPoint = geo.point(Double(i) / Double(steps))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

// MARK: ウィジェットの見た目

struct SunMoonWidgetView: View {
    @Environment(\.widgetFamily) private var envFamily
    let entry: DayWidgetEntry
    private let familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var p: Palette { entry.palette }

    init(entry: DayWidgetEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    private var model: SunMoonModel { SunMoonModel(now: entry.date, todos: entry.todos) }
    private var day: DayTodos { entry.day }

    var body: some View {
        let m: SunMoonModel = model
        GeometryReader { g in
            let geo: SunMoonArcGeometry = SunMoonArcGeometry.make(family, size: g.size)
            ZStack(alignment: .topLeading) {
                SunMoonSky(period: m.period, world: p.world, accent: p.accent)
                if !m.isDay { stars(g.size) }
                arc(m, geo)
                if family != .systemSmall { labels(m, geo, size: g.size) }
                celestial(m).position(geo.point(m.fraction))
                texts(m, size: g.size)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .fontDesign(p.fontDesign)
        .worldWidgetAnimation(p, value: entry.date)
    }

    // MARK: 空・弧・点

    private func stars(_ size: CGSize) -> some View {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.58, 0.10, 1.3), (0.82, 0.22, 1.1), (0.68, 0.40, 0.9), (0.9, 0.46, 0.9),
            (0.5, 0.52, 0.9), (0.16, 0.14, 1.1), (0.36, 0.08, 1.2), (0.95, 0.08, 1.0),
        ]
        return ZStack {
            ForEach(0..<spots.count, id: \.self) { i in
                let s = spots[i]
                Circle().fill(Color.white.opacity(0.75))
                    .frame(width: s.2 * 2.4, height: s.2 * 2.4)
                    .position(x: size.width * s.0, y: size.height * s.1)
            }
        }
    }

    private func arc(_ m: SunMoonModel, _ geo: SunMoonArcGeometry) -> some View {
        let shape = SunMoonArcShape(geo: geo)
        let dash = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
        let solid = StrokeStyle(lineWidth: 2, lineCap: .round)
        let r: CGFloat = dotRadius
        return ZStack {
            shape.stroke(m.period.line.opacity(m.period.dashOpacity), style: dash)
            shape.trim(from: 0, to: m.fraction)
                .stroke(m.period.line.opacity(m.period.passedOpacity), style: solid)
            ForEach(m.dots) { d in
                let pt: CGPoint = geo.point(d.fraction)
                dot(d, period: m.period, radius: r)
                    .position(pt)
                    .transition(p.world.widgetRowTransition(p))
            }
        }
    }

    private var dotRadius: CGFloat {
        switch family {
        case .systemSmall: 3.5
        case .systemLarge: 5
        default: 4.5
        }
    }

    /// TODO の点：○ これから、● 済み（ブルータルは四角）
    @ViewBuilder private func dot(_ d: SunMoonDot, period: SkyPeriod, radius: CGFloat) -> some View {
        let size: CGFloat = radius * 2
        if p.world == .brutal {
            let shape = Rectangle()
            ZStack {
                shape.fill(d.done ? period.ink.opacity(0.6) : period.hollowFill)
                shape.strokeBorder(period.ink, lineWidth: 1.5)
            }
            .frame(width: size, height: size)
        } else {
            ZStack {
                Circle().fill(d.done ? period.ink.opacity(0.55) : period.hollowFill)
                if !d.done { Circle().strokeBorder(period.ink, lineWidth: 1.5) }
            }
            .frame(width: size, height: size)
        }
    }

    /// 太陽（昼）か月（夜）
    @ViewBuilder private func celestial(_ m: SunMoonModel) -> some View {
        let r: CGFloat = bodyRadius
        let glowScale: CGFloat = p.world == .hinata ? 2.4 : 1.85
        if m.isDay {
            let core: Color = m.period == .day ? skyx(0xFFD84A) : (m.period == .dusk ? skyx(0xFFB36B) : skyx(0xFFE07A))
            let glow: Color = m.period == .day ? skyx(0xFFF6C8, 0.5) : skyx(0xFFF1B8, 0.45)
            ZStack {
                Circle().fill(glow).frame(width: r * 2 * glowScale, height: r * 2 * glowScale)
                Circle().fill(core).frame(width: r * 2, height: r * 2)
                    .shadow(color: p.world == .clay ? Color.black.opacity(0.18) : Color.clear, radius: 2, x: 1, y: 2)
                if p.world == .brutal {
                    Circle().strokeBorder(Color.black, lineWidth: 2).frame(width: r * 2, height: r * 2)
                }
            }
        } else {
            ZStack {
                Circle().fill(skyx(0xE8E4FF, 0.15)).frame(width: r * 2 * 1.75, height: r * 2 * 1.75)
                Circle().fill(skyx(0xF4EFD9)).frame(width: r * 2, height: r * 2)
                Circle().fill(m.period.moonShade).frame(width: r * 1.68, height: r * 1.68)
                    .offset(x: r * 0.47, y: -r * 0.38)
                if p.world == .brutal {
                    Circle().strokeBorder(Color.black, lineWidth: 2).frame(width: r * 2, height: r * 2)
                }
            }
        }
    }

    private var bodyRadius: CGFloat {
        switch family {
        case .systemSmall: 9
        case .systemLarge: 14
        default: 11
        }
    }

    // MARK: 点の名前（中・大）

    private struct PlacedLabel: Identifiable {
        let id: String
        let text: String
        let done: Bool
        let center: CGPoint
        let width: CGFloat
        let trailing: Bool
    }

    /// 点の右上に「14:00 歯医者」。右寄りの点は左上に。重なるものは名前を省く（点は残す）
    private func placedLabels(_ m: SunMoonModel, _ geo: SunMoonArcGeometry, size: CGSize) -> [PlacedLabel] {
        let large: Bool = family == .systemLarge
        let fontSize: CGFloat = large ? 11 : 10
        let maxChars: Int = large ? 9 : 5
        let limit: Int = large ? 6 : 4
        var placed: [PlacedLabel] = []
        var rects: [CGRect] = []
        // これからのものを優先して置き、済みは後から（入るときだけ）
        let ordered: [SunMoonDot] = m.dots.filter { !$0.done } + m.dots.filter { $0.done }
        for d in ordered where placed.count < limit {
            let title: String = d.title.count > maxChars ? String(d.title.prefix(maxChars)) + "…" : d.title
            let text: String = d.done ? "\(d.time) \(large ? title + " " : "")済" : "\(d.time) \(title)"
            let width: CGFloat = Self.estimateWidth(text, fontSize: fontSize)
            let pt: CGPoint = geo.point(d.fraction)
            let trailing: Bool = pt.x > size.width * 0.66
            let gap: CGFloat = dotRadius + 4
            let left: CGFloat = trailing ? pt.x - gap - width : pt.x + gap
            let top: CGFloat = pt.y - fontSize - 4
            let rect = CGRect(x: max(4, left), y: max(2, top), width: width, height: fontSize + 4)
            let sunPt: CGPoint = geo.point(m.fraction)
            let sunRect = CGRect(x: sunPt.x - bodyRadius, y: sunPt.y - bodyRadius, width: bodyRadius * 2, height: bodyRadius * 2)
            let dateRect = CGRect(x: 0, y: 0, width: size.width, height: large ? 34 : 28)
            if rects.contains(where: { $0.intersects(rect) }) || rect.intersects(sunRect) || rect.intersects(dateRect)
                || rect.maxX > size.width - 4 {
                continue
            }
            rects.append(rect)
            placed.append(PlacedLabel(id: d.id, text: text, done: d.done,
                                      center: CGPoint(x: rect.midX, y: rect.midY), width: width, trailing: trailing))
        }
        return placed
    }

    /// 文字の幅のおおよそ（漢字・かなは字の大きさ、数字と記号は 0.6 倍）
    private static func estimateWidth(_ s: String, fontSize: CGFloat) -> CGFloat {
        var w: CGFloat = 0
        for ch in s {
            if ch.isASCII { w += fontSize * (ch == " " ? 0.3 : 0.62) } else { w += fontSize * 1.02 }
        }
        return ceil(w) + 2
    }

    private func labels(_ m: SunMoonModel, _ geo: SunMoonArcGeometry, size: CGSize) -> some View {
        let fontSize: CGFloat = family == .systemLarge ? 11 : 10
        let font: Font = Font.system(size: fontSize, weight: .bold, design: p.fontDesign)
        let list: [PlacedLabel] = placedLabels(m, geo, size: size)
        return ZStack {
            ForEach(list) { l in
                let align: Alignment = l.trailing ? Alignment.trailing : Alignment.leading
                let color: Color = m.period.ink.opacity(l.done ? 0.7 : 1)
                Text(l.text).font(font)
                    .foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: l.width, alignment: align)
                    .position(l.center)
                    .transition(p.world.widgetRowTransition(p))
            }
        }
    }

    // MARK: 文字（次の1件と残りの数）

    private var nextLine: String {
        guard let n = day.next else { return "次の予定はありません" }
        return "次 \(day.nextClock(n)) \(n.title)"
    }

    private var untilLine: String? {
        guard let due = day.next?.due else { return nil }
        return WidgetFeedDay.untilText(due, from: entry.date)
    }

    @ViewBuilder private func texts(_ m: SunMoonModel, size: CGSize) -> some View {
        switch family {
        case .systemSmall: smallTexts(m)
        case .systemLarge: largeTexts(m, size: size)
        default: mediumTexts(m)
        }
    }

    private func smallTexts(_ m: SunMoonModel) -> some View {
        let ink: Color = m.period.ink
        let sub: String = "のこり"
        return VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            Text(nextLine).font(Font.system(size: 13, weight: .heavy, design: p.fontDesign))
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.75)
                .id(day.next?.id ?? "none")
                .transition(p.world.widgetSwapTransition(p))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(sub).font(Font.system(size: 11, weight: .bold, design: p.fontDesign)).foregroundStyle(ink.opacity(0.8))
                WidgetCount(p: p, text: "\(day.today.count)", value: Double(day.today.count), size: 15, color: ink)
                if !m.isDay && !day.doneToday.isEmpty {
                    Text("・今日 \(day.doneToday.count)件済").font(Font.system(size: 11, weight: .bold, design: p.fontDesign))
                        .foregroundStyle(ink.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private func dateHeader(_ m: SunMoonModel, fontSize: CGFloat, showPeriod: Bool) -> some View {
        HStack {
            Text(JP.date(entry.date)).font(Font.system(size: fontSize, weight: .bold, design: p.fontDesign))
            Spacer(minLength: 0)
            if showPeriod {
                Text(m.period.name).font(Font.system(size: fontSize, weight: .bold, design: p.fontDesign))
                    .contentTransition(.interpolate)
            }
        }
        .foregroundStyle(m.period.ink)
    }

    private func mediumTexts(_ m: SunMoonModel) -> some View {
        let ink: Color = m.period.ink
        return VStack(alignment: .leading, spacing: 0) {
            dateHeader(m, fontSize: 11, showPeriod: false)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(nextLine).font(Font.system(size: 14, weight: .heavy, design: p.fontDesign))
                        .foregroundStyle(ink).lineLimit(1)
                    if let u = untilLine {
                        Text(u).font(Font.system(size: 12, weight: .bold, design: p.fontDesign))
                            .foregroundStyle(m.period.highlight).lineLimit(1).fixedSize()
                            .contentTransition(.numericText())
                    }
                }
                .id(day.next?.id ?? "none")
                .transition(p.world.widgetSwapTransition(p))
                Spacer(minLength: 4)
                Text("のこり").font(Font.system(size: 11, weight: .bold, design: p.fontDesign)).foregroundStyle(ink.opacity(0.8))
                WidgetCount(p: p, text: "\(day.today.count)", value: Double(day.today.count), size: 20, color: ink)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func largeTexts(_ m: SunMoonModel, size: CGSize) -> some View {
        let panelTop: CGFloat = size.height * 0.53
        return VStack(alignment: .leading, spacing: 0) {
            dateHeader(m, fontSize: 12, showPeriod: true)
                .padding(.horizontal, 16).padding(.top, 14)
            Spacer(minLength: 0)
            panel(m)
                .frame(height: size.height - panelTop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 大の下の帯：次の1件、今日の一覧、のこり
    private func panel(_ m: SunMoonModel) -> some View {
        let period: SkyPeriod = m.period
        let bento: Bool = p.world == .bento
        let shape = RoundedRectangle(cornerRadius: bento ? 16 : 0, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(nextLine).font(Font.system(size: 16, weight: .heavy, design: p.fontDesign))
                    .foregroundStyle(period.panelText).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let u = untilLine {
                    Text(u).font(Font.system(size: 12, weight: .bold, design: p.fontDesign))
                        .foregroundStyle(period.panelHighlight).lineLimit(1).fixedSize()
                        .contentTransition(.numericText())
                }
            }
            .id(day.next?.id ?? "none")
            .transition(p.world.widgetSwapTransition(p))
            if m.isDay { dayRows(period) } else { nightRows(m) }
            Spacer(minLength: 0)
            footer(m)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack(alignment: .top) {
                shape.fill(period.panel)
                switch p.world {
                case .brutal: Rectangle().fill(Color.black).frame(height: 3)
                case .swiss: Rectangle().fill(period.panelText).frame(height: 1.5)
                default: EmptyView()
                }
            }
        }
        .padding(bento ? 6 : 0)
    }

    private func row(time: String, title: String, done: Bool, period: SkyPeriod, timeColor: Color? = nil) -> some View {
        let font: Font = Font.system(size: 13, weight: done ? .regular : .semibold, design: p.fontDesign)
        let timeFont: Font = Font.system(size: 12, weight: .bold, design: p.fontDesign).monospacedDigit()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time).font(timeFont).foregroundStyle(timeColor ?? (done ? period.panelSub : period.panelHighlight))
                .lineLimit(1).frame(width: 40, alignment: .leading)
            Text(title).font(font).strikethrough(done, color: period.panelSub)
                .foregroundStyle(done ? period.panelSub : period.panelText).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// 昼：今日の一覧（時刻順。済みは線を引く）
    private func dayRows(_ period: SkyPeriod) -> some View {
        let list: [TodoItem] = (day.today + day.doneToday.filter { $0.due != nil })
            .sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
        let shown: [TodoItem] = Array(list.prefix(4))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(shown) { item in
                row(time: day.shortClock(item), title: item.title, done: item.done, period: period,
                    timeColor: item.isOverdue(entry.date) ? p.overdue : nil)
                    .transition(p.world.widgetRowTransition(p))
            }
            if list.isEmpty {
                Text("今日の予定はありません").font(Font.system(size: 13, weight: .semibold, design: p.fontDesign))
                    .foregroundStyle(period.panelSub)
            }
        }
    }

    /// 夜：今日済んだもの、今夜の残り、明日の最初
    private func nightRows(_ m: SunMoonModel) -> some View {
        let period: SkyPeriod = m.period
        let tonight: [TodoItem] = day.open.filter { item in
            guard let due = item.due, !item.isAllDay else { return false }
            return due >= entry.date && due <= m.windowEnd
        }
        let doneNames: String = day.doneToday.prefix(4).map { String($0.title.prefix(4)) }.joined(separator: "・")
        let tomorrowFirst: TodoItem? = day.tomorrow.first
        let tomorrowText: String = tomorrowFirst.map { t in
            let clock: String = t.isAllDay ? "終日" : (t.due.map { JP.time($0) } ?? "")
            let rest: String = day.tomorrow.count > 1 ? " ほか \(day.tomorrow.count - 1)件" : ""
            return "\(clock) \(t.title)\(rest)"
        } ?? "予定はありません"
        return VStack(alignment: .leading, spacing: 6) {
            if !day.doneToday.isEmpty {
                row(time: "今日", title: "\(day.doneToday.count)件 済み（\(doneNames)）", done: false, period: period,
                    timeColor: period.panelSub)
            }
            ForEach(tonight.prefix(2)) { item in
                row(time: item.due.map { JP.time($0) } ?? "", title: item.title, done: false, period: period)
                    .transition(p.world.widgetRowTransition(p))
            }
            row(time: "明日", title: tomorrowText, done: false, period: period, timeColor: period.panelSub)
        }
    }

    private func footer(_ m: SunMoonModel) -> some View {
        let period: SkyPeriod = m.period
        let tail: String
        if !m.isDay {
            tail = "朝 6:00 に太陽へ戻る"
        } else if !day.noDue.isEmpty {
            tail = "期限なし \(day.noDue.count)"
        } else {
            tail = "済み \(day.doneToday.count)"
        }
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("のこり").font(Font.system(size: 12, weight: .bold, design: p.fontDesign))
            WidgetCount(p: p, text: "\(day.today.count)", value: Double(day.today.count), size: 14, color: period.panelText)
            Text("・\(tail)").font(Font.system(size: 12, weight: .bold, design: p.fontDesign)).lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .foregroundStyle(period.panelSub)
    }
}

/// 空の背景（時間帯の色＋世界観の飾り）。containerBackground にも敷く
struct SunMoonSky: View {
    let period: SkyPeriod
    let world: World
    let accent: Color

    var body: some View {
        let colors: [Color] = period.sky
        let base = LinearGradient(stops: [
            Gradient.Stop(color: colors[0], location: 0),
            Gradient.Stop(color: colors[1], location: 0.6),
            Gradient.Stop(color: colors[2], location: 1),
        ], startPoint: .top, endPoint: .bottom)
        ZStack {
            base
            switch world {
            case .brutal:
                ContainerRelativeShape().strokeBorder(Color.black, lineWidth: 4)
            case .swiss:
                HStack(spacing: 0) {
                    Rectangle().fill(accent).frame(width: 5)
                    Spacer(minLength: 0)
                }
            case .aurora:
                RadialGradient(colors: [skyx(0x6D4BFF, 0.35), .clear], center: UnitPoint(x: 0.1, y: 0.05), startRadius: 0, endRadius: 170)
                RadialGradient(colors: [skyx(0x12C2B5, 0.25), .clear], center: UnitPoint(x: 1.0, y: 0.5), startRadius: 0, endRadius: 150)
            case .hinata:
                RadialGradient(colors: [skyx(0xFFE3A8, 0.5), .clear], center: UnitPoint(x: 0.92, y: 0.0), startRadius: 4, endRadius: 220)
            case .clay:
                RadialGradient(colors: [Color.white.opacity(0.35), .clear], center: UnitPoint(x: 0.2, y: 0.1), startRadius: 2, endRadius: 140)
            case .bento, .none:
                EmptyView()
            }
        }
    }
}
