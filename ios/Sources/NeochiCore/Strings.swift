import Foundation

/// 表示文字列の唯一の置き場。絵文字は使わない。診断に見える語は使わない。
public enum NCString {
    /// 程よい興味の水準の言葉(番組の傾向と、話の根拠で同じ言葉を使う)。
    public static func interestWord(_ l: InterestLevel) -> String {
        switch l { case .low: "静かめ"; case .mid: "程よい"; case .high: "強め" }
    }

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
    public static let ratingHeader = "この話の評価"
    public static let ratingFooter = "番組の評価に使います。答えなくても記録できます。"
    public static let interestQuestion = "この話に、どれくらい引き込まれましたか"
    public static let interestLow = "ほとんど引き込まれない"
    public static let interestHigh = "続きが気になって仕方ない"

    /// 🎯 の10段階のゾーン。AIの採点と同じ区切り(`config/scoring.yaml` の total.interest_zone、docs/SCORE.md §2)。
    public enum InterestZone: CaseIterable, Sendable { case bored, justRight, absorbed }
    public static func interestZone(_ rating: Int) -> InterestZone {
        rating <= 3 ? .bored : (rating <= 6 ? .justRight : .absorbed)
    }
    public static func interestZoneRange(_ z: InterestZone) -> String {
        switch z { case .bored: return "1〜3"; case .justRight: return "4〜6"; case .absorbed: return "7〜10" }
    }
    public static func interestZoneName(_ z: InterestZone) -> String {
        switch z { case .bored: return "退屈寄り"; case .justRight: return "ちょうどよい"; case .absorbed: return "引き込まれすぎ" }
    }
    public static func interestZoneNote(_ z: InterestZone) -> String {
        switch z {
        case .bored: return "気が散って、別のことを考えてしまう"
        case .justRight: return "少し気になるが、追わなくても困らない"
        case .absorbed: return "続きが気になって、聞き続けてしまう"
        }
    }
    public static let calmQuestion = "話の流れは、ゆるやかでしたか"
    public static let calmLow = "起伏が多かった"
    public static let calmHigh = "ゆるやかだった"
    // ⓘ から開く説明。長く書かない(1〜2行)。定義の出どころは docs/SCORE.md §2・§3
    public static let infoInterest = "話にどれくらい引き込まれたかを、1〜10で選びます。4〜6(少し気になるが、追わなくても困らない)が、眠るにはいちばん向いています。低すぎると気が散り、高すぎると聞き続けてしまいます。"
    public static let infoCalm = "盛り上がり、驚き、対立、急な話題の転換が少ないほど、ゆるやかです。数字が大きいほど、寝落ちに向いています。"
    public static let memoHeader = "メモ"
    public static let save = "記録する"
    public static let later = "あとで"

    public static let selfReportHeader = "寝落ちまでの目安"
    public static let selfReportFooter = "答えは目安として記録します。番組の評点には入れません。"

    public static let noResult = "寝落ちまで ―"
    public static let noResultNote = "寝落ちの記録を確認中です"
    /// ヘルスケアに睡眠データが入る人(ウォッチなど)の朝。反映が遅れて、まだ入っていないとき。
    public static let awaitingHealthNote = "ヘルスケアへの反映には、時間がかかることがあります。反映されたら、記録に自動で追記します。"
    public static let researching = "調査中"
    /// 検索で見つからないとき。理由は書かず、評点も出さない。
    public static let notListed = "まだ掲載していません"
    /// 評点の内訳。あるものだけ並べる(`docs/SCORE.md` §1)。
    public static func ratingBreakdown(watchCount: Int, avgMinutes: Int) -> String {
        watchCount >= 3 ? "AI解析・寝落ちまで 平均\(avgMinutes)分(ヘルスケアの実測 \(watchCount)件)" : "AI解析"
    }

    // 番組詳細の図
    public static func momentLabel(minute: Int) -> String { "\(minute)分の山" }
    public static func analyzedEpisode(_ number: Int?) -> String { number.map { "\($0)話の解析" } ?? "この話の解析" }
    public static let summaryHeader = "この話の内容(AIの要約)"
    public static let interestZoneNote = "4〜6が寝落ち向き"
    public static let analyzing = "解析中"
    /// 起伏・興味の AI の判定が、まだ済んでいない観点。
    public static let judgePending = "判定待ち"
    public static let deltaCaptionRecords = "前の4件"
    public static let deltaCaptionEpisodes = "前の4話"

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

    /// 「スコアと根拠」のページ(サイトの about/。出典つき)。公開先は .github/workflows/site.yml と同じ。
    public static let explainerURL = URL(string: "https://neochipickzz.vercel.app/about/")!
    public static let explainerLinkLabel = "スコアと根拠を見る(出典つき)"

    /// 「解析について」に書く、格付けの基準。
    public static var rankCriteriaNote: String {
        let f = { (r: ZRank) in String(format: "%.1f", RankCriteria.minStar(r)) }
        return "寝落ち格付けは、番組の評点で決めます。Z は\(f(.z))以上、ZZ は\(f(.zz))以上、ZZZ は\(f(.zzz))以上です。基準に届かない番組は、掲載しません。評点は、AI解析を土台に、ヘルスケアの実測とみんなの評価が集まるほど、それらを足したものです。"
    }
}

/// 格付けの線(`config/z_rank.yaml` と同じ値。仮)。変えるときは、yaml と一緒に直す。
public enum RankCriteria {
    public static func minStar(_ r: ZRank) -> Double {
        switch r { case .z: 3.6; case .zz: 4.1; case .zzz: 4.5 }
    }
}
