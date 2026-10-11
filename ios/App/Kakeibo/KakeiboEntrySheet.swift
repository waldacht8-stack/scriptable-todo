import SwiftUI

/// 手入力のシート：支出／収入・大きなキーパッド・分類・日付・メモ・最近の記録をもう一度。
/// editing があればその1件を直す（Apple Pay で金額が届かなかった1件もここで金額を入れる）
struct KakeiboEntrySheet: View {
    @ObservedObject var store: KakeiboStore
    let editing: KakeiboEntry?
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.dismiss) private var dismiss

    @State private var kind: KakeiboKind = .expense
    @State private var digits = ""
    @State private var category = "食費"
    @State private var date = Date()
    @State private var memo = ""
    @State private var saved = 0
    @FocusState private var memoFocused: Bool

    private var amount: Int { Int(digits) ?? 0 }
    private var categories: [String] {
        let all: [String] = store.settings.categories
        if kind == .income {
            let first: [String] = all.filter { $0 == "収入" || $0 == "その他" }
            let rest: [String] = all.filter { $0 != "収入" && $0 != "その他" }
            return first + rest
        }
        return all.filter { $0 != "収入" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                amountDisplay
                if editing == nil && kind == .expense && !store.recentTemplates.isEmpty { recents }
                categoryChips
                dateAndMemo
                keypad
                KakeiboPrimaryButton(title: editing == nil ? "記録する" : "保存する", enabled: amount > 0) { save() }
                if let editing {
                    Button(role: .destructive) {
                        store.delete([editing.id])
                        dismiss()
                    } label: {
                        Text("この記録を消す").font(.subheadline.weight(.bold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(p.overdue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .paletteBackground(p)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: saved)
        .onAppear(perform: load)
    }

    private func load() {
        guard let e = editing else {
            category = categories.first ?? "食費"
            return
        }
        kind = e.kind
        digits = e.amount > 0 ? String(e.amount) : ""
        category = e.category
        date = e.date
        memo = e.memo
    }

    // MARK: 上の切り替え

    private var topBar: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(KakeiboKind.allCases) { k in
                    Button {
                        withAnimation(motion.tap) {
                            kind = k
                            if !categories.contains(category) { category = categories.first ?? category }
                        }
                    } label: {
                        Text(k.name)
                            .font(.subheadline.weight(kind == k ? .heavy : .medium))
                            .foregroundStyle(kind == k ? p.text : p.sub)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(kind == k ? p.card : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .frame(width: 180)
            .background(p.sub.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer()
            KakeiboCloseButton { dismiss() }
        }
    }

    // MARK: 金額

    private var amountDisplay: some View {
        let shown: String = digits.isEmpty ? "0" : KakeiboFormat.yen(amount)
        let color: Color = digits.isEmpty ? p.sub.opacity(0.5) : p.text
        return HStack(alignment: .lastTextBaseline) {
            Text(editing?.isPending == true ? "金額（届かなかった分）" : "金額")
                .font(.footnote.weight(.bold)).foregroundStyle(p.sub)
            Spacer()
            Text(shown)
                .font(.system(size: 52, weight: .heavy, design: p.fontDesign))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.5)
            Rectangle().fill(p.accent).frame(width: 3, height: 40)
            Text("円").font(.title3.weight(.bold)).foregroundStyle(p.text)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(p.sub.opacity(0.25)).frame(height: 2) }
        .animation(motion.tap, value: digits)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("金額 \(shown) 円")
    }

    // MARK: 最近の記録をもう一度

    private var recents: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近の記録をもう一度").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(store.recentTemplates) { t in
                        Button { repeatEntry(t) } label: { recentChip(t) }.buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func recentChip(_ t: KakeiboEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise").font(.caption.weight(.heavy)).foregroundStyle(p.accent)
            Text("\(t.memo) \(KakeiboFormat.yen(t.amount))円").font(.footnote.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(p.card, in: Capsule())
        .overlay(Capsule().strokeBorder(p.sub.opacity(0.25), lineWidth: 1.5))
    }

    private func repeatEntry(_ t: KakeiboEntry) {
        withAnimation(motion.tap) {
            kind = .expense
            digits = String(t.amount)
            memo = t.memo
            if store.settings.categories.contains(t.category) { category = t.category }
        }
    }

    // MARK: 分類

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("分類").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            KakeiboFlowLayout(spacing: 6) {
                ForEach(categories, id: \.self) { c in
                    Button { withAnimation(motion.tap) { category = c } } label: { chip(c) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == c ? .isSelected : [])
                }
            }
        }
    }

    private func chip(_ c: String) -> some View {
        let on = category == c
        return Text(c)
            .font(.subheadline.weight(on ? .heavy : .bold))
            .foregroundStyle(on ? p.onAccent : p.text)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(on ? p.accent : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : p.sub.opacity(0.3), lineWidth: 1.5))
    }

    // MARK: 日付・メモ

    private var dateAndMemo: some View {
        HStack(spacing: 8) {
            DatePicker("日付", selection: $date, in: ...Date().addingTimeInterval(86_400 * 31), displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .tint(p.accent)
            TextField("メモ（なくても大丈夫）", text: $memo)
                .focused($memoFocused)
                .font(.subheadline)
                .foregroundStyle(p.text)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(p.sub.opacity(0.25), lineWidth: 1.5))
                .submitLabel(.done)
        }
    }

    // MARK: キーパッド

    private var keypad: some View {
        let keys: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "⌫"]
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: { keyLabel(k) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(k == "⌫" ? "1文字消す" : k)
            }
        }
    }

    private func keyLabel(_ k: String) -> some View {
        let special = k == "00" || k == "⌫"
        let bg: Color = special ? p.accent.opacity(0.14) : p.card
        return Group {
            if k == "⌫" {
                Image(systemName: "delete.left").font(.title2.weight(.semibold))
            } else {
                Text(k).font(.system(size: k == "00" ? 22 : 24, weight: .bold, design: p.fontDesign))
            }
        }
        .foregroundStyle(p.text)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private func press(_ k: String) {
        memoFocused = false
        switch k {
        case "⌫":
            if !digits.isEmpty { digits.removeLast() }
        default:
            guard digits.count + k.count <= 9 else { return }
            if digits.isEmpty && k.hasPrefix("0") { return }
            digits += k
        }
    }

    private func save() {
        guard amount > 0 else { return }
        let text = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if var e = editing {
            let old = e
            e.kind = kind
            e.amount = amount
            e.category = category
            e.date = date
            e.memo = text
            store.save(e, learnFrom: old)
        } else {
            let e = KakeiboEntry(date: date, amount: amount, kind: kind, category: category, memo: text, source: .manual,
                                 dedupeKey: KakeiboDedupe.key(date: date, amount: amount, kind: kind, text: text))
            store.add(e)
        }
        saved += 1
        dismiss()
    }
}

/// 折り返して並べる（分類のチップ）
struct KakeiboFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
