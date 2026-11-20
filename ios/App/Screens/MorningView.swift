import SwiftUI
import NeochiCore

/// 朝の振り返り(`docs/SCORE.md` §4)。「あなたの睡眠の結果」と「この回について(質問)」を、見出しで分ける。
/// 「記録する」を押すまで保存しない。質問はすべて任意。
struct MorningView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var interest: Int?
    @State private var calm: Int?
    @State private var note = ""
    @State private var selfReport: SelfReportLatency?

    private var minutes: Int? { model.pendingLatency }

    /// 聴いたコンテンツ。再生した回、なければ昨夜の回。
    private var listened: (show: Show, episode: Episode?)? {
        let showID = model.playShowID ?? model.lastNight?.showID
        let epID = model.playEpisodeID ?? model.lastNight?.episodeID
        guard let showID, let show = model.shows.first(where: { $0.id == showID }) else { return nil }
        return (show, epID.flatMap { id in model.episodes[showID]?.first { $0.id == id } })
    }

    var body: some View {
        NavigationStack {
            Form {
                resultSection
                if minutes == nil { selfReportSection }
                if let l = listened { listenedSection(l.show, l.episode) }
                ratingSection
                Section {
                    TextField(NCString.memoHeader, text: $note, axis: .vertical).lineLimit(1...4).ncText(NCText.body)
                        .listRowBackground(Color.nc(.surface))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.nc(.bgBase))
            .scrollDismissesKeyboard(.interactively)
            .appDestinations()
            .navigationTitle(NCString.morningTitle)
            .toolbarTitleDisplayMode(.inlineLarge)
            .safeAreaInset(edge: .bottom) { actions }
        }
        .task { await model.refreshOnset() }
    }

    /// 睡眠の結果: 分数と、それに対するひとこと。
    private var resultSection: some View {
        Section {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                Text(NCString.resultFrom).ncText(NCText.footnote, .textSub)
                if let m = minutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s2) {
                        Text("\(m)").ncText(NCText.numHero, .accentResult)
                        Text("分").ncText(NCText.title, .accentResult)
                    }
                    Text(NCString.comment(minutes: m)).ncText(NCText.headline)
                    LatencyGauge(minutes: m).padding(.top, NCSpace.s2)
                    let recent = model.recentNights(including: (model.playStartedAt ?? Date(), m))
                    if recent.count >= 2 { DataAccordion(title: "最近の夜と比べる") { RecentNightsChart(nights: recent) } }
                    if let s = model.playStartedAt, let o = model.onsetAt {
                        HStack(spacing: NCSpace.s6) {
                            timeColumn(NCString.startedLabel, s)
                            timeColumn(NCString.onsetLabel, o)
                        }
                        .padding(.top, NCSpace.s2)
                    }
                } else {
                    // 測れていない朝(ウォッチがない人が多い。あっても、反映が遅れていることがある)。大きな「―」は出さず、
                    // 答えられるようにする。答えたら、その目安をゾーンの目盛りに置く。
                    if let r = selfReport {
                        Text(r.label).ncText(NCText.title, .accentResult)
                        LatencyGauge(minutes: r.minutes, approximate: true).padding(.top, NCSpace.s1)
                    } else if model.onsetAfterPlayback {
                        Text(NCString.notWhileListeningNote).ncText(NCText.title)
                    } else {
                        Text(model.hasHealthSleepData ? "ヘルスケアの記録を待っています" : "睡眠データがありません").ncText(NCText.title)
                    }

                }
            }
            .listRowBackground(Color.nc(.surface))
        }
    }

    /// ヘルスケアに睡眠の記録がない朝。分数ではなく、選択肢で答える(答えなくても記録できる)。
    private var selfReportSection: some View {
        Section {
            ForEach(SelfReportLatency.allCases, id: \.self) { opt in
                Button { selfReport = selfReport == opt ? nil : opt } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: NCSpace.s1) {
                            Text(opt.label).ncText(NCText.body)
                            Text(opt.hint).ncText(NCText.footnote, .textSub)
                        }
                        Spacer()
                        if selfReport == opt { Image(systemName: "checkmark").font(.system(size: NCSize.iconSm, weight: .semibold)).foregroundStyle(Color.nc(.accentResult)) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selfReport == opt ? .isSelected : [])
                .listRowBackground(Color.nc(.surface))
            }
        } header: { Text(NCString.selfReportHeader) } footer: {
            Text(model.onsetAfterPlayback ? NCString.selfReportFooterNotWhileListening
                 : (model.hasHealthSleepData ? NCString.awaitingHealthNote + "" : "") + NCString.selfReportFooter)
        }
    }

    /// 数字の元になった時刻(データ)。ヘルスケアで入眠が確認できたときだけ出す。
    private func timeColumn(_ label: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: NCSpace.s1) {
            Text(label).ncText(NCText.footnote, .textSub)
            Text(date.formatted(.dateTime.hour().minute())).ncText(NCText.numMd)
        }
    }

    /// どのコンテンツを聴いたか。
    private func listenedSection(_ show: Show, _ episode: Episode?) -> some View {
        Section {
            NavigationLink(value: show.id) {
                HStack(spacing: NCSpace.s3) {
                    ArtworkView(show: show)
                    VStack(alignment: .leading, spacing: NCSpace.s1) {
                        Text(show.title).ncText(NCText.headline).lineLimit(2)
                        if let e = episode { Text(e.number.map { "第\($0)話" } ?? e.title).ncText(NCText.footnote, .textSub) }
                    }
                }
            }
            .listRowBackground(Color.nc(.surface))
        }
    }

    /// そのコンテンツの評価。2つの質問は、同じ部品(`ChoiceScale`)で出す。
    private var ratingSection: some View {
        Section {
            InterestRatingPicker(selection: $interest)
                .listRowBackground(Color.nc(.surface))
            ChoiceScale(question: NCString.calmQuestion, info: NCString.infoCalm, count: 5, selection: $calm,
                        leading: NCString.calmLow, trailing: NCString.calmHigh)
                .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.ratingHeader) } footer: { Text(NCString.ratingFooter) }
    }

    /// 親指が届く画面の下に置く。
    private var actions: some View {
        VStack(spacing: NCSpace.s1) {
            NCButton(title: NCString.save) {
                model.saveLog(interest: interest, calm: calm, note: note, selfReport: selfReport)
                dismiss()
            }
            NCButton(title: NCString.later, kind: .text, size: .medium) { dismiss() }
        }
        .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s2)
        .background(Color.nc(.bgBase))
    }
}
