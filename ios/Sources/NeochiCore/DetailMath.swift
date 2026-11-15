import Foundation

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

    /// 寝落ちの実績の軸の区間(ゾーン)。結果のコメント(`NCString.comment`、SCORE.md §3)の区切りと同じ。
    /// 画面では、記録の点をこの帯の上に置く。「何分で寝落ちできるといいか」を、軸の上で見せる。
    public struct SleepZone: Hashable, Sendable {
        public let lo: Int, hi: Int
        /// 軸の下に出す短い名前。
        public let label: String
        /// いちばん勧める区間(理想の寝落ち)。
        public let ideal: Bool
    }
    public static let sleepZones: [SleepZone] = [
        .init(lo: 0, hi: 10, label: "即落ち", ideal: false),
        .init(lo: 10, hi: 20, label: "理想", ideal: true),
        .init(lo: 20, hi: 30, label: "やや粘る", ideal: false),
        .init(lo: 30, hi: 60, label: "最後まで聴いた", ideal: false),
    ]

    /// 寝落ちの実績の点。0〜60分の軸に置くので、60分を超える記録は端に寄せる。
    public static let recordAxisMax = 60
    public static func clampedMinutes(_ m: Int) -> Int { min(max(0, m), recordAxisMax) }
}
