import SwiftUI

/// アプリ内で切り替えるデザイン。色だけでなく、ホーム画面の構成と操作が変わる。
enum AppTheme: String, CaseIterable, Identifiable {
    case sky      // 空：時刻で空の色が変わる背景＋ガラスのカード
    case dial     // ダイヤル：24時間の円にTODOを配置
    case focus    // フォーカス：1件ずつ大きなカード。スワイプで完了・延期
    case paper    // 手帳：罫線の紙と明朝体。完了で「済」のはんこ

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sky: "空"
        case .dial: "ダイヤル"
        case .focus: "フォーカス"
        case .paper: "手帳"
        }
    }

    var summary: String {
        switch self {
        case .sky: "時刻で変わる空の色とガラスのカード"
        case .dial: "一日を24時間の円で見る"
        case .focus: "1件ずつ。スワイプで完了・延期"
        case .paper: "罫線の紙。完了ではんこ"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .sky: .rounded
        case .dial: .monospaced
        case .focus: .default
        case .paper: .serif
        }
    }

    var accent: Color {
        switch self {
        case .sky: .white
        case .dial: Color(red: 0.20, green: 0.83, blue: 0.60)
        case .focus: Color(red: 0.11, green: 0.31, blue: 0.85)
        case .paper: Color(red: 0.75, green: 0.16, blue: 0.13)
        }
    }

    var prefersDark: Bool? {
        switch self {
        case .dial: true
        case .paper: false
        default: nil
        }
    }

    static func from(_ raw: String) -> AppTheme { AppTheme(rawValue: raw) ?? .sky }
}

// MARK: - 空の色（時刻で変わる）

enum Sky {
    /// 時刻ごとの空のグラデーション（上・下）
    static func colors(at date: Date = .now) -> [Color] {
        let h = Double(Calendar.current.component(.hour, from: date)) + Double(Calendar.current.component(.minute, from: date)) / 60
        let stops: [(Double, Color, Color)] = [
            (0, rgb(0.04, 0.06, 0.16), rgb(0.10, 0.13, 0.30)),   // 深夜
            (5, rgb(0.16, 0.18, 0.40), rgb(0.95, 0.55, 0.45)),   // 夜明け
            (7, rgb(0.40, 0.65, 0.95), rgb(0.98, 0.80, 0.62)),   // 朝焼け
            (11, rgb(0.20, 0.52, 0.95), rgb(0.62, 0.82, 0.98)),  // 青空
            (16, rgb(0.30, 0.50, 0.90), rgb(0.95, 0.75, 0.55)),  // 午後
            (18, rgb(0.35, 0.25, 0.55), rgb(0.98, 0.50, 0.35)),  // 夕焼け
            (20, rgb(0.07, 0.09, 0.25), rgb(0.20, 0.18, 0.42)),  // 夜
            (24, rgb(0.04, 0.06, 0.16), rgb(0.10, 0.13, 0.30)),
        ]
        var lower = stops[0], upper = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where h >= stops[i].0 && h < stops[i + 1].0 {
            lower = stops[i]; upper = stops[i + 1]
        }
        let t = (h - lower.0) / max(upper.0 - lower.0, 0.001)
        return [mix(lower.1, upper.1, t), mix(lower.2, upper.2, t)]
    }

    static func isNight(at date: Date = .now) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        return h >= 19 || h < 5
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ra = UIColor(a).rgba, rb = UIColor(b).rgba
        return Color(red: ra.0 + (rb.0 - ra.0) * t, green: ra.1 + (rb.1 - ra.1) * t, blue: ra.2 + (rb.2 - ra.2) * t)
    }
}

private extension UIColor {
    var rgba: (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}

// MARK: - ガラスのカード（iOS 26 は Liquid Glass、それより前は半透明の素材）

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func glassCard(_ radius: CGFloat = 22) -> some View { modifier(GlassCard(cornerRadius: radius)) }
}

// MARK: - 期限の表示

enum DueText {
    static func label(_ t: TodoItem, now: Date = .now) -> String {
        guard let due = t.due else { return "期限なし" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        let time = due.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        let day: String
        switch days {
        case 0: day = "今日"
        case -1: day = "昨日"
        case 1: day = "明日"
        default: day = due.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated))
        }
        if t.isAllDay { return days == 0 ? "今日・終日" : day }
        return days == 0 ? time : "\(day) \(time)"
    }
}
