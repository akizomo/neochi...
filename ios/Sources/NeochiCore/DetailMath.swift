import Foundation

/// 差のピルの、どちら向きが番組にとって良いか。
public enum DeltaPolarity: Sendable {
    /// 評点など。上がると良い。
    case higherIsBetter
    /// 寝落ちまでの分など。短くなると良い。
    case lowerIsBetter
}

/// 差のピルの色の意味(semantic token の positive / negative / 無彩色)。
public enum DeltaTone: Sendable, Equatable { case positive, negative, neutral }

/// 番組詳細の図で使う計算。画面に依存しないので、ここでテストする。
public enum DetailMath {
    /// 差のピルを出すのに要る件数(直近4件と、その前の4件)。
    public static let deltaWindow = 4

    /// 直近4件の平均 − その前の4件の平均。values は古い順。8件未満なら nil(ピルを出さない)。
    public static func delta(_ values: [Double]) -> Double? {
        let w = deltaWindow
        guard values.count >= w * 2 else { return nil }
        let last = values.suffix(w), prev = values.dropLast(w).suffix(w)
        return last.reduce(0, +) / Double(w) - prev.reduce(0, +) / Double(w)
    }

    /// 差の色。表示の丸めで 0 になる差(flat)は無彩色。
    public static func tone(_ delta: Double, _ polarity: DeltaPolarity, flat: Bool) -> DeltaTone {
        if flat || delta == 0 { return .neutral }
        let up = delta > 0
        return (up == (polarity == .higherIsBetter)) ? .positive : .negative
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// 回の番号。`number` があればそれ、なければタイトルの「第81回」「#81」「81話」「EP81」「81.」から読む。
    public static func episodeNumber(_ e: Episode) -> Int? {
        if let n = e.number { return n }
        let patterns = [#"第\s*(\d{1,5})\s*[回話]"#, #"#\s*(\d{1,5})"#, #"(\d{1,5})\s*[回話]"#,
                        #"(?i)\bep(?:isode)?\.?\s*(\d{1,5})"#, #"^\s*(\d{1,5})[\.\s:：]"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(e.title.startIndex..., in: e.title)
            if let m = re.firstMatch(in: e.title, range: range), let r = Range(m.range(at: 1), in: e.title) {
                return Int(e.title[r])
            }
        }
        return nil
    }

    /// 1分ごとの起伏を読み上げるための言葉(縦軸の なし/少し/多い に合わせる)。
    public static func calmWord(_ v: Double) -> String {
        v < 0.5 ? "なし" : v < 1.5 ? "少し" : "多い"
    }

    /// 山の強さの言葉。level が無い古い解析は nil。
    public static func momentStrength(_ m: Moment) -> String? {
        switch m.level { case 1?: "少し"; case 2?: "多い"; default: nil }
    }

    /// 起伏の線の判定の一行。山の数と強さから。
    public static func calmCurveVerdict(_ moments: [Moment], minutes: Int) -> String {
        let strong = moments.filter { $0.level == 2 }.count
        if moments.isEmpty { return "冒頭\(minutes)分に、昂らせる山はありません。" }
        if strong == 0 { return "冒頭\(minutes)分に、小さな山が\(moments.count)つだけです。" }
        return "冒頭\(minutes)分に山が\(moments.count)つ、うち\(strong)つは強めです。"
    }

    /// 寝落ちの実績の軸の区間。30分で「寝落ちした」とみなす(SCORE.md §3。DBの集計 `show_stats` の under30 と同じ)。
    /// 短いほど良い、とは軸の上では言わない(10分以下は、評点の計算では満点だが、即落ちを悪い・良いと評価しない)。
    public static let fellAsleepMinutes = 30
    public struct SleepZone: Hashable, Sendable {
        public let lo: Int, hi: Int
        /// 軸の下に出す名前。
        public let label: String
        /// 「寝落ちした」とみなす区間。
        public let fell: Bool
    }
    public static let sleepZones: [SleepZone] = [
        .init(lo: 0, hi: fellAsleepMinutes, label: "寝落ちした", fell: true),
        .init(lo: fellAsleepMinutes, hi: 60, label: "30分以上", fell: false),
    ]

    /// 寝落ちの実績の点。0〜60分の軸に置くので、60分を超える記録は端に寄せる。
    public static let recordAxisMax = 60
    public static func clampedMinutes(_ m: Int) -> Int { min(max(0, m), recordAxisMax) }
}
