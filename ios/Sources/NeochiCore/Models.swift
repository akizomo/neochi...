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

    public init(id: String, title: String, genre: String, artworkURL: URL? = nil, linkURL: URL? = nil,
                appleURL: URL? = nil, star: Double? = nil, rank: ZRank? = nil) {
        self.id = id; self.title = title; self.genre = genre; self.artworkURL = artworkURL
        self.linkURL = linkURL; self.appleURL = appleURL; self.star = star; self.rank = rank
    }
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
    /// 程よい興味。0〜100の10刻み。
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
