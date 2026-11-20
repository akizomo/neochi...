import Foundation

/// 🎧 の内訳(各 1.0〜5.0)。
public struct EarParts: Hashable, Codable, Sendable {
    public var rate: Double?
    public var rateCV: Double?
    public var volume: Double?
    public var sudden: Double?
    public init(rate: Double? = nil, rateCV: Double? = nil, volume: Double? = nil, sudden: Double? = nil) {
        self.rate = rate; self.rateCV = rateCV; self.volume = volume; self.sudden = sudden
    }
}

/// 冒頭20分の中の、起伏の山。level は 1 = 少し、2 = 多い(古い解析には無い)。
public struct Moment: Hashable, Codable, Sendable {
    public var minute: Int
    public var note: String
    public var level: Int?
    public init(minute: Int, note: String, level: Int? = nil) { self.minute = minute; self.note = note; self.level = level }
}

/// 🎯 / 🌊 の採点項目ひとつぶん。score は 0〜2、minute は根拠になった分(なければ nil)。
public struct ScoredItem: Hashable, Codable, Sendable {
    public var key: String
    public var score: Int
    public var minute: Int?
    public init(key: String, score: Int, minute: Int? = nil) { self.key = key; self.score = score; self.minute = minute }
}

/// 🎯の観察の1件(分と引用)。1つの分は fromMinute == toMinute。
public struct InterestObservation: Hashable, Codable, Sendable {
    public var fromMinute: Int
    public var toMinute: Int
    public var quote: String
    public init(fromMinute: Int, toMinute: Int, quote: String) {
        self.fromMinute = fromMinute; self.toMinute = toMinute; self.quote = quote
    }
}

public extension Array where Element == InterestObservation {
    /// 観察がおおう分の数(重なりは1回)。
    var coveredMinutes: Int {
        var minutes = Set<Int>()
        for o in self where o.fromMinute <= o.toMinute { for m in o.fromMinute...o.toMinute { minutes.insert(m) } }
        return minutes.count
    }
}

/// 🎯(程よい興味)の観察。観察で判定した回だけにある(旧の判定の回は nil。`neochi/observe.py`)。
public struct InterestObservations: Hashable, Codable, Sendable {
    /// 先を引っぱる場面。
    public var hook: [InterestObservation]
    /// 前を覚えていないと分からない筋。
    public var follow: [InterestObservation]
    /// 思い浮かぶ具体的な話。
    public var imagery: [InterestObservation]
    public init(hook: [InterestObservation] = [], follow: [InterestObservation] = [], imagery: [InterestObservation] = []) {
        self.hook = hook; self.follow = follow; self.imagery = imagery
    }
}

/// 1回ぶんの解析(★と、根拠になったデータ)。無い項目は nil(古い解析には timeline などがない)。
public struct EpisodeAnalysis: Hashable, Codable, Sendable {
    public var episodeID: String
    public var finalStar: Double?
    public var calmStar: Double?
    public var earStar: Double?
    public var interest: InterestLevel?
    /// 🎯 のゾーン(1〜10)。
    public var interestScore: Int?
    /// 🌊🎯 の根拠の一行(60字以内)。
    public var reason: String?
    public var inputDepth: String?
    public var durationSec: Double?
    public var earParts: EarParts?
    /// 話す速さ(字/分)・ばらつき・音量の変化(dB)・突発音(回/10分)。
    public var speechRate: Double?
    /// 1分ごとの話す速さの変動係数(0.10 で満点、0.40 で最低)。
    public var speechRateCV: Double?
    /// 🎯 引き込み力(A〜E)と 🌊 起伏(A〜D)の、項目ごとの点。
    public var interestItems: [ScoredItem]
    public var calmItems: [ScoredItem]
    public var volumeStdDB: Double?
    public var suddenPer10Min: Double?
    /// 1分ごと。話す速さは冒頭20分、音量は冒頭30分。無い分は nil。
    public var ratePerMin: [Double?]
    public var volumePerMin: [Double?]
    public var suddenAtSec: [Int]
    public var moments: [Moment]
    /// 冒頭20分の、1分ごとの起伏の強さ(0〜2)。古い解析は空。
    public var calmPerMin: [Double] = []
    /// 内容の要約(120字以内)。古い解析は nil。
    public var contentSummary: String?
    /// 🎯の観察(分と引用)。観察で判定した回だけ。旧の判定の回は nil で、interestScore と interestItems を使う。
    public var interestObs: InterestObservations?

    public init(episodeID: String, finalStar: Double? = nil, calmStar: Double? = nil, earStar: Double? = nil,
                interest: InterestLevel? = nil, interestScore: Int? = nil, reason: String? = nil,
                inputDepth: String? = nil, durationSec: Double? = nil, earParts: EarParts? = nil,
                speechRate: Double? = nil, speechRateCV: Double? = nil, volumeStdDB: Double? = nil, suddenPer10Min: Double? = nil,
                interestItems: [ScoredItem] = [], calmItems: [ScoredItem] = [],
                ratePerMin: [Double?] = [], volumePerMin: [Double?] = [], suddenAtSec: [Int] = [], moments: [Moment] = []) {
        self.episodeID = episodeID; self.finalStar = finalStar; self.calmStar = calmStar; self.earStar = earStar
        self.interest = interest; self.interestScore = interestScore; self.reason = reason
        self.inputDepth = inputDepth; self.durationSec = durationSec; self.earParts = earParts
        self.speechRate = speechRate; self.speechRateCV = speechRateCV; self.volumeStdDB = volumeStdDB
        self.suddenPer10Min = suddenPer10Min; self.interestItems = interestItems; self.calmItems = calmItems
        self.ratePerMin = ratePerMin; self.volumePerMin = volumePerMin; self.suddenAtSec = suddenAtSec; self.moments = moments
    }

    /// 起伏と興味の両方を判定済みか。番組の評点・格付け・最近の回の棒には、判定済みの回だけを使う
    /// (`neochi/scoring.py` の is_judged と同じ)。
    public var isJudged: Bool { calmStar != nil && (interestScore != nil || interest != nil) }

    /// 画面に出す評点。起伏と興味の判定が済むまでは出さない(耳のゆるさだけの点は高く出やすい。docs/SCORE.md §1)。
    public var shownStar: Double? { isJudged ? finalStar : nil }

    /// 観点ごとの根拠に出せるものがあるか(説明文だけの解析には無い)。
    public var hasAnyAspect: Bool { calmStar != nil || earStar != nil || interest != nil }

    /// 観点別の★の平均(番組の一覧・詳細で使う)。
    public static func aspects(_ list: [EpisodeAnalysis]) -> ShowAspects {
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return ShowAspects(calmStar: avg(list.compactMap(\.calmStar)), earStar: avg(list.compactMap(\.earStar)),
                           interest: list.compactMap(\.interest).first)
    }
}

/// 番組の実績の点(1晩ぶん。日付と分数だけ)。
public struct SleepPoint: Hashable, Codable, Sendable {
    public var night: Date
    public var minutes: Int
    public init(night: Date, minutes: Int) { self.night = night; self.minutes = minutes }
}

/// 番組の実績(みんなの実測の集計)。30分より前に寝落ちした回数で見せる。
public struct ShowStats: Hashable, Codable, Sendable {
    public var count: Int
    public var avgMinutes: Int
    public var minMinutes: Int
    public var maxMinutes: Int
    public var under30: Int
    public init(count: Int, avgMinutes: Int, minMinutes: Int, maxMinutes: Int, under30: Int) {
        self.count = count; self.avgMinutes = avgMinutes; self.minMinutes = minMinutes
        self.maxMinutes = maxMinutes; self.under30 = under30
    }
}
