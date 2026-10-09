import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - デザイン（色合い）
// 画面の構成はすべて「フォーカス」の考え方（大きなカード・余白・スワイプ）でそろえ、
// デザインの切り替えは色・書体・角の丸みを変える。各画面は @Environment(\.palette) で色を受け取る。
//
// 色合い（AppTheme）が土台の色を決め、設定の「カスタマイズ」（強調色・角の丸み・書体・表示の密度）が上書きする。
// 画面全体に渡す値は `AppTheme.current()`（または `theme.palette(with: settings)`）で作る。
// 文字とカード、onAccent と accent の明るさの比はどの色合いでも 4.5:1 以上（WCAG AA）。

/// 0xRRGGBB から色を作る（このファイルの中だけで使う）
fileprivate func hx(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

enum AppTheme: String, CaseIterable, Identifiable {
    case focus      // クリーン：明るいグレーに白いカード、青（端末の外観に合わせる）
    case night      // ナイト：黒にミント（常にダーク）
    case dawn       // 朝焼け：やわらかい朝の色、コーラル
    case paper      // 手帳：クリーム色の紙と明朝体、朱色
    case forest     // 森：若葉色の背景に深い緑
    case ocean      // 海：紺色にアクア（常にダーク）
    case lavender   // ラベンダー：薄紫
    case sakura     // 桜：淡い桜色に紅
    case coffee     // コーヒー：こげ茶にキャラメル色、明朝体（常にダーク）
    case mono       // モノクロ：白と黒だけ、細い枠線
    case contrast   // ハイコントラスト：黒地に白と黄色、枠線つき（読みやすさ重視）

    var id: String { rawValue }

    var name: String {
        switch self {
        case .focus: "クリーン"
        case .night: "ナイト"
        case .dawn: "朝焼け"
        case .paper: "手帳"
        case .forest: "森"
        case .ocean: "海"
        case .lavender: "ラベンダー"
        case .sakura: "桜"
        case .coffee: "コーヒー"
        case .mono: "モノクロ"
        case .contrast: "ハイコントラスト"
        }
    }

    var summary: String {
        switch self {
        case .focus: "明るく、すっきり"
        case .night: "黒とミント。夜も目にやさしい"
        case .dawn: "朝の光のような暖かい色"
        case .paper: "紙の手帳と明朝体"
        case .forest: "若葉色と深い緑で落ち着いた印象"
        case .ocean: "夜の海の紺色とアクア"
        case .lavender: "やわらかな薄紫"
        case .sakura: "淡い桜色と紅色"
        case .coffee: "こげ茶とキャラメル色。明朝体"
        case .mono: "白と黒だけのシンプルな見た目"
        case .contrast: "黒地に白と黄色。文字がくっきり"
        }
    }

    static func from(_ raw: String) -> AppTheme { AppTheme(rawValue: raw) ?? .focus }

    /// 設定に保存された色合いとカスタマイズを合わせた、いま使う色の組
    static func current(_ s: AppSettings = SettingsData.load()) -> Palette { from(s.theme).palette(with: s) }

    /// この色合いに、設定のカスタマイズ（強調色・角の丸み・書体・表示の密度）を重ねる
    func palette(with s: AppSettings) -> Palette {
        var p = palette
        if let c = AccentChoice.from(s.accentColor).colors(for: p) {
            p.accent = c.accent
            p.onAccent = c.onAccent
        }
        if let r = CornerChoice.from(s.cornerStyle).radius { p.radius = r }
        if let d = FontChoice.from(s.fontStyle).design { p.fontDesign = d }
        p.density = Density.from(s.density)
        return p
    }

    /// 色合いそのもの（カスタマイズなし）
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
                    sub: Color(red: 0.50, green: 0.40, blue: 0.42), accent: Color(red: 0.78, green: 0.28, blue: 0.27),
                    overdue: Color(red: 0.80, green: 0.25, blue: 0.10), onAccent: .white,
                    fontDesign: .rounded, radius: 30, scheme: .light)
        case .paper:
            Palette(background: [Color(red: 0.97, green: 0.95, blue: 0.89)], card: Color(red: 0.995, green: 0.985, blue: 0.95),
                    text: Color(red: 0.16, green: 0.14, blue: 0.12), sub: Color(red: 0.45, green: 0.42, blue: 0.38),
                    accent: Color(red: 0.75, green: 0.16, blue: 0.13), overdue: Color(red: 0.75, green: 0.16, blue: 0.13), onAccent: .white,
                    fontDesign: .serif, radius: 14, scheme: .light)
        // 比（文字/カード・onAccent/accent）：森 13.5・6.4、海 12.1・9.2、ラベンダー 14.5・6.8、桜 14.3・5.6、
        // コーヒー 11.4・7.1、モノクロ 21・18.9、ハイコントラスト 18.1・14.9
        case .forest:
            Palette(background: [hx(0xE6EFE3), hx(0xCFE0CF)], card: hx(0xF7FAF5),
                    text: hx(0x15301F), sub: hx(0x4C6354), accent: hx(0x2D6A46),
                    overdue: hx(0xB5462A), onAccent: .white,
                    fontDesign: .default, radius: 22, scheme: .light)
        case .ocean:
            Palette(background: [hx(0x0B1A2E), hx(0x0E2A45)], card: hx(0x15304D),
                    text: hx(0xEAF4FB), sub: hx(0x9DB4C8), accent: hx(0x4FD1E0),
                    overdue: hx(0xFF9B6B), onAccent: hx(0x06202E),
                    fontDesign: .rounded, radius: 26, scheme: .dark)
        case .lavender:
            Palette(background: [hx(0xF3EEFC), hx(0xE3D9F6)], card: hx(0xFCFAFF),
                    text: hx(0x2A2240), sub: hx(0x665D80), accent: hx(0x6447B5),
                    overdue: hx(0xB93E0B), onAccent: .white,
                    fontDesign: .rounded, radius: 28, scheme: .light)
        case .sakura:
            Palette(background: [hx(0xFFF3F6), hx(0xFADAE3)], card: hx(0xFFFAFB),
                    text: hx(0x3A2028), sub: hx(0x7A5862), accent: hx(0xB8365F),
                    overdue: hx(0xB5400F), onAccent: .white,
                    fontDesign: .rounded, radius: 30, scheme: .light)
        case .coffee:
            Palette(background: [hx(0x2E2119), hx(0x1D1410)], card: hx(0x3A2B22),
                    text: hx(0xF5E9DC), sub: hx(0xC2AE9A), accent: hx(0xD9A066),
                    overdue: hx(0xFF8A65), onAccent: hx(0x2A1E17),
                    fontDesign: .serif, radius: 18, scheme: .dark)
        case .mono:
            Palette(background: [hx(0xF2F2F2)], card: .white,
                    text: .black, sub: hx(0x555555), accent: hx(0x111111),
                    overdue: hx(0xB00020), onAccent: .white,
                    fontDesign: .default, radius: 8, scheme: .light, outline: Color.black.opacity(0.85))
        case .contrast:
            Palette(background: [.black], card: hx(0x161616),
                    text: .white, sub: hx(0xD6D6D6), accent: hx(0xFFD60A),
                    overdue: hx(0xFF6B6B), onAccent: .black,
                    fontDesign: .default, radius: 12, scheme: .dark, outline: Color.white.opacity(0.55))
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
    var outline: Color? = nil    // カードの枠線（モノクロ・ハイコントラスト）
    var density: Density = .regular  // 表示の密度（@Environment(\.density) でも読める）

    /// 常に暗い色合いか（端末の外観に合わせる色合いは false）
    var isDark: Bool { scheme == .dark }

    static let `default` = AppTheme.focus.palette
}

// MARK: - カスタマイズ（設定で色合いの上に重ねる）

/// 強調色の上書き。明るい色合いでは濃い色＋白い文字、暗い色合いでは明るい色＋黒い文字にする（どちらも 4.5:1 以上）
enum AccentChoice: String, CaseIterable, Identifiable {
    case theme, blue, teal, green, orange, red, pink, purple, graphite

    var id: String { rawValue }
    static func from(_ raw: String) -> AccentChoice { AccentChoice(rawValue: raw) ?? .theme }

    var name: String {
        switch self {
        case .theme: "色合いのまま"
        case .blue: "青"
        case .teal: "青緑"
        case .green: "緑"
        case .orange: "オレンジ"
        case .red: "赤"
        case .pink: "ピンク"
        case .purple: "紫"
        case .graphite: "グラファイト"
        }
    }

    /// 明るい背景用（白い文字を載せる）と暗い背景用（黒い文字を載せる）
    private var pair: (light: Color, dark: Color)? {
        switch self {
        case .theme: nil
        case .blue: (hx(0x1F5FD6), hx(0x6EA8FF))
        case .teal: (hx(0x0F766E), hx(0x3DD6C6))
        case .green: (hx(0x2E7D32), hx(0x6FD67A))
        case .orange: (hx(0xC2410C), hx(0xFFA45C))
        case .red: (hx(0xC62828), hx(0xFF7A7A))
        case .pink: (hx(0xC2185B), hx(0xFF8AB8))
        case .purple: (hx(0x6D3FC0), hx(0xB79CFF))
        case .graphite: (hx(0x3F4651), hx(0xD5D9E0))
        }
    }

    /// 見本に出す色（明るい背景用）
    var swatch: Color? { pair?.light }

    func colors(for p: Palette) -> (accent: Color, onAccent: Color)? {
        guard let pair else { return nil }
        let darkOn = Color(red: 0.04, green: 0.05, blue: 0.06)
        switch p.scheme {
        case .dark?: return (pair.dark, darkOn)
        case .light?: return (pair.light, .white)
        default:
            // 端末の外観に合わせる色合い：ライトとダークで切り替わる色にする
            return (Self.adaptive(pair.light, pair.dark), Self.adaptive(.white, darkOn))
        }
    }

    private static func adaptive(_ light: Color, _ dark: Color) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        light
        #endif
    }
}

/// 角の丸み
enum CornerChoice: String, CaseIterable, Identifiable {
    case theme, small, medium, large
    var id: String { rawValue }
    static func from(_ raw: String) -> CornerChoice { CornerChoice(rawValue: raw) ?? .theme }

    var name: String {
        switch self {
        case .theme: "色合い"
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var radius: CGFloat? {
        switch self {
        case .theme: nil
        case .small: 10
        case .medium: 20
        case .large: 32
        }
    }
}

/// 書体
enum FontChoice: String, CaseIterable, Identifiable {
    case theme, standard, rounded, serif
    var id: String { rawValue }
    static func from(_ raw: String) -> FontChoice { FontChoice(rawValue: raw) ?? .theme }

    var name: String {
        switch self {
        case .theme: "色合い"
        case .standard: "標準"
        case .rounded: "丸"
        case .serif: "明朝"
        }
    }

    var design: Font.Design? {
        switch self {
        case .theme: nil
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        }
    }
}

/// 表示の密度。各画面は `@Environment(\.density) private var density` で読み、余白や行の高さに掛ける
enum Density: String, CaseIterable, Identifiable {
    case relaxed, regular, compact
    var id: String { rawValue }
    static func from(_ raw: String) -> Density { Density(rawValue: raw) ?? .regular }

    var name: String {
        switch self {
        case .relaxed: "ゆったり"
        case .regular: "ふつう"
        case .compact: "コンパクト"
        }
    }

    /// 余白に掛ける倍率（ふつう＝1）
    var scale: CGFloat {
        switch self {
        case .relaxed: 1.2
        case .regular: 1.0
        case .compact: 0.78
        }
    }

    /// カードとカードの間隔
    var spacing: CGFloat {
        switch self {
        case .relaxed: 18
        case .regular: 14
        case .compact: 9
        }
    }

    /// 一覧の1行の上下の余白
    var rowPadding: CGFloat {
        switch self {
        case .relaxed: 16
        case .regular: 12
        case .compact: 8
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.default
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    /// 表示の密度（palette と一緒に渡るので、別に設定しなくてよい）
    var density: Density { palette.density }
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

    /// デザインのカード（全幅・角丸・やわらかい影。余白は表示の密度に合わせる）
    func paletteCard(_ p: Palette, padding: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: p.radius, style: .continuous)
        let shadow: Color = .black.opacity(p.scheme == .dark || p.outline != nil ? 0 : 0.06)
        let fill = shape.fill(p.card).shadow(color: shadow, radius: 12, y: 4)
        let border = shape.strokeBorder(p.outline ?? .clear, lineWidth: p.outline == nil ? 0 : 1.5)
        return self
            .padding((padding * p.density.scale).rounded())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(border)
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
