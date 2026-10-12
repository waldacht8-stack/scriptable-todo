import SwiftUI
import UIKit

// MARK: - アプリのアイコン
// 設定の「アプリのアイコン」。ホーム画面のアイコン「日の窓」の地の色を選べる。
// アイコンの絵は ios/Tools/MakeIcon.swift が描き（GitHub Actions）、ここの見本（HiyoriIconMark）も同じ絵を SwiftUI で描く
// （アプリに入れたほかのアイコンの画像は UIImage でうまく読めないため）。
// ほかのアイコンの名前は project.yml の ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES と合わせる。
// 起動引数（スクリーンショット用）：-settings -settingsSection icon

/// 選べるアイコン（並びは設定に出す順）
enum AppIconOption: String, CaseIterable, Identifiable {
    case w2 = "W2", w6 = "W6", w1 = "W1", w3 = "W3", w4 = "W4", w5 = "W5", w7 = "W7", w8 = "W8"

    var id: String { rawValue }

    /// ふだんのアイコン（AppIcon）
    static let primary: AppIconOption = .w2

    /// 設定に出す名前
    var label: String {
        switch self {
        case .w2: return "珊瑚"
        case .w6: return "生成り"
        case .w1: return "朱"
        case .w3: return "山吹"
        case .w4: return "若草"
        case .w5: return "抹茶"
        case .w7: return "白"
        case .w8: return "桜"
        }
    }

    /// setAlternateIconName に渡す名前（ふだんのアイコンは nil）
    var alternateName: String? {
        self == Self.primary ? nil : "AppIcon-\(rawValue)"
    }

    /// 地の色（0xRRGGBB）
    var ground: UInt32 {
        switch self {
        case .w2: return 0xF08A6A
        case .w6: return 0xF3EBCF
        case .w1: return 0xD9482B
        case .w3: return 0xF2B33D
        case .w4: return 0x8CBF6A
        case .w5: return 0x5E8B5A
        case .w7: return 0xFFFFFF
        case .w8: return 0xF2B8BE
        }
    }

    /// 鳥の色（抹茶の地では暗い色が沈むので生成りにする）
    var bird: UInt32 { self == .w5 ? 0xF3EBCF : 0x24345E }

    /// いまのアイコン名（UIApplication.alternateIconName）から選択肢へ。nil や知らない名前はふだんのアイコン
    static func from(alternateName: String?) -> AppIconOption {
        guard let alternateName else { return primary }
        return allCases.first { $0.alternateName == alternateName } ?? primary
    }
}

/// 「日の窓」の見本（MakeIcon.swift と同じ絵。180 四方の下書きを大きさに合わせて描き、角を丸める）
struct HiyoriIconMark: View {
    let option: AppIconOption

    private static func c(_ hex: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: a)
    }

    /// 波の上の縁（上・下・上・下にうねる）
    private static func crest(_ y: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 52, y: y))
        for i in 0..<4 {
            let x0: CGFloat = 52 + CGFloat(i) * 19
            let dy: CGFloat = i % 2 == 0 ? -8 : 8
            path.addQuadCurve(to: CGPoint(x: x0 + 19, y: y), control: CGPoint(x: x0 + 9.5, y: y + dy))
        }
        return path
    }

    private static func waveBody(_ y: CGFloat) -> Path {
        var path: Path = crest(y)
        path.addLine(to: CGPoint(x: 128, y: 150))
        path.addLine(to: CGPoint(x: 52, y: 150))
        path.closeSubpath()
        return path
    }

    private static func bird(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - w / 2))
        path.addQuadCurve(to: CGPoint(x: x + w * 2, y: y), control: CGPoint(x: x + w * 1.5, y: y - w / 2))
        return path
    }

    var body: some View {
        let ground: Color = Self.c(option.ground)
        let bird: Color = Self.c(option.bird)
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            Canvas { ctx, size in
                let k: CGFloat = min(size.width, size.height) / 180
                ctx.scaleBy(x: k, y: k)
                ctx.fill(Path(CGRect(x: 0, y: 0, width: 180, height: 180)), with: .color(ground))

                var inner: GraphicsContext = ctx
                inner.clip(to: Path(roundedRect: CGRect(x: 52, y: 30, width: 76, height: 120), cornerRadius: 18))
                // 空・太陽のぼんやりした光・太陽・鳥
                inner.fill(Path(CGRect(x: 52, y: 30, width: 76, height: 60)),
                           with: .linearGradient(Gradient(colors: [Self.c(0x7EC6F2), Self.c(0xCDEBFB)]),
                                                 startPoint: CGPoint(x: 90, y: 30), endPoint: CGPoint(x: 90, y: 90)))
                let sun = CGPoint(x: 108, y: 54)
                inner.fill(Path(ellipseIn: CGRect(x: sun.x - 24, y: sun.y - 24, width: 48, height: 48)),
                           with: .radialGradient(Gradient(colors: [Self.c(0xFFF1B8, 0.9), Self.c(0xFFF1B8, 0)]),
                                                 center: sun, startRadius: 0, endRadius: 24))
                inner.fill(Path(ellipseIn: CGRect(x: sun.x - 11, y: sun.y - 11, width: 22, height: 22)), with: .color(Self.c(0xFFC94D)))
                inner.stroke(Self.bird(64, 64, 8), with: .color(bird), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                inner.stroke(Self.bird(80, 75, 6), with: .color(bird), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                // 海と波
                inner.fill(Path(CGRect(x: 52, y: 90, width: 76, height: 60)),
                           with: .linearGradient(Gradient(colors: [Self.c(0x3F95CC), Self.c(0x1B5590)]),
                                                 startPoint: CGPoint(x: 90, y: 90), endPoint: CGPoint(x: 90, y: 150)))
                inner.fill(Self.waveBody(116), with: .color(Self.c(0x2C73AE)))
                inner.stroke(Self.crest(116), with: .color(Self.c(0xCDEBFB, 0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                inner.fill(Self.waveBody(134), with: .color(Self.c(0x1B5590)))
                inner.stroke(Self.crest(134), with: .color(Self.c(0xCDEBFB, 0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // 「日」の横線
                ctx.fill(Path(CGRect(x: 52, y: 84, width: 76, height: 12)), with: .color(ground))
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// 設定の「アプリのアイコン」の見出し（8つを並べ、押すとホーム画面のアイコンを変える）
struct AppIconSection: View {
    @Environment(\.palette) private var p
    @State private var current: AppIconOption = AppIconOption.from(alternateName: UIApplication.shared.alternateIconName)
    @State private var error: String? = nil
    @State private var busy: Bool = false

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        SettingsSection("アプリのアイコン", icon: "app.fill",
                        footer: "変えると、iPhone が「アイコンを変更しました」と知らせます。") {
            SettingsCard {
                LazyVGrid(columns: columns, spacing: 14 * p.density.scale) {
                    ForEach(AppIconOption.allCases) { option in
                        cell(option)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16 * p.density.scale)
                if let error {
                    RowDivider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(p.overdue)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
        .onAppear { current = AppIconOption.from(alternateName: UIApplication.shared.alternateIconName) }
    }

    private func cell(_ option: AppIconOption) -> some View {
        let selected: Bool = option == current
        return Button {
            choose(option)
        } label: {
            VStack(spacing: 6) {
                HiyoriIconMark(option: option)
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? p.accent : p.sub.opacity(0.25), lineWidth: selected ? 2.5 : 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(p.onAccent, p.accent)
                                .offset(x: 5, y: 5)
                        }
                    }
                Text(option.label)
                    .font(.caption.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? p.text : p.sub)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("アイコン \(option.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ option: AppIconOption) {
        guard option != current else { return }
        let app: UIApplication = UIApplication.shared
        guard app.supportsAlternateIcons else {
            error = "この iPhone ではアイコンを変えられません。"
            return
        }
        busy = true
        error = nil
        let name: String? = option.alternateName
        Task { @MainActor in
            do {
                try await app.setAlternateIconName(name)
                current = option
            } catch let e {
                error = "アイコンを変えられませんでした（\(e.localizedDescription)）"
            }
            busy = false
        }
    }
}
