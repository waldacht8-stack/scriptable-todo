import SwiftUI

/// 画面構成の見本（ボタンの位置がわかる簡単な図）
struct LayoutThumb: View {
    let layout: TodayLayout
    private let ink = Color.secondary.opacity(0.35)
    private let accent = Color.accentColor

    var body: some View {
        ZStack {
            Color(.tertiarySystemGroupedBackground)
            switch layout {
            case .focus:
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)).shadow(radius: 1)
                                .frame(width: 70 - CGFloat(i) * 6, height: 56).offset(y: CGFloat(i) * 5).zIndex(Double(-i))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Circle().fill(accent).frame(width: 18, height: 18).padding(8)
                }
            case .board:
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([Color.red, accent, ink], id: \.self) { c in
                        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 3, height: 8); Capsule().fill(ink).frame(width: 24, height: 4) }
                        RoundedRectangle(cornerRadius: 3).fill(Color(.systemBackground)).frame(height: 12)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) { Capsule().fill(Color(.systemBackground)).frame(height: 12); Circle().fill(accent).frame(width: 12, height: 12) }
                }
                .padding(10)
            case .thumb:
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 6) {
                        HStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(i == 0 ? accent : Color(.systemBackground)).frame(height: 16) }
                        }
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(spacing: 5) { Capsule().fill(accent.opacity(0.6)).frame(width: 14, height: 5); Capsule().fill(ink).frame(height: 5) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    Circle().fill(accent).frame(width: 16, height: 16).padding(8)
                }
            case .timeline:
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(ink).frame(width: 2).padding(.leading, 31).padding(.vertical, 10)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            if i == 2 { Rectangle().fill(Color.red).frame(height: 2).padding(.leading, 18) }
                            HStack(spacing: 5) {
                                Capsule().fill(ink).frame(width: 12, height: 3)
                                Circle().fill(i < 2 ? ink : accent).frame(width: 8, height: 8)
                                RoundedRectangle(cornerRadius: 3).fill(Color(.systemBackground)).frame(height: 12)
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private var tileShape: some View { RoundedRectangle(cornerRadius: 5).fill(Color(.systemBackground)).frame(height: 24) }
}
