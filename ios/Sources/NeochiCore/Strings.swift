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

    public static let noResult = "寝落ちまで ―"
    public static let noResultNote = "寝落ちの記録を確認中です"
    public static let researching = "調査中"
}
