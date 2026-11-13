import Foundation

/// 表示文字列の唯一の置き場。絵文字は使わない。診断に見える語は使わない。
public enum NCString {
    /// 寝落ちまでの分数 → コメント。
    public static func comment(minutes: Int) -> String {
        switch minutes {
        case ..<5: return "それは番組の力ではなく、ただの寝不足です"
        case 5..<10: return "即落ちでした"
        case 10..<20: return "理想の寝落ちでした"
        case 20..<30: return "やや粘りました"
        default: return "最後まで聞いてしまいました"
        }
    }

    // 朝の振り返り(`docs/SCORE.md` §4)
    public static let morningTitle = "朝の振り返り"
    public static let resultFrom = "寝落ちまで"
    public static let startedLabel = "再生開始"
    public static let onsetLabel = "入眠"
    public static let ratingHeader = "このコンテンツの評価"
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
}
