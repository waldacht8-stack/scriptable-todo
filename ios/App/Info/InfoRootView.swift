import SwiftUI

/// 「情報」タブ：好きな話題の投稿・記事、ゲーム（スプラトゥーン3・Steam）、趣味の情報を集めて見る
struct InfoRootView: View {
    @Environment(\.palette) private var p

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("情報").font(.largeTitle.weight(.heavy)).foregroundStyle(p.text)
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
