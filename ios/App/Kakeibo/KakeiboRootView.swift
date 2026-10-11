import SwiftUI

/// 「家計簿」タブ（リリース4で担当が作り込む）
struct KakeiboRootView: View {
    @Environment(\.palette) private var p

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("家計簿").font(.largeTitle.weight(.heavy)).foregroundStyle(p.text)
                    Spacer()
                    SettingsButton()
                }
                .padding(.horizontal, 20)
                Spacer()
                Text("準備中").foregroundStyle(p.sub)
                Spacer()
            }
            .paletteBackground(p)
        }
    }
}
