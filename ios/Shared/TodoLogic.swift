import Foundation

// MARK: - 繰り返し

enum RepeatRule: String, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly
    var id: String { rawValue }
    var name: String {
        switch self {
        case .daily: "毎日"
        case .weekdays: "平日（月〜金）"
        case .weekly: "毎週"
        case .monthly: "毎月"
        }
    }
}

extension TodoItem {
    /// 繰り返しの次の期限（今日より前にならないところまで進める）
    func nextOccurrence(now: Date = .now) -> Date? {
        guard let rule = repeatRule.flatMap(RepeatRule.init(rawValue:)), let due else { return nil }
        let cal = Calendar.current
        func step(_ d: Date) -> Date {
            switch rule {
            case .daily: return cal.date(byAdding: .day, value: 1, to: d)!
            case .weekly: return cal.date(byAdding: .day, value: 7, to: d)!
            case .monthly: return cal.date(byAdding: .month, value: 1, to: d)!
            case .weekdays:
                var x = cal.date(byAdding: .day, value: 1, to: d)!
                while cal.isDateInWeekend(x) { x = cal.date(byAdding: .day, value: 1, to: x)! }
                return x
            }
        }
        // 毎月は元の期限から nか月後で数える（1/31 → 2/28 → 3/31。2月の28日に引きずられない）
        if rule == .monthly {
            let today = cal.startOfDay(for: now)
            var n = 1
            var next = cal.date(byAdding: .month, value: n, to: due)!
            while next < today && n < 1000 { n += 1; next = cal.date(byAdding: .month, value: n, to: due)! }
            return next
        }
        var next = step(due)
        let today = cal.startOfDay(for: now)
        var guardCount = 0
        while next < today && guardCount < 1000 { next = step(next); guardCount += 1 }
        return next
    }
}

/// 完了の処理（画面・通知・ウィジェットで共通）。繰り返しなら次の回を作る
enum TodoActions {
    static func complete(_ items: inout [TodoItem], at i: Int, now: Date = .now) {
        items[i].done = true
        items[i].doneAt = now
        if !items[i].isCalendar, let next = items[i].nextOccurrence(now: now) {
            var copy = items[i]
            copy.id = UUID().uuidString
            copy.done = false
            copy.doneAt = nil
            copy.due = next
            items.append(copy)
        }
    }
}

