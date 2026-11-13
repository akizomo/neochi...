import SwiftUI
import NeochiCore

/// 見つける: 発見の場。AIの★が高い順に、ジャンルで絞れる。
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var genre: String?

    private var genres: [String] { Array(Set(model.shows.map(\.genre))).sorted() }
    private var list: [Show] {
        model.shows.filter { genre == nil || $0.genre == genre }.sorted { ($0.star ?? 0) > ($1.star ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s3) {
                    Text("見つける").ncText(NCText.title).frame(minHeight: NCSize.tapMin, alignment: .leading)
                    Text("AIのおすすめ順").ncText(NCText.headline).padding(.top, NCSpace.s2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NCSpace.s2) {
                            chip("すべて", selected: genre == nil) { genre = nil }
                            ForEach(genres, id: \.self) { g in chip(g, selected: genre == g) { genre = g } }
                        }
                    }
                    ForEach(list) { show in
                        NavigationLink(value: show.id) {
                            ScoreRow(show: show, isFavorite: model.favorites.contains(show.id)) { model.toggleFavorite(show) }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NCSpace.s4).padding(.bottom, NCSpace.s8)
            }
            .background(Color.nc(.bgBase))
            .navigationDestination(for: String.self) { DetailView(showID: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ncText(NCText.body, selected ? .bgBase : .textMain)
                .padding(.horizontal, NCSpace.s4).frame(minHeight: NCSize.tapMin)
                .background(Capsule().fill(selected ? Color.nc(.textMain) : Color.clear))
                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: selected ? 0 : 1))
        }
    }
}

/// 詳細(最初の形): 番組、★と実績、AIの一行、「今夜聴く」と「次に聴く」。観点ごとの図は、このあと足す。
struct DetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let showID: String

    private var show: Show? { model.shows.first { $0.id == showID } }

    var body: some View {
        ScrollView {
            if let show {
                VStack(alignment: .leading, spacing: NCSpace.s4) {
                    HStack(spacing: NCSpace.s4) {
                        ArtworkView(show: show, size: NCSize.artworkL)
                        Text(show.title).ncText(NCText.title)
                    }
                    MetricsRow(show: show)
                    if let line = show.oneLiner { Text(line).ncText(NCText.body) }
                    HStack(spacing: NCSpace.s2) {
                        Button {
                            if let c = model.slate(night: 0).first(where: { $0.show.id == show.id }) ?? model.slate(night: 0).first {
                                model.reserve(night: 0, c); dismiss()
                            }
                        } label: {
                            Text("今夜聴く").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: 52)
                                .background(Capsule().fill(Color.nc(.textMain)))
                        }
                        Button {
                            if let i = model.queue.firstIndex(of: show.id) { model.queue.remove(at: i) } else { model.queue.append(show.id) }
                        } label: {
                            Text(model.queue.contains(show.id) ? "次に聴くから外す" : "次に聴く").ncText(NCText.body)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: 1))
                        }
                    }
                }
                .padding(NCSpace.s4)
            }
        }
        .background(Color.nc(.bgBase))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let show { FavoriteButton(isOn: model.favorites.contains(show.id), title: show.title) { model.toggleFavorite(show) } }
            }
        }
    }
}

/// 記録: 日付ごとの結果。(実データはあとでつなぐ)
struct LogView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text("記録").ncText(NCText.title).frame(minHeight: NCSize.tapMin, alignment: .leading)
                Text("まだ記録がありません。").ncText(NCText.footnote, .textSub)
                Spacer()
            }
            .padding(.horizontal, NCSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.nc(.bgBase))
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

