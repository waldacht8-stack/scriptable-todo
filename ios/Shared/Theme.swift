import SwiftUI

// MARK: - デザイン（色合い）
// 画面の構成はすべて「フォーカス」の考え方（大きなカード・余白・スワイプ）でそろえ、
// デザインの切り替えは色・書体・角の丸みを変える。各画面は @Environment(\.palette) で色を受け取る。

enum AppTheme: String, CaseIterable, Identifiable {
    case focus   // クリーン：明るいグレーに白いカード、青
    case night   // ナイト：黒にミント（常にダーク）
    case dawn    // 朝焼け：やわらかい朝の色、コーラル
    case paper   // 手帳：クリーム色の紙と明朝体、朱色

    var id: String { rawValue }

    var name: String {
        switch self {
        case .focus: "クリーン"
        case .night: "ナイト"
        case .dawn: "朝焼け"
        case .paper: "手帳"
        }
    }

    var summary: String {
        switch self {
        case .focus: "明るく、すっきり"
        case .night: "黒とミント。夜も目にやさしい"
        case .dawn: "朝の光のような暖かい色"
        case .paper: "紙の手帳と明朝体"
        }
    }

    static func from(_ raw: String) -> AppTheme { AppTheme(rawValue: raw) ?? .focus }

    var palette: Palette {
        switch self {
        case .focus:
            Palette(background: [Color(.systemGroupedBackground)], card: Color(.secondarySystemGroupedBackground),
                    text: .primary, sub: .secondary, accent: Color(red: 0.11, green: 0.31, blue: 0.85),
                    overdue: Color(red: 0.86, green: 0.36, blue: 0.10), onAccent: .white,
                    fontDesign: .default, radius: 28, scheme: nil)
        case .night:
            Palette(background: [Color(red: 0.04, green: 0.05, blue: 0.06)], card: Color(red: 0.11, green: 0.12, blue: 0.14),
                    text: .white, sub: Color(white: 0.62), accent: Color(red: 0.20, green: 0.83, blue: 0.60),
                    overdue: Color(red: 0.98, green: 0.57, blue: 0.24), onAccent: Color(red: 0.04, green: 0.05, blue: 0.06),
                    fontDesign: .rounded, radius: 24, scheme: .dark)
        case .dawn:
            Palette(background: [Color(red: 1.0, green: 0.93, blue: 0.86), Color(red: 0.99, green: 0.84, blue: 0.80)],
                    card: Color(red: 1.0, green: 0.98, blue: 0.95), text: Color(red: 0.24, green: 0.16, blue: 0.20),
                    sub: Color(red: 0.50, green: 0.40, blue: 0.42), accent: Color(red: 0.78, green: 0.28, blue: 0.27),   // 白い文字と 4.5:1 以上
                    overdue: Color(red: 0.80, green: 0.25, blue: 0.10), onAccent: .white,
                    fontDesign: .rounded, radius: 30, scheme: .light)
        case .paper:
            Palette(background: [Color(red: 0.97, green: 0.95, blue: 0.89)], card: Color(red: 0.995, green: 0.985, blue: 0.95),
                    text: Color(red: 0.16, green: 0.14, blue: 0.12), sub: Color(red: 0.45, green: 0.42, blue: 0.38),
                    accent: Color(red: 0.75, green: 0.16, blue: 0.13), overdue: Color(red: 0.75, green: 0.16, blue: 0.13), onAccent: .white,
                    fontDesign: .serif, radius: 14, scheme: .light)
        }
    }
}

/// 画面が使う色の組。新しい画面はこれだけを使って色を決める（デザイン切り替えに自動で追従する）
struct Palette {
    var background: [Color]      // 背景（2色ならグラデーション）
    var card: Color              // カードの背景
    var text: Color              // 本文
    var sub: Color               // 補足の文字
    var accent: Color            // 強調・ボタン
    var overdue: Color           // 期限切れ・警告
    var onAccent: Color          // accent の上に載せる文字
    var fontDesign: Font.Design
    var radius: CGFloat          // カードの角の丸み
    var scheme: ColorScheme?     // nil なら端末の外観に合わせる

    static let `default` = AppTheme.focus.palette
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.default
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// 共通の部品
extension View {
    /// デザインの背景を全画面に敷く
    func paletteBackground(_ p: Palette) -> some View {
        background(
            LinearGradient(colors: p.background.count > 1 ? p.background : [p.background[0], p.background[0]],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    /// デザインのカード（全幅・角丸・やわらかい影）
    func paletteCard(_ p: Palette, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: p.radius, style: .continuous)
                    .fill(p.card)
                    .shadow(color: .black.opacity(p.scheme == .dark ? 0 : 0.06), radius: 12, y: 4)
            )
    }
}

/// 見出し（画面上部の大きな数字など）
struct BigCount: View {
    @Environment(\.palette) private var p
    let prefix: String
    let value: Int
    let suffix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(prefix).font(.title3.weight(.semibold)).foregroundStyle(p.sub)
            Text("\(value)").font(.system(size: 56, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                .contentTransition(.numericText())
            Text(suffix).font(.title3.weight(.semibold)).foregroundStyle(p.sub)
            Spacer()
        }
    }
}

// MARK: - 日付の表示（端末の言語設定にかかわらず日本語）

enum JP {
    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = pattern
        return f
    }
    private static let md = fmt("M月d日（E）")
    private static let ymd = fmt("y年M月d日 EEEE")
    private static let hm = fmt("HH:mm")
    private static let mdShort = fmt("M/d（E）")

    static func date(_ d: Date) -> String { md.string(from: d) }
    static func longDate(_ d: Date) -> String { ymd.string(from: d) }
    static func time(_ d: Date) -> String { hm.string(from: d) }
    static func shortDate(_ d: Date) -> String { mdShort.string(from: d) }

    /// 一覧の左に出す短い時刻（時刻なし＝終日、期限なし）
    static func clock(_ t: TodoItem, none: String = "--:--") -> String {
        guard let due = t.due else { return none }
        return t.isAllDay ? "終日" : time(due)
    }
}

// MARK: - 期限の表示

enum DueText {
    static func label(_ t: TodoItem, now: Date = .now) -> String {
        guard let due = t.due else { return "期限なし" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day ?? 0
        let time = JP.time(due)
        let day: String
        switch days {
        case 0: day = "今日"
        case -1: day = "昨日"
        case 1: day = "明日"
        default: day = JP.shortDate(due)
        }
        if t.isAllDay { return days == 0 ? "今日・終日" : day }
        return days == 0 ? time : "\(day) \(time)"
    }
}
/// 「今日」の画面構成。構成ごとにボタンの位置と操作が変わる。
enum TodayLayout: String, CaseIterable, Identifiable {
    case focus      // 1件ずつ大きなカード。右下の＋、スワイプで完了・延期
    case board      // グループ：期限ごとの見出しで分けた一覧。下の入力欄で追加
    case thumb      // 週間：日付ボタンで日を選び、時刻つきで一覧
    case timeline   // ながれ：1本の線でつないだ時系列と「いま」の印

    var id: String { rawValue }

    var name: String {
        switch self {
        case .focus: "フォーカス"
        case .board: "グループ"
        case .thumb: "週間"
        case .timeline: "ながれ"
        }
    }

    var summary: String {
        switch self {
        case .focus: "1件ずつ大きく。スワイプで完了・延期"
        case .board: "今日・明日…と期限ごとに分けて一覧"
        case .thumb: "日付を選んで、その日を時刻順に"
        case .timeline: "1本の線で時系列。いまの位置がわかる"
        }
    }

    static func from(_ raw: String) -> TodayLayout { TodayLayout(rawValue: raw) ?? .focus }
}

