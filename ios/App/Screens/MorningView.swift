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

    var body: some View {
        NavigationStack {
            Form {
                resultSection
                if let m = minutes { Section(NCString.evaluationHeader) { Text(NCString.comment(minutes: m)).ncText(NCText.headline).listRowBackground(Color.nc(.surface)) } }
                interestSection
                calmSection
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

    private var resultSection: some View {
        Section {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                Text(NCString.resultFrom).ncText(NCText.footnote, .textSub)
                if let m = minutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s2) {
                        Text("\(m)").ncText(NCText.numHero, .accentResult)
                        Text("分").ncText(NCText.title, .accentResult)
                    }
                    if model.onsetAt != nil { Text(NCString.resultSourceWatch).ncText(NCText.footnote, .textSub) }
                } else {
                    Text("―").ncText(NCText.numHero, .textSub)
                    Text(NCString.noResultNote).ncText(NCText.body, .textSub)
                }
            }
            .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.resultHeader) }
    }

    private var interestSection: some View {
        Section {
            Picker(NCString.interestQuestion, selection: $interest) {
                ForEach(InterestAnswer.allCases) { Text(NCString.interestLabel($0)).tag(Optional($0)) }
            }
            .pickerStyle(.inline).labelsHidden()
            .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.interestQuestion) } footer: { Text(NCString.askedFooter) }
    }

    private var calmSection: some View {
        Section {
            VStack(spacing: NCSpace.s2) {
                Picker(NCString.calmQuestion, selection: $calm) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
                }
                .pickerStyle(.segmented).labelsHidden()
                HStack {
                    Text(NCString.calmLow); Spacer(); Text(NCString.calmHigh)
                }.ncText(NCText.footnote, .textSub)
            }
            .listRowBackground(Color.nc(.surface))
        } header: { Text(NCString.calmQuestion) }
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
