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
    public static let resultHeader = "あなたの睡眠の結果"
    public static let resultFrom = "寝落ちまで"
    public static let resultSourceWatch = "ヘルスケアの記録から"
    public static let evaluationHeader = "ひとこと"
    public static let askedHeader = "この回について"
    public static let askedFooter = "番組の評価に使います。答えなくても記録できます。"
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
    public static let memoHeader = "メモ"
    public static let save = "記録する"
    public static let later = "あとで"

    public static let noResult = "寝落ちまで ―"
    public static let noResultNote = "寝落ちの記録を確認中です"
    public static let researching = "調査中"
}
