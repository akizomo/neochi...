import Foundation

/// 昨夜の結果。実測(または自己申告)の分数。記録がなければ minutes は nil。
public struct LastNight: Hashable, Sendable {
    public let showID: String
    public let episodeID: String
    public let minutes: Int?
    public init(showID: String, episodeID: String, minutes: Int?) {
        self.showID = showID; self.episodeID = episodeID; self.minutes = minutes
    }
}

public struct TonightContext: Sendable {
    public var shows: [Show]
    /// 番組ごとの回。新しい順。判断に使うのは直近5回まで。
    public var episodes: [String: [Episode]]
    public var history: [PlayRecord]
    public var favorites: Set<String>
    /// 「次に聴く」の順番待ち。
    public var queue: [String]
    /// いまの番組(最後に再生した番組)。
    public var currentShowID: String?
    public var lastNight: LastNight?
    /// いまの番組のジャンルが、何晩続いているか。
    public var genreStreakNights: Int

    public init(shows: [Show], episodes: [String: [Episode]], history: [PlayRecord] = [],
                favorites: Set<String> = [], queue: [String] = [], currentShowID: String? = nil,
                lastNight: LastNight? = nil, genreStreakNights: Int = 0) {
        self.shows = shows; self.episodes = episodes; self.history = history; self.favorites = favorites
        self.queue = queue; self.currentShowID = currentShowID; self.lastNight = lastNight
        self.genreStreakNights = genreStreakNights
    }
}

public struct Candidate: Hashable, Sendable {
    public let show: Show
    /// 明日以降の「続きの回」は、今夜の結果で変わるので nil。
    public let episode: Episode?
    /// この再生が、その回の何回目か。2以上のときだけ「N回目」と出す。
    public let playCount: Int
    public let reason: Reason
}

/// 今夜の3つを決める。1つの指標の上位3件ではなく、尺度の違う3本(安心→変化→冒険)。
public enum TonightEngine {
    /// 3回聴いたら飽きる。3回に達した回は候補から外す。
    public static let playCap = 3
    /// 昨夜この分数より前に寝落ちできていたら、同じ回をもう一度。
    public static let fastThresholdMinutes = 30
    static let recentEpisodes = 5

    public static func playCounts(_ history: [PlayRecord]) -> [String: Int] {
        history.reduce(into: [:]) { $0[$1.episodeID, default: 0] += 1 }
    }

    /// 番組の最後に再生した回。
    public static func lastPlayedEpisodeID(show: String, history: [PlayRecord]) -> String? {
        history.filter { $0.showID == show }.max(by: { $0.playedAt < $1.playedAt })?.episodeID
    }

    private static func recent(_ show: Show, _ ctx: TonightContext) -> [Episode] {
        Array((ctx.episodes[show.id] ?? []).prefix(recentEpisodes))
    }

    private static func lastMinutes(for show: Show, _ ctx: TonightContext) -> Int? {
        ctx.lastNight?.showID == show.id ? ctx.lastNight?.minutes : nil
    }

    /// 番組の「今夜の回」。昨夜30分未満で寝落ちできた回は、3回目まで同じ回。
    /// そうでなければ、3回未満の回のうち新しい順(未聴を優先)。記録がなければ次へ進める。
    public static func pick(show: Show, ctx: TonightContext) -> (episode: Episode, playCount: Int)? {
        let eps = recent(show, ctx)
        guard !eps.isEmpty else { return nil }
        let counts = playCounts(ctx.history)
        let last = lastPlayedEpisodeID(show: show.id, history: ctx.history)
        if let last, let m = lastMinutes(for: show, ctx), m < fastThresholdMinutes,
           counts[last, default: 0] < playCap, let same = eps.first(where: { $0.id == last }) {
            return (same, counts[last, default: 0] + 1)
        }
        let rest = eps.filter { counts[$0.id, default: 0] < playCap && $0.id != last }
        let chosen = rest.first(where: { counts[$0.id, default: 0] == 0 }) ?? rest.first ?? eps[0]
        return (chosen, counts[chosen.id, default: 0] + 1)
    }

    /// 番組を指定して「いま聴く」ときの候補。回は `pick` と同じ決め方(時間帯には依存しない。昼寝でも同じ)。
    /// 回がない番組は nil。
    public static func listenNow(show: Show, ctx: TonightContext) -> Candidate? {
        guard let p = pick(show: show, ctx: ctx) else { return nil }
        return Candidate(show: show, episode: p.episode, playCount: p.playCount,
                         reason: p.playCount > 1 ? .heardBefore : .unlistened)
    }

    private static func current(_ ctx: TonightContext) -> Show? {
        ctx.shows.first(where: { $0.id == ctx.currentShowID }) ?? ctx.shows.first
    }

    private static func others(excluding ids: Set<String>, cur: Show, ctx: TonightContext, differentGenre: Bool?) -> [Show] {
        ctx.shows
            .filter { !ids.contains($0.id) }
            .filter { s in differentGenre.map { ($0 ? s.genre != cur.genre : s.genre == cur.genre) } ?? true }
            .sorted { a, b in
                let fa = ctx.favorites.contains(a.id), fb = ctx.favorites.contains(b.id)
                if fa != fb { return fa }
                if differentGenre == nil, (a.genre != cur.genre) != (b.genre != cur.genre) { return a.genre != cur.genre }
                return (a.star ?? 0) > (b.star ?? 0)
            }
    }

    /// 今夜(night = 0)と、明日以降(night >= 1)の3つ。
    public static func slate(night: Int = 0, ctx: TonightContext) -> [Candidate] {
        guard let cur = current(ctx) else { return [] }
        return night == 0 ? tonight(cur: cur, ctx: ctx) : later(cur: cur, ctx: ctx)
    }

    private static func tonight(cur: Show, ctx: TonightContext) -> [Candidate] {
        let eps = recent(cur, ctx)
        let counts = playCounts(ctx.history)
        let last = lastPlayedEpisodeID(show: cur.id, history: ctx.history)
        let lastMin = lastMinutes(for: cur, ctx)
        func cnt(_ e: Episode) -> Int { counts[e.id, default: 0] }
        func make(_ s: Show, _ e: Episode?, _ r: Reason) -> Candidate {
            Candidate(show: s, episode: e, playCount: (e.map(cnt) ?? 0) + 1, reason: r)
        }

        let rep: Episode? = last.flatMap { l in counts[l, default: 0] < playCap ? eps.first(where: { $0.id == l }) : nil }
        let rest = eps.filter { cnt($0) < playCap && $0.id != last }
        let next = rest.first(where: { cnt($0) == 0 }) ?? rest.first
        let repeatFirst = rep != nil && (lastMin.map { $0 < fastThresholdMinutes } ?? false)

        let whyRep: Reason = lastMin.map { .sleptFast(minutes: $0) } ?? .sameAsLastNight
        let whyNext: Reason = lastMin.map { $0 < fastThresholdMinutes ? .unlistened : .tookLong(minutes: $0) } ?? .latest

        let first = repeatFirst ? rep : (next ?? rep ?? eps.first)
        let second = repeatFirst ? next : (rep ?? rest.first(where: { $0 != first }))

        var items: [Candidate] = []
        if let first { items.append(make(cur, first, repeatFirst ? whyRep : whyNext)) }
        if let second, second != first {
            let why: Reason = repeatFirst ? .unlistened : (second == rep ? (cur.id == ctx.lastNight?.showID ? .sameAsLastNight : .heardBefore) : .previous)
            items.append(make(cur, second, why))
        }

        let queued = ctx.queue.filter { $0 != cur.id }.compactMap { id in ctx.shows.first(where: { $0.id == id }) }.first
        if let queued, items.count < 3, let p = pick(show: queued, ctx: ctx) {
            items.append(make(queued, p.episode, .queued))
        }
        let skip = Set([cur.id] + (queued.map { [$0.id] } ?? []))
        for o in others(excluding: skip, cur: cur, ctx: ctx, differentGenre: nil) where items.count < 3 {
            guard let p = pick(show: o, ctx: ctx) else { continue }
            let why: Reason = o.genre != cur.genre
                ? .genreStreak(from: cur.genre, to: o.genre, nights: max(ctx.genreStreakNights, 1))
                : .sameGenreOther(genre: cur.genre)
            items.append(make(o, p.episode, why))
        }
        return Array(items.prefix(3))
    }

    /// 明日以降: 回は今夜の結果で変わるので、いまの番組は回を決めずに「続き」とする。
    private static func later(cur: Show, ctx: TonightContext) -> [Candidate] {
        var items = [Candidate(show: cur, episode: nil, playCount: 1, reason: .continuation)]
        let queued = ctx.queue.filter { $0 != cur.id }.compactMap { id in ctx.shows.first(where: { $0.id == id }) }.first
        let sameGenre = others(excluding: Set([cur.id] + (queued.map { [$0.id] } ?? [])), cur: cur, ctx: ctx, differentGenre: false).first
        if let second = queued ?? sameGenre, let p = pick(show: second, ctx: ctx) {
            items.append(Candidate(show: second, episode: p.episode, playCount: p.playCount,
                                   reason: queued != nil ? .queued : .sameGenreOther(genre: cur.genre)))
        }
        let skip = Set([cur.id] + items.dropFirst().map { $0.show.id })
        if let diff = others(excluding: skip, cur: cur, ctx: ctx, differentGenre: true).first, let p = pick(show: diff, ctx: ctx) {
            items.append(Candidate(show: diff, episode: p.episode, playCount: p.playCount,
                                   reason: .genreContinues(from: cur.genre, to: diff.genre)))
        }
        return Array(items.prefix(3))
    }
}
