import SwiftUI
import Charts
import NeochiCore

/// 寝落ちまでの分数が、いいのか悪いのかを、目盛りで見せる。
/// 4つのゾーン(すぐ / 理想 / やや粘り / 長め。朝のひとことと同じ区切り)の上に、今夜の位置を置く。
struct LatencyGauge: View {
    let minutes: Int
    /// 自己申告の選択肢から出した、おおよその分(「約」をつける)。
    var approximate = false

    var body: some View {
        let zone = LatencyZone.of(minutes: minutes)
        let maxV = CGFloat(LatencyZone.scaleMax)
        GeometryReader { g in
            let w = g.size.width
            let x = w * CGFloat(min(minutes, LatencyZone.scaleMax)) / maxV
            ZStack(alignment: .topLeading) {
                // 位置の目印(数字と三角)
                VStack(spacing: 2) {
                    Text("\(approximate ? "約" : "")\(minutes)分").ncText(NCText.numSm, .accentResult)
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(Color.nc(.accentResult))
                }
                .fixedSize()
                .position(x: min(max(x, 24), w - 24), y: 14)
                // ゾーンの帯と、ゾーン名(同じ幅)
                ForEach(LatencyZone.allCases, id: \.self) { z in
                    let x0 = w * CGFloat(z.range.lowerBound) / maxV
                    let zw = w * CGFloat(z.range.upperBound - z.range.lowerBound) / maxV
                    Capsule().fill(z == zone ? Color.nc(.accentResult) : Color.nc(.line))
                        .frame(width: max(4, zw - 2), height: 10)
                        .offset(x: x0, y: 34)
                    Text(z.name).ncText(NCText.caption, z == zone ? .textMain : .textSub)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: max(4, zw - 2), alignment: .leading)
                        .offset(x: x0, y: 50)
                }
            }
        }
        .frame(height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("寝落ちまで\(minutes)分。\(zone.name)のゾーン")
    }
}

/// 最近の夜の寝落ちまでの分数。30分の線(今夜の提案が「早く眠れた」とみなす境目)と、今夜の棒の色で、比べられる。
struct RecentNightsChart: View {
    struct Night: Identifiable { let id: String; let date: Date; let minutes: Int; let current: Bool }
    let nights: [Night]

    private static let dayFormat: Date.FormatStyle = .dateTime.month(.defaultDigits).day()

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Text("最近の夜").ncText(NCText.footnote, .textSub)
            Chart {
                ForEach(nights) { n in
                    BarMark(x: .value("日", n.date, unit: .day), y: .value("分", n.minutes))
                        .foregroundStyle(n.current ? Color.nc(.accentResult) : Color.nc(.line))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("基準", TonightEngine.fastThresholdMinutes))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.nc(.textSub))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("\(TonightEngine.fastThresholdMinutes)分").ncText(NCText.caption, .textSub)
                    }
            }
            .chartYScale(domain: 0...max(LatencyZone.scaleMax, (nights.map(\.minutes).max() ?? 0) + 5))
            .chartYAxis { AxisMarks(position: .leading, values: [0, 15, 30, 45]) { _ in AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: Self.dayFormat).font(.caption2) } }
            .frame(height: 120)
        }
    }
}


/// 目盛りのほかの睡眠データ(最近の夜との比べなど)を、たたんでおく。開くと中身が出る。
struct DataAccordion<Content: View>: View {
    let title: String
    @State private var open = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            Button { withAnimation(.snappy(duration: 0.25)) { open.toggle() } } label: {
                HStack {
                    Text(title).ncText(NCText.footnote, .textSub)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.nc(.textSub))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: NCSize.tapMin).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "開いています" : "閉じています")
            if open { content().transition(.opacity) }
        }
    }
}
