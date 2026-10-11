import SwiftUI

/// Apple Pay の自動記録の設定案内：① オートメーションを作る → ② 日和に送る → ③ テストで確かめる
struct KakeiboApplePayGuide: View {
    @ObservedObject var store: KakeiboStore
    let startPage: Int
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var page = 0
    @State private var test: KakeiboEntry?
    @State private var started = false

    private static let labels = ["① 作る", "② 送る", "③ 確かめる"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Apple Pay を自動で記録").font(.title3.weight(.heavy)).foregroundStyle(p.text)
                Spacer()
                KakeiboCloseButton { dismiss() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            KakeiboProgress(labels: Self.labels, current: page)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch page {
                    case 0: makePage
                    case 1: sendPage
                    default: checkPage
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .id(page)
                .transition(motion.appear)
            }
            .scrollIndicators(.hidden)
            .animation(motion.change, value: page)
            bottomBar
        }
        .paletteBackground(p)
        .onAppear {
            guard !started else { return }
            started = true
            page = startPage
            if startPage == 2 { sendTest() }
        }
    }

    // MARK: ① 作る

    private var makePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ウォレットのカードで払うたびに、「ショートカット」アプリが金額・お店・カードを日和に送ります。iOS 17 以上で使えます")
                .font(.subheadline).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                guideRow(1, "「ショートカット」アプリを開き、下の「オートメーション」→ 右上の「＋」", icon: "square.stack.3d.up")
                divider
                guideRow(2, "一覧から「取引」を選ぶ", icon: "creditcard")
                divider
                guideRow(3, "記録したいカードを選び、「すぐに実行」を選んで「次へ」", icon: "bolt.fill", unverified: true)
            }
            .paletteCard(p, padding: 14)
        }
    }

    // MARK: ② 送る

    private var sendPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                guideRow(4, "「新規の空のオートメーション」→ アクションの検索で「日和」と入れる", icon: "magnifyingglass", unverified: true)
                divider
                VStack(alignment: .leading, spacing: 8) {
                    guideRow(5, "「日和に支出を記録」を選び、金額・お店・カードの欄に「ショートカットの入力」を入れる", icon: "arrow.right.circle")
                    actionPreview.padding(.leading, 34)
                }
                divider
                guideRow(6, "右上の「完了」", icon: "checkmark")
            }
            .paletteCard(p, padding: 14)
            Label("日和が受け取るのは、金額・お店の名前・カードの名前だけです", systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日和に支出を記録").font(.footnote.weight(.heavy)).foregroundStyle(p.text)
            tokenRow("金額", "取引 › 金額")
            tokenRow("お店", "取引 › 加盟店")
            tokenRow("カード", "取引 › カード")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.sub.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tokenRow(_ label: String, _ token: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(p.text).frame(width: 44, alignment: .leading)
            Text(token).font(.caption.weight(.bold)).foregroundStyle(Color.blue)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: ③ 確かめる

    private var checkPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = test {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell.badge.fill").font(.title3).foregroundStyle(p.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("テストの1件が届きました").font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                        Text("\(t.memo) ・ \(KakeiboFormat.yen(t.amount)) 円").font(.footnote).foregroundStyle(p.sub)
                    }
                }
                .paletteCard(p, padding: 14)
                Text("届いた中身").font(.title3.weight(.heavy)).foregroundStyle(p.text).padding(.top, 4)
                VStack(spacing: 0) {
                    receivedRow("金額", "\(KakeiboFormat.yen(t.amount)) 円", ok: t.amount > 0)
                    divider
                    receivedRow("お店", t.memo, ok: !t.memo.isEmpty)
                    divider
                    receivedRow("カード", t.card ?? "（なし）", ok: t.card != nil)
                    divider
                    receivedRow("分類", "お店の名前から自動で決めます（今回は「\(t.category)」）", ok: nil)
                }
                .paletteCard(p, padding: 14)
                Text("家計簿の一覧には「テスト」の印つきで入ります。合計には入りません")
                    .font(.caption).foregroundStyle(p.sub)
            } else {
                Text("「テストで1件送る」を押すと、ショートカットと同じ道で1件を記録します")
                    .font(.subheadline).foregroundStyle(p.sub)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("金額が届かないとき").font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                Text("カードや支払い方（iD・QUICPay など）によっては、金額やお店が空で届くことがあります。そのときは「金額の入力待ち」に入り、通知から日和を開いて金額だけ入れられます")
                    .font(.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func receivedRow(_ label: String, _ value: String, ok: Bool?) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.subheadline).foregroundStyle(p.sub).frame(width: 56, alignment: .leading)
            Text(value).font(.subheadline.weight(ok == nil ? .semibold : .heavy)).foregroundStyle(ok == nil ? p.sub : p.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let ok {
                Image(systemName: ok ? "checkmark" : "minus").font(.subheadline.weight(.heavy))
                    .foregroundStyle(ok ? KakeiboStyle.color("収入") : p.sub)
                    .accessibilityLabel(ok ? "届いた" : "届かなかった")
            }
        }
        .frame(minHeight: 48)
    }

    // MARK: 部品

    private var divider: some View { Divider().overlay(p.sub.opacity(0.2)) }

    private func guideRow(_ n: Int, _ text: String, icon: String, unverified: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            KakeiboStepNumber(n: n)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.subheadline.weight(.medium)).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
                if unverified { KakeiboUnverified() }
            }
            Spacer(minLength: 4)
            Image(systemName: icon).font(.title3).foregroundStyle(p.accent.opacity(0.7)).frame(width: 28)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 6) {
            switch page {
            case 0:
                KakeiboPrimaryButton(title: "できた ・ 次へ") { go(1) }
                linkButton("「ショートカット」アプリを開く ›") {
                    if let u = URL(string: "shortcuts://") { openURL(u) }
                }
            case 1:
                KakeiboPrimaryButton(title: "テストで1件送る", systemImage: "paperplane.fill") {
                    sendTest()
                    go(2)
                }
                linkButton("あとで設定する") { dismiss() }
            default:
                KakeiboPrimaryButton(title: "設定を終える") { dismiss() }
                HStack {
                    linkButton("もう一度テストで送る") { sendTest() }
                    linkButton("テストの1件を消す") {
                        store.deleteTests()
                        test = nil
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.bold)).foregroundStyle(p.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func go(_ n: Int) { withAnimation(motion.change) { page = n } }

    /// ショートカットの App Intent と同じ処理で、テストの1件を記録する
    private func sendTest() {
        let r = KakeiboRecorder.recordPayment(amountText: "100", merchant: "テスト用のお店", card: "テスト用のカード", isTest: true)
        store.reload()
        withAnimation(motion.change) {
            test = r.entry ?? store.entries.first { $0.isTest == true }
        }
    }
}
