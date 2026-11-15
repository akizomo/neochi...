import Foundation

/// 表示文字列の唯一の置き場。絵文字は使わない。診断に見える語は使わない。
public enum NCString {
    /// 寝落ちまでの分数 → コメント。
    public static func comment(minutes: Int) -> String {
        switch minutes {
        case ..<10: return "即落ちでした"
        case 10..<20: return "理想の寝落ちでした"
        case 20..<30: return "やや粘りました"
        default: return "最後まで聴いてしまいました"
        }
    }

    // 朝の振り返り(`docs/SCORE.md` §4)
    public static let morningTitle = "朝の振り返り"
    public static let resultFrom = "寝落ちまで"
    public static let startedLabel = "再生開始"
    public static let onsetLabel = "入眠"
    public static let ratingHeader = "この回の評価"
    public static let ratingFooter = "番組の評価に使います。答えなくても記録できます。"
    public static let interestQuestion = "この回の話は、どうでしたか"
    public static func interestLabel(_ a: InterestAnswer) -> String {
        switch a {
        case .bored: return "退屈だった"
        case .justRight: return "ちょうどよかった"
        case .absorbed: return "聴き入った"
        }
    }
    public static let calmQuestion = "話の流れは、ゆるやかでしたか"
    public static let calmLow = "起伏が多かった"
    public static let calmHigh = "ゆるやかだった"
    // ⓘ から開く説明。長く書かない(1〜2行)。定義の出どころは docs/SCORE.md §2・§3
    public static let infoInterest = "「ちょうどよかった」は、少し気になるが、追わなくても困らない状態です。眠るには、これがいちばん向いています。"
    public static let infoCalm = "盛り上がり、驚き、対立、急な話題の転換が少ないほど、ゆるやかです。数字が大きいほど、寝落ちに向いています。"
    public static let memoHeader = "メモ"
    public static let save = "記録する"
    public static let later = "あとで"

    public static let noResult = "寝落ちまで ―"
    public static let noResultNote = "寝落ちの記録を確認中です"
    public static let researching = "調査中"
    /// 検索で見つからないとき。理由は書かず、評点も出さない。
    public static let notListed = "まだ掲載していません"
    /// 評点の内訳。あるものだけ並べる(`docs/SCORE.md` §1)。
    public static func ratingBreakdown(watchCount: Int, avgMinutes: Int) -> String {
        watchCount >= 3 ? "AI解析・寝落ちまで 平均\(avgMinutes)分(ウォッチの実測 \(watchCount)件)" : "AI解析"
    }

    // 番組詳細の図
    public static func momentLabel(minute: Int) -> String { "\(minute)分の山" }
    public static func analyzedEpisode(_ number: Int?) -> String { number.map { "\($0)回の解析" } ?? "最新の回の解析" }
    public static let summaryHeader = "この回の内容(AIの要約)"
    public static let interestZoneNote = "4〜6が寝落ち向き"
    public static let analyzing = "解析中"
    public static let deltaCaptionRecords = "前の4件"
    public static let deltaCaptionEpisodes = "前の4回"

    /// 寝落ちの実績の軸の下の説明。軸の帯(`DetailMath.sleepZones`)に合わせる。
    public static let sleepZoneNote = "再生を始めてから、30分未満で眠れた記録は、寝落ちしたとみなします。"

    /// 格付けのバッジの横に出す、ひとこと(番組の詳細)。基準の数字は出さず、その番組をどう勧めるかを言う。
    /// 効くとも、必ず眠れるとも言わない(`docs/VOICE.md`)。基準の数字は「解析について」に書く。
    public static func rankMeaning(_ r: ZRank) -> String {
        switch r {
        case .zzz: "眠りたい夜は、まずこの番組"
        case .zz: "寝落ちのために選びたい番組"
        case .z: "寝落ちに向いた番組"
        }
    }

    /// 「解析について」に書く、格付けの基準。
    public static var rankCriteriaNote: String {
        let f = { (r: ZRank) in String(format: "%.1f", RankCriteria.minStar(r)) }
        return "寝落ち格付けは、番組の評点で決めます。Z は\(f(.z))以上、ZZ は\(f(.zz))以上、ZZZ は\(f(.zzz))以上です。基準に届かない番組は、掲載しません。評点は、AI解析を土台に、ウォッチの実測とみんなの評価が集まるほど、それらを足したものです。"
    }
}

/// 格付けの線(`config/z_rank.yaml` と同じ値。仮)。変えるときは、yaml と一緒に直す。
public enum RankCriteria {
    public static func minStar(_ r: ZRank) -> Double {
        switch r { case .z: 3.0; case .zz: 3.6; case .zzz: 4.2 }
    }
}
