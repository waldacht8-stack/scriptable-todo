import SwiftUI
import SafariServices
#if canImport(Translation)
import Translation
#endif

// MARK: - 話題の色（利用者が話題ごとに選ぶ目印。0 はデザインの強調色）

enum InfoTopicColor {
    static let count = 7

    static func color(_ index: Int, _ p: Palette) -> Color {
        switch index {
        case 1: .blue
        case 2: .orange
        case 3: .green
        case 4: .pink
        case 5: .purple
        case 6: .teal
        default: p.accent
        }
    }
}

// MARK: - アプリ内のブラウザ（SFSafariViewController）

/// 開くもの（記事、または X の検索など）
struct InfoOpenTarget: Identifiable {
    let id = UUID()
    let url: URL
    let article: InfoArticle?
}

struct InfoSafariView: UIViewControllerRepresentable {
    let url: URL
    let tint: Color
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(tint)
        vc.dismissButtonStyle = .close
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDone() }
    }
}

// MARK: - 小さな部品

/// 上部の切り替え（話題 / ゲーム）。3つめの項目を足せる形にしてある
enum InfoSection: String, CaseIterable, Identifiable {
    case topics, games, consult
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topics: "話題"
        case .games: "ゲーム"
        case .consult: "相談"
        }
    }
}

struct InfoSegmented: View {
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space
    @Binding var selection: InfoSection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InfoSection.allCases) { s in
                Button {
                    withAnimation(reduceMotion ? nil : motion.tap) { selection = s }
                } label: {
                    segmentLabel(s)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(p.card, in: Capsule())
    }

    private func segmentLabel(_ s: InfoSection) -> some View {
        let on: Bool = selection == s
        let text: Text = Text(s.title).font(Font.subheadline.weight(.bold))
        return text
            .foregroundStyle(on ? p.onAccent : p.sub)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background {
                if on { Capsule().fill(p.accent).matchedGeometryEffect(id: "infoSegment", in: space) }
            }
    }
}

/// 丸いアイコンのボタン（歯車と同じ大きさ）
struct InfoRoundIcon: View {
    @Environment(\.palette) private var p
    let symbol: String

    var body: some View {
        Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(p.text)
            .frame(width: 44, height: 44)
            .background(p.card, in: Circle())
    }
}

/// 絞り込みのチップ
struct InfoChip: View {
    @Environment(\.palette) private var p
    let title: String
    var symbol: String? = nil
    var dot: Color? = nil
    var count: Int? = nil
    let selected: Bool
    var ns: Namespace.ID? = nil      // 選択の背景を動かす（matchedGeometryEffect）

    var body: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            if let symbol { Image(systemName: symbol).font(.caption.weight(.bold)) }
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let count, count > 0 {
                Text("\(count)").font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(selected ? p.onAccent.opacity(0.85) : p.sub)
            }
        }
        .foregroundStyle(selected ? p.onAccent : p.text)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background { chipBackground }
    }

    @ViewBuilder
    private var chipBackground: some View {
        ZStack {
            Capsule().fill(p.card)
            if selected {
                if let ns {
                    Capsule().fill(p.accent).matchedGeometryEffect(id: "infoChipSelection", in: ns)
                } else {
                    Capsule().fill(p.accent)
                }
            }
        }
    }
}

/// 「翻訳済み」の印
struct InfoTranslatedBadge: View {
    @Environment(\.palette) private var p

    var body: some View {
        Label("翻訳済み", systemImage: "character.bubble")
            .font(.caption2.weight(.bold))
            .foregroundStyle(p.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(p.accent.opacity(0.12), in: Capsule())
    }
}

/// 記事の画像（無いときは話題の色と元のアイコン）
struct InfoThumb: View {
    let article: InfoArticle
    let tint: Color
    var symbolSize: CGFloat = 34

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: InfoSource(rawValue: article.source)?.symbol ?? "flame")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(tint.opacity(0.75))
            if let s = article.image, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .clipped()
    }
}

/// 「Google ニュース・3分前」
struct InfoMeta: View {
    @Environment(\.palette) private var p
    let article: InfoArticle

    private var line: String {
        var parts: [String] = []
        if !article.isPost { parts.append(article.site ?? article.sourceName) }
        let ago = InfoText.ago(article.published)
        if !ago.isEmpty { parts.append(ago) }
        return parts.joined(separator: "・")
    }

    var body: some View {
        Text(line)
            .font(.caption.weight(.medium))
            .foregroundStyle(p.sub)
            .lineLimit(1)
    }
}

// MARK: - 翻訳（端末の翻訳機能。iOS 18 以降）

extension View {
    @ViewBuilder
    func infoTranslation(_ model: InfoModel) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            self.modifier(InfoTranslateModifier(model: model))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct InfoTranslateModifier: ViewModifier {
    @ObservedObject var model: InfoModel
    @State private var config: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(config) { session in
                await translate(session)
            }
            .onChange(of: model.translateRequest, initial: true) { _, _ in
                start()
            }
    }

    private func start() {
        guard !model.isDemo, !model.pendingTranslations.isEmpty else { return }
        if config == nil {
            config = TranslationSession.Configuration(source: Locale.Language(identifier: "en"),
                                                      target: Locale.Language(identifier: "ja"))
        } else {
            config?.invalidate()
        }
    }

    private func translate(_ session: TranslationSession) async {
        let items = model.pendingTranslations
        guard !items.isEmpty else { return }
        let requests = items.map { TranslationSession.Request(sourceText: $0.title, clientIdentifier: $0.id) }
        do {
            let responses = try await session.translations(from: requests)
            var out: [String: String] = [:]
            for r in responses {
                if let id = r.clientIdentifier { out[id] = r.targetText }
            }
            model.applyTranslations(out)
            model.translationUnavailable = false
        } catch {
            model.translationUnavailable = true
        }
    }
}
#endif
