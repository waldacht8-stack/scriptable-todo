import Foundation

// MARK: - 今日の気分（相談の「今日の気分は？」）の記録
// アプリとウィジェット（LogMoodIntent）が同じファイル consult-moods.json を読み書きする。同じ日は上書き
// 色や分析の画面はアプリの App/Info/Consult/ConsultMoodStats.swift

enum ConsultMood: Int, CaseIterable, Identifiable, Codable {
    case great, good, okay, low, bad
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .great: "最高"
        case .good: "いい"
        case .okay: "ふつう"
        case .low: "いまいち"
        case .bad: "つらい"
        }
    }

    var symbol: String {
        switch self {
        case .great: "sun.max.fill"
        case .good: "cloud.sun.fill"
        case .okay: "cloud.fill"
        case .low: "cloud.drizzle.fill"
        case .bad: "cloud.heavyrain.fill"
        }
    }

    /// 点数（最高 5 〜 つらい 1）
    var score: Int { 5 - rawValue }

    static func from(score: Int) -> ConsultMood { ConsultMood(rawValue: 5 - min(max(score, 1), 5)) ?? .okay }
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

    /// その日の気分を記録する（同じ日は上書き）。ウィジェットの元データも書き直す
    static func record(_ mood: ConsultMood, now: Date = .now) {
        var list = entries()
        let day = WakeLogic.key(now)
        list.removeAll { $0.day == day }
        list.append(MoodEntry(day: day, mood: mood, at: now))
        list.sort { $0.day < $1.day }
        SplatFiles.save(Array(list.suffix(800)), file)
        ConsultWidgetSync.write(now: now)
    }

    static func today(now: Date = .now) -> ConsultMood? {
        let day = WakeLogic.key(now)
        return entries().first { $0.day == day }?.mood
    }

    static func remove(day: String) {
        var list = entries()
        list.removeAll { $0.day == day }
        SplatFiles.save(list, file)
        ConsultWidgetSync.write()
    }

    static func analysis() -> MoodAnalysis? { SplatFiles.load(MoodAnalysis.self, analysisFile) }
    static func save(_ a: MoodAnalysis) { SplatFiles.save(a, analysisFile) }
}
