import SwiftUI

/// 画面構成の見本（ボタンの位置がわかる簡単な図）。色はいまの色合いに合わせる
struct LayoutThumb: View {
    let layout: TodayLayout
    @Environment(\.palette) private var p

    private var ink: Color { p.sub.opacity(0.35) }
    private var accent: Color { p.accent }
    private var paper: Color { p.card }
    private var back: Color { p.background.first ?? p.card }

    var body: some View {
        ZStack {
            back
            switch layout {
            case .focus: focus
            case .board: board
            case .thumb: week
            case .timeline: timeline
            case .kanban: kanban
            case .checklist: checklist
            }
        }
    }

    private var focus: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8).fill(paper).shadow(color: .black.opacity(0.12), radius: 1)
                        .frame(width: 70 - CGFloat(i) * 6, height: 56).offset(y: CGFloat(i) * 5).zIndex(Double(-i))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Circle().fill(accent).frame(width: 18, height: 18).padding(8)
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([p.overdue, accent, ink], id: \.self) { c in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 3, height: 8)
                    Capsule().fill(ink).frame(width: 24, height: 4)
                }
                RoundedRectangle(cornerRadius: 3).fill(paper).frame(height: 12)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Capsule().fill(paper).frame(height: 12)
                Circle().fill(accent).frame(width: 12, height: 12)
            }
        }
        .padding(10)
    }

    private var week: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3).fill(i == 0 ? accent : paper).frame(height: 16)
                    }
                }
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 5) {
                        Capsule().fill(accent.opacity(0.6)).frame(width: 14, height: 5)
                        Capsule().fill(ink).frame(height: 5)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            Circle().fill(accent).frame(width: 16, height: 16).padding(8)
        }
    }

    private var timeline: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(ink).frame(width: 2).padding(.leading, 31).padding(.vertical, 10)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    if i == 2 { Rectangle().fill(p.overdue).frame(height: 2).padding(.leading, 18) }
                    HStack(spacing: 5) {
                        Capsule().fill(ink).frame(width: 12, height: 3)
                        Circle().fill(i < 2 ? ink : accent).frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 3).fill(paper).frame(height: 12)
                    }
                }
            }
            .padding(10)
        }
    }

    /// かんばん：上に3つの見出し、手前の列と、のぞく次の列
    private var kanban: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Capsule().fill(accent).frame(height: 9)
                Capsule().fill(paper).frame(height: 9)
                Capsule().fill(paper).frame(height: 9)
            }
            HStack(alignment: .top, spacing: 5) {
                VStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(paper).frame(height: 15)
                            .overlay(alignment: .leading) {
                                Circle().stroke(accent, lineWidth: 1.5).frame(width: 6, height: 6).padding(.leading, 4)
                            }
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(height: 10)
                }
                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(paper.opacity(0.6)).frame(height: 15)
                    }
                }
                .frame(width: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private static let checklistWidths: [CGFloat] = [40, 30, 46, 26, 36]

    /// チェックリスト：紙に罫線と四角いチェック欄
    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                checklistLine(i)
                Rectangle().fill(ink.opacity(0.6)).frame(height: 0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .background(paper)
        .overlay(alignment: .leading) {
            Rectangle().fill(p.overdue.opacity(0.35)).frame(width: 1).padding(.leading, 19)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }

    private func checklistLine(_ i: Int) -> some View {
        let done: Bool = i == 1
        let box: Color = done ? accent : p.text.opacity(0.6)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(done ? accent : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(box, lineWidth: 1.2))
                .frame(width: 9, height: 9)
            Capsule().fill(done ? ink.opacity(0.5) : ink).frame(width: Self.checklistWidths[i], height: 4)
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .padding(.horizontal, 6)
    }
}
