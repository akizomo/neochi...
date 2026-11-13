import SwiftUI
import NeochiCore

/// 朝の振り返り(`docs/SCORE.md` §4)。「あなたの睡眠の結果」と「この回について(質問)」を、見出しで分ける。
/// 「記録する」を押すまで保存しない。質問はすべて任意。
struct MorningView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var interest: InterestAnswer?
    @State private var calm: Int?
    @State private var note = ""

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
                if let l = listened { listenedSection(l.show, l.episode) }
                ratingSection
                Section(NCString.memoHeader) {
                    TextField("", text: $note, axis: .vertical).lineLimit(1...4).ncText(NCText.body)
                        .listRowBackground(Color.nc(.surface))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.nc(.bgBase))
            .scrollDismissesKeyboard(.interactively)
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
                HStack {
                    Text(NCString.resultFrom).ncText(NCText.footnote, .textSub)
                    Spacer()
                    InfoButton(title: NCString.infoResultTitle, lines: NCString.infoResult)
                }
                if let m = minutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s2) {
                        Text("\(m)").ncText(NCText.numHero, .accentResult)
                        Text("分").ncText(NCText.title, .accentResult)
                    }
                    Text(NCString.comment(minutes: m)).ncText(NCText.headline)
                    if model.onsetAt != nil { Text(NCString.resultSourceWatch).ncText(NCText.footnote, .textSub) }
                } else {
                    Text("―").ncText(NCText.numHero, .textSub)
                    Text(NCString.noResultNote).ncText(NCText.body, .textSub)
                }
            }
            .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.resultHeader) }
    }

    /// どのコンテンツを聴いたか。
    private func listenedSection(_ show: Show, _ episode: Episode?) -> some View {
        Section {
            HStack(spacing: NCSpace.s3) {
                ArtworkView(show: show)
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text(show.title).ncText(NCText.headline).lineLimit(2)
                    if let e = episode { Text(e.number.map { "第\($0)回" } ?? e.title).ncText(NCText.footnote, .textSub) }
                }
            }
            .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.listenedHeader) }
    }

    /// そのコンテンツの評価。2つの質問は、同じ部品(`ChoiceScale`)で出す。
    private var ratingSection: some View {
        Section {
            ChoiceScale(question: NCString.interestQuestion, infoTitle: NCString.infoInterestTitle, infoLines: NCString.infoInterest, count: InterestAnswer.allCases.count,
                        selection: interestBinding,
                        leading: NCString.interestLabel(.bored), middle: NCString.interestLabel(.justRight),
                        trailing: NCString.interestLabel(.absorbed))
                .listRowBackground(Color.nc(.surface))
            ChoiceScale(question: NCString.calmQuestion, infoTitle: NCString.infoCalmTitle, infoLines: NCString.infoCalm, count: 5, selection: $calm,
                        leading: NCString.calmLow, trailing: NCString.calmHigh)
                .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.ratingHeader) } footer: { Text(NCString.ratingFooter) }
    }

    /// 1〜3 の選択位置 ↔ 興味の3択(-1 / 0 / 1)。
    private var interestBinding: Binding<Int?> {
        Binding(get: { interest.map { $0.rawValue + 2 } },
                set: { interest = $0.flatMap { InterestAnswer(rawValue: $0 - 2) } })
    }

    /// 親指が届く画面の下に置く。
    private var actions: some View {
        VStack(spacing: NCSpace.s1) {
            Button {
                model.saveLog(interest: interest, calm: calm, note: note)
                dismiss()
            } label: {
                Text(NCString.save).ncText(NCText.headline, .bgBase)
                    .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            Button(NCString.later) { dismiss() }
                .ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
        }
        .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s2)
        .background(Color.nc(.bgBase))
    }
}
