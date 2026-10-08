import SwiftUI

/// 習慣タブの入口（エージェント2が作り込む）
struct HabitRootView: View {
    @Environment(\.palette) private var p
    var body: some View {
        Text("習慣（準備中）").font(.title2.bold()).foregroundStyle(p.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity).paletteBackground(p)
    }
}
