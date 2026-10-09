import Foundation

// 公開データの読み込み（ログイン不要・キー不要）
// - splatoon3.ink：https://splatoon3.ink/data/schedules.json・festivals.json・locale/ja-JP.json
// - stat.ink：https://stat.ink/@<スクリーンネーム>/spl3/index.json（バトル）・/salmon3.json（サーモンラン）
// 読み方はゆるくする：項目はすべて省略可能、知らないモードや壊れた要素は飛ばす。

enum SplatAPIError: Error {
    case notFound
    case http(Int)
    case badData
}

enum SplatAPI {
    static let userAgent = "Hiyori iOS app (personal)"

    static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, res) = try await URLSession.shared.data(for: req)
        let code = (res as? HTTPURLResponse)?.statusCode ?? 200
        if code == 404 { throw SplatAPIError.notFound }
        guard (200..<300).contains(code) else { throw SplatAPIError.http(code) }
        return data
    }

    // MARK: ステージ情報

    static func fetchSchedule() async throws -> SplatSchedule {
        let base = "https://splatoon3.ink/data/"
        guard let sURL = URL(string: base + "schedules.json"),
              let lURL = URL(string: base + "locale/ja-JP.json"),
              let fURL = URL(string: base + "festivals.json") else { throw SplatAPIError.badData }
        async let sData = get(sURL)
        async let lData = try? get(lURL)
        async let fData = try? get(fURL)
        let schedules = try await sData
        let locale = await lData
        let fests = await fData
        return try await Task.detached(priority: .userInitiated) {
            try SplatAPI.parseSchedule(schedules, locale: locale, festivals: fests)
        }.value
    }

    static func parseSchedule(_ data: Data, locale: Data?, festivals: Data?, now: Date = .now) throws -> SplatSchedule {
        let dec = JSONDecoder()
        guard let root = try? dec.decode(RawSchedRoot.self, from: data), let d = root.data else { throw SplatAPIError.badData }
        let loc = locale.flatMap { try? dec.decode(SplatLocale.self, from: $0) } ?? SplatLocale()
        var rotations: [SplatRotation] = []

        func stages(_ list: [SplatLossy<RawStage>]?) -> [SplatStage] {
            (list ?? []).compactMap(\.value).map { s in
                SplatStage(name: loc.name("stages", s.id) ?? s.name ?? "？", image: s.image?.url)
            }
        }
        func add(_ mode: SplatMode, _ setting: RawVsSetting?, _ start: Date?, _ end: Date?) {
            guard let setting, let start, let end else { return }
            let key = setting.vsRule?.rule ?? ""
            let rule = loc.name("rules", setting.vsRule?.id) ?? SplatRuleNames.name(key) ?? setting.vsRule?.name ?? "？"
            rotations.append(SplatRotation(mode: mode, rule: rule, ruleKey: key, start: start, end: end, stages: stages(setting.vsStages)))
        }

        for n in d.regularSchedules?.items ?? [] {
            add(.regular, n.regularMatchSetting, n.start, n.end)
        }
        for n in d.bankaraSchedules?.items ?? [] {
            for s in (n.bankaraMatchSettings?.items ?? []) {
                switch s.bankaraMode {
                case "CHALLENGE": add(.bankaraChallenge, s, n.start, n.end)
                case "OPEN": add(.bankaraOpen, s, n.start, n.end)
                default: break
                }
            }
        }
        for n in d.xSchedules?.items ?? [] {
            add(.x, n.xMatchSetting, n.start, n.end)
        }
        for n in d.festSchedules?.items ?? [] {
            for s in (n.festMatchSettings?.items ?? []) {
                switch s.festMode {
                case "REGULAR": add(.festOpen, s, n.start, n.end)
                case "CHALLENGE": add(.festChallenge, s, n.start, n.end)
                default: break
                }
            }
        }
        for n in d.eventSchedules?.items ?? [] {
            guard let s = n.leagueMatchSetting else { continue }
            let ev = s.leagueMatchEvent
            let evName = loc.name("events", ev?.id) ?? ev?.name ?? "イベントマッチ"
            let evDesc = loc.desc("events", ev?.id) ?? ev?.desc
            let key = s.vsRule?.rule ?? ""
            let rule = loc.name("rules", s.vsRule?.id) ?? SplatRuleNames.name(key) ?? s.vsRule?.name ?? "？"
            for p in (n.timePeriods?.items ?? []) {
                guard let st = SplatDate.parse(p.startTime), let en = SplatDate.parse(p.endTime) else { continue }
                rotations.append(SplatRotation(mode: .event, rule: rule, ruleKey: key, start: st, end: en,
                                               stages: stages(s.vsStages), eventName: evName, eventDesc: evDesc))
            }
        }

        var salmon: [SplatSalmonShift] = []
        let coop = d.coopGroupingSchedule
        let groups: [(String, RawNodes<RawCoopNode>?)] = [("通常", coop?.regularSchedules),
                                                          ("ビッグラン", coop?.bigRunSchedules),
                                                          ("バイトチームコンテスト", coop?.teamContestSchedules)]
        for (kind, nodes) in groups {
            for n in nodes?.items ?? [] {
                guard let st = n.start, let en = n.end, let setting = n.setting else { continue }
                let cs = setting.coopStage
                let stage = SplatStage(name: loc.name("stages", cs?.id) ?? cs?.name ?? "？",
                                       image: cs?.thumbnailImage?.url ?? cs?.image?.url)
                let weapons: [SplatStage] = (setting.weapons?.items ?? []).map { w in
                    let name = loc.name("weapons", w.inkID) ?? ((w.name == "Random" || w.name == nil) ? "ランダム" : w.name!)
                    return SplatStage(name: name, image: w.image?.url)
                }
                let boss = loc.name("bosses", setting.boss?.id) ?? setting.boss?.name
                salmon.append(SplatSalmonShift(kind: kind, start: st, end: en, stage: stage, weapons: weapons, boss: boss))
            }
        }
        salmon.sort { $0.start < $1.start }

        let fest = festivals.flatMap { parseFest($0, now: now) }
        return SplatSchedule(fetchedAt: now, rotations: rotations, salmon: salmon, fest: fest)
    }

    /// 日本のフェス：開催前・開催中、または終わって3日以内のもの
    static func parseFest(_ data: Data, now: Date = .now) -> SplatFest? {
        guard let root = try? JSONDecoder().decode(RawFestRoot.self, from: data) else { return nil }
        let nodes = root.JP?.data?.festRecords?.items ?? []
        let fests: [SplatFest] = nodes.compactMap { n in
            guard let st = SplatDate.parse(n.startTime), let en = SplatDate.parse(n.endTime) else { return nil }
            let teams: [SplatFestTeam] = (n.teams?.items ?? []).map { t in
                SplatFestTeam(name: t.teamName ?? "？", r: t.color?.r ?? 0.5, g: t.color?.g ?? 0.5, b: t.color?.b ?? 0.5,
                              winner: t.result?.isWinner)
            }
            return SplatFest(title: n.title ?? "フェス", start: st, end: en, state: n.state ?? "", image: n.image?.url, teams: teams)
        }
        let open = fests.filter { !$0.isClosed && $0.end > now }.sorted { $0.start < $1.start }
        if let f = open.first { return f }
        let recent = fests.filter { $0.end <= now && now.timeIntervalSince($0.end) < 3 * 86400 }.sorted { $0.end > $1.end }
        return recent.first
    }

    // MARK: 戦績（stat.ink）

    /// stat.ink のスクリーンネームとして使える形にする（@ を外し、英数字と _ だけ）
    static func cleanScreenName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "stat.ink/@") { s = String(s[r.upperBound...]) }
        if s.hasPrefix("@") { s.removeFirst() }
        let allowed = s.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        return String(allowed.prefix(30))
    }

    static func fetchRecords(screenName: String) async throws -> SplatRecords {
        let name = cleanScreenName(screenName)
        guard !name.isEmpty,
              let bURL = URL(string: "https://stat.ink/@\(name)/spl3/index.json"),
              let sURL = URL(string: "https://stat.ink/@\(name)/salmon3.json") else { throw SplatAPIError.notFound }
        async let bData = get(bURL)
        async let sData = try? get(sURL)
        let battlesData = try await bData
        let salmonData = await sData
        return try await Task.detached(priority: .userInitiated) {
            try SplatAPI.parseRecords(name: name, battles: battlesData, salmon: salmonData)
        }.value
    }

    static func parseRecords(name: String, battles: Data, salmon: Data?, now: Date = .now) throws -> SplatRecords {
        let dec = JSONDecoder()
        guard let raw = try? dec.decode([SplatLossy<RawBattle>].self, from: battles) else { throw SplatAPIError.badData }
        let list: [SplatBattle] = raw.compactMap(\.value).compactMap { b in
            guard let id = b.uuid ?? b.id else { return nil }
            let at = (b.start_at?.time ?? b.end_at?.time).map { Date(timeIntervalSince1970: $0) } ?? now
            return SplatBattle(
                id: id, at: at, result: b.result ?? "",
                lobbyKey: b.lobby?.key ?? "", lobby: b.lobby?.name?.ja ?? "",
                rule: b.rule?.name?.ja ?? "", stage: b.stage?.name?.ja ?? "？", weapon: b.weapon?.name?.ja ?? "？",
                kill: b.kill?.int, assist: b.assist?.int, death: b.death?.int, special: b.special?.int,
                inked: b.inked?.int, knockout: b.knockout)
        }
        var shifts: [SplatSalmonRecord] = []
        if let salmon, let rawS = try? dec.decode([SplatLossy<RawSalmon>].self, from: salmon) {
            shifts = rawS.compactMap(\.value).compactMap { s in
                guard let id = s.uuid ?? s.id else { return nil }
                let at = (s.start_at?.time ?? s.end_at?.time).map { Date(timeIntervalSince1970: $0) } ?? now
                let me = (s.players?.items ?? []).first { $0.me == true }
                let waves = (s.eggstra_work == true) ? 5 : 3
                let clear = s.clear_waves?.int
                let kind: String? = s.eggstra_work == true ? "バイトチームコンテスト" : (s.big_run == true ? "ビッグラン" : nil)
                return SplatSalmonRecord(
                    id: id, at: at, stage: s.stage?.name?.ja ?? s.big_stage?.name?.ja ?? "？",
                    cleared: (clear ?? 0) >= waves, clearWaves: clear, waves: waves, dangerRate: s.danger_rate?.value,
                    goldenEggs: s.golden_eggs?.int, powerEggs: s.power_eggs?.int,
                    rescue: me?.rescue?.int, rescued: me?.rescued?.int,
                    weapons: (me?.weapons?.items ?? []).compactMap { $0.name?.ja }, kind: kind)
            }
        }
        let sortedB = list.sorted { $0.at > $1.at }
        let sortedS = shifts.sorted { $0.at > $1.at }
        return SplatRecords(screenName: name, fetchedAt: now, battles: Array(sortedB.prefix(50)), salmon: Array(sortedS.prefix(20)))
    }
}

// MARK: - 補助

enum SplatRuleNames {
    static func name(_ key: String) -> String? {
        switch key {
        case "TURF_WAR": return "ナワバリバトル"
        case "AREA": return "ガチエリア"
        case "LOFT": return "ガチヤグラ"
        case "GOAL": return "ガチホコバトル"
        case "CLAM": return "ガチアサリ"
        case "TRI_COLOR": return "トリカラバトル"
        default: return nil
        }
    }
}

enum SplatDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return plain.date(from: s) ?? withFraction.date(from: s)
    }
}

/// 壊れた要素があっても配列全体を捨てない
private struct SplatLossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// 配列（または1つだけ・null）を受け付ける
private struct SplatLossyList<T: Decodable>: Decodable {
    let items: [T]
    init(from decoder: Decoder) throws {
        if let arr = try? [SplatLossy<T>](from: decoder) {
            items = arr.compactMap(\.value)
        } else if let one = try? T(from: decoder) {
            items = [one]
        } else {
            items = []
        }
    }
}

/// 数値（文字列で来ることもある）
private struct SplatFlexNum: Decodable {
    let value: Double?
    var int: Int? { value.map { Int($0.rounded()) } }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// splatoon3.ink の日本語の名前（stages・rules・weapons・bosses・events を id で引く）
struct SplatLocale: Decodable {
    var names: [String: [String: String]] = [:]
    var descs: [String: [String: String]] = [:]

    init() {}

    private struct Entry: Decodable {
        let name: String?
        let title: String?
        let desc: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for table in c.allKeys {
            guard let sub = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: table) else { continue }
            var n: [String: String] = [:]
            var d: [String: String] = [:]
            for id in sub.allKeys {
                guard let e = try? sub.decode(Entry.self, forKey: id) else { continue }
                if let v = e.name ?? e.title { n[id.stringValue] = v }
                if let v = e.desc { d[id.stringValue] = v }
            }
            names[table.stringValue] = n
            descs[table.stringValue] = d
        }
    }

    func name(_ table: String, _ id: String?) -> String? {
        guard let id else { return nil }
        return names[table]?[id]
    }

    func desc(_ table: String, _ id: String?) -> String? {
        guard let id else { return nil }
        return descs[table]?[id]
    }
}

// MARK: - splatoon3.ink の元の形

private struct RawSchedRoot: Decodable { let data: RawSchedData? }

private struct RawNodes<T: Decodable>: Decodable {
    let nodes: SplatLossyList<T>?
    var items: [T] { nodes?.items ?? [] }
}

private struct RawSchedData: Decodable {
    let regularSchedules: RawNodes<RawVsNode>?
    let bankaraSchedules: RawNodes<RawVsNode>?
    let xSchedules: RawNodes<RawVsNode>?
    let eventSchedules: RawNodes<RawEventNode>?
    let festSchedules: RawNodes<RawVsNode>?
    let coopGroupingSchedule: RawCoop?
}

private struct RawImage: Decodable { let url: String? }

private struct RawStage: Decodable {
    let id: String?
    let name: String?
    let image: RawImage?
}

private struct RawRule: Decodable {
    let id: String?
    let rule: String?
    let name: String?
}

private struct RawVsSetting: Decodable {
    let vsStages: [SplatLossy<RawStage>]?
    let vsRule: RawRule?
    let bankaraMode: String?
    let festMode: String?
}

private struct RawVsNode: Decodable {
    let startTime: String?
    let endTime: String?
    let regularMatchSetting: RawVsSetting?
    let bankaraMatchSettings: SplatLossyList<RawVsSetting>?
    let xMatchSetting: RawVsSetting?
    let festMatchSettings: SplatLossyList<RawVsSetting>?

    var start: Date? { SplatDate.parse(startTime) }
    var end: Date? { SplatDate.parse(endTime) }
}

private struct RawLeagueEvent: Decodable {
    let id: String?
    let name: String?
    let desc: String?
}

private struct RawLeagueSetting: Decodable {
    let leagueMatchEvent: RawLeagueEvent?
    let vsStages: [SplatLossy<RawStage>]?
    let vsRule: RawRule?
}

private struct RawPeriod: Decodable {
    let startTime: String?
    let endTime: String?
}

private struct RawEventNode: Decodable {
    let leagueMatchSetting: RawLeagueSetting?
    let timePeriods: SplatLossyList<RawPeriod>?
}

private struct RawCoop: Decodable {
    let regularSchedules: RawNodes<RawCoopNode>?
    let bigRunSchedules: RawNodes<RawCoopNode>?
    let teamContestSchedules: RawNodes<RawCoopNode>?
}

private struct RawCoopStage: Decodable {
    let id: String?
    let name: String?
    let thumbnailImage: RawImage?
    let image: RawImage?
}

private struct RawCoopWeapon: Decodable {
    let inkID: String?
    let name: String?
    let image: RawImage?
    enum CodingKeys: String, CodingKey {
        case inkID = "__splatoon3ink_id"
        case name, image
    }
}

private struct RawBoss: Decodable {
    let id: String?
    let name: String?
}

private struct RawCoopSetting: Decodable {
    let coopStage: RawCoopStage?
    let weapons: SplatLossyList<RawCoopWeapon>?
    let boss: RawBoss?
}

private struct RawCoopNode: Decodable {
    let startTime: String?
    let endTime: String?
    let setting: RawCoopSetting?

    var start: Date? { SplatDate.parse(startTime) }
    var end: Date? { SplatDate.parse(endTime) }
}

private struct RawFestRoot: Decodable { let JP: RawFestRegion? }
private struct RawFestRegion: Decodable { let data: RawFestData? }
private struct RawFestData: Decodable { let festRecords: RawNodes<RawFest>? }

private struct RawFestColor: Decodable {
    let r: Double?
    let g: Double?
    let b: Double?
}

private struct RawFestResult: Decodable { let isWinner: Bool? }

private struct RawFestTeam: Decodable {
    let teamName: String?
    let color: RawFestColor?
    let result: RawFestResult?
}

private struct RawFest: Decodable {
    let title: String?
    let startTime: String?
    let endTime: String?
    let state: String?
    let image: RawImage?
    let teams: SplatLossyList<RawFestTeam>?
}

// MARK: - stat.ink の元の形（自分の記録に要る項目だけ読む。ほかの人の名前などは読まない）

private struct RawName: Decodable {
    let ja: String?
    let en: String?
    enum CodingKeys: String, CodingKey {
        case ja = "ja_JP"
        case en = "en_US"
    }
}

private struct RawKeyed: Decodable {
    let key: String?
    let name: RawLocalized?
}

/// { "ja_JP": "…", "en_US": "…" } の日本語（なければ英語）
private struct RawLocalized: Decodable {
    let ja: String?
    init(from decoder: Decoder) throws {
        let n = try? RawName(from: decoder)
        ja = n?.ja ?? n?.en
    }
}

private struct RawTime: Decodable { let time: Double? }

private struct RawBattle: Decodable {
    let id: String?
    let uuid: String?
    let lobby: RawKeyed?
    let rule: RawKeyed?
    let stage: RawKeyed?
    let weapon: RawKeyed?
    let result: String?
    let knockout: Bool?
    let kill: SplatFlexNum?
    let assist: SplatFlexNum?
    let death: SplatFlexNum?
    let special: SplatFlexNum?
    let inked: SplatFlexNum?
    let start_at: RawTime?
    let end_at: RawTime?
}

private struct RawSalmonPlayer: Decodable {
    let me: Bool?
    let rescue: SplatFlexNum?
    let rescued: SplatFlexNum?
    let weapons: SplatLossyList<RawKeyed>?
}

private struct RawSalmon: Decodable {
    let id: String?
    let uuid: String?
    let big_run: Bool?
    let eggstra_work: Bool?
    let stage: RawKeyed?
    let big_stage: RawKeyed?
    let danger_rate: SplatFlexNum?
    let clear_waves: SplatFlexNum?
    let golden_eggs: SplatFlexNum?
    let power_eggs: SplatFlexNum?
    let players: SplatLossyList<RawSalmonPlayer>?
    let start_at: RawTime?
    let end_at: RawTime?
}
