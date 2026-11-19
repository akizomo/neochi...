import SwiftUI
import Charts
import NeochiCore

/// Player の寝落ちグラフ(プレミアム)。再生バーの背後に、話の落ち着きの起伏(線)と、寝落ちしやすい区間(帯)を描く。
/// 横軸は話の全体(分)。解析は冒頭だけなので、後半は空白(解析していない)。
struct SleepGraph: View {
    let ease: SleepEase
    /// 話の全体の長さ(秒)。
    let totalSec: Double

    var body: some View {
        let totalMin = max(1, totalSec / 60)
        Chart {
            ForEach(Array(ease.zones.enumerated()), id: \.offset) { _, z in
                RectangleMark(xStart: .value("から", Double(z.lowerBound)), xEnd: .value("まで", Double(z.upperBound + 1)),
                              yStart: .value("下", 0), yEnd: .value("上", 1))
                    .foregroundStyle(Color.nc(.accentResult).opacity(0.18))
            }
            ForEach(Array(ease.perMin.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("分", Double(i) + 0.5), y: .value("落ち着き", v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.nc(.textSub).opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: 0...totalMin)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if ease.zones.isEmpty { return "寝落ちしやすい区間の推定: 見つかりませんでした" }
        let t = ease.zones.map { "\($0.lowerBound)分から\($0.upperBound + 1)分" }.joined(separator: "、")
        return "寝落ちしやすい区間の推定: \(t)"
    }
}
