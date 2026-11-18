import SwiftUI
import Charts
import NeochiCore

/// 番組の詳細。「どんな番組か。次にどの話を聴くか」に答える。
/// 上から: 評点と実測 → 次に聴く話(今夜・明日聴く) → この番組の傾向 → 寝落ちの実績 → 最近の話 → 話の一覧 → 解析について。
/// 観点ごとの根拠(起伏・耳・興味の中身)は、話ごとのものなので、話の詳細で見せる。
/// 要因(★・琥珀)は左、結果(ランク・分・青灰)は右。合算しない。
struct DetailView: View {
    @Environment(AppModel.self) private var model
    let showID: String
    /// 話の一覧を、すべて広げているか。
    @State private var listExpanded = false

    private var show: Show? { model.shows.first { $0.id == showID } }
    /// 話(新しい順)。
    private var episodes: [Episode] { model.episodes[showID] ?? [] }
    /// 解析がある話(新しい順)。
    private var analyzed: [(Episode, EpisodeAnalysis)] {
        episodes.compactMap { e in model.analyses[e.id].map { (e, $0) } }
    }
    private var latest: (Episode, EpisodeAnalysis)? { analyzed.first }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "M/d"; return f
    }()

    var body: some View {
        ScrollView {
            if let show {
                VStack(alignment: .leading, spacing: NCSpace.s4) {
                    header(show)
                    duo(show)
                    nextEpisode(show)
                    tendency(show)
                    record(show)
                    if analyzed.filter({ $0.1.finalStar != nil && $0.1.isJudged }).count >= 2 { recent }
                    // 話の一覧は長くなるので、実績と最近の話のあと(話が多いと、実績が下に押しやられるため)。
                    episodeList
                    if let (_, a) = latest { AboutAnalysis(analysis: a) } else {
                        Text("この番組の解析は、まだありません。").ncText(NCText.footnote, .textSub)
                    }
                    #if DEBUG
                    Text("読み込み: \(model.remoteStatus)").ncText(NCText.caption, .textSub)
                    #endif
                }
                .padding(NCSpace.s4)
            }
        }
        .refreshable { await model.refresh() }
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
                if let g = GenreLabel.display(show.genre) { Text(g).ncText(NCText.footnote, .textSub) }
            }
        }
    }

    private func duo(_ show: Show) -> some View { duoRow(show) }

    private func duoRow(_ show: Show) -> some View {
        HStack(alignment: .top, spacing: NCSpace.s4) {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                // 何から出した評点かは、見出しに添える(下に別の行で「AI解析」と出すと、浮いて見えたため)。
                let n = show.stats?.count ?? 0
                Text(n >= 3 ? "評点(AI解析と実測\(n)件)" : "評点(AI解析)").ncText(NCText.caption, .textSub)
                StarScore(star: show.star)
            }
            Rectangle().fill(Color.nc(.line)).frame(width: 1, height: 56)
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("寝落ちまで(ヘルスケアの実測の平均)").ncText(NCText.caption, .textSub)
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

    // MARK: 次に聴く話

    /// 主役は、次に聴く話。「今夜聴く」は、この話を予約する(どの話か見える)。
    @ViewBuilder private func nextEpisode(_ show: Show) -> some View {
        let candidate = model.nextCandidate(for: show)
        let tonightC = model.reservation(night: 0).flatMap { $0.show.id == show.id ? $0 : nil }
        let tomorrowC = model.reservation(night: 1).flatMap { $0.show.id == show.id ? $0 : nil }
        let shown = tonightC ?? tomorrowC ?? candidate
        let reserved = tonightC != nil
        VStack(spacing: NCSpace.s3) {
            if let c = shown, let ep = c.episode {
                NavigationLink(value: EpisodeRoute(id: ep.id)) {
                    VStack(alignment: .leading, spacing: NCSpace.s2) {
                        // 見出しは1つだけ。予約済みなら「今夜聴く話」、まだなら、その話を選んだ理由(最新の話、昨夜は18分で寝落ち、など)。
                        if reserved || tomorrowC != nil {
                            Text(reserved ? "今夜聴く話" : "明日聴く話").ncText(NCText.caption, .textSub)
                        } else {
                            ReasonText(reason: c.reason)
                        }
                        HStack(alignment: .top, spacing: NCSpace.s2) {
                            VStack(alignment: .leading, spacing: NCSpace.s1) {
                                Text(ep.title).ncText(NCText.headline).lineLimit(2).multilineTextAlignment(.leading)
                                Text(episodeMeta(ep)).ncText(NCText.footnote, .textSub)
                            }
                            Spacer(minLength: 0)
                            if let star = model.analyses[ep.id]?.shownStar { StarScore(star: star, style: NCText.numMd) }
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.nc(.textSub))
                                .padding(.top, NCSpace.s1)
                        }
                    }
                    .padding(NCSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
                }
                .buttonStyle(.pressable)
            }
            HStack(spacing: NCSpace.s2) {
                ReserveButton(night: 0, reserved: reserved) { model.toggleReserve(show, night: 0) }
                ReserveButton(night: 1, reserved: tomorrowC != nil) { model.toggleReserve(show, night: 1) }
            }
            // 決めたあと、何が起きるかを書く(今夜タブと同じ言葉)。
            if reserved || tomorrowC != nil {
                Text(model.reservationNote(night: reserved ? 0 : 1)).ncText(NCText.footnote, .textSub)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            if let c = candidate {
                NCButton(title: "いま聴く", kind: .text, size: .medium) { model.play(c) }
            }
        }
    }

    /// 「11/12 · 42分 · 聴いた」。あるものだけ。
    private func episodeMeta(_ ep: Episode) -> String {
        var parts: [String] = []
        if let d = ep.publishedAt { parts.append(Self.monthDay.string(from: d)) }
        if let s = ep.durationSec { parts.append("\(max(1, Int((Double(s) / 60).rounded())))分") }
        if model.listenCount(ep) > 0 { parts.append("聴いた") }
        if model.isReservedTonight(episode: ep) { parts.append("今夜予約済み") }
        return parts.joined(separator: " · ")
    }

    // MARK: この番組の傾向(話の平均)

    @ViewBuilder private func tendency(_ show: Show) -> some View {
        let a = show.aspects
        let line = show.oneLiner
        if line != nil || a?.calmStar != nil || a?.earStar != nil || a?.interest != nil {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHead("この番組の傾向")
                    Spacer()
                    Text("AI解析、話の平均").ncText(NCText.caption, .textSub)
                }.padding(.top, NCSpace.s2)
                card {
                    if let line { Text(line).ncText(NCText.body) }
                    // 3つの観点は、いつも並べる。判定がまだの観点は「判定待ち」(1つだけ出すと、それが番組の評価に見える)。
                    if let v = a?.calmStar { tendencyRow("起伏の少なさ", star: v) } else { tendencyRow("起伏の少なさ", pending: true) }
                    if let v = a?.earStar { tendencyRow("耳のゆるさ", star: v) } else { tendencyRow("耳のゆるさ", pending: true) }
                    if let l = a?.interest { tendencyRow("程よい興味", text: NCString.interestWord(l)) } else { tendencyRow("程よい興味", pending: true) }
                }
            }
        }
    }

    private func tendencyRow(_ title: String, star: Double? = nil, text: String? = nil, pending: Bool = false) -> some View {
        HStack {
            Text(title).ncText(NCText.body)
            Spacer()
            if let star {
                Text("★").ncText(NCText.numSm, .accentFactor)
                Text(String(format: "%.1f", star)).ncText(NCText.numMd, .accentFactor)
            } else if let text {
                Text(text).ncText(NCText.body, .accentFactor)
            } else if pending {
                Text(NCString.judgePending).ncText(NCText.footnote, .textSub)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 話の一覧

    @ViewBuilder private var episodeList: some View {
        if !episodes.isEmpty {
            let visible = listExpanded ? episodes : Array(episodes.prefix(8))
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHead("話の一覧")
                    Spacer()
                    Text("\(episodes.count)話").ncText(NCText.caption, .textSub)
                }.padding(.top, NCSpace.s2)
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { i, ep in
                        if i > 0 { Divider().overlay(Color.nc(.line)) }
                        episodeRow(ep)
                    }
                    if episodes.count > visible.count {
                        Divider().overlay(Color.nc(.line))
                        Button { withAnimation { listExpanded = true } } label: {
                            Text("すべての話を見る").ncText(NCText.footnote, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NCSpace.s4)
                .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
            }
        }
    }

    private func episodeRow(_ ep: Episode) -> some View {
        let a = model.analyses[ep.id]
        return NavigationLink(value: EpisodeRoute(id: ep.id)) {
            HStack(spacing: NCSpace.s3) {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(ep.title).ncText(NCText.body).lineLimit(1).truncationMode(.tail)
                    Text(episodeMeta(ep)).ncText(NCText.caption, .textSub)
                }
                Spacer(minLength: 0)
                if let star = a?.shownStar {
                    StarScore(star: star, style: NCText.headline)
                } else {
                    Text(a == nil ? "解析待ち" : NCString.judgePending).ncText(NCText.caption, .textSub)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.nc(.textSub))
            }
            .padding(.vertical, NCSpace.s2)
            .frame(minHeight: NCSize.rowH * 0.8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                Text("再生を始めてから眠るまで(ヘルスケアの実測)").ncText(NCText.caption, .textSub)
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
                            DeltaPill(delta: d, polarity: .lowerIsBetter, format: { "\(Int($0.rounded()))分" }, caption: NCString.deltaCaptionRecords,
                                      spoken: ("長い", "短い"))
                        }
                    }
                    if !mins.isEmpty {
                        SleepDotAxis(points: points)
                        HStack(spacing: NCSpace.s4) {
                            legendDot("30分未満 \(mins.filter { $0 < 30 }.count)件", filled: true)
                            legendDot("30分以上 \(mins.filter { $0 >= 30 }.count)件", filled: false)
                        }
                        Text(NCString.sleepZoneNote).ncText(NCText.caption, .textSub)
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
        // 棒は、起伏・興味を判定済みの回だけ(耳だけの点を、回の評点として並べない)。それより新しい未判定の回は「解析中」。
        let scored = analyzed.filter { $0.1.finalStar != nil && $0.1.isJudged }
        guard let newest = scored.first?.0, let idx = episodes.firstIndex(where: { $0.id == newest.id }) else { return [] }
        let pending = episodes[..<idx].filter { model.analyses[$0.id]?.isJudged != true }.prefix(2)
        func label(_ e: Episode) -> String {
            if let n = DetailMath.episodeNumber(e) { return "\(n)話" }
            return e.publishedAt.map { Self.monthDay.string(from: $0) } ?? ""
        }
        let cols = pending.map { RecentBars.Column(id: $0.id, label: label($0), value: nil, isLatest: false) }
            + scored.prefix(8).map { RecentBars.Column(id: $0.0.id, label: label($0.0), value: $0.1.finalStar, isLatest: $0.0.id == newest.id) }
        return cols.reversed()
    }


    private var recent: some View {
        let cols = recentColumns
        let values = cols.compactMap(\.value)          // 古い順
        let avg = DetailMath.mean(values) ?? 0
        return VStack(alignment: .leading, spacing: NCSpace.s2) {
            HStack {
                sectionHead("最近の話")
                Spacer()
                Text("話ごとの評点").ncText(NCText.caption, .textSub)
            }.padding(.top, NCSpace.s2)
            card {
                HStack(alignment: .center, spacing: NCSpace.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text(String(format: "%.1f", avg)).ncText(NCText.numMd, .accentFactor)
                        Text("\(values.count)話の平均").ncText(NCText.footnote, .textSub)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    if let d = DetailMath.delta(values) {
                        DeltaPill(delta: d, polarity: .higherIsBetter, format: { String(format: "%.1f", $0) }, caption: NCString.deltaCaptionEpisodes,
                                  spoken: ("高い", "低い"))
                    }
                }
                RecentBars(columns: cols, average: avg)
            }
        }
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
