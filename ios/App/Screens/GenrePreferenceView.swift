import SwiftUI
import NeochiCore

/// 最初に一度だけ聞く、好みのジャンル。記録がたまるまでの、最初の番組と並びに使う(答えなくてもよい)。
struct GenrePreferenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 設定から開いた変更のとき。「あとで」は「閉じる」。
    var editing = false
    @State private var selected: Set<String> = []

    private var genres: [String] { Discover.genres(in: model.shows).filter { Discover.genreOrder.contains($0) } }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: NCSpace.s5) {
            Text("どんな番組が好きですか").ncText(NCText.title)
            Text("最初に出す番組の選び方に使います。いくつでも選べて、あとから変えられます。")
                .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: NCSpace.s2) {
                ForEach(genres, id: \.self) { g in
                    let on = selected.contains(g)
                    Button { if on { selected.remove(g) } else { selected.insert(g) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: NCSpace.s1) {
                                Text(g).ncText(NCText.headline)
                                let hint = Discover.genreHint(g)
                                if !hint.isEmpty { Text(hint).ncText(NCText.footnote, .textSub) }
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: NCSize.iconMd + NCSize.iconSm))
                                .foregroundStyle(on ? Color.nc(.textMain) : Color.nc(.textSub))
                        }
                        .padding(NCSpace.s4)
                        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
                        .overlay(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous)
                            .strokeBorder(on ? Color.nc(.textMain) : .clear, lineWidth: NCSize.borderW * 2))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Button { model.savePreferredGenres(selected); dismiss() } label: {
                Text("決める").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                    .background(Capsule().fill(Color.nc(.textMain)))
            }
            .buttonStyle(.pressable)
            Button { if editing { dismiss() } else { model.savePreferredGenres([]); dismiss() } } label: {
                Text(editing ? "閉じる" : "あとで").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
            }
            .buttonStyle(.pressable)
        }
        .padding(NCSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top) }
        .background(Color.nc(.bgBase).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(editing ? .visible : .hidden)
        .onAppear { selected = model.preferredGenres }
    }
}
