import Foundation

/// 見つける: 総合ベストと、2つの棚(寝落ち用の上位／寝落ち用ではないのに眠れる番組)。
/// 系統の定義は `neochi/genre.py` と同じ。変えるときは、両方と `docs/VOICE.md` §7 を揃える。
public enum Discover {
    /// 寝落ちのために作られた系統。朗読と環境音は、実質、寝落ち用として扱う(2026-11-16)。
    public static let sleepMadeGenres: Set<String> = ["寝落ち用", "朗読", "環境音"]
    /// 寝落ち用ではない系統。
    public static let notSleepMadeGenres: Set<String> = ["コメディ", "雑談", "教養"]

    /// 画面に出す系統の並び(絞り込みのチップの順)。
    public static let genreOrder = ["寝落ち用", "朗読", "環境音", "コメディ", "雑談", "教養"]

    /// 好みのジャンルを聞くときの、ひとこと(系統ごと)。決まりにない系統は空。
    public static func genreHint(_ genre: String) -> String {
        switch genre {
        case "寝落ち用": return "眠るために作られた番組"
        case "朗読": return "物語や本の読み聞かせ"
        case "環境音": return "雨や波などの、音だけの番組"
        case "コメディ": return "芸人ラジオ、バラエティ"
        case "雑談": return "ゆるいおしゃべり"
        case "教養": return "歴史・科学・解説"
        default: return ""
        }
    }

    /// 評点の高い順。同点は、実測の件数が多い番組、平均が短い番組、番組名の順(いつも同じ並びになる)。
    public static func ranked(_ shows: [Show]) -> [Show] {
        shows.filter { $0.star != nil }.sorted { a, b in
            if a.star != b.star { return (a.star ?? 0) > (b.star ?? 0) }
            let ca = a.stats?.count ?? 0, cb = b.stats?.count ?? 0
            if ca != cb { return ca > cb }
            let ma = a.avgMinutes ?? .max, mb = b.avgMinutes ?? .max
            if ma != mb { return ma < mb }
            return a.title < b.title
        }
    }

    /// 総合でいちばん評点の高い番組。
    public static func best(_ shows: [Show]) -> Show? { ranked(shows).first }

    /// 上の大きなカード。毎日同じにならないよう、日替わりで「総合」「寝落ち用の上位」「寝落ち用ではない上位」を回す。
    public enum SpotlightKind: Int, CaseIterable, Sendable { case overall, sleepMade, notSleepMade }
    public struct Spotlight: Equatable, Sendable { public let kind: SpotlightKind; public let show: Show }

    /// その日のカード。`day` は日付の通し番号。3つの番組は重ならない(同じ番組が総合と寝落ち用の両方で1位でも、次点を出す)。
    /// ある種類の番組がなければ、次の種類へ回す。
    public static func spotlight(_ shows: [Show], day: Int) -> Spotlight? {
        guard let overall = best(shows) else { return nil }
        var picks: [SpotlightKind: Show] = [.overall: overall]
        if let s = ranked(shows.filter { sleepMadeGenres.contains($0.genre) && $0.id != overall.id }).first { picks[.sleepMade] = s }
        let used = Set(picks.values.map(\.id))
        if let n = ranked(shows.filter { notSleepMadeGenres.contains($0.genre) && !used.contains($0.id) }).first { picks[.notSleepMade] = n }
        let kinds = SpotlightKind.allCases
        let start = ((day % kinds.count) + kinds.count) % kinds.count
        for i in 0..<kinds.count {
            let k = kinds[(start + i) % kinds.count]
            if let s = picks[k] { return Spotlight(kind: k, show: s) }
        }
        return nil
    }

    public static func sleepMade(_ shows: [Show], limit: Int = 10) -> [Show] {
        Array(ranked(shows.filter { sleepMadeGenres.contains($0.genre) }).prefix(limit))
    }

    public static func notSleepMade(_ shows: [Show], limit: Int = 10) -> [Show] {
        Array(ranked(shows.filter { notSleepMadeGenres.contains($0.genre) }).prefix(limit))
    }

    /// 絞り込みのチップに出す系統。決まった順に、番組がある系統だけ。決まりにない系統は、最後に番組数の多い順。
    public static func genres(in shows: [Show]) -> [String] {
        let present = Dictionary(grouping: shows.filter { !$0.genre.isEmpty }, by: \.genre).mapValues(\.count)
        let known = genreOrder.filter { present[$0] != nil }
        let other = present.keys.filter { !genreOrder.contains($0) }.sorted { (present[$0]!, $1) > (present[$1]!, $0) }
        return known + other
    }
}
