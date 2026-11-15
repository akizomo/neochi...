import SwiftUI
import Charts
import NeochiCore

/// 番組の詳細。上から: 評点と実測 → AI解析 → 観点ごとの根拠 → 寝落ちの実績 → 最近の回 → 解析について。
/// 要因(★・琥珀)は左、結果(ランク・分・青灰)は右。合算しない。
struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let showID: String
    /// 開いている観点(観点名)。
    @State private var openAxes: Set<String> = []

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
                    if let (e, a) = latest {
                        if let line = a.reason ?? show.oneLiner { card { sectionHead("AI解析"); Text(line).ncText(NCText.body) } }
                        evidence(e, a)
                    } else if let line = show.oneLiner {
                        card { sectionHead("AI解析"); Text(line).ncText(NCText.body) }
                    }
                    record(show)
                    if analyzed.filter({ $0.1.finalStar != nil }).count >= 2 { recent }
                    if let (e, a) = latest { about(a, episode: e) } else {
                        Text("この番組の解析は、まだありません。").ncText(NCText.footnote, .textSub)
                    }
                    #if DEBUG
                    Text("読み込み: \(model.remoteStatus)").ncText(NCText.caption, .textSub)
                    #endif
                }
                .padding(NCSpace.s4)
            }
        }
        .background(Color.nc(.bgBase))
        .toolbar {
            // 右上: 元のPodcastへ(外部リンク)と、お気に入り。
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let show {
                    if let url = show.appleURL ?? show.linkURL {
                        Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                            .accessibilityLabel("元のPodcastを開く")
                    }
                    FavoriteButton(isOn: model.favorites.contains(show.id), title: show.title, inToolbar: true) { model.toggleFavorite(show) }
                }
            }
        }
    }

    // MARK: 上部

    private func header(_ show: Show) -> some View {
        HStack(spacing: NCSpace.s4) {
            ArtworkView(show: show, size: NCSize.artworkL)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                if let r = show.rank {   // 詳細では、格付けはタイトルの上。横に意味を添える
                    HStack(spacing: NCSpace.s2) {
                        RankBadge(rank: r)
                        Text(NCString.rankMeaning(r)).ncText(NCText.caption, .textSub)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(show.title).ncText(NCText.title)
                if let e = episodes.first { Text(e.title).ncText(NCText.footnote, .textSub).lineLimit(1) }
            }
        }
    }

    private func duo(_ show: Show) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            duoRow(show)
            Text(NCString.ratingBreakdown(watchCount: show.stats?.count ?? 0, avgMinutes: show.stats?.avgMinutes ?? 0))
                .ncText(NCText.caption, .textSub)
        }
    }

    private func duoRow(_ show: Show) -> some View {
        HStack(alignment: .top, spacing: NCSpace.s4) {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("評点").ncText(NCText.caption, .textSub)
                StarScore(star: show.star)
            }
            Rectangle().fill(Color.nc(.line)).frame(width: 1, height: 56)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("寝落ちまで(ウォッチの実測の平均)").ncText(NCText.caption, .textSub)
                HStack(spacing: NCSpace.s2) {
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

    /// 主役は「今夜聴く」(昼に決めて夜に聴く)。「いま聴く」は、昼寝などのために控えめに置く。
    private func actions(_ show: Show) -> some View {
        VStack(spacing: NCSpace.s2) {
            tonightRow(show)
            if let c = TonightEngine.listenNow(show: show, ctx: model.context) {
                Button { model.play(c) } label: {
                    Text("いま聴く").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func tonightRow(_ show: Show) -> some View {
        HStack(spacing: NCSpace.s2) {
            Button {
                if let c = model.slate(night: 0).first(where: { $0.show.id == show.id }) ?? model.slate(night: 0).first {
                    model.reserve(night: 0, c); dismiss()
                }
            } label: {
                Text("今夜聴く").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            .buttonStyle(.pressable)
            Button {
                model.toggleQueue(show)
            } label: {
                Text(model.queue.contains(show.id) ? "次に聴くから外す" : "次に聴く").ncText(NCText.body)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: 観点ごとの根拠(最新の解析済みの回だけ)

    private func evidence(_ e: Episode, _ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack(alignment: .firstTextBaseline) {
                sectionHead("観点ごとの根拠")
                Spacer()
                Text(NCString.analyzedEpisode(DetailMath.episodeNumber(e))).ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
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
                    let total = a.interestScore ?? Explain.interestTotal(a.interestItems)
                    axis("程よい興味", text: interestWord(l), number: total) { interestDetail(a, total: total) }
                }
            }
            .padding(.horizontal, NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
    }

    // 起伏の少なさ: 判定の一行 → 1分ごとの起伏の線 → 4項目の行 → 計算式の注記。
    private func calmDetail(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            if !a.calmPerMin.isEmpty {
                Text(DetailMath.calmCurveVerdict(a.moments, minutes: a.calmPerMin.count)).ncText(NCText.body)
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("起伏の強さ(1分ごと)").ncText(NCText.footnote, .textSub)
                    CalmCurveChart(values: a.calmPerMin, moments: a.moments.filter { $0.minute < a.calmPerMin.count })
                }
            } else if !a.calmItems.isEmpty {
                Text(Explain.calmVerdict(a.calmItems)).ncText(NCText.body)
            }
            if !a.calmItems.isEmpty {
                itemRows(a.calmItems, labels: Explain.calmLabels)
                Text("項目は 0〜2 点。合計が小さいほど、★が多くなります(5 − 合計×0.5)").ncText(NCText.caption, .textSub)
            }
            if a.calmPerMin.isEmpty {   // 古い解析: 線がないので、目立つ箇所を文字で出す
                ForEach(a.moments, id: \.self) { m in
                    (Text("\(m.minute)分").font(.nc(NCText.numSm)).foregroundStyle(Color.nc(.accentFactor))
                     + Text("  \(m.note)").font(.nc(NCText.footnote)).foregroundStyle(Color.nc(.textSub)))
                }
            }
        }
    }

    // 耳のゆるさ: 話す速さと音量を、同じ横軸で縦に並べる。下に4項目それぞれの理由。
    private func earDetail(_ a: EpisodeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            EarCharts(analysis: a)
            let parts = Explain.earParts(a)
            if !parts.isEmpty {
                Text("なぜこの点か").ncText(NCText.footnote, .textSub).padding(.top, NCSpace.s1)
                VStack(spacing: NCSpace.s2) { ForEach(parts) { partCard($0) } }
            }
        }
    }

    // 程よい興味: 内容の要約 → 5項目の行 → 10段の目盛り(と注記)。
    private func interestDetail(_ a: EpisodeAnalysis, total: Int) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s3) {
            if let summary = a.contentSummary {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(NCString.summaryHeader).ncText(NCText.caption, .textSub)
                    Text(summary).ncText(NCText.footnote).fixedSize(horizontal: false, vertical: true)
                }
                .padding(NCSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NCRadius.sm, style: .continuous).fill(Color.nc(.bgBase)))
                .accessibilityElement(children: .combine)
            }
            if !a.interestItems.isEmpty {
                itemRows(a.interestItems, labels: Explain.interestLabels)
            }
            InterestScale(total: total)
        }
    }

    /// 採点項目を1行ずつ。点(●●○)と、根拠になった分。
    private func itemRows(_ items: [ScoredItem], labels: [String: String]) -> some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.key) { it in
                HStack(spacing: NCSpace.s2) {
                    Text(labels[it.key] ?? it.key).ncText(NCText.footnote)
                    Spacer()
                    if let m = it.minute, it.score > 0 { Text("\(m)分ごろ").ncText(NCText.caption, .textSub) }
                    Text(Explain.levelWord(it.score)).ncText(NCText.footnote, it.score > 0 ? .accentFactor : .textSub)
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle().fill(i < it.score ? Color.nc(.accentFactor) : Color.nc(.line)).frame(width: 8, height: 8)
                        }
                    }
                }.frame(minHeight: 32)
            }
        }
    }

    /// 🎧 の1項目: 測った値・結果のひとこと・基準。
    private func partCard(_ r: EarPartReport) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s1) {
            HStack {
                Text(r.title).ncText(NCText.footnote)
                Spacer()
                if let s = r.star {
                    Text("★").ncText(NCText.numSm, .accentFactor)
                    Text(String(format: "%.1f", s)).ncText(NCText.numSm, .accentFactor)
                }
            }
            Text("\(r.measured)。\(r.verdict)").ncText(NCText.footnote, r.good ? .accentResult : .textMain)
            Text(r.criterion).ncText(NCText.caption, .textSub)
        }
        .padding(NCSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NCRadius.sm, style: .continuous).fill(Color.nc(.bgBase)))
    }

    private func interestWord(_ l: InterestLevel) -> String {
        switch l { case .low: "静かめ"; case .mid: "程よい"; case .high: "強め" }
    }

    /// 開閉できる観点の行。右に★(または言葉)を出し、押すと根拠が開く。
    private func axis<Content: View>(_ title: String, star: Double? = nil, text: String? = nil, number: Int? = nil,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        let open = openAxes.contains(title)
        return VStack(alignment: .leading, spacing: 0) {
            // 見出しの行だけが開閉する(中の図を押しても閉じない)。
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if open { openAxes.remove(title) } else { openAxes.insert(title) }
                }
            } label: {
                HStack(spacing: NCSpace.s2) {
                    Text(title).ncText(NCText.body)
                    Spacer()
                    if let star {
                        Text("★").ncText(NCText.numSm, .accentFactor)
                        Text(String(format: "%.1f", star)).ncText(NCText.numMd, .accentFactor)
                    } else if let text {
                        Text(text).ncText(NCText.body, .accentFactor)
                        if let number { Text("\(number)").ncText(NCText.numMd, .accentFactor) }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.nc(.textSub))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: NCSize.tapMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(open ? "開いています" : "閉じています")
            if open {
                content().padding(.bottom, NCSpace.s3)
            }
        }
    }

    // MARK: 実績・最近の回・解析について

    private func record(_ show: Show) -> some View {
        let points = model.sleepPoints[show.id] ?? []
        let mins = points.map(\.minutes)
        let avg = DetailMath.mean(mins.map(Double.init)).map { Int($0.rounded()) } ?? show.stats?.avgMinutes
        return VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack {
                sectionHead("寝落ちの実績")
                Spacer()
                Text("再生を始めてから眠るまで(ウォッチの実測)").ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
            card {
                if let avg {
                    HStack(alignment: .center, spacing: NCSpace.s2) {
                        HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                            Text("平均").ncText(NCText.footnote, .textSub)
                            Text("\(avg)").ncText(NCText.numMd, .accentResult)
                            Text("分").ncText(NCText.footnote, .accentResult)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer()
                        if let d = DetailMath.delta(mins.map(Double.init)) {
                            DeltaPill(delta: d, format: { "\(Int($0.rounded()))分" }, caption: NCString.deltaCaptionRecords,
                                      spoken: ("長い", "短い"))
                        }
                    }
                    if !mins.isEmpty {
                        SleepDotAxis(minutes: mins, average: avg)
                        NightRow(points: points)
                        HStack(spacing: NCSpace.s4) {
                            legendDot("30分未満 \(mins.filter { $0 < 30 }.count)件", filled: true)
                            legendDot("30分以上 \(mins.filter { $0 >= 30 }.count)件", filled: false)
                        }
                    } else if let st = show.stats {
                        Text("最短 \(st.minMinutes)分、最長 \(st.maxMinutes)分。\(st.count)件のうち \(st.under30)件が、30分より前に寝落ちしました。")
                            .ncText(NCText.footnote)
                    }
                } else {
                    HStack {
                        Text("寝落ちの記録").ncText(NCText.headline)
                        Spacer()
                        Text("―").ncText(NCText.numMd, .textSub)
                    }
                    Text("実測の記録はまだありません。").ncText(NCText.footnote, .textSub)
                }
            }
        }
    }

    private func legendDot(_ text: String, filled: Bool) -> some View {
        HStack(spacing: NCSpace.s1) {
            Group {
                if filled { Circle().fill(Color.nc(.accentResult)) }
                else { Circle().strokeBorder(Color.nc(.accentResult), lineWidth: 1.5) }
            }.frame(width: 8, height: 8)
            Text(text).ncText(NCText.caption, .textSub)
        }
    }

    /// 最近の回の列(古い順)。解析済みの回を直近8回まで。それより新しい未解析の回は「解析中」として2回まで。
    private var recentColumns: [RecentBars.Column] {
        let scored = analyzed.filter { $0.1.finalStar != nil }
        guard let newest = scored.first?.0, let idx = episodes.firstIndex(where: { $0.id == newest.id }) else { return [] }
        let pending = episodes[..<idx].filter { model.analyses[$0.id] == nil }.prefix(2)
        func label(_ e: Episode) -> String {
            if let n = DetailMath.episodeNumber(e) { return "\(n)回" }
            return e.publishedAt.map { Self.monthDay.string(from: $0) } ?? ""
        }
        let cols = pending.map { RecentBars.Column(id: $0.id, label: label($0), value: nil, isLatest: false) }
            + scored.prefix(8).map { RecentBars.Column(id: $0.0.id, label: label($0.0), value: $0.1.finalStar, isLatest: $0.0.id == newest.id) }
        return cols.reversed()
    }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "M/d"; return f
    }()

    private var recent: some View {
        let cols = recentColumns
        let values = cols.compactMap(\.value)          // 古い順
        let avg = DetailMath.mean(values) ?? 0
        return VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack {
                sectionHead("最近の回")
                Spacer()
                Text("回ごとの評点").ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
            card {
                HStack(alignment: .center, spacing: NCSpace.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text(String(format: "%.1f", avg)).ncText(NCText.numMd, .accentFactor)
                        Text("\(values.count)回の平均").ncText(NCText.footnote, .textSub)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    if let d = DetailMath.delta(values) {
                        DeltaPill(delta: d, format: { String(format: "%.1f", $0) }, caption: NCString.deltaCaptionEpisodes,
                                  spoken: ("高い", "低い"))
                    }
                }
                RecentBars(columns: cols, average: avg)
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
        return "音量の推移と突発音は、冒頭30分を測っています。話す速さと、起伏・興味の判定は、冒頭を文字起こしして行っています。30分以降を聴くのは寝つけなかったときだけなので、内容の評価は冒頭20分までにしています。" + depth
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
