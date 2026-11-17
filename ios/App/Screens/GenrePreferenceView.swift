import SwiftUI
import NeochiCore

/// 最初に一度だけ聞く、好みのジャンル。記録がたまるまでの、最初の番組と並びに使う(答えなくてもよい)。
/// ジャンルを選んだときだけ、次のステップで、そのジャンルの上位の番組を出し、気になるものをお気に入りにしてもらう
/// (音楽アプリの、最初に好みを選ぶ流れ)。設定から変えるとき(editing)は、ジャンルだけ。
struct GenrePreferenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 設定から開いた変更のとき。「あとで」は「閉じる」で、次のステップは出さない。
    var editing = false
    @State private var selected: Set<String> = []
    @State private var step = 1

    private var genres: [String] { Discover.genres(in: model.shows).filter { Discover.genreOrder.contains($0) } }

    /// 選んだジャンルの上位の番組。ジャンルごとに上位3つずつを、順に並べる(1つのジャンルに偏らない)。
    private var picks: [Show] {
        let per = Discover.genreOrder.filter { selected.contains($0) }.map { g in
            Array(Discover.ranked(model.shows.filter { $0.genre == g }).prefix(3))
        }
        var out: [Show] = []
        for i in 0..<3 { for list in per where i < list.count { out.append(list[i]) } }
        return out
    }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: NCSpace.s5) {
            if step == 1 { genreStep } else { showStep }
        }
        .padding(NCSpace.s5)
        .frame(maxWidth: .infinity, alignment: .top) }
        .safeAreaInset(edge: .bottom) { actions }
        .background(Color.nc(.bgBase).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(editing ? .visible : .hidden)
        .onAppear { selected = model.preferredGenres }
    }

    // MARK: 1. ジャンル

    @ViewBuilder private var genreStep: some View {
        Text("どんな番組が好きですか").ncText(NCText.title)
        Text(editing ? "最初に出す番組の選び方に使います。いくつでも選べます。"
                     : "最初に出す番組の選び方に使います。いくつでも選べて、あとから変えられます。")
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
    }

    // MARK: 2. お気に入り

    @ViewBuilder private var showStep: some View {
        Text("気になる番組を選びましょう").ncText(NCText.title)
        Text("しおりを付けた番組は、今夜の画面のお気に入りに並びます。あとからでも変えられます。")
            .ncText(NCText.body, .textSub).fixedSize(horizontal: false, vertical: true)
        VStack(spacing: NCSpace.s2) {
            ForEach(picks) { show in
                ScoreRow(show: show, isFavorite: model.favorites.contains(show.id)) { model.toggleFavorite(show) }
            }
        }
    }

    // MARK: 下部のボタン(固定。スクロールするのは、上の内容だけ)

    @ViewBuilder private var actions: some View {
        VStack(spacing: NCSpace.s1) {
            if step == 1 {
        Button {
            model.savePreferredGenres(selected)
            if editing || selected.isEmpty { dismiss() } else { withAnimation { step = 2 } }
        } label: {
            Text(editing || selected.isEmpty ? "決める" : "次へ").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                .background(Capsule().fill(Color.nc(.textMain)))
        }
        .buttonStyle(.pressable)
        Button { if editing { dismiss() } else { model.savePreferredGenres([]); dismiss() } } label: {
            Text(editing ? "閉じる" : "あとで").ncText(NCText.body, .textSub).frame(maxWidth: .infinity, minHeight: NCSize.tapMin)
        }
        .buttonStyle(.pressable)
            } else {
        Button { dismiss() } label: {
            Text(model.favorites.isEmpty ? "あとで選ぶ" : "はじめる").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                .background(Capsule().fill(Color.nc(.textMain)))
        }
        .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, NCSpace.s5).padding(.top, NCSpace.s2)
        .background(Color.nc(.bgBase))
    }
}
