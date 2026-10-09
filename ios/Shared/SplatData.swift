import Foundation

// スプラトゥーン3：ステージ情報（splatoon3.ink の公開データ）と戦績（stat.ink の公開データ）。
// ここには画面に出すための小さな形だけを置く（元の JSON は SplatAPI.swift で読み替える）。
// 保存先は App Group の共有フォルダの splat-*.json（SharedStore.url に直接書く）。

// MARK: - ステージ情報

enum SplatMode: String, Codable, CaseIterable, Hashable {
    case regular, bankaraChallenge, bankaraOpen, x, event, festOpen, festChallenge

    var title: String {
        switch self {
        case .regular: return "レギュラーマッチ"
        case .bankaraChallenge: return "バンカラマッチ チャレンジ"
        case .bankaraOpen: return "バンカラマッチ オープン"
        case .x: return "Xマッチ"
        case .event: return "イベントマッチ"
        case .festOpen: return "フェスマッチ オープン"
        case .festChallenge: return "フェスマッチ チャレンジ"
        }
    }

    var short: String {
        switch self {
        case .regular: return "レギュラー"
        case .bankaraChallenge: return "チャレンジ"
        case .bankaraOpen: return "オープン"
        case .x: return "Xマッチ"
        case .event: return "イベント"
        case .festOpen: return "フェス オープン"
        case .festChallenge: return "フェス チャレンジ"
        }
    }

    /// 並べる順
    var order: Int { SplatMode.allCases.firstIndex(of: self) ?? 0 }
}

struct SplatStage: Codable, Hashable {
    var name: String
    var image: String? = nil
}

struct SplatRotation: Codable, Hashable, Identifiable {
    var mode: SplatMode
    var rule: String            // 日本語のルール名（ナワバリバトル・ガチエリア…）
    var ruleKey: String = ""    // TURF_WAR・AREA・LOFT・GOAL・CLAM など
    var start: Date
    var end: Date
    var stages: [SplatStage]
    var eventName: String? = nil
    var eventDesc: String? = nil

    var id: String { "\(mode.rawValue)-\(Int(start.timeIntervalSince1970))-\(eventName ?? "")" }

    func isActive(at d: Date) -> Bool { start <= d && d < end }
}

struct SplatSalmonShift: Codable, Hashable, Identifiable {
    var kind: String            // 通常 / ビッグラン / バイトチームコンテスト
    var start: Date
    var end: Date
    var stage: SplatStage
    var weapons: [SplatStage]
    var boss: String? = nil

    var id: String { "\(kind)-\(Int(start.timeIntervalSince1970))" }
}

struct SplatFestTeam: Codable, Hashable {
    var name: String
    var r: Double
    var g: Double
    var b: Double
    var winner: Bool? = nil
}

struct SplatFest: Codable, Hashable {
    var title: String
    var start: Date
    var end: Date
    var state: String           // SCHEDULED / FIRST_HALF / SECOND_HALF / CLOSED
    var image: String? = nil
    var teams: [SplatFestTeam]

    var isClosed: Bool { state == "CLOSED" }

    var stateText: String {
        switch state {
        case "SCHEDULED": return "開催予定"
        case "FIRST_HALF": return "開催中（前半）"
        case "SECOND_HALF": return "開催中（後半）"
        case "CLOSED": return "終了"
        default: return "フェス"
        }
    }
}

struct SplatSchedule: Codable {
    var fetchedAt: Date
    var rotations: [SplatRotation]
    var salmon: [SplatSalmonShift]
    var fest: SplatFest? = nil

    /// 時間帯（レギュラー・フェスの区切り）の開始時刻。終わったものは除く
    func slots(now: Date = .now) -> [Date] {
        let base = rotations.filter { $0.mode != .event && $0.end > now }
        let starts = Set(base.map { $0.start })
        return starts.sorted()
    }

    /// ある時間帯に遊べるもの（イベントは重なっていれば含める）
    func rotations(at slot: Date) -> [SplatRotation] {
        let list = rotations.filter { r in
            r.mode == .event ? r.isActive(at: slot) : r.start == slot
        }
        return list.sorted { $0.mode.order < $1.mode.order }
    }

    /// 次に切り替わる時刻（今の時間帯の終わり）
    func nextSwitch(now: Date = .now) -> Date? {
        rotations.filter { $0.mode != .event && $0.isActive(at: now) }.map(\.end).min()
    }

    /// 今の主な3つ（レギュラー・チャレンジ・X。フェス中はフェスの2つ）
    func headline(now: Date = .now) -> [SplatRotation] {
        let active = rotations.filter { $0.isActive(at: now) && $0.mode != .event }
        let preferred: [SplatMode] = [.regular, .bankaraChallenge, .x, .festOpen, .festChallenge, .bankaraOpen]
        var out: [SplatRotation] = []
        for m in preferred {
            if let r = active.first(where: { $0.mode == m }) { out.append(r) }
            if out.count == 3 { break }
        }
        return out
    }

    /// これからのイベントマッチ（イベントごとに一番近い回）
    func upcomingEvents(now: Date = .now) -> [SplatRotation] {
        let future = rotations.filter { $0.mode == .event && $0.end > now }.sorted { $0.start < $1.start }
        var seen = Set<String>()
        var out: [SplatRotation] = []
        for r in future where !seen.contains(r.eventName ?? "") {
            seen.insert(r.eventName ?? "")
            out.append(r)
        }
        return out
    }

    func currentSalmon(now: Date = .now) -> [SplatSalmonShift] {
        salmon.filter { $0.end > now }.sorted { $0.start < $1.start }
    }
}

// MARK: - 戦績（stat.ink）

struct SplatBattle: Codable, Hashable, Identifiable {
    var id: String
    var at: Date
    var result: String          // win / lose / draw など
    var lobbyKey: String        // regular / bankara_challenge / xmatch / event / splatfest_open …
    var lobby: String
    var rule: String
    var stage: String
    var weapon: String
    var kill: Int? = nil
    var assist: Int? = nil
    var death: Int? = nil
    var special: Int? = nil
    var inked: Int? = nil
    var knockout: Bool? = nil

    var isWin: Bool { result == "win" }
    var isLose: Bool { result == "lose" || result == "exempted_lose" }
}

struct SplatSalmonRecord: Codable, Hashable, Identifiable {
    var id: String
    var at: Date
    var stage: String
    var cleared: Bool
    var clearWaves: Int? = nil
    var waves: Int = 3
    var dangerRate: Double? = nil
    var goldenEggs: Int? = nil
    var powerEggs: Int? = nil
    var rescue: Int? = nil
    var rescued: Int? = nil
    var weapons: [String] = []
    var kind: String? = nil     // ビッグラン など
}

struct SplatRecords: Codable {
    var screenName: String
    var fetchedAt: Date
    var battles: [SplatBattle]
    var salmon: [SplatSalmonRecord]

    /// 勝ち・負けが決まった試合だけ
    var decided: [SplatBattle] { battles.filter { $0.isWin || $0.isLose } }

    func winRate(last n: Int) -> Double? {
        let list = Array(decided.prefix(n))
        guard !list.isEmpty else { return nil }
        return Double(list.filter(\.isWin).count) / Double(list.count)
    }
}

struct SplatSettings: Codable {
    var screenName: String = ""

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screenName = try c.decodeIfPresent(String.self, forKey: .screenName) ?? ""
    }
    enum CodingKeys: String, CodingKey { case screenName }
}

// MARK: - 保存（App Group の共有フォルダに直接書く）

enum SplatFiles {
    static let schedule = "splat-schedule.json"
    static let records = "splat-records.json"
    static let settings = "splat-settings.json"

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: SharedStore.url(name)) else { return nil }
        return try? JSONDecoder.iso.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder.iso.encode(value) else { return }
        try? data.write(to: SharedStore.url(name), options: .atomic)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: SharedStore.url(name))
    }
}

// MARK: - 見本データ（起動引数 -demo。通信しない・架空の内容）

enum SplatDemo {
    private static let stages = ["ユノハナ大渓谷", "ゴンズイ地区", "ヤガラ市場", "マテガイ放水路", "ナメロウ金属",
                                 "マサバ海峡大橋", "キンメダイ美術館", "マヒマヒリゾート＆スパ", "海女美術大学",
                                 "チョウザメ造船", "ザトウマーケット", "スメーシーワールド", "クサヤ温泉", "ヒラメが丘団地"]
    private static let rules: [(String, String)] = [("ガチエリア", "AREA"), ("ガチヤグラ", "LOFT"),
                                                    ("ガチホコバトル", "GOAL"), ("ガチアサリ", "CLAM")]
    private static let weapons = ["わかばシューター", "スプラシューター", "スプラローラー", "スプラチャージャー",
                                  "ボールドマーカー", "ホットブラスター", "スプラマニューバー", "パブロ", "バケットスロッシャー"]

    static func schedule(now: Date = .now) -> SplatSchedule {
        let twoHours: TimeInterval = 7200
        let base = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / twoHours) * twoHours)
        var rotations: [SplatRotation] = []
        for i in 0..<6 {
            let s = base.addingTimeInterval(Double(i) * twoHours)
            let e = s.addingTimeInterval(twoHours)
            func st(_ k: Int) -> [SplatStage] {
                [SplatStage(name: stages[(i * 5 + k) % stages.count]), SplatStage(name: stages[(i * 5 + k + 7) % stages.count])]
            }
            let r1 = rules[i % 4], r2 = rules[(i + 1) % 4], r3 = rules[(i + 2) % 4]
            rotations.append(SplatRotation(mode: .regular, rule: "ナワバリバトル", ruleKey: "TURF_WAR", start: s, end: e, stages: st(0)))
            rotations.append(SplatRotation(mode: .bankaraChallenge, rule: r1.0, ruleKey: r1.1, start: s, end: e, stages: st(1)))
            rotations.append(SplatRotation(mode: .bankaraOpen, rule: r2.0, ruleKey: r2.1, start: s, end: e, stages: st(2)))
            rotations.append(SplatRotation(mode: .x, rule: r3.0, ruleKey: r3.1, start: s, end: e, stages: st(3)))
        }
        let ev = base.addingTimeInterval(2 * twoHours)
        rotations.append(SplatRotation(mode: .event, rule: "ガチヤグラ", ruleKey: "LOFT", start: ev, end: ev.addingTimeInterval(twoHours),
                                       stages: [SplatStage(name: stages[2]), SplatStage(name: stages[9])],
                                       eventName: "見本のイベントマッチ", eventDesc: "サブウェポンが強くなる、架空のイベントです。"))
        let sStart = base.addingTimeInterval(-6 * 3600)
        let salmon = [
            SplatSalmonShift(kind: "通常", start: sStart, end: sStart.addingTimeInterval(40 * 3600),
                             stage: SplatStage(name: "シェケナダム"),
                             weapons: ["スプラシューター", "バケットスロッシャー", "ノヴァブラスター", "ランダム"].map { SplatStage(name: $0) },
                             boss: "ヨコヅナ"),
            SplatSalmonShift(kind: "通常", start: sStart.addingTimeInterval(40 * 3600), end: sStart.addingTimeInterval(80 * 3600),
                             stage: SplatStage(name: "アラマキ砦"),
                             weapons: ["スプラチャージャー", "パブロ", "ジムワイパー", "ダイナモローラー"].map { SplatStage(name: $0) },
                             boss: "タツ"),
        ]
        let fStart = Calendar.current.startOfDay(for: now).addingTimeInterval(9 * 86400 + 9 * 3600)
        let fest = SplatFest(title: "朝ごはんはどれ派？", start: fStart, end: fStart.addingTimeInterval(48 * 3600), state: "SCHEDULED",
                             teams: [SplatFestTeam(name: "ごはん", r: 0.96, g: 0.85, b: 0.25),
                                     SplatFestTeam(name: "パン", r: 0.98, g: 0.45, b: 0.30),
                                     SplatFestTeam(name: "シリアル", r: 0.35, g: 0.78, b: 0.95)])
        return SplatSchedule(fetchedAt: now, rotations: rotations, salmon: salmon, fest: fest)
    }

    static func records(now: Date = .now) -> SplatRecords {
        let lobbies: [(String, String)] = [("regular", "レギュラーマッチ"), ("bankara_challenge", "バンカラマッチ（チャレンジ）"),
                                           ("bankara_open", "バンカラマッチ（オープン）"), ("xmatch", "Xマッチ")]
        let pattern: [Bool] = [true, true, false, true, false, true, true, false, true, true, false, false, true, true, true,
                               false, true, false, true, true, true, false, true, false, true, true, false, true, false, true]
        var battles: [SplatBattle] = []
        for (i, win) in pattern.enumerated() {
            let lobby = lobbies[(i / 3) % lobbies.count]
            let isTurf = lobby.0 == "regular"
            let rule = isTurf ? "ナワバリバトル" : rules[i % 4].0
            let weapon = weapons[[0, 1, 1, 4, 1, 2, 0, 1, 5, 4][i % 10]]
            let at: Date = now.addingTimeInterval(Double(-i * 260 - 600))
            let ko: Bool? = (!isTurf && win && i % 5 == 0) ? true : nil
            var b = SplatBattle(id: "demo-\(i)", at: at, result: win ? "win" : "lose", lobbyKey: lobby.0, lobby: lobby.1,
                                rule: rule, stage: stages[(i * 3) % stages.count], weapon: weapon)
            b.kill = 3 + (i * 7) % 9
            b.assist = (i * 3) % 5
            b.death = 2 + (i * 5) % 7
            b.special = 1 + i % 4
            b.inked = 700 + (i * 137) % 900
            b.knockout = ko
            battles.append(b)
        }
        var salmon: [SplatSalmonRecord] = []
        for i in 0..<6 {
            let at: Date = now.addingTimeInterval(Double(-i * 900 - 3600 * 5))
            let ok: Bool = i % 3 != 2
            var r = SplatSalmonRecord(id: "demo-s\(i)", at: at, stage: "シェケナダム", cleared: ok)
            r.clearWaves = ok ? 3 : 2
            r.dangerRate = 1.2 + Double(i % 4) * 0.4
            r.goldenEggs = 38 + (i * 11) % 30
            r.powerEggs = 1400 + (i * 230) % 900
            r.rescue = i % 3
            r.rescued = (i + 1) % 3
            r.weapons = ["スプラシューター", "バケットスロッシャー", "ノヴァブラスター"]
            salmon.append(r)
        }
        return SplatRecords(screenName: "sample", fetchedAt: now, battles: battles, salmon: salmon)
    }
}
