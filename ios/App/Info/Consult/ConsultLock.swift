import LocalAuthentication
import SwiftUI

// MARK: - 相談の会話のロック（過去の会話は Face ID か iPhone のパスコードで開く）
// - 鍵をかけた時刻より前の会話を隠す。鍵をかけてから書いた会話はそのまま見える
// - 解除してから 5 分さわらなければ、また鍵をかける（アプリの外にいた時間も数える）
// - iPhone にパスコードがないときは守れないので、鍵をかけない。-demo でも鍵をかけない

@MainActor
final class ConsultLock: ObservableObject {
    static let shared = ConsultLock()
    static let timeout: TimeInterval = 5 * 60

    /// この時刻より前の会話を隠す（nil なら全部見える）
    @Published private(set) var hiddenBefore: Date?
    @Published private(set) var failed = false
    private var lastActive: Date?

    private init() {
        if !ProcessInfo.processInfo.arguments.contains("-demo") { lock() }
    }

    /// 端末のパスコードが設定されていて、鍵が使えるか
    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func isHidden(_ m: ConsultMessage) -> Bool {
        guard let h = hiddenBefore else { return false }
        return m.date < h
    }

    /// 操作したときに呼ぶ（5 分の数え直し）
    func touch(now: Date = .now) {
        if hiddenBefore == nil { lastActive = now }
    }

    /// 5 分たっていたら鍵をかける（画面を開いたとき・アプリに戻ったとき・時計で呼ぶ）
    func check(now: Date = .now) {
        guard hiddenBefore == nil, let last = lastActive, now.timeIntervalSince(last) >= Self.timeout else { return }
        lock(now: now)
    }

    func lock(now: Date = .now) {
        guard Self.available else { hiddenBefore = nil; lastActive = now; return }
        hiddenBefore = now
        lastActive = nil
    }

    func unlock() async {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "やめる"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "過去の相談を表示します")
            if ok {
                hiddenBefore = nil
                failed = false
                lastActive = .now
            }
        } catch let e as LAError where e.code == .userCancel || e.code == .appCancel || e.code == .systemCancel {
            failed = false
        } catch {
            failed = true
        }
    }
}

/// 隠している会話の代わりに出すカード
struct ConsultLockedCard: View {
    @ObservedObject var lock: ConsultLock
    let count: Int
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.title2).foregroundStyle(p.accent)
            Text("過去の会話 \(count)件 はロック中").font(.headline).foregroundStyle(p.text)
            Text("Face ID か iPhone のパスコードで表示します。")
                .font(.footnote).foregroundStyle(p.sub).multilineTextAlignment(.center)
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("表示する", systemImage: "faceid")
                    .font(.subheadline.weight(.bold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            if lock.failed {
                Text("確認できませんでした。もう一度試してください。")
                    .font(.footnote.weight(.semibold)).foregroundStyle(p.overdue)
            }
        }
        .frame(maxWidth: .infinity)
        .paletteCard(p)
        .accessibilityElement(children: .contain)
    }
}
