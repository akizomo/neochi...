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

/// 冒頭20分の中の、目立つ箇所。
public struct Moment: Hashable, Codable, Sendable {
    public var minute: Int
    public var note: String
    public init(minute: Int, note: String) { self.minute = minute; self.note = note }
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
    public var volumeStdDB: Double?
    public var suddenPer10Min: Double?
    /// 1分ごと。話す速さは冒頭20分、音量は全編。無い分は nil。
    public var ratePerMin: [Double?]
    public var volumePerMin: [Double?]
    public var suddenAtSec: [Int]
    public var moments: [Moment]

    public init(episodeID: String, finalStar: Double? = nil, calmStar: Double? = nil, earStar: Double? = nil,
                interest: InterestLevel? = nil, interestScore: Int? = nil, reason: String? = nil,
                inputDepth: String? = nil, durationSec: Double? = nil, earParts: EarParts? = nil,
                speechRate: Double? = nil, volumeStdDB: Double? = nil, suddenPer10Min: Double? = nil,
                ratePerMin: [Double?] = [], volumePerMin: [Double?] = [], suddenAtSec: [Int] = [], moments: [Moment] = []) {
        self.episodeID = episodeID; self.finalStar = finalStar; self.calmStar = calmStar; self.earStar = earStar
        self.interest = interest; self.interestScore = interestScore; self.reason = reason
        self.inputDepth = inputDepth; self.durationSec = durationSec; self.earParts = earParts
        self.speechRate = speechRate; self.volumeStdDB = volumeStdDB; self.suddenPer10Min = suddenPer10Min
        self.ratePerMin = ratePerMin; self.volumePerMin = volumePerMin; self.suddenAtSec = suddenAtSec; self.moments = moments
    }

    /// 観点別の★の平均(番組の一覧・詳細で使う)。
    public static func aspects(_ list: [EpisodeAnalysis]) -> ShowAspects {
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return ShowAspects(calmStar: avg(list.compactMap(\.calmStar)), earStar: avg(list.compactMap(\.earStar)),
                           interest: list.compactMap(\.interest).first)
    }
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
