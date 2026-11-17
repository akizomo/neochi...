import Foundation

/// 寝落ちまでの分数のゾーン。朝の振り返りの一言(`NCString.comment`)と同じ区切り。
/// 分数だけでは、いいのか悪いのか分かりにくいので、目盛りと位置で見せるために使う。
public enum LatencyZone: Int, CaseIterable, Sendable {
    case instant, ideal, lingered, long

    /// 区切りの分(すぐ寝た 0〜10、理想 10〜20、やや粘った 20〜30、長め 30〜)。
    public static let boundaries = [0, 10, 20, 30]
    /// 目盛りの右端(これより長い夜は、右端に置く)。
    public static let scaleMax = 45

    public static func of(minutes: Int) -> LatencyZone {
        switch minutes {
        case ..<10: return .instant
        case 10..<20: return .ideal
        case 20..<30: return .lingered
        default: return .long
        }
    }

    public var name: String {
        switch self {
        case .instant: return "すぐ"
        case .ideal: return "理想"
        case .lingered: return "やや粘り"
        case .long: return "長め"
        }
    }

    /// ゾーンの始まりと終わり(分)。最後は目盛りの右端まで。
    public var range: ClosedRange<Int> {
        let b = Self.boundaries
        return b[rawValue]...(rawValue + 1 < b.count ? b[rawValue + 1] : Self.scaleMax)
    }
}
