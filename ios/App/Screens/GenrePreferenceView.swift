import SwiftUI
import NeochiCore

/// 設定から変える、好みのジャンル。最初に聞くのは、オンボーディング(OnboardingView)の中。
struct GenrePreferenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: NCSpace.s5) {
            Text("どんな番組が好きですか").ncText(NCText.title)
            Text("最初に出す番組の選び方に使います。いくつでも選べます。")
                .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
            GenreChoiceList(selected: $selected)
        }
        .padding(NCSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top) }
        .safeAreaInset(edge: .bottom) {
            NCButton(title: "決める") { model.savePreferredGenres(selected); dismiss() }
            .padding(.horizontal, NCSpace.s5).padding(.vertical, NCSpace.s2)
            .background(Color.nc(.bgBase))
        }
        .background(Color.nc(.bgBase).ignoresSafeArea())
        .onAppear { selected = model.preferredGenres }
    }
}

/// ジャンルを、いくつでも選べる一覧。オンボーディングと設定で使う。
struct GenreChoiceList: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: Set<String>

    private var genres: [String] { Discover.genres(in: model.shows).filter { Discover.genreOrder.contains($0) } }

    var body: some View {
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
    }
}
