import AppIntents
import WidgetKit
import Foundation

// MARK: - 相談のウィジェット用：今日の気分の記録（アプリは開かない）と、ウィジェットに渡す元データ

/// ウィジェットのボタンで今日の気分を記録する（1 つらい 〜 5 最高。アプリの気分と同じ記録に上書き）
struct LogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "今日の気分を記録"

    @Parameter(title: "気分（1〜5）")
    var level: Int

    init() {}
    init(level: Int) { self.level = level }

    func perform() async throws -> some IntentResult {
        MoodData.record(ConsultMood.from(score: level))
        return .result()
    }
}

/// consult-widget.json（ウィジェット担当が読む。項目名は変えない）
struct ConsultWidgetFeed: Codable, Equatable {
    var todayMood: Int?          // 1〜5（未記録は nil）
    var dayCardWritten: Bool     // 今日の「1日1枚」を書いたか
    var streakDays: Int          // 「1日1枚」を続けて書いた日数（今日、まだなら昨日から数える）
    var day: String? = nil       // この状態の日（yyyy-MM-dd）。ウィジェットは今日でなければ未記録として扱う
}

enum ConsultWidgetSync {
    static let file = "consult-widget.json"
    /// 1日1枚のファイル名（daycard-yyyy-MM-dd.json。App/Info/Consult/DayCardData.swift と同じ形）
    static func dayCardFile(_ day: String) -> String { "daycard-\(day).json" }

    static func load() -> ConsultWidgetFeed? { SharedStore.load(ConsultWidgetFeed.self, from: file) }

    /// 書いた日の集まりから、続けて書いた日数を数える
    static func streak(days: Set<String>, now: Date = .now) -> Int {
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: now)
        if !days.contains(WakeLogic.key(cursor)) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var n = 0
        while days.contains(WakeLogic.key(cursor)), n < 3650 {
            n += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return n
    }

    static func make(now: Date = .now) -> ConsultWidgetFeed {
        let dir = SharedStore.url("x").deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var days = Set<String>()
        for n in names where n.hasPrefix("daycard-") && n.hasSuffix(".json") {
            let core = String(n.dropFirst(8).dropLast(5))
            if core.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { days.insert(core) }
        }
        return ConsultWidgetFeed(todayMood: MoodData.today(now: now)?.score,
                                 dayCardWritten: days.contains(WakeLogic.key(now)),
                                 streakDays: streak(days: days, now: now),
                                 day: WakeLogic.key(now))
    }

    /// 書き直して、ウィジェットを更新する（-demo のときは書かない）
    static func write(now: Date = .now) {
        guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return }
        SharedStore.save(make(now: now), to: file)   // SharedStore.save が reloadAllTimelines も呼ぶ
    }
}
