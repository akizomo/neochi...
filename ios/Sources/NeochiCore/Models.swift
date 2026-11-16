import Foundation

/// 番組。お気に入りは番組単位。
public struct Show: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var title: String
    public var genre: String
    public var artworkURL: URL?
    public var linkURL: URL?
    public var appleURL: URL?
    /// 総合評点(1.0〜5.0)。AI解析を土台に、実測とみんなの評価を足したもの。解析前は nil。
    public var star: Double?
    /// 寝落ち格付け(総合評点で決まる)。基準未満の番組は掲載しない。
    public var rank: ZRank?
    /// AIの一行(一覧に出す)。
    public var oneLiner: String?
    /// 実測の平均(分)。実測がなければ nil。
    public var avgMinutes: Int?
    public var aspects: ShowAspects?
    public var stats: ShowStats?

    public init(id: String, title: String, genre: String, artworkURL: URL? = nil, linkURL: URL? = nil,
                appleURL: URL? = nil, star: Double? = nil, rank: ZRank? = nil,
                oneLiner: String? = nil, avgMinutes: Int? = nil, aspects: ShowAspects? = nil, stats: ShowStats? = nil) {
        self.id = id; self.title = title; self.genre = genre; self.artworkURL = artworkURL
        self.linkURL = linkURL; self.appleURL = appleURL; self.star = star; self.rank = rank
        self.oneLiner = oneLiner; self.avgMinutes = avgMinutes; self.aspects = aspects; self.stats = stats
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

/// 自己申告の答え。ヘルスケアに睡眠の記録がない朝に、分数ではなく4つの選択肢で聞く。
/// 内部では、おおよその分数(`minutes`)に直して保存する。自己申告は実測とは別の行(source = self)で、
/// 番組の評点・格付けの集計には入れない(Z ランクは source = watch だけで集計する)。
public enum SelfReportLatency: String, Codable, CaseIterable, Sendable {
    case quick, short, long, never

    /// 選択肢の言葉。
    public var label: String {
        switch self {
        case .quick: return "すぐ寝た"
        case .short: return "少し起きていた"
        case .long: return "なかなか寝つけなかった"
        case .never: return "最後まで聴いた"
        }
    }
    /// 選択肢の下の目安。
    public var hint: String {
        switch self {
        case .quick: return "10分くらいまで"
        case .short: return "10〜20分くらい"
        case .long: return "20〜30分くらい"
        case .never: return "30分以上"
        }
    }
    /// 保存する、おおよその分数(帯の真ん中あたり。最後の帯は 40)。
    public var minutes: Int {
        switch self { case .quick: return 5; case .short: return 15; case .long: return 25; case .never: return 40 }
    }
}

/// 1晩の記録。実測(watch)と自己申告(self)は別の行で保存する。
public struct SleepLog: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let episodeID: String
    public let showID: String
    public var startedAt: Date
    public var sleepOnsetAt: Date?
    public var source: SleepSource
    /// 引き込み力の10段階(1〜10。DB の `interest_rating`)。意味とゾーンは `NCString.interestZone`。
    public var interestRating: Int?
    /// 10段階の導入前の3択(-1 退屈だった / 0 ちょうどよかった / 1 聴き入った)。端末に残る古い記録の読み込み用で、新しくは書かない。
    public var interestVote: Int?
    /// 起伏の少なさ。1〜5。
    public var calmVote: Int?
    public var note: String?
    /// 自己申告の答え(source = self のときだけ)。
    public var selfReport: SelfReportLatency?
    /// その回を何回目に聴いたか。番組の実績は1回目だけで集計する。
    public var listenNo: Int

    public init(id: String, episodeID: String, showID: String, startedAt: Date, sleepOnsetAt: Date? = nil,
                source: SleepSource = .watch, interestRating: Int? = nil, interestVote: Int? = nil, calmVote: Int? = nil,
                note: String? = nil, listenNo: Int = 1, selfReport: SelfReportLatency? = nil) {
        self.id = id; self.episodeID = episodeID; self.showID = showID; self.startedAt = startedAt
        self.sleepOnsetAt = sleepOnsetAt; self.source = source; self.interestRating = interestRating; self.interestVote = interestVote
        self.calmVote = calmVote; self.note = note; self.listenNo = listenNo; self.selfReport = selfReport
    }

    /// 送信する、寝落ちまでの分。実測はそのまま、自己申告は選択肢のおおよその分数。
    public var uploadLatencyMinutes: Int? { latencyMinutes ?? selfReport?.minutes }

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
