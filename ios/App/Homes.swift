import SwiftUI

/// 設定のデザインに合わせてホーム画面を切り替える
struct HomeView: View {
    @EnvironmentObject var store: TodoStore
    @State private var adding = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch store.theme {
            case .sky: SkyHome()
            case .dial: DialHome()
            case .focus: FocusHome()
            case .paper: PaperHome()
            }
            Button { adding = true } label: {
                Image(systemName: "plus").font(.title2.bold()).frame(width: 58, height: 58)
            }
            .buttonStyle(AddButtonStyle(theme: store.theme))
            .padding(20)
            .accessibilityLabel("TODOを追加")
        }
        .fontDesign(store.theme.fontDesign)
        .sheet(isPresented: $adding) { AddSheet().environmentObject(store).presentationDetents([.medium]) }
    }
}

struct AddButtonStyle: ButtonStyle {
    let theme: AppTheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme == .sky || theme == .dial ? Color.black : Color.white)
            .background(theme == .sky ? Color.white : theme.accent, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - 共通：チェックの丸

struct CheckCircle: View {
    let done: Bool
    let color: Color
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2.5)
            if done {
                Circle().fill(color)
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// 長押しメニュー（重要・明日へ・削除）
struct TodoMenu: ViewModifier {
    @EnvironmentObject var store: TodoStore
    let item: TodoItem
    func body(content: Content) -> some View {
        content.contextMenu {
            Button { store.toggleImportant(item) } label: {
                Label(item.isImportant ? "重要を外す" : "重要にする", systemImage: item.isImportant ? "star.slash" : "star")
            }
            Button { store.postpone(item) } label: { Label("明日へ延期", systemImage: "arrow.turn.up.right") }
            Button(role: .destructive) { store.delete(item) } label: { Label("削除", systemImage: "trash") }
        }
    }
}

extension View {
    func todoMenu(_ item: TodoItem) -> some View { modifier(TodoMenu(item: item)) }
}

// MARK: - ① 空：時刻で変わる空の色＋ガラスのカード

struct SkyHome: View {
    @EnvironmentObject var store: TodoStore
    @State private var feedback = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            ZStack {
                LinearGradient(colors: Sky.colors(at: ctx.date), startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                SkyOrb(date: ctx.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ctx.date.formatted(.dateTime.month().day().weekday(.wide))).font(.subheadline.weight(.semibold)).opacity(0.85)
                            Text(greeting(ctx.date)).font(.largeTitle.bold())
                            Text("のこり \(store.open.count) 件").font(.title3.weight(.semibold)).opacity(0.9)
                        }
                        .padding(.top, 40)
                        VStack(spacing: 0) {
                            ForEach(store.open) { item in
                                SkyRow(item: item) { store.complete(item); feedback += 1 }
                                if item.id != store.open.last?.id { Divider().overlay(.white.opacity(0.25)).padding(.leading, 56) }
                            }
                            if store.open.isEmpty {
                                Text("今日はもう、やることはありません").padding(24)
                            }
                        }
                        .glassCard()
                        if !store.doneToday.isEmpty {
                            Text("完了 \(store.doneToday.count) 件").font(.footnote.weight(.semibold)).opacity(0.8).padding(.leading, 6)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 4..<11: "おはようございます"
        case 11..<17: "こんにちは"
        default: "こんばんは"
        }
    }
}

/// 時刻の位置に太陽（夜は月）を浮かべる
struct SkyOrb: View {
    let date: Date
    var body: some View {
        GeometryReader { g in
            let h = Double(Calendar.current.component(.hour, from: date)) + Double(Calendar.current.component(.minute, from: date)) / 60
            let night = Sky.isNight(at: date)
            let t = night ? ((h < 5 ? h + 24 : h) - 19) / 10 : (h - 5) / 14 // 0〜1 で東から西へ
            let x = g.size.width * (0.1 + 0.8 * t)
            let y = g.size.height * (0.32 - 0.22 * sin(.pi * t))
            Circle()
                .fill(night ? Color(white: 0.95) : Color(red: 1, green: 0.93, blue: 0.7))
                .frame(width: night ? 44 : 64, height: night ? 44 : 64)
                .shadow(color: night ? .white.opacity(0.5) : .yellow.opacity(0.7), radius: night ? 18 : 40)
                .position(x: x, y: y)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct SkyRow: View {
    @EnvironmentObject var store: TodoStore
    let item: TodoItem
    let onDone: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onDone) { CheckCircle(done: item.done, color: .white) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.isImportant { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                    Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                }
                Text(DueText.label(item)).font(.caption.weight(.medium))
                    .foregroundStyle(item.isOverdue() ? Color(red: 1, green: 0.75, blue: 0.6) : .white.opacity(0.8))
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .todoMenu(item)
    }
}

// MARK: - ② ダイヤル：一日を24時間の円で見る

struct DialHome: View {
    @EnvironmentObject var store: TodoStore
    private let mint = AppTheme.dial.accent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            ScrollView {
                VStack(spacing: 22) {
                    Text(ctx.date.formatted(.dateTime.month().day().weekday(.abbreviated))).font(.headline).foregroundStyle(.secondary)
                        .padding(.top, 24)
                    ZStack {
                        DayRing(items: todayItems, now: ctx.date, accent: mint).frame(width: 300, height: 300)
                        VStack(spacing: 4) {
                            if let next = store.nextTimed, let due = next.due {
                                Text("次の予定まで").font(.caption).foregroundStyle(.secondary)
                                Text(due, style: .timer).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(mint)
                                Text(next.title).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: 170)
                            } else {
                                Text("\(store.open.count)").font(.system(size: 54, weight: .bold, design: .monospaced)).foregroundStyle(mint)
                                Text("のこり").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(store.open) { item in
                            HStack(spacing: 12) {
                                Button { store.complete(item) } label: {
                                    RoundedRectangle(cornerRadius: 7).strokeBorder(item.isOverdue() ? .orange : mint, lineWidth: 2.5).frame(width: 26, height: 26)
                                }.buttonStyle(.plain)
                                Text(item.due.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "--:--")
                                    .font(.callout.monospacedDigit()).foregroundStyle(item.isOverdue() ? .orange : .secondary)
                                Text(item.title).lineLimit(1)
                                Spacer()
                                if item.isImportant { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption) }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .todoMenu(item)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 110)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.06).ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
    }

    private var todayItems: [TodoItem] {
        store.items.filter { $0.due.map { Calendar.current.isDateInToday($0) } ?? false }
    }
}

/// 24時間の円：外周に時刻の目盛り、今日のTODOを点で、現在時刻を針で
struct DayRing: View {
    let items: [TodoItem]
    let now: Date
    let accent: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 18
            func point(_ hour: Double, _ radius: CGFloat) -> CGPoint {
                let a = (hour / 24) * 2 * .pi - .pi / 2
                return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
            }
            var track = Path(); track.addArc(center: c, radius: r, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(track, with: .color(.white.opacity(0.12)), lineWidth: 14)
            let h = hourOf(now)
            var passed = Path(); passed.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + h / 24 * 360), clockwise: false)
            ctx.stroke(passed, with: .color(accent.opacity(0.35)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            for hour in 0..<24 {
                var tick = Path()
                tick.move(to: point(Double(hour), r - 14)); tick.addLine(to: point(Double(hour), r - (hour % 6 == 0 ? 26 : 20)))
                ctx.stroke(tick, with: .color(.white.opacity(hour % 6 == 0 ? 0.6 : 0.25)), lineWidth: hour % 6 == 0 ? 2 : 1)
                if hour % 6 == 0 {
                    ctx.draw(Text("\(hour)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary), at: point(Double(hour), r - 40))
                }
            }
            for item in items {
                guard let due = item.due else { continue }
                let p = point(hourOf(due), r)
                let color: Color = item.done ? .gray : (item.isOverdue(now) ? .orange : accent)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(color))
            }
            var hand = Path(); hand.move(to: c); hand.addLine(to: point(h, r - 30))
            ctx.stroke(hand, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.white))
        }
    }

    private func hourOf(_ d: Date) -> Double {
        Double(Calendar.current.component(.hour, from: d)) + Double(Calendar.current.component(.minute, from: d)) / 60
    }
}

// MARK: - ③ フォーカス：1件ずつ。右スワイプで完了、左で明日へ

struct FocusHome: View {
    @EnvironmentObject var store: TodoStore
    @State private var drag: CGSize = .zero
    @State private var feedback = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("あと").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(store.open.count)").font(.system(size: 56, weight: .heavy))
                Text("件").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 30)
            ZStack {
                if store.open.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 72)).foregroundStyle(AppTheme.focus.accent)
                        Text("全部終わりました").font(.title2.bold())
                    }
                }
                ForEach(Array(store.open.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                    FocusCard(item: item, index: index, drag: index == 0 ? drag : .zero)
                        .gesture(swipe(item), including: index == 0 ? .all : .none)
                        .todoMenu(item)
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Label("明日へ", systemImage: "arrow.left").foregroundStyle(.orange)
                Spacer()
                Label("完了", systemImage: "arrow.right").labelStyle(TrailingIcon()).foregroundStyle(.green)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 32).padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func swipe(_ item: TodoItem) -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if v.translation.width > 120 {
                    withAnimation(.spring(duration: 0.35)) { drag = CGSize(width: 600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { store.complete(item); drag = .zero; feedback += 1 }
                } else if v.translation.width < -120 {
                    withAnimation(.spring(duration: 0.35)) { drag = CGSize(width: -600, height: 0) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { store.postpone(item); drag = .zero }
                } else {
                    withAnimation(.spring(duration: 0.35)) { drag = .zero }
                }
            }
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

struct FocusCard: View {
    let item: TodoItem
    let index: Int
    let drag: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(DueText.label(item))
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((item.isOverdue() ? Color.orange : AppTheme.focus.accent).opacity(0.14), in: Capsule())
                    .foregroundStyle(item.isOverdue() ? .orange : AppTheme.focus.accent)
                Spacer()
                if item.isImportant { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            }
            Spacer()
            Text(item.title).font(.system(size: 34, weight: .bold)).lineLimit(3).minimumScaleFactor(0.6)
            Spacer()
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 32))
        .overlay(alignment: .topTrailing) {
            if drag.width > 30 { stamp("完了", .green) } else if drag.width < -30 { stamp("明日へ", .orange) }
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 24)
        .scaleEffect(1 - CGFloat(index) * 0.05)
        .offset(x: drag.width, y: CGFloat(index) * 18 + drag.height * 0.1)
        .rotationEffect(.degrees(Double(drag.width) / 20))
    }

    private func stamp(_ text: String, _ color: Color) -> some View {
        Text(text).font(.title2.bold()).foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(drag.width > 0 ? -12 : 12))
            .padding(22)
            .opacity(min(1, abs(drag.width) / 120))
    }
}

// MARK: - ④ 手帳：罫線の紙と明朝体。完了で「済」のはんこ

struct PaperHome: View {
    @EnvironmentObject var store: TodoStore
    @State private var stamped: Set<String> = []
    private let ink = Color(red: 0.16, green: 0.14, blue: 0.12)
    private let red = AppTheme.paper.accent
    private let line: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(.dateTime.year().month().day().weekday(.wide)))
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .padding(.top, 36).padding(.bottom, 4)
                Text("本日の用事　\(store.open.count)").font(.system(.subheadline, design: .serif)).foregroundStyle(ink.opacity(0.6))
                    .frame(height: line, alignment: .bottom)
                ForEach(store.open + store.doneToday) { item in
                    HStack(spacing: 12) {
                        Text(item.due.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "　―　")
                            .font(.system(.footnote, design: .serif).monospacedDigit()).foregroundStyle(item.isOverdue() ? red : ink.opacity(0.55))
                            .frame(width: 48, alignment: .leading)
                        Text((item.isImportant ? "◎ " : "") + item.title)
                            .font(.system(size: 19, design: .serif))
                            .strikethrough(item.done, color: ink.opacity(0.5))
                            .foregroundStyle(item.done ? ink.opacity(0.45) : ink)
                            .lineLimit(1)
                        Spacer()
                        ZStack {
                            if item.done || stamped.contains(item.id) { Hanko(color: red).transition(.scale(scale: 2.4).combined(with: .opacity)) }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .frame(height: line)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !item.done else { store.uncomplete(item); return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { _ = stamped.insert(item.id) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { store.complete(item); stamped.remove(item.id) }
                    }
                    .todoMenu(item)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 120)
            .background(alignment: .topLeading) { RuledLines(spacing: line, offset: 36 + 30 + line, color: Color(red: 0.55, green: 0.70, blue: 0.85).opacity(0.45)) }
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.98, green: 0.96, blue: 0.90).ignoresSafeArea())
        .overlay(alignment: .leading) { Rectangle().fill(red.opacity(0.35)).frame(width: 1.5).padding(.leading, 18).ignoresSafeArea() }
        .preferredColorScheme(.light)
        .sensoryFeedback(.impact(weight: .heavy), trigger: stamped.count)
    }
}

struct RuledLines: View {
    let spacing: CGFloat
    let offset: CGFloat
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var y = offset
            while y < size.height + 2000 {
                var p = Path(); p.move(to: CGPoint(x: -40, y: y)); p.addLine(to: CGPoint(x: size.width + 40, y: y))
                ctx.stroke(p, with: .color(color), lineWidth: 0.8)
                y += spacing
            }
        }
        .frame(height: 3000)
        .allowsHitTesting(false)
    }
}

/// 朱色の丸いはんこ「済」
struct Hanko: View {
    let color: Color
    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2.5)
            Text("済").font(.system(size: 20, weight: .heavy, design: .serif)).foregroundStyle(color)
        }
        .frame(width: 40, height: 40)
        .rotationEffect(.degrees(-14))
        .opacity(0.88)
    }
}
