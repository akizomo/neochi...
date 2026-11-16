import Foundation

/// ★の基準(`config/scoring.yaml` の `ear` と同じ値)。変えるときは、yaml と一緒に直す。
public enum EarCriteria {
    public static let rateBestMax = 250.0      // 字/分。これ以下は満点
    public static let rateWorst = 400.0
    public static let cvBest = 0.10, cvWorst = 0.40
    public static let volumeBest = 4.0, volumeWorst = 12.0   // 音量のばらつき(dB)
    public static let suddenBest = 0.0, suddenWorst = 10.0   // 突発音(回/10分)
}

/// 🎧 の1項目ぶんの説明。「何を測って、どうだったか、基準はどこか」を、言葉で出す。
public struct EarPartReport: Hashable, Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let star: Double?
    /// 測った値。例「1分に282字」
    public let measured: String
    /// 結果のひとこと。例「ゆったりです」
    public let verdict: String
    /// 基準。例「250字/分までは満点、400字で最低」
    public let criterion: String
    public let good: Bool
    /// 行に出す、測った値の短い形。例「274字/分」
    public let short: String
    /// 満点(1)から最低(0)の間の位置。ゲージの長さ。
    public let fill: Double
}

/// ★の理由を、言葉にする(画面に出す文言)。
public enum Explain {
    /// best で 1、worst で 0 の位置(★と同じ線形)。範囲外は丸める。
    static func unit(_ v: Double, best: Double, worst: Double) -> Double {
        best == worst ? 1 : max(0, min(1, (v - worst) / (best - worst)))
    }

    /// 位置(0〜1)から、3段階の言い方を選ぶ。0.7 以上を「よい」とする。
    private static func pick(_ u: Double, _ good: String, _ mid: String, _ bad: String) -> (String, Bool) {
        u >= 0.7 ? (good, true) : u >= 0.3 ? (mid, false) : (bad, false)
    }

    public static func earParts(_ a: EpisodeAnalysis) -> [EarPartReport] {
        var out: [EarPartReport] = []
        let p = a.earParts
        let c = EarCriteria.self
        if let r = a.speechRate {
            // 速さは台形: 250字/分以下は、遅くても満点。
            let u = r <= c.rateBestMax ? 1 : unit(r, best: c.rateBestMax, worst: c.rateWorst)
            let (v, good) = pick(u, "寝落ちに向く速さです", "やや速めです", "かなり速いです")
            out.append(.init(title: "話す速さ", star: p?.rate, measured: "1分に\(Int(r.rounded()))字", verdict: v,
                             criterion: "\(Int(c.rateBestMax))字/分までは満点、\(Int(c.rateWorst))字で最低", good: good,
                             short: "\(Int(r.rounded()))字/分", fill: u))
        }
        if let cv = a.speechRateCV {
            let u = unit(cv, best: c.cvBest, worst: c.cvWorst)
            let (v, good) = pick(u, "速さがほぼ一定です", "速さが、ところどころ変わります", "速さが大きく揺れます")
            out.append(.init(title: "速さのばらつき", star: p?.rateCV, measured: "1分ごとの速さの揺れ \(Int((cv * 100).rounded()))%", verdict: v,
                             criterion: "揺れが\(Int(c.cvBest * 100))%以下なら満点、\(Int(c.cvWorst * 100))%で最低", good: good,
                             short: "\(Int((cv * 100).rounded()))%", fill: u))
        }
        if let d = a.volumeStdDB {
            let u = unit(d, best: c.volumeBest, worst: c.volumeWorst)
            let (v, good) = pick(u, "音量が安定しています", "音量に、ところどころ大小があります", "音量が大きく上下します")
            out.append(.init(title: "音量の変化", star: p?.volume, measured: "音量のばらつき \(String(format: "%.1f", d))dB", verdict: v,
                             criterion: "\(Int(c.volumeBest))dB以下なら満点、\(Int(c.volumeWorst))dBで最低", good: good,
                             short: "\(String(format: "%.1f", d))dB", fill: u))
        }
        if let s = a.suddenPer10Min {
            let u = unit(s, best: c.suddenBest, worst: c.suddenWorst)
            let (v, good) = pick(u, "急に大きな音は、ほとんどありません", "急な音が、ときどきあります", "急な音が多めです")
            out.append(.init(title: "突発音", star: p?.sudden, measured: "10分に\(String(format: "%.1f", s))回", verdict: v,
                             criterion: "0回なら満点、\(Int(c.suddenWorst))回で最低(屋外の音や、音の演出が多い話は、多めに数えます)", good: good,
                             short: "\(String(format: "%.1f", s))回/10分", fill: u))
        }
        return out
    }

    public static let interestLabels: [String: String] = [
        "A": "未解決の問い", "B": "驚き・新しい情報", "C": "笑い", "D": "追い続ける必要", "E": "聴き手への働きかけ"]
    public static let calmLabels: [String: String] = [
        "A": "感情の強さ", "B": "対立・緊張", "C": "頭の負荷", "D": "急な転換"]

    public static func levelWord(_ score: Int) -> String {
        switch score { case 0: "なし"; case 1: "少し"; default: "多い" }
    }

    /// 項目の合計(🎯 引き込み力。0 のときは 1)。
    public static func interestTotal(_ items: [ScoredItem]) -> Int { max(1, items.reduce(0) { $0 + $1.score }) }

    /// 🎯 のゾーン(引き込み力 4〜6 が最良)の説明。
    public static func interestVerdict(_ level: InterestLevel, total: Int) -> String {
        switch level {
        case .low: "引き込む要素が少なく、頭が静かなぶん、雑念が戻りやすい側です(いまは\(total)。4〜6がちょうどいい)"
        case .mid: "続きは気になるが、追い続けなくていい、ちょうどいい引き込みです(いまは\(total)。4〜6がちょうどいい)"
        case .high: "引き込む要素が多く、眠らずに聴き続けてしまう側です(いまは\(total)。4〜6がちょうどいい)"
        }
    }

    /// 🌊 起伏の少なさ(★)= 5 − 項目の合計 × 0.5。
    public static func calmVerdict(_ items: [ScoredItem]) -> String {
        let sum = items.reduce(0) { $0 + $1.score }
        return sum == 0 ? "気持ちや頭を昂らせる要素は、見当たりませんでした"
            : "昂らせる要素が合計\(sum)点ありました(0点に近いほど、穏やかです)"
    }
}
