import AVFoundation
import SwiftUI
import UIKit
import WebKit

/// Web版 Discord（試作）を開くためのただのブラウザ。
/// ページに台本（スクリプト）を差し込まない・クッキーやトークンを読まない。ログインは Discord のページに直接入力する。
/// 画面を出している間はこのオブジェクトが WKWebView を持ち続ける（通話をなるべく切らないため）。
@MainActor
final class DiscordWebController: NSObject, ObservableObject {
    static let startURL = URL(string: "https://discord.com/app")!
    /// PC 表示のときに名乗るブラウザ（Mac の Safari）。スマホの Safari だと「アプリをダウンロード」に回されることがある
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    static let zoomSteps: [CGFloat] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

    let webView: WKWebView
    let isDemo: Bool
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published var micDenied = false
    private var observations: [NSKeyValueObservation] = []

    init(desktop: Bool, zoom: CGFloat, isDemo: Bool) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()          // ログインを次に開いたときも残す
        config.ignoresViewportScaleLimits = true      // ページが拡大を止めていても、指で拡大できるように
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.customUserAgent = desktop ? Self.desktopUserAgent : nil
        web.pageZoom = zoom
        self.webView = web
        self.isDemo = isDemo
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        let back = web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] w, _ in
            let v = w.canGoBack
            Task { @MainActor in self?.canGoBack = v }
        }
        let forward = web.observe(\.canGoForward, options: [.initial, .new]) { [weak self] w, _ in
            let v = w.canGoForward
            Task { @MainActor in self?.canGoForward = v }
        }
        let loading = web.observe(\.isLoading, options: [.initial, .new]) { [weak self] w, _ in
            let v = w.isLoading
            Task { @MainActor in self?.isLoading = v }
        }
        observations = [back, forward, loading]
        loadStart()
    }

    func loadStart() {
        if isDemo {
            webView.loadHTMLString(Self.demoHTML, baseURL: nil)
        } else {
            webView.load(URLRequest(url: Self.startURL))
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        if webView.url == nil || isDemo { loadStart() } else { webView.reload() }
    }

    func setDesktop(_ on: Bool) {
        webView.customUserAgent = on ? Self.desktopUserAgent : nil
        reload()
    }

    func setZoom(_ zoom: CGFloat) {
        webView.pageZoom = zoom
    }

    func stop() {
        webView.stopLoading()
    }

    /// discord.com とその下のドメインだけ
    nonisolated static func isDiscord(host: String) -> Bool {
        let h = host.lowercased()
        return h == "discord.com" || h.hasSuffix(".discord.com")
    }

    private static let demoHTML = """
    <!doctype html><html lang="ja"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
    font-family:-apple-system,sans-serif;background:#313338;color:#F2F3F5;text-align:center}
    .box{padding:24px} h1{font-size:22px;margin:0 0 10px} p{font-size:15px;color:#B5BAC1;margin:0}
    </style></head><body><div class="box">
    <h1>Web版 Discord（試作）— 実機で開きます</h1>
    <p>見本の画面です。ネットにはつないでいません。</p>
    </div></body></html>
    """
}

// MARK: - 読み込み

extension DiscordWebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow); return
        }
        let inside: Set<String> = ["http", "https", "about", "blob", "data"]
        if inside.contains(scheme) {
            decisionHandler(.allow)
            return
        }
        // discord:// などはこの中では開けない。押されたときだけ端末に任せる
        if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}

// MARK: - 新しい窓・マイク

extension DiscordWebController: WKUIDelegate {
    /// target=_blank や window.open は、同じ画面で開く（新しい窓は作らない）
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }

    /// マイクは discord.com のページにだけ許す。カメラは使わない（許可の説明文を持っていないため）
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let isMic: Bool = type == .microphone
        guard isMic, origin.protocol == "https", Self.isDiscord(host: origin.host) else {
            decisionHandler(.deny)
            return
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            decisionHandler(.grant)
        case .denied:
            micDenied = true
            decisionHandler(.deny)
        default:
            AVAudioApplication.requestRecordPermission { ok in
                Task { @MainActor in
                    self.micDenied = !ok
                    decisionHandler(ok ? .grant : .deny)
                }
            }
        }
    }
}

// MARK: - SwiftUI に置く

struct DiscordWebView: UIViewRepresentable {
    let controller: DiscordWebController

    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 音声：通話向けにして、閉じたら元に戻す

@MainActor
final class DiscordAudioSession {
    private var saved: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var savedIdle = false

    func begin() {
        guard saved == nil else { return }
        let s = AVAudioSession.sharedInstance()
        saved = (s.category, s.mode, s.categoryOptions)
        let options: AVAudioSession.CategoryOptions = [.allowBluetooth, .defaultToSpeaker]
        do {
            try s.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try s.setActive(true)
        } catch {
            print("DiscordAudioSession begin:", error)
        }
        // 画面が自動で消えると通話が止まりやすいので、開いている間は消さない
        savedIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func end() {
        guard let old = saved else { return }
        saved = nil
        let (category, mode, options) = old
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setActive(false, options: .notifyOthersOnDeactivation)
            try s.setCategory(category, mode: mode, options: options)
        } catch {
            print("DiscordAudioSession end:", error)
        }
        UIApplication.shared.isIdleTimerDisabled = savedIdle
    }
}
