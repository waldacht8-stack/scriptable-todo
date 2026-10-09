import SwiftUI
import Charts

// MARK: - 気分の記録と分析（相談の「今日の気分は？」を1日1件ずつ残し、傾向を見る）
// - 記録は端末のファイル（consult-moods.json）。同じ日に選び直すと、その日の気分を上書きする
// - 分析は端末の中で計算する（平均・推移・曜日・起床/習慣/TODO/集中との関係）
// - 「AI で性格と傾向を分析」だけ Gemini に送る。送るのは集計した数字と、相談で自分が書いた文（最近の10件）だけ
// - 起動引数 -moodstats で分析の画面を開く（スクリーンショット用。-demo では見本の記録）

extension ConsultMood {
    /// 点数（最高 5 〜 つらい 1）
    var score: Int { 5 - rawValue }

    static func from(score: Int) -> ConsultMood { ConsultMood(rawValue: 5 - min(max(score, 1), 5)) ?? .okay }

    func color(_ p: Palette) -> Color {
        switch self {
        case .great: Color(red: 0.95, green: 0.62, blue: 0.10)
        case .good: Color(red: 0.36, green: 0.70, blue: 0.36)
        case .okay: p.sub
        case .low: Color(red: 0.36, green: 0.55, blue: 0.85)
        case .bad: Color(red: 0.45, green: 0.38, blue: 0.75)
        }
    }
}

struct MoodEntry: Codable, Identifiable, Equatable {
    var day: String          // yyyy-MM-dd（WakeLogic.key と同じ形）
    var mood: ConsultMood
    var at: Date
    var id: String { day }
}

struct MoodAnalysis: Codable, Equatable {
    var text: String
    var at: Date
}

enum MoodData {
    static let file = "consult-moods.json"
    static let analysisFile = "consult-analysis.json"

    static func entries() -> [MoodEntry] { SplatFiles.load([MoodEntry].self, file) ?? [] }

    /// その日の気分を記録する（同じ日は上書き）
    static func record(_ mood: ConsultMood, now: Date = .now) {
        var list = entries()
        let day = WakeLogic.key(now)
        list.removeAll { $0.day == day }
        list.append(MoodEntry(day: day, mood: mood, at: now))
        list.sort { $0.day < $1.day }
        SplatFiles.save(Array(list.suffix(800)), file)
    }

    static func today(now: Date = .now) -> ConsultMood? {
        let day = WakeLogic.key(now)
        return entries().first { $0.day == day }?.mood
    }

    static func remove(day: String) {
        var list = entries()
        list.removeAll { $0.day == day }
        SplatFiles.save(list, file)
    }

    static func analysis() -> MoodAnalysis? { SplatFiles.load(MoodAnalysis.self, analysisFile) }
    static func save(_ a: MoodAnalysis) { SplatFiles.save(a, analysisFile) }
}

// MARK: - 1日分（気分と、その日のほかの記録）

struct MoodDay: Identifiable, Equatable {
    var date: Date
    var mood: ConsultMood
    var wake: Int?              // 起床スコア（記録がない日は nil）
    var habitRate: Double?      // 習慣の達成率 0〜1（習慣がなければ nil）
    var doneCount: Int          // 完了した TODO の数
    var focusMinutes: Double    // 集中した分

    var id: Date { date }
    var score: Int { mood.score }
    var weekday: Int { Calendar.current.component(.weekday, from: date) }   // 1=日曜
}

/// 「〜の日は気分が高い/低い」の比較
struct MoodFactor: Identifiable, Equatable {
    var title: String           // 例：起床スコアが80点以上の日
    var diff: Double            // その日の平均 − それ以外の日の平均
    var withCount: Int
    var withoutCount: Int
    var id: String { title }
}

struct MoodStats: Equatable {
    var days: [MoodDay]                 // 古い順
    var average: Double?
    var recent7: Double?
    var previous7: Double?
    var counts: [ConsultMood: Int]
    var weekday: [Int: Double]          // 1=日曜 … 7=土曜
    var factors: [MoodFactor]
    var streak: Int                     // 今日（または昨日）まで続けて記録した日数

    static let empty = MoodStats(days: [], average: nil, recent7: nil, previous7: nil, counts: [:], weekday: [:], factors: [], streak: 0)

    static func average(_ xs: [MoodDay]) -> Double? {
        xs.isEmpty ? nil : Double(xs.map(\.score).reduce(0, +)) / Double(xs.count)
    }

    static func make(_ input: [MoodDay], now: Date = .now) -> MoodStats {
        let cal = Calendar.current
        let days: [MoodDay] = input.sorted { $0.date < $1.date }
        let today = cal.startOfDay(for: now)
        func within(_ from: Int, _ to: Int) -> [MoodDay] {
            days.filter {
                let d = cal.dateComponents([.day], from: cal.startOfDay(for: $0.date), to: today).day ?? 999
                return d >= from && d < to
            }
        }
        var counts: [ConsultMood: Int] = [:]
        for d in days { counts[d.mood, default: 0] += 1 }
        var weekday: [Int: Double] = [:]
        for w in 1...7 {
            if let a = average(days.filter { $0.weekday == w }) { weekday[w] = a }
        }
        // 続けて記録した日数（今日か昨日から数える）
        let keys: Set<Date> = Set(days.map { cal.startOfDay(for: $0.date) })
        var cursor: Date = keys.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0
        while keys.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            if streak > 3650 { break }
        }
        return MoodStats(days: days, average: average(days), recent7: average(within(0, 7)), previous7: average(within(7, 14)),
                         counts: counts, weekday: weekday, factors: factors(days), streak: streak)
    }

    /// 比べる条件。どちらの側も3日以上あるものだけ、差の大きい順
    static func factors(_ days: [MoodDay]) -> [MoodFactor] {
        func compare(_ title: String, _ pick: (MoodDay) -> Bool?) -> MoodFactor? {
            var yes: [MoodDay] = []
            var no: [MoodDay] = []
            for d in days {
                guard let v = pick(d) else { continue }
                if v { yes.append(d) } else { no.append(d) }
            }
            guard yes.count >= 3, no.count >= 3, let a = average(yes), let b = average(no) else { return nil }
            return MoodFactor(title: title, diff: a - b, withCount: yes.count, withoutCount: no.count)
        }
        let list: [MoodFactor?] = [
            compare("起床スコアが80点以上の日") { d in d.wake.map { s in s >= 80 } },
            compare("習慣を半分以上できた日") { d in d.habitRate.map { r in r >= 0.5 } },
            compare("TODO を3件以上終えた日") { d in d.doneCount >= 3 },
            compare("30分以上集中した日") { d in d.focusMinutes >= 30 },
            compare("土日") { d in [1, 7].contains(d.weekday) },
        ]
        return list.compactMap { $0 }.sorted { abs($0.diff) > abs($1.diff) }
    }

    var hasEnough: Bool { days.count >= 3 }

    /// 端末の中で作る、ことばの分析
    var insights: [String] {
        var out: [String] = []
        if let r = recent7, let p = previous7 {
            let d = r - p
            if d >= 0.3 { out.append("この1週間は、その前の週より気分が上向きです（\(Self.signed(d))）。") }
            else if d <= -0.3 { out.append("この1週間は、その前の週より気分が下がりぎみです（\(Self.signed(d))）。無理をしすぎていないか、休めているかを見直してみましょう。") }
            else { out.append("この2週間の気分は安定しています。") }
        }
        if weekday.count >= 4,
           let best = weekday.max(by: { $0.value < $1.value }), let worst = weekday.min(by: { $0.value < $1.value }),
           best.value - worst.value >= 0.5 {
            out.append("\(Self.weekdayName(best.key))曜日は気分が高く、\(Self.weekdayName(worst.key))曜日は低くなりやすい傾向です。")
        }
        for f in factors.prefix(2) where abs(f.diff) >= 0.3 {
            out.append(f.diff > 0 ? "\(f.title)は、そうでない日より気分が平均 \(Self.signed(f.diff)) 高めです。"
                                  : "\(f.title)は、そうでない日より気分が平均 \(Self.signed(f.diff)) 低めです。")
        }
        if let top = counts.max(by: { $0.value < $1.value }), days.count >= 7 {
            let ratio = Int((Double(top.value) / Double(days.count) * 100).rounded())
            out.append("いちばん多い気分は「\(top.key.title)」で、全体の \(ratio)% です。")
        }
        return out
    }

    /// AI に渡す集計（数字だけ）
    var summaryForAI: String {
        var lines: [String] = ["記録した日数: \(days.count)日（連続 \(streak)日）"]
        if let a = average { lines.append("気分の平均: \(String(format: "%.2f", a)) / 5（5=最高、1=つらい）") }
        if let r = recent7 { lines.append("直近7日の平均: \(String(format: "%.2f", r))") }
        if let p = previous7 { lines.append("その前の7日の平均: \(String(format: "%.2f", p))") }
        let dist = ConsultMood.allCases.map { "\($0.title) \(counts[$0] ?? 0)日" }.joined(separator: "、")
        lines.append("気分の内訳: \(dist)")
        let wd = (1...7).compactMap { w in weekday[w].map { "\(Self.weekdayName(w)) \(String(format: "%.1f", $0))" } }.joined(separator: "、")
        if !wd.isEmpty { lines.append("曜日ごとの平均: \(wd)") }
        for f in factors {
            lines.append("\(f.title)（\(f.withCount)日）とそれ以外（\(f.withoutCount)日）の差: \(Self.signed(f.diff))")
        }
        let recent = days.suffix(14).map { "\(JP.shortDate($0.date)) \($0.mood.title)" }.joined(separator: "、")
        lines.append("最近14日の気分: \(recent)")
        return lines.joined(separator: "\n")
    }

    static func signed(_ d: Double) -> String { String(format: d >= 0 ? "+%.1f" : "%.1f", d) }
    static func weekdayName(_ w: Int) -> String { ["日", "月", "火", "水", "木", "金", "土"][(w - 1 + 7) % 7] }
}

// MARK: - 記録を集める（気分と、同じ日の起床・習慣・TODO・集中）

enum MoodCollector {
    @MainActor
    static func days(now: Date = .now) -> [MoodDay] {
        if ProcessInfo.processInfo.arguments.contains("-demo") { return MoodDemo.days(now: now) }
        let entries = MoodData.entries()
        guard !entries.isEmpty else { return [] }
        let cal = Calendar.current
        var wake: [String: Int] = [:]
        for s in WakeStore.sessions() where !s.isMissed { wake[s.day] = s.score }
        let habits = HabitData.habits()
        let log = HabitData.log()
        var done: [String: Int] = [:]
        for t in TodoData.all() {
            if let d = t.doneAt { done[WakeLogic.key(d), default: 0] += 1 }
        }
        var focus: [String: Double] = [:]
        for r in FocusTimerData.sessions() { focus[WakeLogic.key(r.start), default: 0] += r.minutes }
        return entries.compactMap { e in
            guard let date = WakeLogic.date(fromKey: e.day) else { return nil }
            let rate: Double? = habits.isEmpty ? nil : HabitData.dayProgress(habits, log, on: cal.startOfDay(for: date))
            return MoodDay(date: date, mood: e.mood, wake: wake[e.day], habitRate: rate,
                           doneCount: done[e.day] ?? 0, focusMinutes: focus[e.day] ?? 0)
        }
    }
}

// MARK: - 見本（-demo。架空の記録。起床がよい日・習慣ができた日は気分が高め）

enum MoodDemo {
    static func days(now: Date = .now) -> [MoodDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [MoodDay] = []
        for i in 0..<42 {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if i % 9 == 5 { continue }   // 記録しなかった日
            let w = cal.component(.weekday, from: date)
            let wake = 60 + (i * 37 % 41)
            let habit = Double((i * 13) % 10) / 10
            var s = 3
            if wake >= 80 { s += 1 }
            if habit >= 0.6 { s += 1 }
            if w == 2 { s -= 1 }          // 月曜は低め
            if w == 7 || w == 1 { s += 0 }
            if i % 7 == 3 { s -= 1 }
            if i < 7 { s = min(s + 1, 5) } // 最近は上向き
            let mood = ConsultMood.from(score: s)
            out.append(MoodDay(date: date, mood: mood, wake: wake, habitRate: habit,
                               doneCount: (i * 5) % 6, focusMinutes: Double((i * 17) % 70)))
        }
        return out.sorted { $0.date < $1.date }
    }

    static let analysis = """
    【気分の傾向】
    この6週間は「いい」「ふつう」の日が中心で、大きく崩れる日は多くありません。この1週間は上向きです。月曜日は低くなりやすく、週の始まりに負担を感じやすいようです。

    【性格の特徴（記録からの傾向）】
    ・朝の調子がその日の気分に強く響くタイプのようです。よく起きられた日は気分が高めです。
    ・習慣をこなせた日に気分が上がっているので、「小さな達成」を積み重ねると元気が出やすい人だと考えられます。
    ・TODO の多さよりも、生活のリズムのほうが気分に影響しています。

    【ストレスのたまり方と発散のしかた】
    週の始まりと、寝不足の日に気分が下がりやすいようです。相談では「たまっている」「追いつかない」という言葉が多く、量の多さが負担になりやすい傾向があります。体を動かした日や、習慣をこなせた日に持ち直しています。

    【自己改革の一歩】
    ・日曜の夜は早めに休み、月曜の朝の負担を軽くする
    ・つらい日は、習慣を1つだけにしぼって「できた」を作る
    【今日の一歩】寝る30分前にスマホを置く
    """
}

// MARK: - 画面：気分の記録と分析

struct MoodStatsView: View {
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motion) private var motion
    @ObservedObject var model: ConsultModel
    @EnvironmentObject var store: TodoStore
    @State private var stats = MoodStats.empty
    @State private var analysis: MoodAnalysis?
    @State private var analyzing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if stats.hasEnough {
                            MoodSummaryCard(stats: stats)
                            MoodTrendCard(stats: stats)
                            MoodDistributionCard(stats: stats)
                            MoodWeekdayCard(stats: stats).id("weekday")
                            if !stats.factors.isEmpty { MoodFactorCard(stats: stats) }
                            MoodInsightCard(stats: stats)
                            aiCard.id("ai")
                        } else {
                            notEnough
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .onAppear { Self.scrollForShot(proxy) }
            }
            .paletteBackground(p)
            .navigationTitle("気分の記録と分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .onAppear {
            stats = MoodStats.make(MoodCollector.days())
            analysis = model.isDemo ? MoodAnalysis(text: MoodDemo.analysis, at: .now) : MoodData.analysis()
        }
    }

    /// 画面写真用：起動引数 -moodscroll weekday|ai でその欄まで下げておく
    private static func scrollForShot(_ proxy: ScrollViewProxy) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-moodscroll"), i + 1 < args.count else { return }
        let target = args[i + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(target, anchor: .top) }
    }

    private var notEnough: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 40)).foregroundStyle(p.accent)
            Text("記録がたまると分析できます").font(.title3.weight(.heavy)).foregroundStyle(p.text)
            Text("相談の「今日の気分は？」を毎日1回選ぶと、ここに推移やグラフが出ます。3日分から傾向を、2週間ほどたまると起床や習慣との関係もわかります。いまの記録：\(stats.days.count)日")
                .font(.subheadline).foregroundStyle(p.sub)
        }
        .paletteCard(p)
    }

    // AI の分析
    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI の分析", systemImage: "sparkles").font(.headline).foregroundStyle(p.text)
                Spacer()
                if let a = analysis {
                    Text(JP.shortDate(a.at)).font(.caption).foregroundStyle(p.sub)
                }
            }
            if let a = analysis {
                Text(a.text).font(.subheadline).lineSpacing(4).foregroundStyle(p.text).textSelection(.enabled)
                if let step = ConsultStep.extract(a.text) {
                    stepButton(step)
                }
            } else {
                Text("気分の記録と、相談で書いた文から、性格の特徴・ストレスのたまり方・自己改革の一歩を AI がまとめます。")
                    .font(.subheadline).foregroundStyle(p.sub)
            }
            if let e = error { Text(e).font(.footnote.weight(.semibold)).foregroundStyle(p.overdue) }
            Button {
                Task { await analyze() }
            } label: {
                HStack(spacing: 8) {
                    if analyzing { ProgressView().tint(p.onAccent) }
                    Text(analysis == nil ? "性格と傾向を分析する" : "もう一度分析する").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(p.onAccent)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(analyzing || !model.hasKey)
            Text(model.hasKey ? "送るのは集計した数字と、相談で書いた最近の文だけです。医学的な診断ではなく、記録から見える傾向です。"
                              : "使うには、相談のメニューから Gemini の API キーを設定してください。")
                .font(.caption2).foregroundStyle(p.sub)
        }
        .paletteCard(p)
    }

    /// 分析の【今日の一歩】を TODO にする
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

    private func analyze() async {
        guard !analyzing else { return }
        if model.isDemo {
            withAnimation(motion.change) { analysis = MoodAnalysis(text: MoodDemo.analysis, at: .now) }
            return
        }
        guard let key = InfoSecrets.get(ConsultModel.keyName) else {
            error = "Gemini の API キーを設定してください。"
            return
        }
        analyzing = true
        defer { analyzing = false }
        let mine: [String] = model.messages.filter(\.fromUser).suffix(10).map { String($0.text.prefix(200)) }
        var prompt = "次は、ある人の気分の記録を集計したものです。\n\n\(stats.summaryForAI)\n"
        if !mine.isEmpty {
            prompt += "\nこの人が相談で書いた最近の文:\n" + mine.map { "・\($0)" }.joined(separator: "\n") + "\n"
        }
        prompt += """

        この相談の目的は、ストレス発散・自己分析・自己改革です。
        これをもとに、日本語で次の4つの見出しに分けて、合わせて500字ほどでまとめてください。
        【気分の傾向】【性格の特徴（記録からの傾向）】【ストレスのたまり方と発散のしかた】【自己改革の一歩】
        - 断定せず「〜のようです」「〜の傾向があります」と書く。診断名は使わない
        - 数字を根拠にする。記録が少ない点は正直に書く
        - 【自己改革の一歩】は、5〜15分でできる具体的な行動を2つまで。続けやすさを優先する
        - 最後の行に「【今日の一歩】」に続けて、いちばん大事な行動を20字以内で1つ書く
        """
        let system = "あなたは、生活の記録から本人の傾向をやさしく読み解き、ストレス発散・自己分析・自己改革を手伝う相手です。医療の診断はしません。"
        do {
            let text = try await GeminiAPI.reply(key: key, system: system,
                                                 history: [ConsultMessage(fromUser: true, text: prompt)])
            let a = MoodAnalysis(text: text, at: .now)
            MoodData.save(a)
            withAnimation(motion.change) { analysis = a }
            error = nil
        } catch GeminiError.quota {
            error = "無料枠の上限に達しました。しばらくしてからもう一度試してください。"
        } catch GeminiError.badKey {
            error = "API キーが使えませんでした。キーを確かめてください。"
        } catch {
            self.error = "分析を受け取れませんでした。通信を確認してください。"
        }
    }
}

// MARK: - 部品

private struct MoodSummaryCard: View {
    @Environment(\.palette) private var p
    let stats: MoodStats

    var body: some View {
        let avg: Double = stats.average ?? 0
        let mood: ConsultMood = ConsultMood.from(score: Int(avg.rounded()))
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: mood.symbol).font(.system(size: 40)).foregroundStyle(mood.color(p))
                .frame(width: 64, height: 64)
                .background(mood.color(p).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("平均の気分").font(.caption.weight(.semibold)).foregroundStyle(p.sub)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", avg)).font(.system(size: 40, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    Text("/ 5").font(.subheadline.weight(.semibold)).foregroundStyle(p.sub)
                }
                trendLine
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stats.days.count)").font(.title2.weight(.heavy)).foregroundStyle(p.text)
                Text("日 記録").font(.caption2).foregroundStyle(p.sub)
                Text("連続 \(stats.streak)日").font(.caption2.weight(.bold)).foregroundStyle(p.accent)
            }
        }
        .paletteCard(p)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trendLine: some View {
        if let r = stats.recent7, let pr = stats.previous7 {
            let d: Double = r - pr
            let up: Bool = d >= 0
            Label("直近7日 \(MoodStats.signed(d))", systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(up ? p.accent : p.overdue)
        } else if let r = stats.recent7 {
            Text("直近7日 \(String(format: "%.1f", r))").font(.caption.weight(.bold)).foregroundStyle(p.sub)
        }
    }
}

private struct MoodCardTitle: View {
    @Environment(\.palette) private var p
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.headline).foregroundStyle(p.text)
    }
}

/// 30日の推移
private struct MoodTrendCard: View {
    @Environment(\.palette) private var p
    let stats: MoodStats

    var body: some View {
        let cal = Calendar.current
        let from: Date = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now)) ?? .now
        let recent: [MoodDay] = stats.days.filter { $0.date >= from }
        VStack(alignment: .leading, spacing: 10) {
            MoodCardTitle(title: "30日の推移", symbol: "chart.xyaxis.line")
            Chart {
                ForEach(recent) { d in
                    LineMark(x: .value("日", d.date, unit: .day), y: .value("気分", d.score))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(p.accent.opacity(0.6))
                    PointMark(x: .value("日", d.date, unit: .day), y: .value("気分", d.score))
                        .foregroundStyle(d.mood.color(p))
                        .symbolSize(40)
                }
            }
            .chartYScale(domain: 0.5...5.5)
            .chartYAxis {
                AxisMarks(position: .leading, values: [1, 3, 5]) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let i = v.as(Int.self) { Text(ConsultMood.from(score: i).title).font(.caption2) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                }
            }
            .frame(height: 170)
        }
        .paletteCard(p)
        .accessibilityLabel("30日の気分の推移")
    }
}

/// 気分の内訳
private struct MoodDistributionCard: View {
    @Environment(\.palette) private var p
    let stats: MoodStats

    var body: some View {
        let total: Int = max(stats.days.count, 1)
        VStack(alignment: .leading, spacing: 10) {
            MoodCardTitle(title: "気分の内訳", symbol: "chart.bar.fill")
            ForEach(ConsultMood.allCases) { m in
                let n: Int = stats.counts[m] ?? 0
                HStack(spacing: 8) {
                    Image(systemName: m.symbol).foregroundStyle(m.color(p)).frame(width: 22)
                    Text(m.title).font(.caption.weight(.bold)).foregroundStyle(p.text).frame(width: 52, alignment: .leading)
                    MoodBar(ratio: Double(n) / Double(total), color: m.color(p))
                    Text("\(n)日").font(.caption.monospacedDigit()).foregroundStyle(p.sub).frame(width: 36, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .paletteCard(p)
    }
}

private struct MoodBar: View {
    @Environment(\.palette) private var p
    let ratio: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width * CGFloat(min(max(ratio, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(p.sub.opacity(0.12))
                Capsule().fill(color).frame(width: max(w, ratio > 0 ? 6 : 0))
            }
        }
        .frame(height: 10)
    }
}

/// 曜日ごとの平均
private struct MoodWeekdayCard: View {
    @Environment(\.palette) private var p
    let stats: MoodStats

    var body: some View {
        let order: [Int] = [2, 3, 4, 5, 6, 7, 1]   // 月〜日
        VStack(alignment: .leading, spacing: 10) {
            MoodCardTitle(title: "曜日ごとの平均", symbol: "calendar")
            Chart {
                ForEach(order, id: \.self) { w in
                    BarMark(x: .value("曜日", MoodStats.weekdayName(w)), y: .value("平均", stats.weekday[w] ?? 0))
                        .foregroundStyle(p.accent.gradient)
                        .cornerRadius(4)
                }
            }
            .chartYScale(domain: 0...5)
            .chartYAxis { AxisMarks(position: .leading, values: [1, 3, 5]) }
            .frame(height: 140)
        }
        .paletteCard(p)
        .accessibilityLabel("曜日ごとの気分の平均")
    }
}

/// 起床・習慣などとの関係
private struct MoodFactorCard: View {
    @Environment(\.palette) private var p
    let stats: MoodStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoodCardTitle(title: "気分と関係していそうなこと", symbol: "link")
            ForEach(stats.factors) { f in
                MoodFactorRow(factor: f)
            }
            Text("それぞれ「その日」と「それ以外の日」の気分の平均の差です（5段階）。")
                .font(.caption2).foregroundStyle(p.sub)
        }
        .paletteCard(p)
    }
}

private struct MoodFactorRow: View {
    @Environment(\.palette) private var p
    let factor: MoodFactor

    var body: some View {
        let up: Bool = factor.diff >= 0
        let color: Color = up ? p.accent : p.overdue
        let ratio: Double = min(abs(factor.diff) / 2, 1)
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(factor.title).font(.subheadline.weight(.semibold)).foregroundStyle(p.text)
                Spacer()
                Text(MoodStats.signed(factor.diff)).font(.subheadline.weight(.heavy).monospacedDigit()).foregroundStyle(color)
            }
            MoodBar(ratio: ratio, color: color)
            Text("\(factor.withCount)日 と \(factor.withoutCount)日 をくらべて").font(.caption2).foregroundStyle(p.sub)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 端末の中で作った、ことばの分析
private struct MoodInsightCard: View {
    @Environment(\.palette) private var p
    let stats: MoodStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoodCardTitle(title: "わかったこと", symbol: "lightbulb.fill")
            ForEach(stats.insights, id: \.self) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(p.accent).frame(width: 6, height: 6)
                    Text(s).font(.subheadline).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            if stats.insights.isEmpty {
                Text("もう少し記録がたまると、傾向が見えてきます。").font(.subheadline).foregroundStyle(p.sub)
            }
        }
        .paletteCard(p)
    }
}
