import SwiftUI
import Charts
import NeochiCore

/// 番組の詳細。上から: 寝落ち適性(★)と実測 → AIの見立て → 観点ごとの根拠 → 寝落ちの実績 → 最近の回 → 解析について。
/// 要因(★・琥珀)は左、結果(ランク・分・青灰)は右。合算しない。
struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let showID: String

    private var show: Show? { model.shows.first { $0.id == showID } }
    private var episodes: [Episode] { model.episodes[showID] ?? [] }
    /// 解析がある回(新しい順)。
    private var analyzed: [(Episode, EpisodeAnalysis)] {
        episodes.compactMap { e in model.analyses[e.id].map { (e, $0) } }
    }
    private var latest: (Episode, EpisodeAnalysis)? { analyzed.first }

    var body: some View {
        ScrollView {
            if let show {
                VStack(alignment: .leading, spacing: NCSpace.s4) {
                    header(show)
                    duo(show)
                    actions(show)
                    if let (_, a) = latest {
                        if let line = a.reason ?? show.oneLiner { card { sectionHead("AIの見立て"); Text(line).ncText(NCText.body) } }
                        evidence(a)
                    } else if let line = show.oneLiner {
                        card { sectionHead("AIの見立て"); Text(line).ncText(NCText.body) }
                    }
                    record(show)
                    if analyzed.count >= 2 { recent }
                    if let (e, a) = latest { about(a, episode: e) }
                }
                .padding(NCSpace.s4)
            }
        }
        .background(Color.nc(.bgBase))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let show { FavoriteButton(isOn: model.favorites.contains(show.id), title: show.title) { model.toggleFavorite(show) } }
            }
        }
    }

    // MARK: 上部

    private func header(_ show: Show) -> some View {
        HStack(spacing: NCSpace.s4) {
            ArtworkView(show: show, size: NCSize.artworkL)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text(show.title).ncText(NCText.title)
                if let e = episodes.first { Text(e.title).ncText(NCText.footnote, .textSub).lineLimit(1) }
            }
        }
    }

    private func duo(_ show: Show) -> some View {
        HStack(alignment: .top, spacing: NCSpace.s4) {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("寝落ち適性(AI解析)").ncText(NCText.caption, .textSub)
                HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                    Text("★").ncText(NCText.numMd, .accentFactor)
                    Text(show.star.map { String(format: "%.1f", $0) } ?? "―").ncText(NCText.numMd, .accentFactor)
                }
            }
            Rectangle().fill(Color.nc(.line)).frame(width: 1, height: 56)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("実測(ウォッチ)").ncText(NCText.caption, .textSub)
                HStack(spacing: NCSpace.s2) {
                    RankBadge(rank: show.rank)
                    if let m = show.avgMinutes {
                        HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                            Text("\(m)").ncText(NCText.numMd, .accentResult)
                            Text("分").ncText(NCText.footnote, .accentResult)
                        }
                    } else {
                        Text("―").ncText(NCText.numMd, .textSub)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ show: Show) -> some View {
        HStack(spacing: NCSpace.s2) {
            Button {
                if let c = model.slate(night: 0).first(where: { $0.show.id == show.id }) ?? model.slate(night: 0).first {
                    model.reserve(night: 0, c); dismiss()
                }
            } label: {
                Text("今夜聴く").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            Button {
                if let i = model.queue.firstIndex(of: show.id) { model.queue.remove(at: i) } else { model.queue.append(show.id) }
            } label: {
                Text(model.queue.contains(show.id) ? "次に聴くから外す" : "次に聴く").ncText(NCText.body)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
            }
        }
    }

    // MARK: 観点ごとの根拠

    private func evidence(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            sectionHead("観点ごとの根拠").padding(.top, NCSpace.s2)
            VStack(spacing: 0) {
                if let v = a.calmStar {
                    axis("起伏の少なさ", star: v) { calmDetail(a) }
                    if a.earStar != nil || a.interest != nil { Divider().overlay(Color.nc(.line)) }
                }
                if let v = a.earStar {
                    axis("耳のゆるさ", star: v) { earDetail(a) }
                    if a.interest != nil { Divider().overlay(Color.nc(.line)) }
                }
                if let l = a.interest {
                    axis("程よい興味", text: interestWord(l)) { interestDetail(a, l) }
                }
            }
            .padding(.horizontal, NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
    }

    private func calmDetail(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            let pts = a.volumePerMin.enumerated().compactMap { i, v in v.map { (i, $0) } }
            if !pts.isEmpty {
                Text("音量の推移(回全体の中央値との差)").ncText(NCText.footnote, .textSub)
                Chart {
                    RuleMark(y: .value("中央値", 0)).foregroundStyle(Color.nc(.line))
                    ForEach(pts, id: \.0) { LineMark(x: .value("分", $0.0), y: .value("dB", $0.1)).foregroundStyle(Color.nc(.textMain)) }
                    ForEach(a.suddenAtSec.prefix(60), id: \.self) {
                        PointMark(x: .value("分", Double($0) / 60), y: .value("dB", 0)).foregroundStyle(Color.nc(.accentFactor)).symbolSize(24)
                    }
                }
                .chartXAxisLabel("分", alignment: .trailing)
                .frame(height: 120)
                HStack(spacing: NCSpace.s4) {
                    if let s = a.suddenPer10Min { legend("突発音 \(String(format: "%.1f", s)) 回/10分", .accentFactor) }
                    if let d = a.volumeStdDB { legend("ばらつき \(String(format: "%.1f", d)) dB", .textMain) }
                }
            }
            ForEach(a.moments, id: \.self) { m in
                (Text("\(m.minute)分").font(.nc(NCText.numSm)).foregroundStyle(Color.nc(.accentFactor))
                 + Text("  \(m.note)").font(.nc(NCText.footnote)).foregroundStyle(Color.nc(.textSub)))
            }
        }
    }

    private func earDetail(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            let pts = a.ratePerMin.enumerated().compactMap { i, v in v.map { (i, $0) } }
            if !pts.isEmpty {
                Text("話す速さの推移(冒頭の20分)").ncText(NCText.footnote, .textSub)
                Chart {
                    ForEach(pts, id: \.0) { LineMark(x: .value("分", $0.0), y: .value("字/分", $0.1)).foregroundStyle(Color.nc(.accentFactor)) }
                    RuleMark(y: .value("満点の上限", 290)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.nc(.textSub))
                }
                .frame(height: 120)
                HStack(spacing: NCSpace.s4) {
                    if let r = a.speechRate { legend("1分に\(Int(r.rounded()))字", .accentFactor) }
                    legend("破線 290字/分(満点の上限)", .textSub)
                }
            }
            if let p = a.earParts {
                VStack(spacing: 0) {
                    partRow("話す速さ", p.rate); partRow("速さのばらつき", p.rateCV)
                    partRow("音量の変化", p.volume); partRow("突発音", p.sudden)
                }
            }
        }
    }

    private func interestDetail(_ a: EpisodeAnalysis, _ l: InterestLevel) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            if let z = a.interestScore {
                HStack(spacing: 3) {
                    ForEach(1...10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(i == z ? Color.nc(.accentFactor) : Color.nc(.line)).frame(height: 8)
                    }
                }
                HStack {
                    Text("退屈寄り").ncText(NCText.caption, .textSub); Spacer(); Text("夢中寄り").ncText(NCText.caption, .textSub)
                }
            }
            Text("AIの見立ては、\(interestWord(l))です").ncText(NCText.footnote, .textSub)
        }
    }

    private func interestWord(_ l: InterestLevel) -> String {
        switch l { case .low: "退屈寄り"; case .mid: "程よい"; case .high: "夢中寄り" }
    }

    private func partRow(_ title: String, _ v: Double?) -> some View {
        Group {
            if let v {
                HStack {
                    Text(title).ncText(NCText.footnote, .textSub)
                    Spacer()
                    Text("★").ncText(NCText.numSm, .accentFactor)
                    Text(String(format: "%.1f", v)).ncText(NCText.numSm, .accentFactor)
                }.frame(minHeight: 32)
            }
        }
    }

    private func legend(_ text: String, _ color: NCColor) -> some View {
        HStack(spacing: NCSpace.s1) {
            Circle().fill(Color.nc(color)).frame(width: 6, height: 6)
            Text(text).ncText(NCText.caption, .textSub)
        }
    }

    /// 開閉できる観点の行。右に★(または言葉)を出し、押すと根拠が開く。
    private func axis<Content: View>(_ title: String, star: Double? = nil, text: String? = nil,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            content().padding(.bottom, NCSpace.s3)
        } label: {
            HStack {
                Text(title).ncText(NCText.body)
                Spacer()
                if let star {
                    Text("★").ncText(NCText.numSm, .accentFactor)
                    Text(String(format: "%.1f", star)).ncText(NCText.numMd, .accentFactor)
                } else if let text {
                    Text(text).ncText(NCText.body, .accentFactor)
                }
            }.frame(minHeight: NCSize.tapMin)
        }
        .tint(Color.nc(.textSub))
    }

    // MARK: 実績・最近の回・解析について

    private func record(_ show: Show) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack {
                sectionHead("寝落ちの実績")
                Spacer()
                Text("ウォッチで測った記録").ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
            card {
                if let st = show.stats {
                    HStack {
                        RankBadge(rank: show.rank)
                        Text("\(st.count)回の記録").ncText(NCText.headline)
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                            Text("\(st.avgMinutes)").ncText(NCText.numMd, .accentResult)
                            Text("分(平均)").ncText(NCText.footnote, .accentResult)
                        }
                    }
                    Text("最短 \(st.minMinutes)分、最長 \(st.maxMinutes)分。\(st.count)回のうち \(st.under30)回が、30分より前に寝落ちしました。")
                        .ncText(NCText.body)
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            Capsule().fill(Color.nc(.accentResult)).frame(width: max(0, g.size.width * CGFloat(st.under30) / CGFloat(st.count)))
                            Capsule().strokeBorder(Color.nc(.accentResult), lineWidth: 1.5)
                        }
                    }.frame(height: 10)
                    HStack(spacing: NCSpace.s4) {
                        legend("30分未満 \(st.under30)回", .accentResult)
                        legend("30分以上 \(st.count - st.under30)回", .textSub)
                    }
                } else {
                    HStack {
                        RankBadge(rank: nil)
                        Text("寝落ちの記録").ncText(NCText.headline)
                        Spacer()
                        Text("―").ncText(NCText.numMd, .textSub)
                    }
                    Text("実測の記録はまだありません。").ncText(NCText.footnote, .textSub)
                }
            }
        }
    }

    private var recent: some View {
        let items = Array(analyzed.prefix(8).reversed())
        return VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack {
                sectionHead("最近の回")
                Spacer()
                Text("寝落ち適性(直近\(items.count)回)").ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
            card {
                Chart(Array(items.enumerated()), id: \.offset) { i, item in
                    BarMark(x: .value("回", i), y: .value("★", item.1.finalStar ?? 0))
                        .foregroundStyle(Color.nc(.accentFactor)).cornerRadius(3)
                }
                .chartYScale(domain: 0...5)
                .chartXAxis(.hidden)
                .frame(height: 100)
            }
        }
    }

    private func about(_ a: EpisodeAnalysis, episode: Episode) -> some View {
        DisclosureGroup {
            Text(aboutText(a)).ncText(NCText.footnote, .textSub).frame(maxWidth: .infinity, alignment: .leading).padding(.top, NCSpace.s2)
        } label: {
            Text("解析について").ncText(NCText.footnote, .textSub)
        }.tint(Color.nc(.textSub))
    }

    private func aboutText(_ a: EpisodeAnalysis) -> String {
        let depth: String
        switch a.inputDepth {
        case "audio": depth = "音響の分析だけで判定しています。"
        case "transcript": depth = "冒頭を文字起こしして判定しています。"
        default: depth = "番組の説明文だけで判定しています。"
        }
        let dur = a.durationSec.map { "音量の推移と突発音は、全編(\(Int(($0 / 60).rounded()))分)を測っています。" } ?? ""
        return dur + "話す速さと、起伏・興味の判定は、冒頭を文字起こしして行っています。30分以降を聴くのは寝つけなかったときだけなので、内容の評価は30分までにしています。" + depth
    }

    // MARK: 部品

    private func sectionHead(_ text: String) -> some View { Text(text).ncText(NCText.headline) }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3, content: content)
            .padding(NCSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }
}
