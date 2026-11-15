import SwiftUI
import Charts
import NeochiCore

// 番組詳細の図。要因(起伏・耳・興味・評点)は琥珀、結果(寝落ちの分)は青灰。帯(寝落ちに向く範囲)は無彩色。

/// 起伏の少なさ: 1分ごとの起伏の線と、山の点。点を押すと吹き出し。
struct CalmCurveChart: View {
    let values: [Double]
    let moments: [Moment]
    @State private var selected: Int?
    @State private var bubbleSize = CGSize(width: 160, height: 28)

    init(values: [Double], moments: [Moment]) {
        self.values = values
        self.moments = moments
        _selected = State(initialValue: moments.first?.minute)   // 開いた直後は、最初の山を選ぶ
    }

    private func value(at minute: Int) -> Double { values.indices.contains(minute) ? values[minute] : 0 }

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("分", i), y: .value("起伏", v))
                    .foregroundStyle(Color.nc(.factorTint))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("分", i), y: .value("起伏", v))
                    .foregroundStyle(Color.nc(.accentFactor))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...20)
        .chartYScale(domain: 0...2)
        .chartXAxis {
            AxisMarks(values: [0, 5, 10, 15, 20]) { v in
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textSub)) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2]) { v in
                AxisGridLine().foregroundStyle(Color.nc(.line))
                AxisValueLabel {
                    Text(DetailMath.calmWord(v.as(Double.self) ?? 0)).font(.nc(NCText.caption)).foregroundStyle(Color.nc(.textSub))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let plot = geo[anchor]
                    ForEach(moments, id: \.minute) { m in
                        if let x = proxy.position(forX: m.minute), let y = proxy.position(forY: value(at: m.minute)) {
                            peakButton(m).position(x: plot.minX + x, y: plot.minY + y)
                        }
                    }
                    if let sel = selected, let m = moments.first(where: { $0.minute == sel }),
                       let x = proxy.position(forX: m.minute), let y = proxy.position(forY: value(at: m.minute)) {
                        let half = bubbleSize.width / 2
                        let cx = min(max(plot.minX + x, half), geo.size.width - half)
                        bubble(m)
                            .position(x: cx, y: plot.minY + y - 12 - bubbleSize.height / 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)   // 内容は点の読み上げで伝える
                    }
                }
            }
        }
        .frame(height: 132)
        .padding(.top, bubbleSize.height + 8)   // 高い山の上にも吹き出しが収まるように
    }

    private func peakButton(_ m: Moment) -> some View {
        let on = selected == m.minute
        return Button {
            selected = on ? nil : m.minute   // もう一度押すと閉じる。別の点なら切り替え
        } label: {
            Circle()
                .fill(Color.nc(.accentFactor))
                .frame(width: on ? 12 : 9, height: on ? 12 : 9)
                .overlay(Circle().strokeBorder(Color.nc(.surface), lineWidth: 2))
                .frame(width: NCSize.tapMin, height: NCSize.tapMin)   // 押せる範囲は 44pt
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NCString.momentLabel(minute: m.minute))
        .accessibilityValue([m.note, DetailMath.momentStrength(m)].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func bubble(_ m: Moment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
            Text("\(m.minute)分").font(.nc(NCText.numSm)).foregroundStyle(Color.nc(.accentFactor))
            Text(m.note).font(.nc(NCText.footnote)).foregroundStyle(Color.nc(.textMain))
            if let s = DetailMath.momentStrength(m) {
                Text(s).font(.nc(NCText.caption)).foregroundStyle(Color.nc(.textSub))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, NCSpace.s2).padding(.vertical, NCSpace.s1)
        .background(RoundedRectangle(cornerRadius: NCRadius.sm, style: .continuous).fill(Color.nc(.bgBase)))
        .overlay(RoundedRectangle(cornerRadius: NCRadius.sm, style: .continuous).strokeBorder(Color.nc(.line), lineWidth: 1))
        .background(GeometryReader { g in Color.clear.onAppear { bubbleSize = g.size }.onChange(of: g.size) { _, s in bubbleSize = s } })
    }
}

/// 耳のゆるさ: 話す速さと音量を、同じ横軸(0〜20分)で縦に並べる。
struct EarCharts: View {
    let analysis: EpisodeAnalysis
    static let minutes = 20

    private var ratePts: [(Int, Double)] {
        analysis.ratePerMin.enumerated().compactMap { i, v in i <= Self.minutes ? v.map { (i, $0) } : nil }
    }
    private var volPts: [(Int, Double)] {
        analysis.volumePerMin.enumerated().compactMap { i, v in i <= Self.minutes ? v.map { (i, $0) } : nil }
    }
    private var sudden: [Double] {
        analysis.suddenAtSec.map { Double($0) / 60 }.filter { $0 <= Double(Self.minutes) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            if !ratePts.isEmpty { rateChart(showAxis: volPts.isEmpty) }
            if !volPts.isEmpty { volumeChart }
            if !ratePts.isEmpty || !volPts.isEmpty {
                HStack(spacing: NCSpace.s4) {
                    HStack(spacing: NCSpace.s1) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.nc(.line)).frame(width: 14, height: 8)
                        Text("寝落ちに向く範囲").ncText(NCText.caption, .textSub)
                    }
                    if !volPts.isEmpty {
                        HStack(spacing: NCSpace.s1) {
                            Rectangle().fill(Color.nc(.textMain)).frame(width: 1.5, height: 8)
                            Text("突発音").ncText(NCText.caption, .textSub)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("横軸は分").ncText(NCText.caption, .textSub)
                }
            }
        }
    }

    private func label(_ title: String, _ unit: String) -> some View {
        HStack {
            Text(title).ncText(NCText.footnote, .textSub)
            Spacer()
            Text(unit).ncText(NCText.caption, .textSub)
        }
    }

    private func rateChart(showAxis: Bool) -> some View {
        let pts = ratePts
        let top = max(EarCriteria.rateWorst, (pts.map(\.1).max() ?? 0) + 40)
        let maxPt = pts.max { $0.1 < $1.1 }
        let marked = Set([pts.first?.0, maxPt?.0, pts.last?.0].compactMap { $0 })   // 最初・最大・最後に値
        return VStack(alignment: .leading, spacing: NCSpace.s1) {
            label("話す速さ", "字/分")
            Chart {
                RectangleMark(xStart: .value("分", 0), xEnd: .value("分", Self.minutes),
                              yStart: .value("下限", 0), yEnd: .value("上限", EarCriteria.rateBestMax))
                    .foregroundStyle(Color.nc(.line).opacity(0.7))
                ForEach(pts, id: \.0) { p in
                    LineMark(x: .value("分", p.0), y: .value("字/分", p.1)).foregroundStyle(Color.nc(.accentFactor))
                }
                ForEach(pts.filter { marked.contains($0.0) }, id: \.0) { p in
                    PointMark(x: .value("分", p.0), y: .value("字/分", p.1))
                        .foregroundStyle(Color.nc(.accentFactor)).symbolSize(28)
                        .annotation(position: .top, spacing: 2) {
                            Text("\(Int(p.1.rounded()))").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textMain))
                        }
                }
            }
            .chartXScale(domain: 0...Self.minutes)
            .chartYScale(domain: 0...top)
            .chartYAxis {
                AxisMarks(position: .leading, values: [EarCriteria.rateBestMax]) { _ in
                    AxisValueLabel { Text("\(Int(EarCriteria.rateBestMax))").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textSub)) }
                }
            }
            .chartXAxis { xAxis(showAxis) }
            .frame(height: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("話す速さ")
            .accessibilityValue("最初 \(Int(pts.first!.1.rounded()))字、最大 \(Int(maxPt!.1.rounded()))字、最後 \(Int(pts.last!.1.rounded()))字、1分あたり。\(Int(EarCriteria.rateBestMax))字までが寝落ちに向く範囲")
        }
    }

    private var volumeChart: some View {
        let band = EarCriteria.volumeBest
        let span = max(band * 2, (volPts.map { abs($0.1) }.max() ?? 0) + 2)
        return VStack(alignment: .leading, spacing: NCSpace.s1) {
            label("音量", "中央値との差 dB")
            Chart {
                RectangleMark(xStart: .value("分", 0), xEnd: .value("分", Self.minutes),
                              yStart: .value("下限", -band), yEnd: .value("上限", band))
                    .foregroundStyle(Color.nc(.line).opacity(0.7))
                ForEach(volPts, id: \.0) { p in
                    LineMark(x: .value("分", p.0), y: .value("dB", p.1)).foregroundStyle(Color.nc(.accentFactor))
                }
                ForEach(Array(sudden.prefix(60).enumerated()), id: \.offset) { _, m in
                    RuleMark(x: .value("分", m), yStart: .value("dB", -span), yEnd: .value("dB", -span + span * 0.3))
                        .foregroundStyle(Color.nc(.textMain)).lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXScale(domain: 0...Self.minutes)
            .chartYScale(domain: -span...span)
            .chartYAxis {
                AxisMarks(position: .leading, values: [-band, 0, band]) { v in
                    AxisValueLabel {
                        let d = Int(v.as(Double.self) ?? 0)
                        Text(d > 0 ? "+\(d)" : "\(d)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textSub))
                    }
                }
            }
            .chartXAxis { xAxis(true) }
            .frame(height: 104)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("音量")
            .accessibilityValue("中央値との差は最大 \(String(format: "%.1f", volPts.map { abs($0.1) }.max() ?? 0))dB。±\(Int(band))dBまでが寝落ちに向く範囲。冒頭\(Self.minutes)分の突発音 \(sudden.count)回")
        }
    }

    private func xAxis(_ show: Bool) -> some AxisContent {
        AxisMarks(values: [0, 5, 10, 15, 20]) { v in
            AxisGridLine().foregroundStyle(Color.nc(.line))
            if show {
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textSub)) }
            }
        }
    }
}

/// 程よい興味: 10段の目盛り。4〜6を帯、現在値を琥珀。
struct InterestScale: View {
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: NCSpace.s1) {
            HStack(spacing: 3) {
                ForEach(1...10, id: \.self) { i in
                    VStack(spacing: NCSpace.s1) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == total ? Color.nc(.accentFactor) : Color.nc(.line))
                            .frame(height: 8)
                        Text("\(i)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(i == total ? .accentFactor : .textSub))
                    }
                    .padding(.vertical, NCSpace.s1)
                    .background((4...6).contains(i) ? Color.nc(.surfacePressed) : Color.clear)
                }
            }
            Text(NCString.interestZoneNote).ncText(NCText.caption, .textSub)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("引き込み力 \(total)、10段階。\(NCString.interestZoneNote)")
    }
}

/// 寝落ちの実績: 0〜60分の1本の軸に、記録を点で置く。30分未満は塗り、30分以上は線だけ。
/// 点を押すと、その記録の「日付と分数」が出る(もう一度押すか、ほかの点を押すと切り替わる)。
struct SleepDotAxis: View {
    let points: [SleepPoint]
    let average: Int
    @State private var selected: Int?

    private let maxM = Double(DetailMath.recordAxisMax)
    private var minutes: [Int] { points.map(\.minutes) }

    private static let shortDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Tokyo"); f.dateFormat = "M/d"; return f
    }()
    private static let spokenDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Tokyo"); f.dateFormat = "M月d日"; return f
    }()

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = { (m: Int) -> CGFloat in 6 + (w - 12) * CGFloat(Double(DetailMath.clampedMinutes(m)) / maxM) }
            let lo = minutes.min() ?? 0, hi = minutes.max() ?? 0
            ZStack(alignment: .topLeading) {
                // 軸と目盛り
                Rectangle().fill(Color.nc(.line)).frame(width: w - 12, height: 1).position(x: w / 2, y: 52)
                ForEach([0, 15, 30, 45, 60], id: \.self) { t in
                    Text("\(t)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textSub))
                        .fixedSize().position(x: x(t), y: 64)
                }
                // 30分の破線
                Path { p in p.move(to: CGPoint(x: x(30), y: 20)); p.addLine(to: CGPoint(x: x(30), y: 52)) }
                    .stroke(Color.nc(.borderControl), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                // 平均の縦線とラベル
                Rectangle().fill(Color.nc(.accentResult)).frame(width: 1.5, height: 40).position(x: x(average), y: 32)
                if selected == nil {
                    Text("平均\(average)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.accentResult))
                        .fixedSize().position(x: min(max(x(average), 24), w - 24), y: 6)
                }
                // 記録の点。押せる(見た目は10pt、押せる範囲は28pt)
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i }
                    } label: {
                        ZStack {
                            Color.clear
                            if p.minutes < 30 { Circle().fill(Color.nc(.accentResult)).frame(width: 10, height: 10) }
                            else { Circle().strokeBorder(Color.nc(.accentResult), lineWidth: 1.5).frame(width: 10, height: 10) }
                            if selected == i { Circle().strokeBorder(Color.nc(.textMain), lineWidth: 1).frame(width: 16, height: 16) }
                        }
                        .frame(width: 28, height: 28).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: x(p.minutes), y: 40)
                    .accessibilityLabel("\(Self.spokenDay.string(from: p.night))、\(p.minutes)分")
                }
                // 押した点の、日付と分数
                if let i = selected, points.indices.contains(i) {
                    let p = points[i]
                    Text("\(Self.shortDay.string(from: p.night))  \(p.minutes)分")
                        .font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textMain))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.nc(.surfacePressed)))
                        .fixedSize()
                        .position(x: min(max(x(p.minutes), 40), w - 40), y: 10)
                        .allowsHitTesting(false)
                } else if points.count >= 2 {
                    // 最短・最長の値
                    ForEach(Array(Set([lo, hi])), id: \.self) { m in
                        Text("\(m)").font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textMain))
                            .fixedSize().position(x: x(m), y: 24)
                    }
                }
            }
        }
        .frame(height: 72)
        .accessibilityElement(children: .contain)
    }
}

/// 最近の回の評点。棒の上に値、平均の破線、横軸に回番号。最新だけ濃く、ほかは50%。解析待ちは点線の枠。
struct RecentBars: View {
    struct Column: Identifiable {
        let id: String
        let label: String
        let value: Double?     // nil = 解析中
        let isLatest: Bool
    }
    let columns: [Column]
    let average: Double

    private let barArea: CGFloat = 88
    private let labelHeight: CGFloat = 14
    private let maxValue = 5.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(columns) { c in
                VStack(spacing: NCSpace.s1) {
                    if let v = c.value {
                        Text(String(format: "%.1f", v)).font(.nc(NCText.numXs))
                            .foregroundStyle(Color.nc(c.isLatest ? .textMain : .textSub))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.nc(.accentFactor).opacity(c.isLatest ? 1 : 0.5))
                            .frame(height: barArea * CGFloat(v / maxValue))
                    } else {
                        Text(NCString.analyzing).font(.nc(NCText.caption)).foregroundStyle(Color.nc(.textSub))
                            .fixedSize()
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.nc(.borderControl), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(height: barArea * 0.5)
                    }
                    Text(c.label).font(.nc(NCText.numXs)).foregroundStyle(Color.nc(.textSub)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(height: labelHeight)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(c.label)
                .accessibilityValue(c.value.map { "評点 \(String(format: "%.1f", $0))" } ?? NCString.analyzing)
            }
        }
        .overlay(alignment: .bottom) {
            // 平均の破線(横軸のラベルの高さぶん上げる)
            GeometryReader { g in
                let y = g.size.height - labelHeight - NCSpace.s1 - barArea * CGFloat(average / maxValue)
                Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                    .stroke(Color.nc(.textSub), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
