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
                .padding(.horizontal, NCSpace.s5).padding(.bottom, NCSpace.s8)
            }
            .background(Color.nc(.bgBase))
            .navigationDestination(for: String.self) { DetailView(showID: $0) }
            .navigationTitle("見つける")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ncText(NCText.body, selected ? .bgBase : .textMain)
                .padding(.horizontal, NCSpace.s4).frame(minHeight: NCSize.tapMin)
                .background(Capsule().fill(selected ? Color.nc(.textMain) : Color.clear))
                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: selected ? 0 : NCSize.borderW))
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
                VStack(alignment: .leading, spacing: NCSpace.s5) {
                    HStack(spacing: NCSpace.s4) {
                        ArtworkView(show: show, size: NCSize.artworkL)
                        Text(show.title).ncText(NCText.title)
                    }
                    MetricsRow(show: show)
                    if let line = show.oneLiner { Text(line).ncText(NCText.body) }
                    if let a = show.aspects { AspectsView(aspects: a) }
                    // 時間帯に関係なく、いつでも聴ける(昼寝など)。
                    if let c = TonightEngine.listenNow(show: show, ctx: model.context) {
                        Button { model.play(c) } label: {
                            Text("いま聴く").ncText(NCText.headline, .bgBase).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                                .background(Capsule().fill(Color.nc(.textMain)))
                        }
                    }
                    HStack(spacing: NCSpace.s2) {
                        Button {
                            if let c = model.slate(night: 0).first(where: { $0.show.id == show.id }) ?? model.slate(night: 0).first {
                                model.reserve(night: 0, c); dismiss()
                            }
                        } label: {
                            Text("今夜聴く").ncText(NCText.body).frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: NCSize.borderW))
                        }
                        Button {
                            if let i = model.queue.firstIndex(of: show.id) { model.queue.remove(at: i) } else { model.queue.append(show.id) }
                        } label: {
                            Text(model.queue.contains(show.id) ? "次に聴くから外す" : "次に聴く").ncText(NCText.body)
                                .frame(maxWidth: .infinity, minHeight: NCSize.buttonH)
                                .overlay(Capsule().strokeBorder(Color.nc(.borderControl), lineWidth: NCSize.borderW))
                        }
                    }
                }
                .padding(NCSpace.s5)
            }
        }
        .background(Color.nc(.bgBase))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let show { FavoriteButton(isOn: model.favorites.contains(show.id), title: show.title, inToolbar: true) { model.toggleFavorite(show) } }
            }
        }
    }
}

/// 記録: 日付ごとの結果(新しい順)。
struct LogView: View {
    @Environment(AppModel.self) private var model

    @State private var editingBedtime = false
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.setLocalizedDateFormatFromTemplate("M/d E"); return f
    }()

    /// ふだんの就寝時刻。履歴が足りないうちは手で決められ、十分になったら自動(ヘルスケアの記録)になる。
    private var bedtimeRow: some View {
        let auto = model.bedtimeIsAuto
        let text = model.bedtimeMinute.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? "未設定"
        return Button { editingBedtime = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: NCSpace.s1) {
                    Text("ふだんの就寝時刻").ncText(NCText.footnote, .textSub)
                    Text(text).ncText(NCText.numMd)
                }
                Spacer()
                if auto { Text("ヘルスケアの記録から").ncText(NCText.footnote, .textSub) }
                else { HStack(spacing: NCSpace.s1) { Text("変える"); Image(systemName: "chevron.right") }.ncText(NCText.footnote, .textSub) }
            }
            .padding(NCSpace.s4)
            .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
        }
        .buttonStyle(.plain).disabled(auto)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NCSpace.s3) {
                    bedtimeRow
                    if model.logs.isEmpty {
                        Text("まだ記録がありません。").ncText(NCText.footnote, .textSub)
                    } else {
                        ForEach(model.logs.sorted { $0.startedAt > $1.startedAt }) { log in row(log) }
                    }
                }
                .padding(.horizontal, NCSpace.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.nc(.bgBase))
            .navigationTitle("記録")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editingBedtime) { BedtimeSetupView(editing: true, initial: model.bedtimeMinute) }
        }
    }

    private func row(_ log: SleepLog) -> some View {
        let title = model.shows.first { $0.id == log.showID }?.title ?? ""
        return HStack(alignment: .center, spacing: NCSpace.s3) {
            VStack(alignment: .leading, spacing: NCSpace.s1) {
                Text(Self.dateFormat.string(from: log.startedAt)).ncText(NCText.footnote, .textSub)
                Text(title).ncText(NCText.headline).lineLimit(1)
                if let note = log.note { Text(note).ncText(NCText.footnote, .textSub).lineLimit(2) }
            }
            Spacer(minLength: NCSpace.s2)
            VStack(alignment: .trailing, spacing: NCSpace.s1) {
                if let m = log.latencyMinutes {
                    HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                        Text("\(m)").ncText(NCText.numMd, .accentResult)
                        Text("分").ncText(NCText.footnote, .accentResult)
                    }
                } else {
                    Text("―").ncText(NCText.numMd, .textSub)
                }
                if let c = log.calmVote {
                    HStack(spacing: NCSpace.s1) {
                        Text("★").ncText(NCText.numSm, .accentFactor)
                        Text("\(c)").ncText(NCText.numSm, .accentFactor)
                    }
                }
            }
        }
        .padding(NCSpace.s4)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }
}

/// 観点ごとの★(要因・琥珀)。合算しない。
struct AspectsView: View {
    let aspects: ShowAspects

    var body: some View {
        VStack(spacing: 0) {
            if let v = aspects.calmStar { row("起伏の少なさ", star: v) }
            if let v = aspects.earStar { row("耳ざわり", star: v) }
            if let l = aspects.interest { row("興味", text: label(l)) }
        }
        .padding(.horizontal, NCSpace.s4)
        .background(RoundedRectangle(cornerRadius: NCRadius.md, style: .continuous).fill(Color.nc(.surface)))
    }

    private func label(_ l: InterestLevel) -> String {
        switch l { case .low: "低め"; case .mid: "ほどほど"; case .high: "高め" }
    }

    private func row(_ title: String, star: Double) -> some View {
        HStack {
            Text(title).ncText(NCText.body)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: NCSpace.s1) {
                Text("★").ncText(NCText.numSm, .accentFactor)
                Text(String(format: "%.1f", star)).ncText(NCText.numMd, .accentFactor)
            }
        }.frame(minHeight: NCSize.tapMin)
    }

    private func row(_ title: String, text: String) -> some View {
        HStack {
            Text(title).ncText(NCText.body)
            Spacer()
            Text(text).ncText(NCText.body, .accentFactor)
        }.frame(minHeight: NCSize.tapMin)
    }
}
