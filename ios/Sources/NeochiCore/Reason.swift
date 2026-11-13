import Foundation

/// 今夜の候補を、なぜ出したか。あなたの実績に基づく理由だけを持つ。
public enum Reason: Hashable, Sendable {
    case sleptFast(minutes: Int)            // 昨夜は18分で寝落ち
    case tookLong(minutes: Int)             // 昨夜は40分かかったので、次の回へ
    case sameAsLastNight                    // 昨夜と同じ回(昨夜の記録がないとき)
    case heardBefore                        // 前に聴いた回
    case unlistened                         // まだ聴いていない回
    case latest                             // 最新の回
    case previous                           // ひとつ前の回
    case continuation                       // いまの番組の続き(明日以降)
    case queued                             // 次に聴くに入れた番組
    case sameGenreOther(genre: String)      // 同じ朗読の、別の番組
    case genreStreak(from: String, to: String, nights: Int)  // 朗読が3晩続いたので、解説の番組
    case genreContinues(from: String, to: String)            // 朗読が続いているので、解説の番組
}

/// 理由の文を、強調する部分(数字)と、しない部分に分ける。強調は `accent-result` の等幅で描く。
public struct ReasonSegment: Hashable, Sendable {
    public let text: String
    public let emphasized: Bool
    public init(_ text: String, emphasized: Bool = false) { self.text = text; self.emphasized = emphasized }
}

public extension Reason {
    var segments: [ReasonSegment] {
        switch self {
        case .sleptFast(let m): return [.init("昨夜は"), .init("\(m)分", emphasized: true), .init("で寝落ち")]
        case .tookLong(let m): return [.init("昨夜は"), .init("\(m)分", emphasized: true), .init("かかったので、次の回へ")]
        case .sameAsLastNight: return [.init("昨夜と同じ回")]
        case .heardBefore: return [.init("前に聴いた回")]
        case .unlistened: return [.init("まだ聴いていない回")]
        case .latest: return [.init("最新の回")]
        case .previous: return [.init("ひとつ前の回")]
        case .continuation: return [.init("いまの番組の続き")]
        case .queued: return [.init("次に聴くに入れた番組")]
        case .sameGenreOther(let g): return [.init("同じ\(g)の、別の番組")]
        case .genreStreak(let from, let to, let n):
            return [.init("\(from)が"), .init("\(n)晩", emphasized: true), .init("続いたので、\(to)の番組")]
        case .genreContinues(let from, let to): return [.init("\(from)が続いているので、\(to)の番組")]
        }
    }

    var text: String { segments.map(\.text).joined() }
}
