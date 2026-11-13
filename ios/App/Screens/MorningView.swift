import SwiftUI
import NeochiCore

/// 朝の振り返り。結果を先に見せ、入力は 興味・起伏・メモ(任意)。「記録する」を押すまで保存しない。
struct MorningView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var interest: Double = 50
    @State private var interestTouched = false
    @State private var calm = 0
    @State private var note = ""

    private var minutes: Int? { model.pendingLatency }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NCSpace.s4) {
                HStack {
                    Text("朝の振り返り").ncText(NCText.footnote, .textSub)
                    Spacer()
                    Button("あとで") { dismiss() }.ncText(NCText.body, .textSub).frame(minHeight: NCSize.tapMin)
                }
                result
                inputs
                Button {
                    model.saveLog(interest: interestTouched ? Int(interest) : nil,
                                  calm: calm > 0 ? calm : nil, note: note)
                    dismiss()
                } label: {
                    Text("記録する").ncText(NCText.headline, .bgBase)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Color.nc(.textMain)))
                }
                .padding(.top, NCSpace.s2)
            }
            .padding(NCSpace.s4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.nc(.bgBase))
        .task { await model.refreshOnset() }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: NCSpace.s2) {
            Text("寝落ちまで").ncText(NCText.footnote, .textSub)
            if let m = minutes {
                HStack(alignment: .firstTextBaseline, spacing: NCSpace.s2) {
                    Text("\(m)").ncText(NCText.numHero, .accentResult)
                    Text("分").ncText(NCText.title, .accentResult)
                }
                Text(NCString.comment(minutes: m)).ncText(NCText.title)
            } else {
                Text("―").ncText(NCText.numHero, .textSub)
                Text(NCString.noResultNote).ncText(NCText.title)
            }
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: NCSpace.s6) {
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                HStack {
                    Text("興味").ncText(NCText.headline)
                    Spacer()
                    Text(interestTouched ? "\(Int(interest))" : "―").ncText(NCText.numMd, .accentFactor)
                }
                InterestScale(value: $interest, touched: $interestTouched)
            }
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                Text("起伏").ncText(NCText.headline)
                StarInput(value: $calm)
            }
            VStack(alignment: .leading, spacing: NCSpace.s2) {
                Text("メモ").ncText(NCText.headline)
                TextField("", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .ncText(NCText.body)
                    .padding(NCSpace.s3)
                    .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
                    .overlay(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous)
                        .strokeBorder(Color.nc(.borderControl), lineWidth: 1))
            }
        }
    }
}

/// 0〜100の10刻み(11か所で止まる)。触るまでは未入力。
struct InterestScale: View {
    @Binding var value: Double
    @Binding var touched: Bool

    var body: some View {
        Slider(value: Binding(get: { value }, set: { value = $0; touched = true }), in: 0...100, step: 10)
            .tint(Color.nc(.accentFactor))
            .frame(minHeight: NCSize.tapMin)
            .sensoryFeedback(.selection, trigger: value)
            .accessibilityLabel("興味")
            .accessibilityValue(touched ? "\(Int(value))" : "未入力")
    }
}

/// 起伏の少なさ。1〜5。同じ星をもう一度押すと未入力に戻る。
struct StarInput: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { i in
                Button { value = (value == i) ? 0 : i } label: {
                    Text("★").ncText(NCText.numMd, i <= value ? .accentFactor : .borderControl)
                        .frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
                }
                .accessibilityLabel("\(i)")
            }
        }
    }
}
