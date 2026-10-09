import SwiftUI

// 画面写真用の起動引数
// -splatdemo：SplatoonHome を全画面で開く
// -splatcard：SplatoonEntryCard だけを並べた見本を全画面で開く（カードの見た目の確認用）
// RootView に `.splatoonDemoLaunch()` を1行足すと有効になる。

struct SplatoonDemoLaunch: ViewModifier {
    @State private var showHome = ProcessInfo.processInfo.arguments.contains("-splatdemo")
    @State private var showCard = ProcessInfo.processInfo.arguments.contains("-splatcard")

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showHome) {
                NavigationStack {
                    SplatoonHome()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("閉じる") { showHome = false }.foregroundStyle(SplatInk.lime)
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $showCard) {
                SplatoonCardPreview { showCard = false }
            }
    }
}

extension View {
    func splatoonDemoLaunch() -> some View { modifier(SplatoonDemoLaunch()) }
}

/// 入口のカードを、情報タブに置いたときのように見る
private struct SplatoonCardPreview: View {
    @Environment(\.palette) private var p
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("ゲーム").font(.title2.weight(.heavy)).foregroundStyle(p.text)
                    Spacer()
                    Button("閉じる", action: close).foregroundStyle(p.accent)
                }
                SplatoonEntryCard()
                SplatoonEntryCard().environment(\.dynamicTypeSize, .xLarge)
            }
            .padding(16)
        }
        .paletteBackground(p)
    }
}

#Preview("入口のカード") {
    SplatoonEntryCard().padding()
}
