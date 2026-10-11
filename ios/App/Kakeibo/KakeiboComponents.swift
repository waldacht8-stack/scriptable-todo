import SwiftUI
import SafariServices

// MARK: - 色

enum KakeiboStyle {
    private static func c(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    private static let fixed: [String: UInt32] = [
        "食費": 0xD2643A, "日用品": 0xE39B3C, "交通": 0x4E8C8A, "娯楽": 0x9A6BC9, "ゲーム": 0x5A7FD8,
        "サブスク": 0xC0598A, "住まい": 0x8A735A, "光熱": 0xCBA92E, "通信": 0x3D98D2, "医療": 0x5CA56A,
        "服": 0xD6849A, "交際": 0xB8862B, "その他": 0x9C9384, "収入": 0x3D9A5B,
    ]
    private static let extra: [UInt32] = [0x6E8B3D, 0xB5603F, 0x4A6FA5, 0xA05C7B, 0x7C7A3A, 0x3F8F7F]

    /// 分類の色（決まった分類は固定、足した分類は名前から決める）
    static func color(_ category: String) -> Color {
        if let v = fixed[category] { return c(v) }
        let h = category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return c(extra[h % extra.count])
    }

    /// 札の色（背景・文字）
    static func tag(_ e: KakeiboEntry, _ p: Palette) -> (bg: Color, fg: Color) {
        switch e.source {
        case .applePay: return (p.text, p.card)
        case .manual: return (p.accent.opacity(0.16), p.text)
        default:
            switch e.institutionValue {
            case .juroku: return (c(0x2F8A4A).opacity(0.18), p.text)
            case .jcb: return (c(0x2A63C9).opacity(0.18), p.text)
            case .mufg: return (c(0xD0343A).opacity(0.16), p.text)
            default: return (p.sub.opacity(0.16), p.text)
            }
        }
    }

    static func monthTitle(_ d: Date) -> String {
        let cal = Calendar.current
        return "\(cal.component(.year, from: d))年\(cal.component(.month, from: d))月"
    }

    static func dayLabel(_ d: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "今日 " + JP.time(d) }
        if cal.isDateInYesterday(d) { return "昨日" }
        return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日"
    }
}

// MARK: - 小さな部品

/// 出どころの札（十六銀行 / JCB / MUFG / Apple Pay / 手入力）
struct KakeiboSourceTag: View {
    let entry: KakeiboEntry
    @Environment(\.palette) private var p

    var body: some View {
        let colors = KakeiboStyle.tag(entry, p)
        Text(entry.sourceTag)
            .font(.caption2.weight(.bold))
            .foregroundStyle(colors.fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(colors.bg, in: Capsule())
    }
}

/// 大きな金額（世界観の BigCount と同じ大きさ・字詰め・色。桁区切りつき）
struct KakeiboBigYen: View {
    @Environment(\.palette) private var p
    let value: Int

    var body: some View {
        let size: CGFloat = min(p.world.bigNumberSize, 56)
        let color: Color = p.world.bigNumberAccent ? p.accent : p.text
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(KakeiboFormat.yen(value))
                .font(.system(size: size, weight: .heavy, design: p.fontDesign))
                .tracking(p.world.bigNumberTracking)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("円").font(.title3.weight(.bold)).foregroundStyle(p.sub)
        }
    }
}

/// 予算の残りの棒
struct KakeiboBudgetBar: View {
    let summary: KakeiboSummary
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion

    var body: some View {
        let over = summary.isOver
        let fill: Color = over ? p.overdue : p.accent
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w: CGFloat = geo.size.width * CGFloat(summary.progress)
                ZStack(alignment: .leading) {
                    Capsule().fill(p.accent.opacity(0.15))
                    Capsule().fill(fill).frame(width: max(summary.spent > 0 ? 12 : 0, w))
                }
            }
            .frame(height: 12)
            .animation(motion.change, value: summary.progress)
            HStack {
                Text(over ? "予算を \(KakeiboFormat.yen(-summary.remaining)) 円こえています" : "残り \(KakeiboFormat.yen(summary.remaining)) 円")
                    .foregroundStyle(over ? p.overdue : p.accent)
                Spacer(minLength: 8)
                Text(budgetNote).foregroundStyle(p.sub)
            }
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var budgetNote: String {
        let base = "予算 \(KakeiboFormat.yen(summary.budget)) 円"
        return summary.daysLeft > 0 ? base + " ・ あと \(summary.daysLeft) 日" : base
    }
}

/// 手順の番号
struct KakeiboStepNumber: View {
    let n: Int
    @Environment(\.palette) private var p

    var body: some View {
        Text("\(n)").font(.caption.weight(.heavy)).foregroundStyle(p.onAccent)
            .frame(width: 24, height: 24)
            .background(p.accent, in: Circle())
    }
}

/// 進み具合の棒（取り込み 4 段・Apple Pay 3 段）
struct KakeiboProgress: View {
    let labels: [String]
    let current: Int
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(labels.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(i <= current ? p.accent : p.sub.opacity(0.22)).frame(height: 6)
                    Text(labels[i]).font(.caption2.weight(.bold))
                        .foregroundStyle(i == current ? p.accent : p.sub)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(motion.change, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(labels.count) 段のうち \(current + 1) 段め：\(labels[min(current, labels.count - 1)])")
    }
}

/// 主なボタン（全幅の丸いボタン）
struct KakeiboPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var enabled: Bool = true
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.body.weight(.heavy))
            .foregroundStyle(p.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(p.accent.opacity(enabled ? 1 : 0.4), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 閉じるボタン（丸）
struct KakeiboCloseButton: View {
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.body.weight(.bold)).foregroundStyle(p.text)
                .frame(width: 44, height: 44)
                .background(p.sub.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("閉じる")
    }
}

/// 確認していないボタン名などに添える小さな注意
struct KakeiboUnverified: View {
    @Environment(\.palette) private var p
    var body: some View {
        Text("（ボタン名は実機で確認）").font(.caption2).foregroundStyle(p.sub)
    }
}

// MARK: - アプリ内のブラウザ（SFSafariViewController）

struct KakeiboSafariTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct KakeiboSafariView: UIViewControllerRepresentable {
    let url: URL
    let tint: Color

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(tint)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
