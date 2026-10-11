import SwiftUI
import UIKit
import UserNotifications

// MARK: - 相談の「1日1枚」（夜に、その日を1枚のカードにまとめる）
// - 自動で入るもの：今日完了した TODO（件数と題名3件まで）・起床スコア・今日の気分（相談の気分の記録）
// - 書くのは「ひとこと」と、なくてもよい写真1枚
// - カードは daycard-yyyy-MM-dd.json（1日1ファイル）。写真はアプリの中（Application Support/DayCardPhotos）にだけ置き、共有フォルダには置かない
// - 夜の通知（daycard- で始まる）：既定は 21:00。今日の1枚を書いたら、今日の分は出さない
// - AI のふり返り：1週間分の数字とひとことだけを Gemini に送る（写真・TODO の題名は送らない）

struct DayCard: Codable, Identifiable, Equatable {
    var day: String                 // yyyy-MM-dd（WakeLogic.key と同じ形）
    var note: String
    var doneCount: Int
    var doneTitles: [String]        // 3件まで
    var wakeScore: Int?
    var wakeTime: Date?
    var mood: ConsultMood?
    var photo: String?              // アプリの中の写真のファイル名
    var savedAt: Date

    var id: String { day }
    var date: Date { WakeLogic.date(fromKey: day) ?? savedAt }
}

/// 今日の自動で入る項目
struct DayCardAuto: Equatable {
    var doneCount = 0
    var doneTitles: [String] = []
    var wakeScore: Int?
    var wakeTime: Date?
    var mood: ConsultMood?

    @MainActor
    static func make(store: TodoStore, now: Date = .now) -> DayCardAuto {
        var a = DayCardAuto()
        let done = store.doneToday
        a.doneCount = done.count
        a.doneTitles = done.suffix(3).map(\.title)
        let key = WakeLogic.key(now)
        if let s = WakeStore.sessions().first(where: { $0.day == key && !$0.isMissed }) {
            a.wakeScore = s.score
            a.wakeTime = s.checkInAt
        }
        a.mood = MoodData.today(now: now)
        return a
    }
}

enum DayCardData {
    static let prefix = "daycard-"
    static let reviewFile = "dayreview-latest.json"

    static func fileName(_ day: String) -> String { "\(prefix)\(day).json" }

    /// daycard-yyyy-MM-dd.json の形のときだけ、その日を返す
    static func day(fromFileName name: String) -> String? {
        guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return nil }
        let core = String(name.dropFirst(prefix.count).dropLast(5))
        guard core.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return core
    }

    /// すべてのカード（古い順）
    static func all() -> [DayCard] {
        if InfoLaunch.isDemo { return DayCardDemo.cards() }
        let dir = SharedStore.url("x").deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let cards: [DayCard] = names.compactMap { n in
            guard day(fromFileName: n) != nil else { return nil }
            return SplatFiles.load(DayCard.self, n)
        }
        return cards.sorted { $0.day < $1.day }
    }

    static func load(day: String) -> DayCard? {
        if InfoLaunch.isDemo { return DayCardDemo.cards().first { $0.day == day } }
        return SplatFiles.load(DayCard.self, fileName(day))
    }

    static func save(_ card: DayCard) {
        guard !InfoLaunch.isDemo else { return }
        SplatFiles.save(card, fileName(card.day))
        ConsultWidgetSync.write()
    }

    static func remove(day: String) {
        guard !InfoLaunch.isDemo else { return }
        if let c = load(day: day), let p = c.photo { removePhoto(p) }
        SplatFiles.remove(fileName(day))
        ConsultWidgetSync.write()
    }

    static func hasCard(on date: Date) -> Bool { load(day: WakeLogic.key(date)) != nil }

    /// その週（月曜はじまり）のカード
    static func week(containing date: Date, cards: [DayCard]) -> [DayCard] {
        let r = weekRange(date)
        return cards.filter { $0.date >= r.start && $0.date < r.end }
    }

    static func weekRange(_ date: Date) -> (start: Date, end: Date) {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    // MARK: 写真（アプリの中だけ）

    static var photoDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DayCardPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 縮めて JPEG で保存し、ファイル名を返す
    static func savePhoto(_ data: Data, day: String) -> String? {
        guard let img = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1400
        let size = img.size
        let scale: CGFloat = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let name = "\(day)-\(Int(Date.now.timeIntervalSince1970)).jpg"
        do {
            try jpeg.write(to: photoDir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return name
        } catch {
            return nil
        }
    }

    static func image(_ name: String?) -> UIImage? {
        guard let name, !name.contains("/") else { return nil }
        return UIImage(contentsOfFile: photoDir.appendingPathComponent(name).path)
    }

    static func removePhoto(_ name: String) {
        guard !name.contains("/") else { return }
        try? FileManager.default.removeItem(at: photoDir.appendingPathComponent(name))
    }

    // MARK: AI のふり返り

    static func savedReview() -> DayCardReview? {
        if InfoLaunch.isDemo { return DayCardDemo.review() }
        return SplatFiles.load(DayCardReview.self, reviewFile)
    }

    static func saveReview(_ r: DayCardReview) {
        guard !InfoLaunch.isDemo else { return }
        SplatFiles.save(r, reviewFile)
    }

    /// AI に渡す1週間分の文（数字とひとことだけ。写真と TODO の題名は入れない）
    static func promptLines(_ cards: [DayCard]) -> String {
        cards.sorted { $0.day < $1.day }.map { c in
            var parts: [String] = [JP.shortDate(c.date)]
            parts.append("TODO完了 \(c.doneCount)件")
            if let w = c.wakeScore { parts.append("起床 \(w)点") }
            if let m = c.mood { parts.append("気分 \(m.title)") }
            let note = c.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { parts.append("ひとこと「\(String(note.prefix(120)))」") }
            return "・" + parts.joined(separator: "、")
        }.joined(separator: "\n")
    }
}

struct DayCardReview: Codable, Equatable {
    var weekStart: String
    var text: String
    var at: Date
}

enum InfoLaunch {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
}

// MARK: - 夜の通知（daycard-）

enum DayCardReminder {
    static let enabledKey = "daycard.remind.on"
    static let minutesKey = "daycard.remind.minutes"   // 0時からの分。既定 21:00

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var minutes: Int {
        get { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 21 * 60 }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23 * 60 + 59), forKey: minutesKey) }
    }

    /// 通知を出す日時（今日から days 日分。今日のカードがあれば今日は飛ばす。過ぎた時刻は飛ばす）
    static func fireDates(now: Date = .now, minutes: Int, writtenToday: Bool, days: Int = 7) -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [Date] = []
        for i in 0..<days {
            guard let base = cal.date(byAdding: .day, value: i, to: today),
                  let at = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: base) else { continue }
            if i == 0 && writtenToday { continue }
            if at <= now { continue }
            out.append(at)
        }
        return out
    }

    /// 作り直す（daycard- で始まる通知だけを消して足す）
    static func reschedule(now: Date = .now) async {
        guard !LaunchArguments.isScripted else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("daycard-") })
        guard enabled else { return }
        let dates = fireDates(now: now, minutes: minutes, writtenToday: DayCardData.hasCard(on: now))
        for at in dates {
            let c = UNMutableNotificationContent()
            c.title = "今日の1枚を書きましょう"
            c.body = "TODO や気分はもう入っています。ひとことだけどうぞ"
            c.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let id = "daycard-\(WakeLogic.key(at))"
            try? await center.add(UNNotificationRequest(identifier: id, content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    static func requestAuthorization() async {
        guard !LaunchArguments.isScripted else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func label(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
}

// MARK: - 見本（-demo。架空のカード）

enum DayCardDemo {
    private static let notes = [
        "朝の散歩が気持ちよかった。午後は集中できた",
        "雨で少しだるい日。早めに寝る",
        "やることを3つにしぼったら、ぜんぶ終わった",
        "久しぶりに友だちと電話。笑った",
        "部屋を片づけた。机が広い",
        "新しいカフェで本を読んだ",
        "",
    ]
    private static let todos = [["資料をまとめる", "洗濯", "買い物"], ["メールの返信", "本を返す"], ["掃除", "請求書の確認", "散歩"],
                                ["料理の下ごしらえ", "日記"], ["机の片づけ", "ストレッチ", "読書"], ["郵便を出す"], []]
    private static let moods: [ConsultMood] = [.good, .low, .great, .good, .okay, .great, .okay]

    static func cards(now: Date = .now) -> [DayCard] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var out: [DayCard] = []
        for i in 1...9 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if i == 6 { continue }   // 書かなかった日
            let k = i % notes.count
            let wake: Int? = i % 4 == 2 ? nil : 62 + (i * 11) % 34
            let wakeAt = cal.date(bySettingHour: 6, minute: 20 + (i * 7) % 30, second: 0, of: d)
            out.append(DayCard(day: WakeLogic.key(d), note: notes[k].isEmpty ? "ゆっくりした日" : notes[k],
                               doneCount: todos[k].count + i % 3, doneTitles: todos[k],
                               wakeScore: wake, wakeTime: wake == nil ? nil : wakeAt, mood: moods[k], photo: nil,
                               savedAt: d.addingTimeInterval(21 * 3600 + 600)))
        }
        return out.sorted { $0.day < $1.day }
    }

    static func review(now: Date = .now) -> DayCardReview {
        DayCardReview(weekStart: WakeLogic.key(DayCardData.weekRange(now).start), text: """
        水曜は雨で少しだるそうでしたが、木曜にやることを3つにしぼってからは、朝も安定して TODO がよく進みました。友だちとの電話や新しいカフェなど、気分が上がる時間をちゃんと作れているのがすてきです。
        来週は、つかれた日ほど「やることを3つにしぼる」を続けてみましょう。
        【今日の一歩】明日のTODOを3つだけ選ぶ
        """, at: now)
    }
}

// MARK: - 状態（書く画面・めくる画面で共有）

@MainActor
final class DayCardModel: ObservableObject {
    @Published private(set) var cards: [DayCard] = []
    @Published var note = ""
    @Published var photoName: String? = nil
    @Published private(set) var savedToday = false
    @Published var reviewing = false
    @Published var review: DayCardReview? = nil
    @Published var reviewError: String? = nil

    let isDemo = InfoLaunch.isDemo

    init() { reload() }

    var todayKey: String { WakeLogic.key(.now) }

    func reload() {
        cards = DayCardData.all()
        if isDemo {
            note = "やることを決めてから動いたら、気持ちが軽かった"
            savedToday = false
        } else if let c = DayCardData.load(day: todayKey) {
            note = c.note
            photoName = c.photo
            savedToday = true
        }
        review = DayCardData.savedReview()
    }

    func attachPhoto(_ data: Data) {
        guard !isDemo, let name = DayCardData.savePhoto(data, day: todayKey) else { return }
        if let old = photoName, old != name, DayCardData.load(day: todayKey)?.photo != old { DayCardData.removePhoto(old) }
        photoName = name
    }

    func removePhoto() {
        if let old = photoName, DayCardData.load(day: todayKey)?.photo != old { DayCardData.removePhoto(old) }
        photoName = nil
    }

    func save(auto a: DayCardAuto) {
        let previous = DayCardData.load(day: todayKey)
        let card = DayCard(day: todayKey, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                           doneCount: a.doneCount, doneTitles: Array(a.doneTitles.prefix(3)),
                           wakeScore: a.wakeScore, wakeTime: a.wakeTime, mood: a.mood, photo: photoName, savedAt: .now)
        if let old = previous?.photo, old != photoName { DayCardData.removePhoto(old) }
        DayCardData.save(card)
        savedToday = true
        if isDemo {
            cards.removeAll { $0.day == card.day }
            cards.append(card)
        } else {
            cards = DayCardData.all()
        }
        Task { await DayCardReminder.reschedule() }
    }

    /// 今週のカードを AI にふり返ってもらう
    func runReview(week: [DayCard]) async {
        guard !reviewing else { return }
        reviewError = nil
        let weekStart = WakeLogic.key(DayCardData.weekRange(.now).start)
        if isDemo {
            review = DayCardDemo.review()
            return
        }
        guard !week.isEmpty else {
            reviewError = "今週のカードがまだありません。"
            return
        }
        guard let key = InfoSecrets.get(ConsultModel.keyName) else {
            reviewError = "相談のメニューから Gemini の API キーを設定してください。"
            return
        }
        reviewing = true
        defer { reviewing = false }
        let prompt = """
        次は、ある人が毎晩1枚ずつ書いた「今日のカード」の1週間分です（数字とひとことだけ）。

        \(DayCardData.promptLines(week))

        これをもとに、日本語の話し言葉で、やさしく短くふり返ってください。
        - 3〜4文で、よかったこと・つらそうだった日・流れの変化にふれる。数字を根拠にし、決めつけない
        - そのあとに、来週への小さな提案を1文
        - 最後の行は「【今日の一歩】」に続けて、5〜15分でできる行動を20字以内で1つ
        """
        let system = "あなたは「日和」という生活管理アプリの中の、やさしいふり返りの相手です。医療の診断はしません。"
        do {
            let text = try await GeminiAPI.reply(key: key, system: system, history: [ConsultMessage(fromUser: true, text: prompt)])
            review = DayCardReview(weekStart: weekStart, text: text, at: .now)
        } catch GeminiError.quota {
            reviewError = "無料枠の上限に達しました。しばらくしてからもう一度試してください。"
        } catch GeminiError.badKey {
            reviewError = "API キーが使えませんでした。キーを確かめてください。"
        } catch {
            reviewError = "ふり返りを受け取れませんでした。通信を確認してください。"
        }
    }

    func keepReview() {
        guard let r = review else { return }
        DayCardData.saveReview(r)
    }
}

// MARK: - 通知から相談タブ（tag 3）を開く
// 夜の通知（daycard-）をタップしたら、RootView のタブを 3 にする。つなぐ2行（統合のとき）：
// - TodoNotifier.userNotificationCenter(_:didReceive:) の先頭：
//   if ConsultDeepLink.opensConsult(response.notification.request.identifier) { await MainActor.run { ConsultDeepLink.request() }; return }
// - RootView の TabView：.onReceive(NotificationCenter.default.publisher(for: .openConsultTab)) { _ in tab = 3 }
//   （起動直後に通知より先に開いたときのため .onAppear { if ConsultDeepLink.consumePending() { tab = 3 } } も）

extension Notification.Name {
    static let openConsultTab = Notification.Name("openConsultTab")
}

@MainActor
enum ConsultDeepLink {
    private static var pending = false

    nonisolated static func opensConsult(_ identifier: String) -> Bool { identifier.hasPrefix("daycard-") }

    static func request() {
        pending = true
        NotificationCenter.default.post(name: .openConsultTab, object: nil)
    }

    /// まだ開いていない要求があれば true（一度だけ）
    static func consumePending() -> Bool {
        defer { pending = false }
        return pending
    }
}
