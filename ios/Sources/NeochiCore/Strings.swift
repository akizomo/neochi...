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
    public static let listenedHeader = "聴いたコンテンツ"
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
    // ⓘ から開く説明。定義の出どころは docs/SCORE.md §2・§3
    public static let infoResultTitle = "寝落ちまで"
    public static let infoResult = [
        "再生を始めてから、ヘルスケアが「眠っている」と記録するまでの時間です。",
        "入眠の推定は数分ずれることがあるので、分単位で表示します。"]
    public static let infoInterestTitle = "この回の話は、どうでしたか"
    public static let infoInterest = [
        "聴きながら、どのくらい引き込まれたかを答えます。",
        "退屈だった: 意識が離れやすかった。内容があまり入ってこなかった。",
        "ちょうどよかった: 少し気になるが、追わなくても困らなかった。",
        "聴き入った: 続きが気になり、聞き入ってしまった。",
        "眠りやすさでは、「ちょうどよかった」が最も向いていると考えています。退屈すぎると雑念が戻り、聴き入ると聞き続けてしまうためです。どれが正解ということはなく、感じたとおりに答えてください。"]
    public static let infoCalmTitle = "話の流れは、ゆるやかでしたか"
    public static let infoCalm = [
        "気持ちや頭を昂らせる場面の少なさを答えます。感情の強さ、対立や緊張、数字や名前の多さ、急な話題の転換が少ないほど、ゆるやかです。",
        "1: 起伏が多かった。盛り上がりや驚きが続いた。",
        "5: ゆるやかだった。同じ調子で淡々と続いた。",
        "数字が大きいほど、寝落ちに向いた話の流れです。"]
    public static let memoHeader = "メモ"
    public static let save = "記録する"
    public static let later = "あとで"

    public static let noResult = "寝落ちまで ―"
    public static let noResultNote = "寝落ちの記録を確認中です"
    public static let researching = "調査中"
}
