import Foundation
import AppIntents
import WidgetKit

// ⚠️ 一時ファイル（r4/widgets の枝だけ）。統合のときに削除する。
// 本物の LogMoodIntent は情報・相談の担当が Shared/ConsultIntents.swift に置く。
// この枝だけでもビルドでき、ウィジェットの気分ボタンが動くよう、同じ名前・同じ引数で仮に置いている。
// 仮の動き：consult-widget.json の todayMood と day だけを書き換える（相談の記録 MoodData には書かない）。
// level は ConsultMood の番号（0 最高・1 いい・2 ふつう・3 いまいち・4 つらい）。

struct LogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "今日の気分を記録"

    @Parameter(title: "気分")
    var level: Int

    init() {}
    init(level: Int) { self.level = level }

    func perform() async throws -> some IntentResult {
        var f: ConsultFeed = SharedStore.load(ConsultFeed.self, from: ConsultFeed.file) ?? ConsultFeed()
        let today: String = WidgetFeedDay.key(.now)
        if f.day != today {
            f.dayCardWritten = false
        }
        f.day = today
        f.todayMood = max(0, min(4, level))
        SharedStore.save(f, to: ConsultFeed.file)
        return .result()
    }
}
