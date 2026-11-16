import SwiftUI
import NeochiCore

/// 話の詳細。「この話は、寝落ちに向くか」に答える。上から: 番組へ → この話の評点 → 今夜聴く → AI解析 → 観点ごとの根拠 → あなたの記録 → 解析について。
/// 番組の詳細と違い、話の一覧は出さない。根拠は、この話のものだけを見せる。
struct EpisodeDetailView: View {
    @Environment(AppModel.self) private var model
    let episodeID: String

    private static let date: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日"; return f
    }()

    var body: some View {
        ScrollView {
            if let (show, ep) = model.episode(id: episodeID) {
                let analysis = model.analyses[ep.id]
                VStack(alignment: .leading, spacing: NCSpace.s4) {
                    showLink(show)
                    heading(show, ep)
                    scoreCard(show, analysis)
                    actions(show, ep)
                    if let line = analysis?.reason { card { sectionHead("AI解析"); Text(line).ncText(NCText.body) } }
                    if let a = analysis, a.hasAnyAspect { EvidenceView(episode: ep, analysis: a) }
                    if analysis == nil || analysis?.finalStar == nil {
                        Text("この話は、まだ解析していません。").ncText(NCText.footnote, .textSub)
                    }
                    myLogs(ep)
                    if let a = analysis { AboutAnalysis(analysis: a) }
                }
                .padding(NCSpace.s4)
            } else {
                Text("この話が見つかりません。").ncText(NCText.footnote, .textSub).padding(NCSpace.s4)
            }
        }
        .background(Color.nc(.bgBase))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let (_, ep) = model.episode(id: episodeID), let url = ep.linkURL {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        .accessibilityLabel("元のPodcastを開く")
                }
            }
        }
    }

    // MARK: 上部

    /// 番組の詳細へ。話の詳細から、番組全体を見に行く入口。
    private func showLink(_ show: Show) -> some View {
        NavigationLink(value: show.id) {
            HStack(spacing: NCSpace.s3) {
                ArtworkView(show: show, size: NCSize.artworkS, showsRank: true)
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(show.title).ncText(NCText.headline).lineLimit(1)
                    Text("番組を見る").ncText(NCText.footnote, .textSub)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.nc(.textSub))
            }
            .padding(NCSpace.s3)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.pressable)
    }

    private func heading(_ show: Show, _ ep: Episode) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s1) {
            Text(ep.title).ncText(NCText.title)
            Text(meta(ep)).ncText(NCText.footnote, .textSub)
        }
    }

    /// 「11月12日 · 42分 · 2回目」。あるものだけ。
    private func meta(_ ep: Episode) -> String {
        var parts: [String] = []
        if let d = ep.publishedAt { parts.append(Self.date.string(from: d)) }
        if let s = ep.durationSec { parts.append("\(max(1, Int((Double(s) / 60).rounded())))分") }
        let n = model.listenCount(ep)
        if n > 0 { parts.append("聴いた \(n)回") }
        return parts.joined(separator: " · ")
    }

    // MARK: 評点

    @ViewBuilder private func scoreCard(_ show: Show, _ a: EpisodeAnalysis?) -> some View {
        if let star = a?.finalStar {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                HStack(alignment: .top, spacing: NCSpace.s4) {
                    VStack(alignment: .leading, spacing: NCSpace.s1) {
                        Text("この話の評点").ncText(NCText.caption, .textSub)
                        StarScore(star: star)
                    }
                    if let s = show.star {
                        Rectangle().fill(Color.nc(.line)).frame(width: 1, height: 56)
                        VStack(alignment: .leading, spacing: NCSpace.s1) {
                            Text("番組の評点").ncText(NCText.caption, .textSub)
                            StarScore(star: s, style: NCText.numMd)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let s = show.star, abs(star - s) >= 0.1 {
                    DeltaPill(delta: star - s, polarity: .higherIsBetter, format: { String(format: "%.1f", $0) },
                              caption: "番組の評点より", spoken: ("高い", "低い"))
                }
            }
        } else if let s = show.star {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text("番組の評点(この話は、解析待ち)").ncText(NCText.caption, .textSub)
                StarScore(star: s)
            }
        }
    }

    // MARK: アクション

    /// 「この話を」と明示して、話を指定して予約する。
    private func actions(_ show: Show, _ ep: Episode) -> some View {
        let reserved = model.isReservedTonight(episode: ep)
        return VStack(spacing: NCSpace.s2) {
            Button { model.toggleTonight(episode: ep, of: show) } label: {
                Label(reserved ? "今夜予約済み" : "この話を今夜聴く", systemImage: reserved ? "checkmark" : "moon")
                    .ncText(NCText.headline, reserved ? .textMain : .bgBase).frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(reserved ? Color.clear : Color.nc(.textMain)))
                    .overlay(Capsule().strokeBorder(Color.nc(.textMain), lineWidth: reserved ? 1.5 : 0))
            }
            .buttonStyle(.pressable)
            Button { model.playNow(episode: ep, of: show) } label: {
                Text("いま聴く").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: あなたの記録

    @ViewBuilder private func myLogs(_ ep: Episode) -> some View {
        let logs = model.logs.filter { $0.episodeID == ep.id }.sorted { $0.startedAt > $1.startedAt }
        if !logs.isEmpty {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                sectionHead("この話の、あなたの記録").padding(.top, NCSpace.s2)
                VStack(spacing: 0) {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { i, log in
                        if i > 0 { Divider().overlay(Color.nc(.line)) }
                        NavigationLink(value: LogRoute(id: log.id)) {
                            HStack(spacing: NCSpace.s3) {
                                Text(Self.date.string(from: log.startedAt)).ncText(NCText.footnote, .textSub)
                                Spacer()
                                if let m = log.latencyMinutes {
                                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                                        Text("\(m)").ncText(NCText.numMd, .accentResult)
                                        Text("分").ncText(NCText.footnote, .accentResult)
                                    }
                                } else {
                                    Text("―").ncText(NCText.numMd, .textSub)
                                }
                            }
                            .frame(minHeight: NCSize.tapMin)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NCSpace.s4)
                .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
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
