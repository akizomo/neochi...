import Foundation

/// Player の寝落ちグラフの材料(docs/PREMIUM.md §3.2 の第1段階)。
/// 実測が少ないうちは、解析の1分ごとのデータ(起伏・話す速さ・音量・突発音)から、
/// 「落ち着いていて、眠りを妨げる要素が少ない区間」を「AIの推定」として出す。
/// 一分ごとの「やすらぎ」(0〜1、高いほど落ち着いている)と、その高い区間(寝落ちしやすい区間)を返す。
public struct SleepEase: Equatable, Sendable {
    /// 1分ごとのやすらぎ(0〜1)。添字は、再生を始めてからの分。
    public var perMin: [Double]
    /// 寝落ちしやすい区間(分、両端を含む)。3分以上続くものだけ。
    public var zones: [ClosedRange<Int>]

    /// やすらぎがこの値以上の分を、寝落ちしやすい区間の候補にする。
    public static let threshold = 0.62
    /// 区間とみなす最短の長さ(分)。
    public static let minRun = 3
    /// 解析がこれより短いときは出さない(分)。
    public static let minMinutes = 5

    public func contains(minute: Int) -> Bool { zones.contains { $0.contains(minute) } }

    /// 解析から推定する。1分ごとのデータが足りない(古い解析など)ときは nil。
    public static func estimate(from a: EpisodeAnalysis) -> SleepEase? {
        let n = max(a.calmPerMin.count, a.ratePerMin.count, a.volumePerMin.count)
        guard n >= minMinutes else { return nil }

        let rateMed = median(a.ratePerMin.compactMap { $0 })
        let volMed = median(a.volumePerMin.compactMap { $0 })
        let suddenMinutes = Set(a.suddenAtSec.map { $0 / 60 })

        var raw: [Double] = []
        for i in 0..<n {
            var parts: [Double] = []
            if i < a.calmPerMin.count { parts.append(1 - clamp(a.calmPerMin[i] / 2)) }
            // 話す速さ・音量は、その回のふだんから外れていないほど落ち着いている(急に速い・大きいを避ける)。
            if let m = rateMed, m > 0, i < a.ratePerMin.count, let r = a.ratePerMin[i] { parts.append(1 - clamp(abs(r - m) / (m * 0.5))) }
            if let m = volMed, i < a.volumePerMin.count, let v = a.volumePerMin[i] { parts.append(1 - clamp(abs(v - m) / 6)) }
            guard !parts.isEmpty else { raw.append(0.5); continue }
            var s = parts.reduce(0, +) / Double(parts.count)
            if suddenMinutes.contains(i) { s -= 0.3 }
            raw.append(clamp(s))
        }
        // 前後1分とならして、1分だけの上下で区間が切れないようにする。
        let smooth = raw.indices.map { i -> Double in
            let lo = max(0, i - 1), hi = min(raw.count - 1, i + 1)
            return raw[lo...hi].reduce(0, +) / Double(hi - lo + 1)
        }
        var zones: [ClosedRange<Int>] = []
        var start: Int?
        for (i, v) in smooth.enumerated() + [(smooth.count, 0.0)] {
            if v >= threshold { if start == nil { start = i } }
            else if let s = start {
                if i - s >= minRun { zones.append(s...(i - 1)) }
                start = nil
            }
        }
        return SleepEase(perMin: smooth, zones: zones)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}
