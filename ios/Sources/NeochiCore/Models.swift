import Foundation

/// 番組。お気に入りは番組単位。
public struct Show: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var title: String
    public var genre: String
    public var artworkURL: URL?
    public var linkURL: URL?
    public var appleURL: URL?
    /// AI解析の最終★(1.0〜5.0)。解析前は nil。
    public var star: Double?
    /// 掲載ランク(実測の集計)。実測がなければ nil(調査中)。
    public var rank: ZRank?
    /// AIの一行(一覧に出す)。
    public var oneLiner: String?
    /// 実測の平均(分)。実測がなければ nil。
    public var avgMinutes: Int?
    public var aspects: ShowAspects?

    public init(id: String, title: String, genre: String, artworkURL: URL? = nil, linkURL: URL? = nil,
                appleURL: URL? = nil, star: Double? = nil, rank: ZRank? = nil,
                oneLiner: String? = nil, avgMinutes: Int? = nil, aspects: ShowAspects? = nil) {
        self.id = id; self.title = title; self.genre = genre; self.artworkURL = artworkURL
        self.linkURL = linkURL; self.appleURL = appleURL; self.star = star; self.rank = rank
        self.oneLiner = oneLiner; self.avgMinutes = avgMinutes; self.aspects = aspects
    }
}

/// 観点ごとのAI解析(番組の各回の平均)。合算した★とは別に見せる。
public struct ShowAspects: Hashable, Codable, Sendable {
    /// 起伏の少なさ(1.0〜5.0)。
    public var calmStar: Double?
    /// 耳ざわり(1.0〜5.0)。
    public var earStar: Double?
    /// 程よい興味の水準。
    public var interest: InterestLevel?
    public init(calmStar: Double? = nil, earStar: Double? = nil, interest: InterestLevel? = nil) {
        self.calmStar = calmStar; self.earStar = earStar; self.interest = interest
    }
}

public enum InterestLevel: String, Codable, Sendable { case low, mid, high }

/// 朝の振り返りの「この回の話は、どうでしたか」(3択)。値は DB の `interest_vote`(-1 / 0 / 1)と同じ。
public enum InterestAnswer: Int, CaseIterable, Identifiable, Sendable {
    case bored = -1, justRight = 0, absorbed = 1
    public var id: Int { rawValue }
}

public enum ZRank: String, Codable, Sendable { case z = "Z", zz = "ZZ", zzz = "ZZZ" }

/// 回。`number` は「第N回」の N。なければ公開日の順で並べる。
public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let showID: String
    public var title: String
    public var number: Int?
    public var publishedAt: Date?
    public var durationSec: Int?
    public var audioURL: URL?
    public var linkURL: URL?

    public init(id: String, showID: String, title: String, number: Int? = nil, publishedAt: Date? = nil,
                durationSec: Int? = nil, audioURL: URL? = nil, linkURL: URL? = nil) {
        self.id = id; self.showID = showID; self.title = title; self.number = number
        self.publishedAt = publishedAt; self.durationSec = durationSec; self.audioURL = audioURL; self.linkURL = linkURL
    }
}

public enum SleepSource: String, Codable, Sendable { case watch, selfReport = "self" }

/// 1晩の記録。実測(watch)と自己申告(self)は別の行で保存する。
public struct SleepLog: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let episodeID: String
    public let showID: String
    public var startedAt: Date
    public var sleepOnsetAt: Date?
    public var source: SleepSource
    /// 程よい興味の3択。-1 = 退屈だった、0 = ちょうどよかった、1 = 聴き入った(`InterestAnswer`)。
    public var interestVote: Int?
    /// 起伏の少なさ。1〜5。
    public var calmVote: Int?
    public var note: String?
    /// その回を何回目に聴いたか。番組の実績は1回目だけで集計する。
    public var listenNo: Int

    public init(id: String, episodeID: String, showID: String, startedAt: Date, sleepOnsetAt: Date? = nil,
                source: SleepSource = .watch, interestVote: Int? = nil, calmVote: Int? = nil,
                note: String? = nil, listenNo: Int = 1) {
        self.id = id; self.episodeID = episodeID; self.showID = showID; self.startedAt = startedAt
        self.sleepOnsetAt = sleepOnsetAt; self.source = source; self.interestVote = interestVote
        self.calmVote = calmVote; self.note = note; self.listenNo = listenNo
    }

    /// 寝落ちまでの分(整数)。入眠が不明なら nil。
    public var latencyMinutes: Int? {
        guard let onset = sleepOnsetAt else { return nil }
        return max(0, Int((onset.timeIntervalSince(startedAt) / 60).rounded()))
    }
}

/// 再生の記録(端末内)。回ごとの再生回数と、いまの番組の判断に使う。
public struct PlayRecord: Hashable, Codable, Sendable {
    public let episodeID: String
    public let showID: String
    public let playedAt: Date
    public init(episodeID: String, showID: String, playedAt: Date) {
        self.episodeID = episodeID; self.showID = showID; self.playedAt = playedAt
    }
}
