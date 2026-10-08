import SwiftUI

/// 集中タブの入口（エージェント2が作り込む）
struct FocusTimerRootView: View {
    @Environment(\.palette) private var p
    var body: some View {
        Text("集中（準備中）").font(.title2.bold()).foregroundStyle(p.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity).paletteBackground(p)
    }
}
