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
