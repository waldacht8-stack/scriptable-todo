import SwiftUI

// MARK: - 相談（AI に悩みを話す。Gemini API の無料枠を使う）
// - 送るのは、書いた文・選んだ気分・記録の要約（件数・平均点・連続日数）だけ。TODO の題名や予定の中身は送らない
// - API キーは Keychain にだけ保存（InfoSecrets）。会話は端末のファイル（consult-history.json）に最新40件まで
// - 起動引数 -demo では通信せず、見本の会話を出す。-consult で情報タブの「相談」を開く

struct ConsultMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var fromUser: Bool
    var text: String
    var date = Date()
}

enum ConsultMood: Int, CaseIterable, Identifiable, Codable {
    case great, good, okay, low, bad
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .great: "最高"
        case .good: "いい"
        case .okay: "ふつう"
        case .low: "いまいち"
        case .bad: "つらい"
        }
    }

    var symbol: String {
        switch self {
        case .great: "sun.max.fill"
        case .good: "cloud.sun.fill"
        case .okay: "cloud.fill"
        case .low: "cloud.drizzle.fill"
        case .bad: "cloud.heavyrain.fill"
        }
    }
}

/// 記録の要約（AI に渡す文と、画面のチップに使う）
struct ConsultContext: Equatable {
    var openCount = 0
    var overdueCount = 0
    var doneToday = 0
    var wakeAverage: Int?
    var wakeStreak = 0
    var habitCount = 0
    var habitDoneToday = 0
    var habitBestStreak = 0

    @MainActor
    static func make(store: TodoStore, now: Date = .now) -> ConsultContext {
        var c = ConsultContext()
        c.openCount = store.open.count
        c.overdueCount = store.overdue.count
        c.doneToday = store.doneToday.count
        let sessions = WakeStore.sessions()
        c.wakeAverage = WakeStore.average(sessions, days: 7, now: now)
        c.wakeStreak = WakeStore.streak(sessions)
        let habits = HabitData.habits()
        let log = HabitData.log()
        c.habitCount = habits.count
        c.habitDoneToday = habits.filter { HabitData.isDone(log, $0, now) }.count
        c.habitBestStreak = habits.map { HabitData.currentStreak($0, log, today: now) }.max() ?? 0
        return c
    }

    var chips: [String] {
        var out: [String] = []
        if let a = wakeAverage { out.append("起床 7日の平均 \(a)点") }
        out.append(overdueCount > 0 ? "TODO \(openCount)件・期限切れ \(overdueCount)" : "TODO \(openCount)件")
        if habitCount > 0 { out.append("習慣 今日 \(habitDoneToday)/\(habitCount)") }
        return out
    }

    /// AI に渡す説明（数字だけ）
    var summary: String {
        var lines: [String] = []
        lines.append("未完了のTODO: \(openCount)件（うち期限切れ \(overdueCount)件）、今日完了: \(doneToday)件")
        if let a = wakeAverage { lines.append("起床スコアの直近7日平均: \(a)点（100点満点）、連続 \(wakeStreak)日") }
        if habitCount > 0 { lines.append("習慣: \(habitCount)個中 今日 \(habitDoneToday)個できた、最長の連続 \(habitBestStreak)日") }
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class ConsultModel: ObservableObject {
    static let keyName = "consult.geminikey"
    private static let historyFile = "consult-history.json"

    @Published var messages: [ConsultMessage] = []
    @Published var mood: ConsultMood?
    @Published private(set) var sending = false
    @Published var error: String?
    @Published private(set) var hasKey: Bool

    let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    init() {
        if isDemo {
            hasKey = true
            mood = .okay
            messages = ConsultDemo.messages()
        } else {
            hasKey = InfoSecrets.has(Self.keyName)
            messages = SplatFiles.load([ConsultMessage].self, Self.historyFile) ?? []
        }
    }

    func saveKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        InfoSecrets.set(Self.keyName, key.isEmpty ? nil : key)
        hasKey = InfoSecrets.has(Self.keyName)
        error = nil
    }

    func removeKey() {
        InfoSecrets.set(Self.keyName, nil)
        hasKey = false
    }

    func clear() {
        messages = []
        error = nil
        if !isDemo { SplatFiles.remove(Self.historyFile) }
    }

    func send(_ raw: String, context: ConsultContext) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        messages.append(ConsultMessage(fromUser: true, text: text))
        persist()
        guard !isDemo else {
            messages.append(ConsultMessage(fromUser: false, text: "（見本）話してくれてありがとう。まずは深呼吸をひとつ。いちばん小さな一歩から始めてみませんか。"))
            return
        }
        guard let key = InfoSecrets.get(Self.keyName) else {
            error = "Gemini の API キーを設定してください。"
            return
        }
        sending = true
        defer { sending = false }
        do {
            let reply = try await GeminiAPI.reply(key: key, system: systemPrompt(context), history: Array(messages.suffix(16)))
            messages.append(ConsultMessage(fromUser: false, text: reply))
            error = nil
            persist()
        } catch GeminiError.badKey {
            error = "API キーが使えませんでした。キーを確かめてください。"
        } catch GeminiError.quota {
            error = "無料枠の上限に達しました。しばらくしてからもう一度送ってください。"
        } catch {
            self.error = "返事を受け取れませんでした。通信を確認してください。"
        }
    }

    private func persist() {
        guard !isDemo else { return }
        if messages.count > 40 { messages = Array(messages.suffix(40)) }
        SplatFiles.save(messages, Self.historyFile)
    }

    private func systemPrompt(_ c: ConsultContext) -> String {
        var s = """
        あなたは「日和」という生活管理アプリの中の、やさしい相談相手です。日本語で、話し言葉で答えてください。
        - まず気持ちを受け止める。説教や決めつけはしない
        - 返事は短く（3〜6文）。箇条書きは最大3つ
        - 最後に「今日できる小さな一歩」を1つだけ提案する
        - 医療・法律・お金の判断が必要そうなときは、専門家や公的な窓口に相談することをすすめる
        - 命に関わるほどつらそうなときは、すぐに身近な人や「いのちの電話」などの相談窓口に連絡するよう、やさしく伝える
        - 名前などの個人情報を聞き出さない

        いまのユーザーの記録（参考。数字だけ）:
        \(c.summary)
        """
        if let m = mood { s += "\n今日の気分: \(m.title)" }
        return s
    }
}

// MARK: - Gemini API（generateContent）

enum GeminiError: Error {
    case badKey
    case quota
    case http(Int)
    case empty
}

enum GeminiAPI {
    /// 新しい順に試す（古いモデルが終了しても動くように）
    static let models = ["gemini-flash-latest", "gemini-2.5-flash"]

    static func reply(key: String, system: String, history: [ConsultMessage]) async throws -> String {
        var last: Error = GeminiError.empty
        for model in models {
            do {
                return try await call(model: model, key: key, system: system, history: history)
            } catch GeminiError.http(let code) where code == 404 {
                last = GeminiError.http(code)
                continue
            }
        }
        throw last
    }

    private static func call(model: String, key: String, system: String, history: [ConsultMessage]) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw GeminiError.empty
        }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let contents: [RawContent] = history.map { RawContent(role: $0.fromUser ? "user" : "model", parts: [RawPart(text: $0.text)]) }
        let body = RawRequest(system_instruction: RawContent(role: nil, parts: [RawPart(text: system)]),
                              contents: contents,
                              generationConfig: RawConfig(temperature: 0.8, maxOutputTokens: 1024))
        req.httpBody = try JSONEncoder().encode(body)
        let (data, res) = try await URLSession.shared.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 200
        if code == 400 || code == 401 || code == 403 {
            // キーの誤りは 400（API_KEY_INVALID）か 403 で返る
            throw GeminiError.badKey
        }
        if code == 429 { throw GeminiError.quota }
        guard (200..<300).contains(code) else { throw GeminiError.http(code) }
        let root = try JSONDecoder().decode(RawResponse.self, from: data)
        let parts: [RawPart] = root.candidates?.first?.content?.parts ?? []
        let text = parts.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GeminiError.empty }
        return text
    }

    private struct RawPart: Codable { var text: String? }
    private struct RawContent: Codable { var role: String?; var parts: [RawPart]? }
    private struct RawConfig: Codable { var temperature: Double; var maxOutputTokens: Int }
    private struct RawRequest: Encodable {
        var system_instruction: RawContent
        var contents: [RawContent]
        var generationConfig: RawConfig
    }
    private struct RawCandidate: Decodable { var content: RawContent? }
    private struct RawResponse: Decodable { var candidates: [RawCandidate]? }
}

// MARK: - 見本（-demo。架空の会話）

enum ConsultDemo {
    static func messages(now: Date = .now) -> [ConsultMessage] {
        [
            ConsultMessage(fromUser: true, text: "最近やる気が出なくて、TODO がたまってしまっています", date: now.addingTimeInterval(-300)),
            ConsultMessage(fromUser: false, text: "たまっていくのを見ると、それだけで気持ちが重くなりますよね。今週は朝が少しつらそうなので、疲れがたまっているのかもしれません。\n\n全部を片づけようとせず、期限切れの2件だけ明日に回して、今日は「歯医者」の1件だけにしぼってみませんか。",
                           date: now.addingTimeInterval(-280)),
        ]
    }
}

// MARK: - 画面

struct ConsultView: View {
    @StateObject private var model = ConsultModel()
    @EnvironmentObject var store: TodoStore
    @Environment(\.palette) private var p
    @Environment(\.motion) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var showKeySheet = false
    @State private var confirmClear = false
    @FocusState private var typing: Bool
    /// 記録の要約（開いたときと TODO の数が変わったときに作り直す。打つたびには読まない）
    @State private var ctx = ConsultContext()

    var body: some View {
        let ctx = self.ctx
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        moodCard
                        chips(ctx)
                        if !model.hasKey { keyCard }
                        if model.messages.isEmpty && model.hasKey { emptyHint }
                        ForEach(model.messages) { m in
                            ConsultBubble(message: m)
                                .id(m.id)
                                .transition(motion.appear)
                        }
                        if model.messages.last?.fromUser == false, ctx.overdueCount > 0 {
                            actions(ctx)
                        }
                        if model.sending { typingIndicator.id("typing") }
                        if let e = model.error {
                            Text(e).font(.footnote.weight(.semibold)).foregroundStyle(p.overdue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.count) { _, _ in
                    guard let last = model.messages.last else { return }
                    withAnimation(reduceMotion ? nil : motion.change) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            composer(ctx)
        }
        .onAppear { self.ctx = ConsultContext.make(store: store) }
        .onChange(of: store.open.count) { _, _ in self.ctx = ConsultContext.make(store: store) }
        .sheet(isPresented: $showKeySheet) {
            ConsultKeySheet(model: model).environment(\.palette, p)
        }
        .confirmationDialog("会話を消しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("会話を消す", role: .destructive) { withAnimation(motion.change) { model.clear() } }
        }
    }

    // 今日の気分
    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日の気分は？").font(.subheadline.weight(.bold)).foregroundStyle(p.sub)
                Spacer()
                Menu {
                    Button { showKeySheet = true } label: { Label("API キーの設定", systemImage: "key") }
                    Button(role: .destructive) { confirmClear = true } label: { Label("会話を消す", systemImage: "trash") }
                        .disabled(model.messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(p.sub)
                        .frame(width: 44, height: 32)
                }
                .accessibilityLabel("相談のメニュー")
            }
            HStack(spacing: 6) {
                ForEach(ConsultMood.allCases) { m in
                    moodButton(m)
                }
            }
        }
        .paletteCard(p, padding: 14)
    }

    private func moodButton(_ m: ConsultMood) -> some View {
        let on: Bool = model.mood == m
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            withAnimation(reduceMotion ? nil : motion.tap) { model.mood = on ? nil : m }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: m.symbol).font(.body)
                Text(m.title).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? p.accent : p.sub)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(on ? p.accent.opacity(0.14) : p.sub.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(on ? p.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("気分：\(m.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chips(_ ctx: ConsultContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ctx.chips, id: \.self) { c in
                    Text(c).font(.caption.weight(.bold)).foregroundStyle(p.sub)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(p.card, in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("いまの記録：" + ctx.chips.joined(separator: "、"))
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("はじめに API キーを設定", systemImage: "key.fill").font(.headline).foregroundStyle(p.text)
            Text("相談は Google の Gemini（無料枠）で返事を作ります。Google AI Studio で無料の API キーを作って入れてください。")
                .font(.subheadline).foregroundStyle(p.sub)
            Button { showKeySheet = true } label: {
                Text("キーを設定する").font(.subheadline.weight(.bold)).foregroundStyle(p.onAccent)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(p.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .paletteCard(p)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("話を聞くよ").font(.title3.weight(.heavy)).foregroundStyle(p.text)
            Text("気になっていること、疲れていること、なんでも書いてください。記録の数字（件数や平均点）だけを参考にして返事をします。")
                .font(.subheadline).foregroundStyle(p.sub)
        }
        .padding(.vertical, 8)
    }

    private func actions(_ ctx: ConsultContext) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(motion.change) { for t in store.overdue { store.postpone(t) } }
            } label: {
                Label("期限切れ\(ctx.overdueCount)件を明日へ", systemImage: "arrow.turn.up.right")
                    .font(.caption.weight(.bold)).foregroundStyle(p.accent)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(p.accent, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("考えています…").font(.footnote).foregroundStyle(p.sub)
        }
        .padding(.vertical, 4)
    }

    private func composer(_ ctx: ConsultContext) -> some View {
        VStack(spacing: 6) {
            Text("Gemini（無料枠）を使います。内容が Google の改善に使われることがあります。名前などは書かないでください。")
                .font(.caption2).foregroundStyle(p.sub).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                TextField("話したいことを書く", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($typing)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .foregroundStyle(p.text)
                Button {
                    let text = draft
                    draft = ""
                    Task { await model.send(text, context: ctx) }
                } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(p.onAccent)
                        .frame(width: 46, height: 46)
                        .background(p.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sending)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                .accessibilityLabel("送る")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

private struct ConsultBubble: View {
    @Environment(\.palette) private var p
    let message: ConsultMessage

    var body: some View {
        let user: Bool = message.fromUser
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: user ? 18 : 4,
                                           bottomTrailingRadius: user ? 4 : 18, topTrailingRadius: 18, style: .continuous)
        HStack {
            if user { Spacer(minLength: 48) }
            Text(message.text)
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(user ? p.onAccent : p.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(user ? AnyShapeStyle(p.accent) : AnyShapeStyle(p.card), in: shape)
                .textSelection(.enabled)
            if !user { Spacer(minLength: 32) }
        }
        .accessibilityLabel((user ? "あなた：" : "相談相手：") + message.text)
    }
}

private struct ConsultKeySheet: View {
    @ObservedObject var model: ConsultModel
    @Environment(\.palette) private var p
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var key = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Google AI Studio で作った Gemini の API キーを入れてください。キーはこの iPhone の Keychain にだけ保存します。")
                    .font(.subheadline).foregroundStyle(p.sub)
                SecureField(model.hasKey ? "保存済み（変えるときだけ入力）" : "API キー", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(p.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    if let u = URL(string: "https://aistudio.google.com/apikey") { openURL(u) }
                } label: {
                    Label("キーを作る（Google AI Studio）", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(p.accent)
                }
                .buttonStyle(.plain)
                Text("無料枠では、送った内容が Google のサービス改善に使われることがあります。名前・住所・連絡先などは書かないでください。")
                    .font(.footnote).foregroundStyle(p.sub)
                if model.hasKey && !model.isDemo {
                    Button("キーを消す", role: .destructive) { model.removeKey(); dismiss() }
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
            .padding(20)
            .paletteBackground(p)
            .navigationTitle("相談の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { model.saveKey(key); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
