import SwiftUI
import NeochiCore

/// Player の寝落ちグラフ(プレミアム)。再生バーの背後に、話の落ち着きの起伏(線)と、寝落ちしやすい区間(帯)を描く。
/// 横軸は話の全体(分)。解析は冒頭だけなので、後半は空白(解析していない)。
struct SleepGraph: View {
    let ease: SleepEase
    /// 話の全体の長さ(秒)。
    let totalSec: Double

    /// Charts ではなく Canvas で描く。再生バーと、横の位置が1ピクセルもずれないようにするため
    /// (Charts は軸の余白で、プロットが再生バーの幅からはみ出した)。
    var body: some View {
        let totalMin = max(1, totalSec / 60)
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func x(_ minute: Double) -> CGFloat { w * CGFloat(min(minute, totalMin) / totalMin) }
            for z in ease.zones {
                let r = CGRect(x: x(Double(z.lowerBound)), y: 0, width: x(Double(z.upperBound + 1)) - x(Double(z.lowerBound)), height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Color.nc(.accentResult).opacity(0.22)))
            }
            var line = Path()
            for (i, v) in ease.perMin.enumerated() {
                let pt = CGPoint(x: x(Double(i) + 0.5), y: h - 4 - CGFloat(v) * (h - 8))
                i == 0 ? line.move(to: pt) : line.addLine(to: pt)
            }
            ctx.stroke(line, with: .color(Color.nc(.textSub).opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        if ease.zones.isEmpty { return "寝落ちしやすい区間の推定: 見つかりませんでした" }
        let t = ease.zones.map { "\($0.lowerBound)分から\($0.upperBound + 1)分" }.joined(separator: "、")
        return "寝落ちしやすい区間の推定: \(t)"
    }
}
