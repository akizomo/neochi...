import Foundation

/// 今夜の候補を、なぜ出したか。あなたの実績に基づく理由だけを持つ。
public enum Reason: Hashable, Sendable {
    case sleptFast(minutes: Int)            // 昨夜は18分で寝落ち
    case tookLong(minutes: Int)             // 昨夜は40分かかったので、次の回へ
    case sameAsLastNight                    // 昨夜と同じ話(昨夜の記録がないとき)
    case heardBefore                        // 前に聴いた話
    case unlistened                         // まだ聴いていない話
    case latest                             // 最新の回
    case previous                           // ひとつ前の話
    case continuation                       // いまの番組の続き(明日以降)
    case queued                             // 次に聴くに入れた番組
    case favorite(genre: String)            // お気に入りの朗読
    case preferredGenre(genre: String)      // 好みの朗読(最初に聞いた好みのジャンル)
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

/// 理由に出す系統名(`docs/VOICE.md` §7)。genre には系統名がそのまま入る。
/// map は、データを書き換える前の古い分類の読み替え(sync-shows を流すまでの移行用)。
public enum GenreLabel {
    static let map: [String: String] = [
        "寝落ち・睡眠導入": "寝落ち用", "寝落ち・睡眠導入（海外基準）": "寝落ち用",
        "芸人ラジオ・バラエティ": "コメディ", "朗読": "朗読", "ゆる雑談": "雑談",
        "教養（比較用含む）": "教養", "環境音・瞑想": "環境音", "人気番組（一般）": "雑談",
    ]
    /// 系統名。出せない分類は nil。
    public static func display(_ genre: String) -> String? {
        if let v = map[genre] { return v.isEmpty ? nil : v }
        let t = genre.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 6, !t.contains("（"), !t.contains("("), !t.contains("・") else { return nil }
        return t
    }
}

public extension Reason {
    var segments: [ReasonSegment] {
        switch self {
        case .sleptFast(let m): return [.init("昨夜は"), .init("\(m)分", emphasized: true), .init("で寝落ち")]
        case .tookLong(let m): return [.init("昨夜は"), .init("\(m)分", emphasized: true), .init("。次の話へ")]
        case .sameAsLastNight: return [.init("昨夜と同じ話")]
        case .heardBefore: return [.init("前に聴いた話")]
        case .unlistened: return [.init("まだ聴いていない話")]
        case .latest: return [.init("最新の話")]
        case .previous: return [.init("ひとつ前の話")]
        case .continuation: return [.init("いまの番組の続き")]
        case .queued: return [.init("「次に聴く」に入れた番組")]
        case .favorite(let g):
            return [.init(GenreLabel.display(g).map { "お気に入りの\($0)" } ?? "お気に入りの番組")]
        case .preferredGenre(let g):
            return [.init(GenreLabel.display(g).map { "好みの\($0)" } ?? "好みの系統の番組")]
        case .sameGenreOther(let g):
            return [.init(GenreLabel.display(g).map { "同じ\($0)の、別の番組" } ?? "同じ系統の、別の番組")]
        case .genreStreak(let from, let to, let n):
            if n >= 2, let f = GenreLabel.display(from), let t = GenreLabel.display(to) {
                return [.init("\(f)が"), .init("\(n)晩", emphasized: true), .init("。\(t)へ")]
            }
            return Reason.change(from, to)
        case .genreContinues(let from, let to): return Reason.change(from, to)
        }
    }

    /// 系統を変える。両方の系統名が出せるときだけ名前を出す。
    private static func change(_ from: String, _ to: String) -> [ReasonSegment] {
        if let f = GenreLabel.display(from), let t = GenreLabel.display(to), f != t { return [.init("\(f)から、\(t)へ")] }
        return [.init("ちがう系統の番組")]
    }

    var text: String { segments.map(\.text).joined() }
}
