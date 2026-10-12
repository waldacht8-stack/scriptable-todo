import SwiftUI
import UniformTypeIdentifiers

/// 取り込みの始め方
enum KakeiboImportStart {
    case fresh                          // ① から
    case file(name: String, data: Data) // 共有で受け取った（③ から）
    case demo(String)                   // 画面写真用（source / pick / mapping / preview / done / help / jcb / mufg）
}

/// 明細の取り込み：① 選ぶ → ② ファイル → ③ 確認 → ④ 完了
struct KakeiboImportView: View {
    @ObservedObject var store: KakeiboStore
    let start: KakeiboImportStart
    let onManual: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var institution: KakeiboInstitution = .juroku
    @State private var fileName = ""
    @State private var fileData: Data?
    @State private var table: KakeiboTable?
    @State private var mapping = KakeiboColumnMapping()
    @State private var needsMapping = false
    @State private var drafts: [KakeiboDraft] = []
    @State private var isPDF = false
    @State private var usedOCR = false
    @State private var hasBalance = false
    @State private var loading = false
    @State private var errorText: String?
    @State private var excludeTransfers = true
    @State private var result: KakeiboStore.ImportResult?
    @State private var showPicker = false
    @State private var showHelp = false
    @State private var safari: KakeiboSafariTarget?
    @State private var editingDraft: KakeiboDraft?
    @State private var touched: Set<UUID> = []
    @State private var started = false
    @State private var undone = false

    private static let labels = ["① 選ぶ", "② ファイル", "③ 確認", "④ 完了"]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            KakeiboProgress(labels: Self.labels, current: step)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    stepContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .id(step)
                .transition(motion.appear)
            }
            .scrollIndicators(.hidden)
            .animation(motion.change, value: step)
            bottomBar
        }
        .paletteBackground(p)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.commaSeparatedText, .pdf, .plainText]) { r in
            picked(r)
        }
        .sheet(item: $safari) { t in
            KakeiboSafariView(url: t.url, tint: p.accent).ignoresSafeArea()
        }
        .sheet(isPresented: $showHelp) {
            KakeiboImportHelp(institution: institution, onSample: {
                showHelp = false
                Task { await loadSample() }
            }, onManual: {
                showHelp = false
                onManual()
            })
            .environment(\.palette, p)
        }
        .sheet(item: $editingDraft) { d in
            KakeiboDraftEditor(draft: d) { updated in replaceDraft(updated) }
                .environment(\.palette, p)
        }
        .interactiveDismissDisabled(step == 2 && !drafts.isEmpty)
        .task {
            guard !started else { return }
            started = true
            excludeTransfers = store.settings.excludeTransfers
            await begin()
        }
    }

    // MARK: 上

    private var topBar: some View {
        HStack {
            Text("明細を取り込む").font(.title3.weight(.heavy)).foregroundStyle(p.text)
            Spacer()
            Button("うまくいかないとき") { showHelp = true }
                .font(.footnote.weight(.bold)).foregroundStyle(p.accent)
            KakeiboCloseButton { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: chooseStep
        case 1: pickStep
        case 2: confirmStep
        default: doneStep
        }
    }

    // MARK: 下のボタン

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 6) {
            switch step {
            case 0:
                KakeiboPrimaryButton(title: "保存できた ・ 次へ ›") { go(1) }
            case 1:
                KakeiboPrimaryButton(title: "ファイルを選ぶ", systemImage: "folder") { showPicker = true }
                secondary("見本のファイルで試してみる") { Task { await loadSample() } }
            case 2:
                if needsMapping {
                    KakeiboPrimaryButton(title: "この対応で読む", enabled: mapping.isUsable) { confirmMapping() }
                } else {
                    KakeiboPrimaryButton(title: "\(includeCount)件を取り込む", enabled: includeCount > 0 && !loading) { commit() }
                }
                secondary("ファイルを選び直す") { go(1) }
            default:
                KakeiboPrimaryButton(title: "家計簿を見る") { dismiss() }
                if result != nil {
                    secondary("今回の取り込みを取り消す") { undo() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.bold))
            .foregroundStyle(p.accent)
            .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var includeCount: Int { drafts.filter(\.include).count }

    private func go(_ s: Int) {
        withAnimation(motion.change) { step = s }
    }

    // MARK: ① 選ぶ

    private var chooseStep: some View {
        let guide = KakeiboGuide.of(institution)
        return VStack(alignment: .leading, spacing: 12) {
            Text("どこの明細？").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
            institutionPicker
            VStack(alignment: .leading, spacing: 10) {
                Text(guide.title).font(.headline.weight(.heavy)).foregroundStyle(p.text)
                Text(guide.intro).font(.subheadline).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, s in
                    stepRow(i + 1, s)
                }
                if let alt = guide.alternative {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(alt, systemImage: "doc.richtext").font(.footnote).foregroundStyle(p.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if guide.alternativeUnverified { KakeiboUnverified().padding(.leading, 28) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if let url = guide.url { siteButtons(guide.siteTitle, url) }
            }
            .paletteCard(p, padding: 16)
        }
    }

    private var institutionPicker: some View {
        HStack(spacing: 6) {
            ForEach(KakeiboInstitution.allCases) { i in
                let on = institution == i
                Button { withAnimation(motion.tap) { institution = i } } label: {
                    Text(i.name)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(on ? p.onAccent : p.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? p.accent : p.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : p.sub.opacity(0.25), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func stepRow(_ n: Int, _ s: KakeiboGuide.Step) -> some View {
        HStack(alignment: .top, spacing: 10) {
            KakeiboStepNumber(n: n)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.text).font(.subheadline.weight(.medium)).foregroundStyle(p.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = s.note {
                    Text(note).font(.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                }
                if s.unverified { KakeiboUnverified() }
            }
        }
    }

    private func siteButtons(_ title: String, _ url: URL) -> some View {
        VStack(spacing: 4) {
            Button { safari = KakeiboSafariTarget(url: url) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                    Text(title)
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(p.accent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .overlay(Capsule().strokeBorder(p.accent, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            Link(destination: url) {
                Text("アプリ内でログインできないときは Safari で開く ›").font(.caption.weight(.bold)).foregroundStyle(p.sub)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
        .padding(.top, 4)
    }

    // MARK: ② ファイル

    private var pickStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("保存した CSV か PDF を選ぶ").font(.headline.weight(.heavy)).foregroundStyle(p.text)
                Text("下のボタンで「ファイル」が開きます。\(institution == .other ? "" : institution.name + "の")明細を選んでください")
                    .font(.subheadline).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    fileBadge("CSV", "tablecells")
                    fileBadge("PDF", "doc.richtext")
                }
            }
            .paletteCard(p, padding: 16)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "square.and.arrow.up").foregroundStyle(p.accent)
                Text("Safari や「ファイル」でファイルを開いたまま、共有のメニューから「日和」を選んでも取り込めます。そのときは、この画面をとばして ③ に進みます")
                    .font(.footnote).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if loading { ProgressView("読んでいます…").tint(p.accent).frame(maxWidth: .infinity) }
            if let errorText { errorBox(errorText) }
        }
    }

    private func fileBadge(_ name: String, _ icon: String) -> some View {
        Label(name, systemImage: icon).font(.footnote.weight(.heavy)).foregroundStyle(p.text)
            .padding(.horizontal, 12).frame(height: 32)
            .background(p.sub.opacity(0.12), in: Capsule())
    }

    private func errorBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(p.overdue)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.footnote.weight(.semibold)).foregroundStyle(p.text).fixedSize(horizontal: false, vertical: true)
                Button("うまくいかないとき ›") { showHelp = true }.font(.footnote.weight(.bold)).foregroundStyle(p.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.overdue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: ③ 確認

    @ViewBuilder private var confirmStep: some View {
        if loading {
            ProgressView("読んでいます…").tint(p.accent).frame(maxWidth: .infinity, minHeight: 200)
        } else if needsMapping, let table {
            KakeiboMappingView(table: table, mapping: $mapping, institution: institution)
        } else {
            previewHeader
            if let errorText { errorBox(errorText) }
            if !drafts.isEmpty { previewRows }
        }
    }

    private var previewHeader: some View {
        let dupes = drafts.filter { $0.flag == .duplicate }.count
        let settlements = drafts.filter { $0.flag == .cardSettlement }.count
        let transfers = drafts.filter { $0.flag == .ownTransfer }.count
        let salaries = drafts.filter { $0.salary && $0.include }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(isPDF ? "PDF" : "CSV") から \(drafts.count)件 読みました")
                    .font(.headline.weight(.heavy)).foregroundStyle(p.text)
                Spacer(minLength: 4)
                Text(rangeText).font(.caption.weight(.bold)).foregroundStyle(p.sub)
            }
            sourceMenu
            if dupes > 0 {
                Text("すでに記録してある \(dupes)件は飛ばします（ほかの明細と同じ取引を含む）").font(.footnote.weight(.semibold)).foregroundStyle(p.sub)
            }
            if salaries > 0 {
                Label("給料 \(salaries)件を見つけました", systemImage: "yensign.circle.fill")
                    .font(.footnote.weight(.bold)).foregroundStyle(KakeiboStyle.color(KakeiboCategories.salary))
            }
            if settlements + transfers > 0 {
                Toggle(isOn: $excludeTransfers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("カードの引き落とし・振替を合計に入れない").font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                        Text("2回数えないため ・ \(settlements + transfers)件（行をタップすると入れられます）").font(.caption).foregroundStyle(p.sub)
                    }
                }
                .tint(p.accent)
                .onChange(of: excludeTransfers) { _, v in applyTransferToggle(v) }
            }
            if store.missingCardStatement(drafts) {
                Label("カードの明細がまだ取り込まれていません。引き落としは合計に入れないので、カードの明細も取り込むと使い道がわかります", systemImage: "creditcard")
                    .font(.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            }
            if usedOCR {
                Label("文字として読めない PDF（Safari で印刷した明細など）だったので、画像から文字を読み取りました。まちがいが出やすいので、よく見てください", systemImage: "text.viewfinder")
                    .font(.footnote).foregroundStyle(p.overdue).fixedSize(horizontal: false, vertical: true)
            }
        }
        .paletteCard(p, padding: 16)
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(KakeiboInstitution.allCases) { i in
                Button(i.name) { changeInstitution(i) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("どこの明細：\(institution.name)")
                Image(systemName: "chevron.down").font(.caption2.weight(.heavy))
            }
            .font(.footnote.weight(.bold)).foregroundStyle(p.accent)
        }
    }

    private var rangeText: String {
        let dates = drafts.map(\.date)
        guard let a = dates.min(), let b = dates.max() else { return "" }
        let cal = Calendar.current
        return "\(cal.component(.month, from: a))/\(cal.component(.day, from: a)) 〜 \(cal.component(.month, from: b))/\(cal.component(.day, from: b))"
    }

    private var previewRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { i, d in
                    KakeiboDraftRow(draft: d, categories: store.categoryChoices(for: d.kind),
                                    onToggle: { toggleDraft(d.id) },
                                    onCategory: { setCategory(d.id, $0) },
                                    onEdit: { editingDraft = d })
                    if i < drafts.count - 1 { Divider().overlay(p.sub.opacity(0.2)) }
                }
            }
            .paletteCard(p, padding: 12)
            Text("読み違いがあれば、行をタップして直せます。分類は取引先から自動で決めます。直すと、次から同じお店はその分類にします。外した行は左の丸をタップすると入れられます")
                .font(.caption).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            if hasBalance {
                Label("残高の数字で、読み取りが合っているか確かめています", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(p.sub)
            }
        }
    }

    // MARK: ④ 完了

    @ViewBuilder private var doneStep: some View {
        if let r = result {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(p.accent)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(r.added)").font(.system(size: 52, weight: .heavy, design: p.fontDesign)).foregroundStyle(p.text)
                    Text("件 取り込みました").font(.title3.weight(.heavy)).foregroundStyle(p.text)
                }
                Text("\(institution.name) ・ \(periodText(r)) の明細").font(.subheadline).foregroundStyle(p.sub)
                VStack(spacing: 0) {
                    countRow("取り込んだ", r.added)
                    Divider().overlay(p.sub.opacity(0.2))
                    countRow("すでにあったので飛ばした", r.duplicates)
                    Divider().overlay(p.sub.opacity(0.2))
                    countRow("合計に入れない記録（カードの引き落とし・振替）", r.excluded)
                    if r.overlapsHidden > 0 {
                        Divider().overlay(p.sub.opacity(0.2))
                        countRow("JCB と重なるので合計から外した銀行の引落", r.overlapsHidden)
                    }
                }
                .paletteCard(p, padding: 14)
                Text("取り込んだファイルは日和の中に残しません。来月も同じ手順で取り込めます。期間が重なっても、すでにある明細は自動で飛ばします")
                    .font(.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            }
        } else if undone {
            Text("今回の取り込みを取り消しました").font(.headline).foregroundStyle(p.text)
        }
    }

    private func countRow(_ label: String, _ n: Int) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(p.text)
            Spacer()
            Text("\(n)件").font(.subheadline.weight(.heavy)).foregroundStyle(p.text).monospacedDigit()
        }
        .frame(minHeight: 44)
    }

    private func periodText(_ r: KakeiboStore.ImportResult) -> String {
        guard let a = r.from, let b = r.to else { return "" }
        let cal = Calendar.current
        return "\(cal.component(.month, from: a))月\(cal.component(.day, from: a))日 〜 \(cal.component(.month, from: b))月\(cal.component(.day, from: b))日"
    }

    // MARK: 読み込み

    private func begin() async {
        switch start {
        case .fresh:
            break
        case .file(let name, let data):
            step = 2
            await load(name: name, data: data, detect: true)
        case .demo(let s):
            switch s {
            case "pick": step = 1
            case "jcb": institution = .jcb
            case "mufg": institution = .mufg
            case "help":
                // 取り込みのシートが出きってから重ねる
                try? await Task.sleep(nanoseconds: 900_000_000)
                showHelp = true
            case "mapping", "preview": await loadSample()
            case "done":
                await loadSample()
                commit()
            default: break
            }
        }
    }

    private func loadSample() async {
        institution = .juroku
        let data = Data(KakeiboDemo.sampleCSV().utf8)
        step = 2
        await load(name: "見本_入出金明細.csv", data: data, detect: false)
    }

    private func picked(_ r: Result<URL, Error>) {
        guard case .success(let url) = r else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorText = "ファイルを開けませんでした。「ファイル」アプリでいったん「このiPhone内」に保存してから選んでください"
            return
        }
        let name = url.lastPathComponent
        Task {
            go(2)
            await load(name: name, data: data, detect: false)
        }
    }

    private func load(name: String, data: Data, detect: Bool) async {
        loading = true
        errorText = nil
        drafts = []
        table = nil
        needsMapping = false
        usedOCR = false
        fileName = name
        fileData = data
        isPDF = name.lowercased().hasSuffix(".pdf") || data.starts(with: Array("%PDF".utf8))
        defer { loading = false }
        if isPDF {
            // 三菱UFJ（MUFG カード）の明細は、1ページ目が宛名と請求額の表紙なので読まない
            let skipFirst: Bool = institution == .mufg
            var text = KakeiboPDF.text(from: data, skipFirstPage: skipFirst)
            // Safari で印刷した PDF などは、取り出した文字が化けている。そのときも画像から読む
            if let t = text, KakeiboPDF.isGarbled(t) { text = nil }
            // 文字で読めたら、まずその行を試す
            if let t = text {
                if detect, let i = KakeiboDetect.institution(t) { institution = i }
                let parsed = KakeiboPDF.drafts(text: t, isCard: institution.isCard)
                if !parsed.rows.isEmpty {
                    hasBalance = parsed.hasBalance
                    drafts = store.prepare(parsed.rows, institution: institution, isCard: institution.isCard, excludeTransfers: excludeTransfers)
                    return
                }
            }
            // 文字が無い・化けた・行が見つからない：画像から読む（化けたと見分けられない PDF もあるので、行が無ければ必ず試す）
            let pages = await KakeiboPDF.recognizeBoxes(data, skipFirstPage: skipFirst)
            let ocrText = KakeiboOCRTable.text(pages: pages)
            guard !ocrText.isEmpty else {
                errorText = text == nil
                    ? "文字が読めない PDF です。明細の画面から PDF を出し直すか、CSV を選んでください"
                    : "日付と金額の行が見つかりませんでした。CSV があれば CSV を選んでください"
                return
            }
            usedOCR = true
            if detect, let i = KakeiboDetect.institution(ocrText) { institution = i }
            // 見出しの位置で列に分ける（ウェブの明細を印刷したもの）
            if let ocr = KakeiboOCRTable.build(pages: pages) {
                table = ocr.table
                if ocr.table.headerFound && ocr.mapping.isUsable {
                    mapping = ocr.mapping
                    buildDrafts()
                    if !drafts.isEmpty { return }
                    errorText = nil
                }
            }
            let parsed = KakeiboPDF.drafts(text: ocrText, isCard: institution.isCard)
            hasBalance = parsed.hasBalance
            var rows = parsed.rows
            for i in rows.indices { rows[i].suspect = true }
            if rows.isEmpty, let t = table {
                // 画像から読んだ表：列の対応を選んでもらう
                mapping = t.headerFound ? mapping : KakeiboColumnMapping()
                needsMapping = true
                errorText = nil
                return
            }
            table = nil
            if rows.isEmpty { errorText = "日付と金額の行が見つかりませんでした。CSV があれば CSV を選んでください" }
            drafts = store.prepare(rows, institution: institution, isCard: institution.isCard, excludeTransfers: excludeTransfers)
        } else {
            guard let text = KakeiboCSV.decode(data), let t = KakeiboCSV.table(text) else {
                errorText = "CSV を読めませんでした。明細のサイトから CSV を保存し直してください"
                return
            }
            if detect, let i = KakeiboDetect.institution(t.preamble + " " + t.headers.joined(separator: " ") + " " + name) { institution = i }
            table = t
            if let saved = store.settings.mappings[institution.rawValue], saved.fits(t.headers) {
                mapping = saved
                buildDrafts()
            } else {
                // 初めての形式：列の対応を選んでもらう（見出しから決めた候補を先に入れておく）
                mapping = t.headerFound ? KakeiboCSV.autoMapping(t.headers) : KakeiboColumnMapping()
                needsMapping = true
            }
        }
    }

    private var csvIsCard: Bool {
        if institution == .jcb { return true }
        guard institution == .other, mapping.withdrawal == nil, mapping.deposit == nil, let a = mapping.amount else { return false }
        return a.contains("利用") || a.contains("支払")
    }

    private func buildDrafts() {
        guard let table else { return }
        var rows = KakeiboCSV.drafts(table, mapping: mapping, isCard: csvIsCard)
        hasBalance = mapping.balance != nil
        if usedOCR {
            // 画像から読んだ行：残高の検算が合わなかった行（残高が読めない行も）はよく見てもらう
            for i in rows.indices where !hasBalance || rows[i].balance == nil { rows[i].suspect = true }
        }
        drafts = store.prepare(rows, institution: institution, isCard: csvIsCard, excludeTransfers: excludeTransfers)
        errorText = rows.isEmpty ? "日付と金額の行が見つかりませんでした。列の対応を選び直してください" : nil
    }

    private func confirmMapping() {
        let inst = institution
        let m = mapping
        store.updateSettings { $0.mappings[inst.rawValue] = m }
        needsMapping = false
        buildDrafts()
    }

    private func changeInstitution(_ i: KakeiboInstitution) {
        guard i != institution, let data = fileData else { return }
        institution = i
        let name = fileName
        Task { await load(name: name, data: data, detect: false) }
    }

    // MARK: 行の操作

    private func toggleDraft(_ id: UUID) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(motion.tap) { drafts[i].include.toggle() }
    }

    private func setCategory(_ id: UUID, _ c: String) {
        guard let i = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[i].category = c
        drafts[i].salary = c == KakeiboCategories.salary
        touched.insert(id)
        let text = drafts[i].text
        if !text.isEmpty {
            store.learn(text, category: c)
            // 覚えた決まりで、まだ直していない行の分類を選び直す
            for j in drafts.indices where !touched.contains(drafts[j].id) {
                let r = store.classify(drafts[j].text, kind: drafts[j].kind)
                drafts[j].category = r.category
                drafts[j].salary = r.salary
            }
        }
    }

    private func replaceDraft(_ d: KakeiboDraft) {
        guard let i = drafts.firstIndex(where: { $0.id == d.id }) else { return }
        var x = d
        x.suspect = false
        // 支出か収入か・内容を直したら、分類も選び直す（手で直した分類はそのまま）
        if (x.kind != drafts[i].kind || x.text != drafts[i].text) && !touched.contains(x.id) {
            let r = store.classify(x.text, kind: x.kind)
            x.category = r.category
            x.salary = r.salary
        }
        drafts[i] = x
    }

    private func applyTransferToggle(_ exclude: Bool) {
        store.updateSettings { $0.excludeTransfers = exclude }
        withAnimation(motion.change) {
            for i in drafts.indices where drafts[i].flag == .cardSettlement || drafts[i].flag == .ownTransfer { drafts[i].include = !exclude }
        }
    }

    private func commit() {
        let card = isPDF ? institution.isCard : csvIsCard
        let source: KakeiboSource = isPDF ? (card ? .cardPDF : .bankPDF) : (card ? .cardCSV : .bankCSV)
        result = store.commit(drafts, institution: institution, source: source)
        undone = false
        go(3)
    }

    private func undo() {
        guard let r = result else { return }
        store.undo(batch: r.batch)
        result = nil
        undone = true
        dismiss()
    }
}

// MARK: - 確認の1行

struct KakeiboDraftRow: View {
    let draft: KakeiboDraft
    let categories: [String]
    let onToggle: () -> Void
    let onCategory: (String) -> Void
    let onEdit: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        let cal = Calendar.current
        let date: String = "\(cal.component(.month, from: draft.date))/\(cal.component(.day, from: draft.date))"
        let sign: String = draft.kind == .expense ? "−" : "+"
        let amountColor: Color = draft.kind == .income ? KakeiboStyle.color("収入") : p.text
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(draft.include ? p.accent : p.sub.opacity(0.6))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.include ? "取り込む" : "取り込まない")
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onEdit) {
                    HStack(spacing: 8) {
                        Text(date).font(.footnote.weight(.bold)).foregroundStyle(p.sub).monospacedDigit().frame(width: 40, alignment: .leading)
                        Text(draft.text.isEmpty ? "（内容なし）" : draft.text)
                            .font(.subheadline.weight(.bold)).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(sign)\(KakeiboFormat.yen(draft.amount))")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(amountColor).monospacedDigit()
                            .strikethrough(!draft.include)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    if let flag = draft.flag, !draft.include {
                        // 外した理由。タップで入れ直す
                        Button(action: onToggle) {
                            Text(flag.label + " ・ 入れる").font(.caption2.weight(.heavy)).foregroundStyle(p.sub)
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(p.sub.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(flag.label)。タップで取り込む")
                    } else {
                        if draft.salary {
                            Text("給料").font(.caption2.weight(.heavy)).foregroundStyle(p.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(KakeiboStyle.color(KakeiboCategories.salary), in: Capsule())
                        }
                        Text("分類").font(.caption).foregroundStyle(p.sub)
                        categoryMenu
                    }
                    if draft.suspect {
                        Label("読み取りが怪しい", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold)).foregroundStyle(p.overdue)
                    }
                }
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 8)
        .opacity(draft.include ? 1 : 0.6)
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(categories, id: \.self) { c in
                Button(c) { onCategory(c) }
            }
        } label: {
            HStack(spacing: 3) {
                Circle().fill(KakeiboStyle.color(draft.category)).frame(width: 8, height: 8)
                Text(draft.category)
                Image(systemName: "chevron.down").font(.caption2.weight(.heavy))
            }
            .font(.caption.weight(.heavy)).foregroundStyle(p.text)
            .padding(.horizontal, 8).frame(height: 26)
            .background(p.sub.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel("分類の候補 \(draft.category)")
    }
}

// MARK: - 読み取った行を直す

struct KakeiboDraftEditor: View {
    @State var draft: KakeiboDraft
    let onSave: (KakeiboDraft) -> Void
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("支出か収入か", selection: $draft.kind) {
                        ForEach(KakeiboKind.allCases) { k in Text(k.name).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("日付", selection: $draft.date, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    TextField("摘要・お店", text: $draft.text)
                    HStack {
                        TextField("金額", text: $amountText).keyboardType(.numberPad)
                        Text("円").foregroundStyle(p.sub)
                    }
                }
                .listRowBackground(p.card)
                if draft.suspect {
                    Section {
                        Text("残高の数字と合いませんでした。明細を見ながら、日付・金額・支出か収入かを確かめてください")
                            .font(.footnote).foregroundStyle(p.sub)
                    }
                    .listRowBackground(p.card)
                }
            }
            .scrollContentBackground(.hidden)
            .paletteBackground(p)
            .navigationTitle("読み取った行を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("直す") {
                        var d = draft
                        d.amount = KakeiboAmountParser.parse(amountText).map { abs($0) } ?? d.amount
                        onSave(d)
                        dismiss()
                    }
                }
            }
            .onAppear { amountText = String(draft.amount) }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 列の対応（初めての形式のとき）

struct KakeiboMappingView: View {
    let table: KakeiboTable
    @Binding var mapping: KakeiboColumnMapping
    let institution: KakeiboInstitution
    @Environment(\.palette) private var p

    private struct Role: Identifiable {
        let id: String
        let label: String
        let key: WritableKeyPath<KakeiboColumnMapping, String?>
    }

    private let roles: [Role] = [
        Role(id: "date", label: "この列が日付", key: \.date),
        Role(id: "text", label: "この列が内容（摘要・お店）", key: \.text),
        Role(id: "withdrawal", label: "この列が出金（お引出し）", key: \.withdrawal),
        Role(id: "deposit", label: "この列が入金（お預入れ）", key: \.deposit),
        Role(id: "amount", label: "この列が金額（1列のとき）", key: \.amount),
        Role(id: "balance", label: "この列が残高（検算だけ）", key: \.balance),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("列を合わせる").font(.headline.weight(.heavy)).foregroundStyle(p.text)
                Text("\(institution.name)の明細を読むのは初めてなので、どの列が何かを選んでください。次からは覚えておきます")
                    .font(.subheadline).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                if !table.headerFound {
                    Text("見出しの行が見つからなかったので「列1」「列2」…と呼んでいます")
                        .font(.caption).foregroundStyle(p.overdue)
                }
            }
            .paletteCard(p, padding: 16)
            VStack(spacing: 0) {
                ForEach(Array(roles.enumerated()), id: \.element.id) { i, r in
                    roleRow(r)
                    if i < roles.count - 1 { Divider().overlay(p.sub.opacity(0.2)) }
                }
            }
            .paletteCard(p, padding: 12)
            if !mapping.isUsable {
                Text("日付と、金額か出金・入金のどれかが必要です").font(.footnote.weight(.bold)).foregroundStyle(p.overdue)
            }
            samplePreview
        }
    }

    private func roleRow(_ r: Role) -> some View {
        let current: String? = mapping[keyPath: r.key]
        let sample: String = current.flatMap { table.column($0) }.map { table.sample($0) } ?? ""
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.subheadline.weight(.bold)).foregroundStyle(p.text)
                if !sample.isEmpty {
                    Text("例：\(sample)").font(.caption).foregroundStyle(p.sub).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("使わない") { mapping[keyPath: r.key] = nil }
                ForEach(table.headers.indices, id: \.self) { c in
                    Button("\(table.headers[c])（\(table.sample(c).prefix(10))）") { mapping[keyPath: r.key] = table.headers[c] }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(current ?? "使わない").lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.heavy))
                }
                .font(.footnote.weight(.heavy))
                .foregroundStyle(current == nil ? p.sub : p.accent)
                .padding(.horizontal, 10).frame(height: 32)
                .background(p.sub.opacity(0.12), in: Capsule())
            }
        }
        .frame(minHeight: 52)
    }

    private var samplePreview: some View {
        let rows = Array(table.rows.prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            Text("ファイルの始めの行").font(.caption.weight(.bold)).foregroundStyle(p.sub)
            Text(table.headers.joined(separator: " ｜ ")).font(.caption2.weight(.bold)).foregroundStyle(p.text).lineLimit(2)
            ForEach(rows.indices, id: \.self) { i in
                Text(rows[i].joined(separator: " ｜ ")).font(.caption2).foregroundStyle(p.sub).lineLimit(2)
            }
        }
        .paletteCard(p, padding: 12)
    }
}

// MARK: - うまくいかないとき

struct KakeiboImportHelp: View {
    let institution: KakeiboInstitution
    let onSample: () -> Void
    let onManual: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        var id: String { q }
        let q: String
        let a: String
    }

    private var items: [Item] {
        [
            Item(q: "「文字が読めない PDF です」と出る",
                 a: "画面を写真のように取り込んだ PDF（スキャンや画面写真）は、文字として読めません。日和が画像から文字を読み取ってみますが、まちがいが出やすいので ③ でよく見てください。できれば明細の画面から PDF を出し直すか、CSV を選んでください"),
            Item(q: "ほしい月が入っていない",
                 a: "十六銀行は最初に最近30日分だけが出ます。前の月は「更に過去の明細へ」で期間を選び直してから保存してください。通帳ありの口座は24か月前まで、通帳なしの口座は120か月前までです。MyJCB は確定した明細だけで、15か月前までです"),
            Item(q: "金額や日付を読みまちがえている",
                 a: "残高の数字が合わない行には「読み取りが怪しい」の印が付きます。行をタップすると、日付・内容・金額・支出か収入かを直せます"),
            Item(q: "サイトにログインできない",
                 a: "アプリ内のブラウザでログインやワンタイムパスワードが通らないときは「Safari で開く」を使ってください。保存したファイルは、共有のメニューから「日和」を選べば取り込めます"),
            Item(q: "CSV の文字化け・列がずれる",
                 a: "UTF-8 と Shift_JIS のどちらでも読めます。列の対応がずれたときは「家計簿の設定」の「列の対応」で忘れさせると、次の取り込みで選び直せます"),
            Item(q: "同じ明細を2回取り込んだ",
                 a: "金額が同じで内容が似ている行は、日付が1日ずれていても自動で飛ばします。銀行の明細にあるカードの引き落としは、カードの明細で1件ずつ数えるので合計に入れません"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.q).font(.subheadline.weight(.heavy)).foregroundStyle(p.text)
                            Text(item.a).font(.footnote).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                        }
                        .paletteCard(p, padding: 14)
                    }
                    KakeiboPrimaryButton(title: "見本のファイルで試してみる", systemImage: "doc.text") { onSample() }
                        .padding(.top, 6)
                    Button("ここから手入力で記録する") { onManual() }
                        .font(.subheadline.weight(.bold)).foregroundStyle(p.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(16)
            }
            .paletteBackground(p)
            .navigationTitle("うまくいかないとき")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }
}

// MARK: - 銀行・カードごとの手順

struct KakeiboGuide {
    struct Step {
        var text: String
        var note: String? = nil
        var unverified: Bool = false
    }

    var title: String
    var intro: String
    var steps: [Step]
    var alternative: String? = nil
    var alternativeUnverified: Bool = false
    var siteTitle: String = ""
    var url: URL? = nil

    static func of(_ i: KakeiboInstitution) -> KakeiboGuide {
        switch i {
        case .juroku:
            return KakeiboGuide(
                title: "十六銀行で明細を保存する",
                intro: "じゅうろくダイレクト（インターネットバンキング）を使います。お金はかかりません。さかのぼれるのは通帳ありの口座で24か月、通帳なしの口座で120か月です",
                steps: [
                    Step(text: "下のボタンでサイトを開き、ログイン"),
                    Step(text: "口座を選んで「入出金明細」を開く"),
                    Step(text: "期間を変えて「照会」", note: "前月より前は「更に過去の明細へ」から"),
                    Step(text: "「明細ダウンロード」で CSV を保存し、「\"ファイル\"に保存」", note: "照会した期間がそのまま入ります。1回 200件まで"),
                ],
                alternative: "PDF でもかまいません：明細の画面を PDF にして、共有で「日和」か「\"ファイル\"に保存」",
                alternativeUnverified: true,
                siteTitle: "十六銀行のサイトを開く",
                url: URL(string: "https://www.juroku.co.jp/j-direct/"))
        case .jcb:
            return KakeiboGuide(
                title: "JCB（MyJCB）で明細を保存する",
                intro: "MyJCB で、確定したご利用明細を CSV か PDF で保存します。15か月前までの確定分だけで、まだ確定していない利用は入りません",
                steps: [
                    Step(text: "下のボタンで MyJCB を開き、ログイン"),
                    Step(text: "確定したご利用明細（明細書）の画面を開く", unverified: true),
                    Step(text: "「明細書をダウンロードできます」から CSV か PDF を選ぶ"),
                    Step(text: "保存して「\"ファイル\"に保存」か、共有で「日和」"),
                ],
                siteTitle: "MyJCB のサイトを開く",
                url: URL(string: "https://my.jcb.co.jp/"))
        case .mufg:
            return KakeiboGuide(
                title: "三菱UFJ銀行で明細を保存する",
                intro: "三菱UFJダイレクトの入出金明細から保存します",
                steps: [
                    Step(text: "下のボタンで三菱UFJダイレクトを開き、ログイン"),
                    Step(text: "口座の「入出金明細」を開いて期間を選ぶ", unverified: true),
                    Step(text: "入出金明細の画面にダウンロード（CSV/PDF）があれば保存。なければ Safari の共有 › フルページで PDF に", unverified: true),
                ],
                siteTitle: "三菱UFJダイレクトのサイトを開く",
                url: URL(string: "https://direct.bk.mufg.jp/"))
        case .other:
            return KakeiboGuide(
                title: "ほかの銀行・カードの明細",
                intro: "銀行やカード会社のサイトで、入出金明細（ご利用明細）を CSV か PDF で保存してください。日付・金額・内容の列があれば読めます",
                steps: [
                    Step(text: "明細の画面で CSV（なければ PDF）を保存"),
                    Step(text: "「\"ファイル\"に保存」か、共有で「日和」"),
                    Step(text: "初めての形式は、次の画面で「この列が日付」などを合わせます。次からは覚えておきます"),
                ])
        }
    }
}
