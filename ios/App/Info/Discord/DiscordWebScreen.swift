import SwiftUI
import UIKit

/// 「情報」→ ゲームの欄に置く、Web版 Discord（試作）への入口
struct DiscordEntryCard: View {
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                Text("日和の中で Discord を開いてボイスに参加できるか試す")
                    .font(.caption)
                    .foregroundStyle(p.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(p.sub)
        }
        .paletteCard(p, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Image(systemName: "headphones")
            .font(.title3.weight(.bold))
            .foregroundStyle(p.onAccent)
            .frame(width: 40, height: 40)
            .background(p.accent, in: shape)
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text("Discord（Web版・試作）")
                .font(.headline.weight(.heavy))
                .foregroundStyle(p.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            DiscordBadge()
        }
    }
}

/// 小さな「試作」の札
struct DiscordBadge: View {
    @Environment(\.palette) private var p

    var body: some View {
        let label = Text("試作")
            .font(.caption2.weight(.bold))
            .foregroundStyle(p.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        label.overlay(Capsule().stroke(p.accent, lineWidth: 1))
    }
}

// MARK: - 全画面：Web版 Discord

struct DiscordWebScreen: View {
    let onClose: () -> Void
    @Environment(\.palette) private var p
    @AppStorage("discordWeb.desktop") private var desktop = true
    @AppStorage("discordWeb.zoom") private var zoom = 1.0
    @StateObject private var web: DiscordWebController
    @State private var showNotice = true
    @State private var audio = DiscordAudioSession()
    /// ボットの画面（お知らせ・募集。DiscordHome）をシートで開く
    @State private var showBot = false
    @Environment(\.motion) private var motion

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let d = UserDefaults.standard
        let desktop: Bool = d.object(forKey: "discordWeb.desktop") as? Bool ?? true
        let saved: Double = d.object(forKey: "discordWeb.zoom") as? Double ?? 1.0
        let demo: Bool = ProcessInfo.processInfo.arguments.contains("-demo")
        _web = StateObject(wrappedValue: DiscordWebController(desktop: desktop, zoom: CGFloat(saved), isDemo: demo))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if showNotice { notice }
            if web.micDenied { micNotice }
            DiscordWebView(controller: web)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .paletteBackground(p)
        .onAppear { if !web.isDemo { audio.begin() } }
        .onDisappear { audio.end() }
        .sheet(isPresented: $showBot) {
            NavigationStack {
                DiscordHome()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showBot = false }.fontWeight(.semibold)
                        }
                    }
            }
            .environment(\.palette, p)
            .environment(\.motion, motion)
        }
    }

    // 閉じる・題名・読み込み中・Discord アプリで開く
    private var topBar: some View {
        HStack(spacing: 10) {
            Button("閉じる") { close() }
                .font(.body.weight(.semibold))
                .foregroundStyle(p.accent)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Text("Discord").font(.headline).foregroundStyle(p.text)
                DiscordBadge()
                if web.isLoading { ProgressView().controlSize(.small) }
            }
            Spacer(minLength: 4)
            Button("ボット") { showBot = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(p.accent)
                .accessibilityLabel("ボットの画面（お知らせ・募集）を開く")
            Button { openInApp() } label: {
                Image(systemName: "arrow.up.forward.app").font(.title3)
            }
            .foregroundStyle(p.accent)
            .accessibilityLabel("Discord アプリで開く")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "testtube.2").foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("これは試作です。").font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                Text("画面を閉じたりアプリを切り替えると通話が切れることがあります。")
                Text("パスワードは Discord のページに直接入力され、日和には保存されません。")
            }
            .font(.caption)
            .foregroundStyle(p.sub)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { withAnimation { showNotice = false } } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(p.sub)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("お知らせを閉じる")
        }
        .paletteCard(p, padding: 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var micNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash").foregroundStyle(p.overdue)
            Text("マイクが許可されていません。設定アプリの「日和」でマイクをオンにしてください。")
                .font(.caption).foregroundStyle(p.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("設定") { openSettings() }
                .font(.caption.weight(.bold)).foregroundStyle(p.accent)
        }
        .paletteCard(p, padding: 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // 戻る・進む・再読み込み・拡大縮小・PC 表示
    private var bottomBar: some View {
        HStack(spacing: 4) {
            barButton("chevron.backward", "戻る", enabled: web.canGoBack) { web.goBack() }
            barButton("chevron.forward", "進む", enabled: web.canGoForward) { web.goForward() }
            barButton("arrow.clockwise", "再読み込み", enabled: true) { web.reload() }
            barButton("bubble.left.and.bubble.right", "DM", enabled: true) { web.openDMs() }
            Spacer(minLength: 2)
            zoomControl
            Spacer(minLength: 2)
            desktopToggle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(p.card.opacity(0.95))
    }

    private func barButton(_ symbol: String, _ label: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        let color: Color = enabled ? p.accent : p.sub.opacity(0.4)
        return Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(color)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var zoomControl: some View {
        let steps = DiscordWebController.zoomSteps
        let index: Int = steps.firstIndex { abs(Double($0) - zoom) < 0.01 } ?? 5
        let percent = Int((zoom * 100).rounded())
        return HStack(spacing: 0) {
            barButton("minus", "縮小", enabled: index > 0) { setZoom(steps[max(index - 1, 0)]) }
            Text("\(percent)%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(p.text)
                .frame(minWidth: 40)
            barButton("plus", "拡大", enabled: index < steps.count - 1) { setZoom(steps[min(index + 1, steps.count - 1)]) }
        }
    }

    private var desktopToggle: some View {
        let fg: Color = desktop ? p.onAccent : p.accent
        let bg: Color = desktop ? p.accent : Color.clear
        return Button {
            desktop.toggle()
            web.setDesktop(desktop)
        } label: {
            Label("PC表示", systemImage: "desktopcomputer")
                .font(.caption.weight(.bold))
                .foregroundStyle(fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(bg, in: Capsule())
                .overlay(Capsule().stroke(p.accent, lineWidth: 1))
        }
        .accessibilityLabel("PC 表示")
        .accessibilityValue(desktop ? "オン" : "オフ")
    }

    private func setZoom(_ z: CGFloat) {
        zoom = Double(z)
        web.setZoom(z)
    }

    private func close() {
        web.stop()
        audio.end()
        onClose()
    }

    private func openInApp() {
        UIApplication.shared.open(DiscordWebController.startURL)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
